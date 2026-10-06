import unittest
from datetime import datetime, timedelta, timezone
from unittest.mock import patch

from services.admin_auth import AdminAuthorizationError
from services.membership_service import (
    access_payload, get_account_access, initialize_membership_policy,
    parse_guest_expiry, verify_reader_authorization,
)
from tests.test_admin_content import fake_transactional
from tests.test_admin_users import Database, NOW, _user


class MembershipServiceTests(unittest.TestCase):
    def setUp(self):
        self.db = Database({"membership_config/default": {"rolloutAt": NOW, "defaultGuestDays": 30}})
        self.transactional = patch("services.membership_service.firestore.transactional", fake_transactional)
        self.transactional.start()
        self.addCleanup(self.transactional.stop)

    def test_rollout_boundary_initializes_once_and_cannot_move_on_restart(self):
        self.db = Database({})
        original = initialize_membership_policy(db=self.db, now=NOW)
        later = initialize_membership_policy(db=self.db, now=NOW + timedelta(days=100))
        self.assertEqual(original["rolloutAt"], NOW)
        self.assertEqual(later["rolloutAt"], NOW)
        self.assertEqual(len(self.db.transactions), 1)

    def test_explicit_rollout_timestamp_is_persisted_and_existing_policy_wins(self):
        self.db = Database({})
        with patch.dict("os.environ", {"MEMBERSHIP_LEGACY_CUTOFF": "2026-10-01T00:00:00Z"}):
            first = initialize_membership_policy(db=self.db, now=NOW)
        self.assertEqual(first["rolloutAt"], datetime(2026, 10, 1, tzinfo=timezone.utc))
        with patch.dict("os.environ", {"MEMBERSHIP_LEGACY_CUTOFF": "invalid"}):
            self.assertEqual(initialize_membership_policy(db=self.db)["rolloutAt"], first["rolloutAt"])

    def test_existing_account_is_subscribed_and_initialization_does_not_create_profile(self):
        access = get_account_access({"uid": "existing", "claims": {}}, db=self.db, get_user=lambda _: _user("existing"), now=NOW)
        self.assertEqual(access["role"], "subscribed")
        self.assertTrue(access["canRead"])
        self.assertNotIn("users/existing", self.db.values)
        self.assertEqual(self.db.values["memberships/existing"]["role"], "subscribed")

    def test_new_guest_gets_30_days_from_auth_creation_not_profile_or_first_login(self):
        created = NOW + timedelta(hours=1)
        user = _user("new")
        user.user_metadata.creation_timestamp = created.timestamp()*1000
        self.db.write("users/new", {"createdAt": datetime(2000, 1, 1, tzinfo=timezone.utc)}, False)
        first = get_account_access({"uid": "new", "claims": {}}, db=self.db, get_user=lambda _: user, now=created + timedelta(days=3))
        self.assertEqual(first["role"], "guest")
        self.assertEqual(first["guestExpiresAt"], (created + timedelta(days=30)).isoformat())
        later = get_account_access({"uid": "new", "claims": {}}, db=self.db, get_user=lambda _: self.fail("Must use assigned membership"), now=created + timedelta(days=29))
        self.assertEqual(first["guestExpiresAt"], later["guestExpiresAt"])
        expired = get_account_access({"uid": "new", "claims": {}}, db=self.db, now=created + timedelta(days=30))
        self.assertFalse(expired["canRead"])
        self.assertTrue(expired["guestExpired"])

    def test_old_admin_id_token_cannot_override_membership_demotion(self):
        self.db.write("memberships/demoted", {"role": "guest", "guestExpiresAt": NOW - timedelta(seconds=1)}, False)
        access = get_account_access({"uid": "demoted", "claims": {"admin": True}}, db=self.db, now=NOW)
        self.assertEqual(access["role"], "guest")
        self.assertFalse(access["canRead"])

    def test_missing_or_invalid_guest_expiry_fails_closed(self):
        for data in [{"role": "guest"}, {"role": "guest", "guestExpiresAt": "invalid"}, {"role": "unknown"}]:
            self.db.write("memberships/broken", data, False)
            self.assertFalse(get_account_access({"uid": "broken", "claims": {"admin": True}}, db=self.db, now=NOW)["canRead"])

    def test_reader_requires_bearer_and_expired_membership_cannot_read(self):
        with self.assertRaises(AdminAuthorizationError) as raised:
            verify_reader_authorization(None, db=self.db)
        self.assertEqual(raised.exception.status, 401)
        self.db.write("memberships/guest", {"role": "guest", "guestExpiresAt": NOW}, False)
        with self.assertRaises(AdminAuthorizationError) as raised:
            verify_reader_authorization("Bearer test", verify_token=lambda token, check_revoked: {"uid": "guest"}, db=self.db, now=NOW)
        self.assertEqual(raised.exception.code, "guest_access_expired")
        self.assertEqual(raised.exception.status, 403)
        self.db.write("memberships/guest", {"role": "subscribed"}, False)
        self.assertTrue(verify_reader_authorization("Bearer test", verify_token=lambda token, check_revoked: {"uid": "guest"}, db=self.db, now=NOW)["access"]["canRead"])

    def test_inclusive_expiry_date_obeys_beirut_day_and_dst(self):
        with patch.dict("os.environ", {"MEMBERSHIP_TIMEZONE": "Asia/Beirut"}):
            summer = parse_guest_expiry({"guestExpiresOn": "2026-10-10"})
            winter = parse_guest_expiry({"guestExpiresOn": "2026-12-10"})
        self.assertEqual(summer.isoformat(), "2026-10-10T21:00:00+00:00")
        self.assertEqual(winter.isoformat(), "2026-12-10T22:00:00+00:00")
        resolved = {"role": "guest", "guestExpiresAt": summer}
        self.assertTrue(access_payload("uid", resolved, now=summer - timedelta(microseconds=1))["canRead"])
        self.assertFalse(access_payload("uid", resolved, now=summer)["canRead"])
        self.assertEqual(access_payload("uid", resolved, now=NOW)["guestExpiresOn"], "2026-10-10")

    def test_initialization_uses_current_auth_claims_not_a_stale_admin_token(self):
        user = _user("demoted-before-init")
        access = get_account_access({"uid": user.uid, "claims": {"admin": True}}, db=self.db, get_user=lambda _: user, now=NOW)
        self.assertEqual(access["role"], "subscribed")

    def test_concurrent_admin_assignment_wins_over_guest_initialization(self):
        self.db.before_transaction = lambda: self.db.write("memberships/reader", {"role": "admin"}, False)
        access = get_account_access({"uid": "reader", "claims": {}}, db=self.db, get_user=lambda _: _user("reader"), now=NOW)
        self.assertEqual(access["role"], "admin")
        self.assertEqual(self.db.values["memberships/reader"], {"role": "admin"})


if __name__ == "__main__":
    unittest.main()
