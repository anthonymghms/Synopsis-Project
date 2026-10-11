import unittest
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from unittest.mock import Mock, patch

from flask import Flask

from admin_users_api import admin_users_api
from services.admin_auth import AdminAuthorizationError
from firebase_admin import auth

from services.admin_user_service import (
    AccountActionIncompleteError, get_admin_user, list_admin_users,
    perform_admin_user_action, update_admin_user,
)
from services.membership_service import MembershipConflictError
from tests.test_admin_content import (
    Batch as BaseBatch, Collection as BaseCollection, Database as BaseDatabase,
    Document as BaseDocument, fake_transactional,
)

NOW = datetime(2026, 10, 6, 12, tzinfo=timezone.utc)


class Document(BaseDocument):
    def delete(self):
        self.db.values.pop(self.path, None)
        self.db.times[self.path] = self.db.times.get(self.path, 0) + 1

    def collection(self, name):
        return Collection(self.db, f"{self.path}/{name}")


class Collection(BaseCollection):
    def document(self, name):
        return Document(self.db, f"{self.path}/{name}")


class Batch(BaseBatch):
    def __init__(self, db):
        super().__init__(db)
        self.deletes = []

    def delete(self, ref):
        self.deletes.append(ref)

    def commit(self):
        super().commit()
        for reference in self.deletes:
            reference.delete()


