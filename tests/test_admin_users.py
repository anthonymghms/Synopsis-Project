import unittest
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from unittest.mock import Mock, patch

from flask import Flask

from admin_users_api import admin_users_api
from services.admin_auth import AdminAuthorizationError
from services.admin_user_service import get_admin_user, list_admin_users, update_admin_user
from services.membership_service import MembershipConflictError
from tests.test_admin_content import Database as BaseDatabase, fake_transactional

NOW = datetime(2026, 10, 6, 12, tzinfo=timezone.utc)


class Database(BaseDatabase):
    def get_all(self, references, field_paths=None):
        return iter([ref.get() for ref in references])


def _user(uid, **overrides):
    values = {"uid": uid, "email": f"{uid}@example.test", "display_name": "", "disabled": False,
              "email_verified": True, "custom_claims": {},
              "user_metadata": SimpleNamespace(creation_timestamp=1000, last_sign_in_timestamp=None)}
    values.update(overrides)
    return SimpleNamespace(**values)


class AdminUserServiceTests(unittest.TestCase):
    def setUp(self):
        self.db = Database({"membership_config/default": {"rolloutAt": NOW, "defaultGuestDays": 30},
                            "memberships/owner": {"role": "admin"}})
        self.actor = {"uid": "owner", "claims": {"admin": True}}
        self.transactional = patch("services.membership_service.firestore.transactional", fake_transactional)
        self.transactional.start()
        self.addCleanup(self.transactional.stop)

    def _list(self, users, profiles=None, **kwargs):
        for uid, fields in (profiles or {}).items():
            self.db.write(f"users/{uid}", fields, False)
        fetch = Mock(return_value=SimpleNamespace(users=users, next_page_token="next+page="))
        result = list_admin_users(db=self.db, fetch_users=fetch, current_user_uid="owner", now=NOW, **kwargs)
        return result, self.db, fetch

    def test_auth_directory_contains_users_without_profiles_and_forwards_pagination(self):
        result, _, fetch = self._list([_user("existing-user")], page_size=20, page_token="previous=")
        fetch.assert_called_once_with(page_token="previous=", max_results=20)
        user = result["users"][0]
        self.assertEqual(result["nextPageToken"], "next+page=")
        self.assertEqual(user["role"], "subscribed")
        self.assertEqual(user["roleSource"], "legacy_account")
        self.assertEqual(user["permissions"], ["read_content", "manage_own_profile"])
        self.assertTrue(user["canEditAccess"])
        self.assertEqual(len(user["revision"]), 64)

    def test_effective_roles_match_backend_authorization_and_hide_unrelated_data(self):
        self.db.write("memberships/stale-admin", {"role": "guest", "guestExpiresAt": NOW - timedelta(days=1)}, False)
        result, _, _ = self._list([
            _user("owner", custom_claims={"roles": ["ADMIN"], "privateClaim": "hidden"}),
            _user("profile-admin"), _user("legacy-flag"), _user("stale-admin", custom_claims={"admin": True}),
        ], {"owner": {"displayName": "Owner", "bio": "hidden"},
            "profile-admin": {"role": " Admin ", "firstName": "Anna", "lastName": "Reader"},
            "legacy-flag": {"isAdmin": True}})
        owner, profile, reader, expired = result["users"]
        self.assertFalse(owner["canEditAccess"])
        self.assertEqual(owner["roleSource"], "membership")
        self.assertEqual(profile["roleSource"], "users_role")
        self.assertEqual(profile["displayName"], "Anna Reader")
        self.assertIn("manage_users", profile["permissions"])
        self.assertEqual(reader["role"], "subscribed")
        self.assertTrue(expired["guestExpired"])
        self.assertEqual(expired["permissions"], ["manage_own_profile"])
        self.assertNotIn("hidden", str(result))

    def test_new_account_defaults_to_creation_plus_30_days_without_profile_trust(self):
        created = NOW + timedelta(days=1)
        result, _, _ = self._list([_user("new", user_metadata=SimpleNamespace(creation_timestamp=created.timestamp()*1000, last_sign_in_timestamp=None))],
                                  {"new": {"createdAt": datetime(2000, 1, 1, tzinfo=timezone.utc)}})
        user = result["users"][0]
        self.assertEqual(user["role"], "guest")
        self.assertEqual(user["guestExpiresAt"], (created + timedelta(days=30)).isoformat())

    def test_disabled_admin_has_no_effective_permissions(self):
        result, _, _ = self._list([_user("blocked", disabled=True, custom_claims={"admin": True})])
        self.assertEqual(result["users"][0]["permissions"], [])
        self.assertFalse(result["users"][0]["canRead"])

    def test_empty_directory_does_not_issue_profile_query(self):
        with patch.object(self.db, "get_all") as get_all:
            result, _, _ = self._list([])
        self.assertEqual(result["users"], [])
        get_all.assert_not_called()

    def test_page_limits_and_token_length_are_bounded(self):
        for size in (0, 101, -1):
            with self.assertRaises(ValueError):
                self._list([], page_size=size)
        with self.assertRaises(ValueError):
            self._list([], page_token="x"*4097)

    def test_roles_and_inclusive_expiry_edit_atomically_without_modifying_claims_or_profile(self):
        target = _user("reader", custom_claims={"unrelated": "retained"})
        self.db.write("users/reader", {"displayName": "Reader", "role": "admin"}, False)
        before = get_admin_user("reader", current_user_uid="owner", db=self.db, get_user=lambda _: target, now=NOW)
        with patch("services.admin_user_service.auth.set_custom_user_claims") as claims:
            result = update_admin_user("reader", {"revision": before["revision"], "role": "guest", "guestExpiresOn": "2026-10-10"},
                                       actor=self.actor, db=self.db, get_user=lambda _: target, now=NOW)
        self.assertEqual(result["guestExpiresAt"], "2026-10-10T21:00:00+00:00")
        self.assertEqual(result["guestExpiresOn"], "2026-10-10")
        self.assertEqual(result["role"], "guest")
        self.assertEqual(self.db.values["users/reader"]["role"], "admin")
        self.assertEqual(len(list(self.db.collection("admin_membership_edits").stream())), 1)
        claims.assert_not_called()

    def test_stale_role_changes_conflict_without_audit(self):
        target = _user("reader")
        before = get_admin_user("reader", current_user_uid="owner", db=self.db, get_user=lambda _: target, now=NOW)
        self.db.write("memberships/reader", {"role": "admin"}, False)
        with self.assertRaises(MembershipConflictError):
            update_admin_user("reader", {"revision": before["revision"], "role": "subscribed"}, actor=self.actor,
                              db=self.db, get_user=lambda _: target, now=NOW)
        self.assertEqual(list(self.db.collection("admin_membership_edits").stream()), [])

    def test_self_changes_and_concurrently_demoted_actor_cannot_lock_out_admins(self):
        with self.assertRaises(AdminAuthorizationError) as raised:
            update_admin_user("owner", {"revision": "a"*64, "role": "subscribed"}, actor=self.actor, db=self.db)
        self.assertEqual(raised.exception.code, "self_access_change_forbidden")
        target = _user("other-admin", custom_claims={"admin": True})
        before = get_admin_user(target.uid, current_user_uid="owner", db=self.db, get_user=lambda _: target, now=NOW)
        self.db.before_transaction = lambda: self.db.write("memberships/owner", {"role": "subscribed"}, False)
        with self.assertRaises(AdminAuthorizationError):
            update_admin_user(target.uid, {"revision": before["revision"], "role": "subscribed"}, actor=self.actor,
                              db=self.db, get_user=lambda _: target, now=NOW)
        self.assertNotIn("memberships/other-admin", self.db.values)
        self.assertEqual(list(self.db.collection("admin_membership_edits").stream()), [])

    def test_invalid_roles_fields_and_expiry_are_rejected(self):
        for payload in [{"role": "owner"}, {"role": "guest", "guestExpiresOn": "invalid"},
                        {"role": "guest", "guestExpiresAt": "2026-12-01T00:00:00"},
                        {"role": "subscribed", "admin": True}]:
            with self.assertRaises(ValueError):
                update_admin_user("reader", {"revision": "a"*64, **payload}, actor=self.actor, db=self.db)


