import unittest
from types import SimpleNamespace
from unittest.mock import patch

from firebase_admin import auth

from services.admin_auth import (
    AdminAuthorizationError,
    verify_admin_authorization,
)


class _Snapshot:
    def __init__(self, data):
        self._data = data
        self.exists = data is not None

    def to_dict(self):
        return self._data


class _Document:
    def __init__(self, data):
        self._data = data

    def get(self):
        return _Snapshot(self._data)


class _Collection:
    def __init__(self, data):
        self._data = data

    def document(self, uid):
        return _Document(self._data.get(uid))


class _Database:
    def __init__(self, users, memberships=None):
        self._users = users
        self._memberships = memberships or {}

    def collection(self, name):
        if name == "memberships":
            return _Collection(self._memberships)
        if name != "users":
            raise AssertionError(name)
        return _Collection(self._users)


class AdminAuthorizationTests(unittest.TestCase):
    def setUp(self):
        users = patch("services.admin_auth.auth.get_user", return_value=SimpleNamespace(disabled=False))
        users.start()
        self.addCleanup(users.stop)

    def test_unauthenticated_request_is_denied(self):
        with self.assertRaises(AdminAuthorizationError) as raised:
            verify_admin_authorization(None, db=_Database({}))
        self.assertEqual(raised.exception.status, 401)

    def test_normal_user_is_denied(self):
        with self.assertRaises(AdminAuthorizationError) as raised:
            verify_admin_authorization(
                "Bearer token",
                verify_token=lambda token, check_revoked: {"uid": "normal"},
                db=_Database({"normal": {"role": "user"}}),
            )
        self.assertEqual(raised.exception.status, 403)

    def test_custom_claim_admin_is_allowed(self):
        result = verify_admin_authorization(
            "Bearer token",
            verify_token=lambda token, check_revoked: {
                "uid": "admin-user",
                "admin": True,
            },
            db=_Database({}),
        )
        self.assertEqual(result["uid"], "admin-user")
        self.assertEqual(result["source"], "custom_claim")

    def test_users_role_admin_is_allowed(self):
        result = verify_admin_authorization(
            "Bearer token",
            verify_token=lambda token, check_revoked: {"uid": "admin-user"},
            db=_Database({"admin-user": {"role": "admin"}}),
        )
        self.assertEqual(result["source"], "users_role")

    def test_legacy_profile_boolean_is_not_trusted_by_backend(self):
        with self.assertRaises(AdminAuthorizationError) as raised:
            verify_admin_authorization(
                "Bearer token",
                verify_token=lambda token, check_revoked: {"uid": "normal"},
                db=_Database({"normal": {"isAdmin": True}}),
            )
        self.assertEqual(raised.exception.status, 403)

    def test_server_membership_demotion_overrides_stale_admin_claims_and_profile(self):
        for role in ("guest", "subscribed", "invalid"):
            with self.assertRaises(AdminAuthorizationError):
                verify_admin_authorization(
                    "Bearer token", verify_token=lambda token, check_revoked: {"uid": "admin-user", "admin": True},
                    db=_Database({"admin-user": {"role": "admin"}}, {"admin-user": {"role": role}}),
                )

    def test_server_membership_promotion_does_not_require_new_token_claims(self):
        result = verify_admin_authorization("Bearer token", verify_token=lambda token, check_revoked: {"uid": "new-admin"},
                                            db=_Database({}, {"new-admin": {"role": "admin"}}))
        self.assertEqual(result["source"], "membership")

    def test_suspended_terminated_or_deleted_admin_cannot_use_stale_tokens(self):
        for status in ("suspended", "terminated", "deleting", "deleted", "invalid"):
            with self.assertRaises(AdminAuthorizationError):
                verify_admin_authorization("Bearer token", verify_token=lambda token, check_revoked: {"uid": "owner", "admin": True},
                                            db=_Database({"owner": {"role": "admin"}}, {"owner": {"role": "admin", "accountStatus": status}}))

    def test_disabled_auth_admin_denied_even_with_active_membership(self):
        with self.assertRaises(AdminAuthorizationError) as raised:
            verify_admin_authorization("Bearer token", verify_token=lambda token, check_revoked: {"uid": "owner", "admin": True},
                                        db=_Database({}, {"owner": {"role": "admin"}}),
                                        get_user=lambda _: SimpleNamespace(disabled=True))
        self.assertEqual(raised.exception.code, "account_access_denied")

    def test_removed_custom_admin_claims_override_stale_token_before_initialization(self):
        with self.assertRaises(AdminAuthorizationError):
            verify_admin_authorization("Bearer token", verify_token=lambda token, check_revoked: {"uid": "owner", "admin": True},
                                        db=_Database({}), get_user=lambda _: SimpleNamespace(disabled=False, custom_claims={}))

    def test_deleted_auth_account_cannot_use_membership_admin_role(self):
        def gone(_uid):
            raise auth.UserNotFoundError("Missing")
        with self.assertRaises(AdminAuthorizationError) as raised:
            verify_admin_authorization("Bearer token", verify_token=lambda token, check_revoked: {"uid": "owner", "admin": True},
                                        db=_Database({}, {"owner": {"role": "admin"}}), get_user=gone)
        self.assertEqual(raised.exception.status, 401)


if __name__ == "__main__":
    unittest.main()