class Database(BaseDatabase):
    def collection(self, path):
        return Collection(self, path)

    def batch(self):
        return Batch(self)

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

    def test_saved_preferences_are_visible_without_other_profile_fields(self):
        preferences = {"contentLanguage": "arabic", "showDiacritics": False, "zoomLevel": 1.5,
                       "versions": {"arabic": "VD"}}
        result, _, _ = self._list([_user("reader"), _user("new-reader")],
                                  {"reader": {"preferences": preferences, "profileCompleted": True, "privateNote": "not exposed"}})
        self.assertEqual(result["users"][0]["preferences"], preferences)
        self.assertEqual(result["users"][0]["preferencesSource"], "saved_profile")
        self.assertEqual(result["users"][1]["preferencesSource"], "not_saved")
        self.assertTrue(result["users"][0]["profileCompleted"])
        self.assertFalse(result["users"][1]["profileCompleted"])
        detail = get_admin_user("reader", current_user_uid="owner", db=self.db, get_user=lambda _: _user("reader"), now=NOW)
        self.assertTrue(detail["profileCompleted"])
        self.assertNotIn("privateNote", str(result))

    def test_subscription_can_be_timed_then_permanent_and_legacy_remains_permanent(self):
        target = _user("reader")
        before = get_admin_user("reader", current_user_uid="owner", db=self.db, get_user=lambda _: target, now=NOW)
        self.assertTrue(before["subscriptionPermanent"])
        timed = update_admin_user("reader", {"revision": before["revision"], "role": "subscribed",
                                           "subscriptionPermanent": False, "subscriptionExpiresOn": "2026-10-10"},
                                  actor=self.actor, db=self.db, get_user=lambda _: target, now=NOW)
        self.assertEqual(timed["subscriptionExpiresAt"], "2026-10-10T21:00:00+00:00")
        self.assertFalse(timed["subscriptionPermanent"])
        preserved = update_admin_user("reader", {"revision": timed["revision"], "role": "subscribed"},
                                      actor=self.actor, db=self.db, get_user=lambda _: target, now=NOW)
        self.assertFalse(preserved["subscriptionPermanent"])
        self.assertEqual(preserved["subscriptionExpiresAt"], timed["subscriptionExpiresAt"])
        permanent = update_admin_user("reader", {"revision": preserved["revision"], "role": "subscribed", "subscriptionPermanent": True},
                                      actor=self.actor, db=self.db, get_user=lambda _: target, now=NOW)
        self.assertTrue(permanent["subscriptionPermanent"])
        self.assertIsNone(permanent["subscriptionExpiresAt"])
        for data in ({"subscriptionPermanent": "false"}, {"subscriptionPermanent": False},
                     {"subscriptionPermanent": True, "subscriptionExpiresOn": "2026-10-10"}):
            with self.assertRaises(ValueError):
                update_admin_user("reader", {"revision": permanent["revision"], "role": "subscribed", **data},
                                  actor=self.actor, db=self.db, get_user=lambda _: target, now=NOW)

    def _action(self, action, *, uid="reader", target=None, revision=None, **kwargs):
        target = target or _user(uid)
        if revision is None:
            revision = get_admin_user(uid, current_user_uid="owner", db=self.db, get_user=lambda _: target, now=NOW)["revision"]
        return perform_admin_user_action(uid, {"action": action, "revision": revision, "confirmation": uid},
                                         actor=self.actor, db=self.db, get_user=lambda _: target, now=NOW, **kwargs)

    def test_suspension_and_termination_block_access_and_resume_restores_role_and_expiry(self):
        expiration = NOW + timedelta(days=10)
        self.db.write("memberships/reader", {"role": "subscribed", "subscriptionPermanent": False,
                                            "subscriptionExpiresAt": expiration}, False)
        suspended = self._action("suspend")["user"]
        self.assertEqual(suspended["accountStatus"], "suspended")
        self.assertFalse(suspended["canRead"])
        self.assertEqual(suspended["subscriptionExpiresAt"], expiration.isoformat())
        resumed = self._action("resume")["user"]
        self.assertTrue(resumed["canRead"])
        revoke = Mock()
        terminated = self._action("terminate", revoke_tokens=revoke)["user"]
        revoke.assert_called_once_with("reader")
        self.assertEqual(terminated["accountStatus"], "terminated")
        self.assertFalse(terminated["canRead"])
        self.assertTrue(self._action("resume")["user"]["canRead"])
        audits = [snapshot.to_dict() for snapshot in self.db.collection("admin_membership_edits").stream()]
        self.assertEqual({audit["action"] for audit in audits}, {"suspend", "resume", "terminate"})
        self.assertTrue(all(audit["outcome"] == "completed" for audit in audits))

    def test_actions_require_confirmation_fresh_revision_and_protect_current_admin(self):
        with self.assertRaises(ValueError):
            perform_admin_user_action("reader", {"action": [], "revision": "a"*64, "confirmation": "reader"},
                                      actor=self.actor, db=self.db)
        for action in ("suspend", "resume", "terminate", "delete"):
            with self.assertRaises(AdminAuthorizationError):
                self._action(action, uid="owner", revision="a"*64)
            with self.assertRaises(ValueError):
                perform_admin_user_action("reader", {"action": action, "revision": "a"*64, "confirmation": "wrong"},
                                          actor=self.actor, db=self.db)
        target = _user("reader")
        previous = get_admin_user("reader", current_user_uid="owner", db=self.db, get_user=lambda _: target, now=NOW)
        self.db.write("memberships/reader", {"role": "admin"}, False)
        with self.assertRaises(MembershipConflictError):
            self._action("delete", target=target, revision=previous["revision"], revoke_tokens=Mock(), delete_user=Mock())
        self.assertEqual(list(self.db.collection("admin_membership_edits").stream()), [])

    def test_inactive_actor_cannot_mutate_users_even_with_cached_admin_claims(self):
        target = _user("reader")
        previous = get_admin_user("reader", current_user_uid="owner", db=self.db, get_user=lambda _: target, now=NOW)
        self.db.before_transaction = lambda: self.db.write("memberships/owner", {"role": "admin", "accountStatus": "suspended"}, False)
        with self.assertRaises(AdminAuthorizationError):
            self._action("suspend", target=target, revision=previous["revision"])
        self.assertNotIn("memberships/reader", self.db.values)

    def test_delete_cleans_profile_and_activity_leaves_denial_tombstone_and_audit(self):
        for path in ("users/reader", "user_activity/reader", "user_activity/reader/sessions/session-1",
                     "user_activity/reader/logins/login-1"):
            self.db.write(path, {"saved": True}, False)
        revoke, delete = Mock(), Mock()
        result = self._action("delete", revoke_tokens=revoke, delete_user=delete)
        self.assertEqual(result, {"deleted": True, "uid": "reader"})
        revoke.assert_called_once_with("reader")
        delete.assert_called_once_with("reader")
        self.assertEqual(self.db.values["memberships/reader"]["accountStatus"], "deleted")
        self.assertFalse(any(path == "users/reader" or path.startswith("user_activity/reader") for path in self.db.values))
        audits = list(self.db.collection("admin_membership_edits").stream())
        self.assertEqual(audits[0].to_dict()["outcome"], "completed")
        self.assertNotIn("saved", str(audits[0].to_dict()))

    def test_failed_delete_stays_denied_and_can_be_retried_after_auth_already_removed(self):
        self.db.write("users/reader", {"preferences": {"zoomLevel": 1.2}}, False)
        deletion = Mock(side_effect=RuntimeError("upstream unavailable"))
        with self.assertRaises(AccountActionIncompleteError):
            self._action("delete", revoke_tokens=Mock(), delete_user=deletion)
        self.assertEqual(self.db.values["memberships/reader"]["accountStatus"], "deleting")
        self.assertFalse(get_admin_user("reader", current_user_uid="owner", db=self.db, get_user=lambda _: _user("reader"), now=NOW)["canRead"])
        with self.assertRaises(MembershipConflictError):
            self._action("resume")
        gone = Mock(side_effect=auth.UserNotFoundError("No account"))
        detail = get_admin_user("reader", current_user_uid="owner", db=self.db, get_user=gone, now=NOW)
        self.assertTrue(detail["canManageAccount"])
        result = perform_admin_user_action("reader", {"action": "delete", "revision": detail["revision"], "confirmation": "reader"},
                                           actor=self.actor, db=self.db, get_user=gone, delete_user=gone, revoke_tokens=Mock(), now=NOW)
        self.assertTrue(result["deleted"])
        self.assertEqual(self.db.values["memberships/reader"]["accountStatus"], "deleted")

    def test_revocation_failure_does_not_restore_terminated_account(self):
        with self.assertRaises(AccountActionIncompleteError):
            self._action("terminate", revoke_tokens=Mock(side_effect=RuntimeError("Auth unavailable")))
        self.assertEqual(self.db.values["memberships/reader"]["accountStatus"], "terminated")
        self.assertFalse(get_admin_user("reader", current_user_uid="owner", db=self.db, get_user=lambda _: _user("reader"), now=NOW)["canRead"])