class AdminUsersApiTests(unittest.TestCase):
    def setUp(self):
        app = Flask(__name__)
        app.register_blueprint(admin_users_api)
        self.client = app.test_client()

    def test_anonymous_and_non_admin_requests_cannot_enumerate_or_change_accounts(self):
        for status in (401, 403):
            with patch("admin_users_api.verify_admin_authorization", side_effect=AdminAuthorizationError("denied", "Denied", status)), patch("admin_users_api.list_admin_users") as listing:
                for method, path in [("get", "/admin/users"), ("get", "/admin/users/reader"), ("post", "/admin/users/reader")]:
                    self.assertEqual(getattr(self.client, method)(path).status_code, status)
                listing.assert_not_called()

    def test_endpoint_forwards_verified_identity_and_encoded_cursor(self):
        with patch("admin_users_api.verify_admin_authorization", return_value={"uid": "owner"}) as verify, patch("admin_users_api.list_admin_users", return_value={"users": [], "nextPageToken": None}) as listing:
            response = self.client.get("/admin/users?pageSize=25&pageToken=opaque%2Btoken%3D", headers={"Authorization": "Bearer verified-token"})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.headers["Cache-Control"], "no-store")
        verify.assert_called_once_with("Bearer verified-token")
        listing.assert_called_once_with(page_size=25, page_token="opaque+token=", current_user_uid="owner")

    def test_invalid_page_size_rejected_before_listing(self):
        with patch("admin_users_api.verify_admin_authorization", return_value={"uid": "owner"}), patch("admin_users_api.list_admin_users") as listing:
            for size in ("abc", "0", "101"):
                self.assertEqual(self.client.get(f"/admin/users?pageSize={size}").status_code, 400)
            listing.assert_not_called()

    def test_mutation_conflict_and_expired_access_status_are_explicit(self):
        with patch("admin_users_api.verify_admin_authorization", return_value={"uid": "owner"}), patch("admin_users_api.update_admin_user", side_effect=MembershipConflictError("Reload user")):
            result = self.client.post("/admin/users/reader", json={"role": "subscribed"})
        self.assertEqual(result.status_code, 409)
        self.assertEqual(result.json["error"]["code"], "membership_conflict")
        with patch("admin_users_api.verify_identity", return_value={"uid": "reader"}), patch("admin_users_api.get_account_access", return_value={"role": "guest", "canRead": False, "guestExpired": True}):
            result = self.client.get("/account/access")
        self.assertEqual(result.status_code, 200)
        self.assertFalse(result.json["canRead"])
        self.assertEqual(result.headers["Cache-Control"], "no-store")

    def test_upstream_error_is_redacted(self):
        with patch("admin_users_api.verify_admin_authorization", return_value={"uid": "owner"}), patch("admin_users_api.list_admin_users", side_effect=RuntimeError("private backend details")), patch("admin_users_api._logger"):
            response = self.client.get("/admin/users")
        self.assertEqual(response.status_code, 503)
        self.assertNotIn("private backend details", response.get_data(as_text=True))


if __name__ == "__main__":
    unittest.main()
