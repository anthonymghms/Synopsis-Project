import unittest

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


if __name__ == "__main__":
    unittest.main()