class AdminUsersApiTests(unittest.TestCase):
    def setUp(self):
        app = Flask(__name__)
        app.register_blueprint(admin_users_api)
        self.client = app.test_client()

    def test_anonymous_and_non_admin_requests_cannot_enumerate_or_change_accounts(self):
        for status in (401, 403):
            with patch("admin_users_api.verify_admin_authorization", side_effect=AdminAuthorizationError("denied", "Denied", status)), patch("admin_users_api.list_admin_users") as listing:
                for method, path in [("get", "/admin/users"), ("get", "/admin/users/reader"), ("post", "/admin/users/reader"), ("post", "/admin/users/reader/actions")]:
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

    def test_confirmed_action_route_forwards_verified_actor_and_sets_no_store(self):
        payload = {"action": "delete", "revision": "a"*64, "confirmation": "reader"}
        with patch("admin_users_api.verify_admin_authorization", return_value={"uid": "owner"}), patch("admin_users_api.perform_admin_user_action", return_value={"deleted": True, "uid": "reader"}) as action:
            result = self.client.post("/admin/users/reader/actions", json=payload)
        self.assertEqual(result.status_code, 200)
        self.assertEqual(result.headers["Cache-Control"], "no-store")
        action.assert_called_once_with("reader", payload, actor={"uid": "owner"})

    def test_unhashable_action_values_return_invalid_request_without_loading_accounts(self):
        with patch("admin_users_api.verify_admin_authorization", return_value={"uid": "owner"}), \
                patch("services.admin_user_service.auth.get_user") as loading:
            for action in ([], {}):
                response = self.client.post("/admin/users/reader/actions",
                                            json={"action": action, "revision": "a"*64, "confirmation": "reader"})
                self.assertEqual(response.status_code, 400)
                self.assertEqual(response.json["error"]["code"], "invalid_user_access")
            loading.assert_not_called()


if __name__ == "__main__":
    unittest.main()
