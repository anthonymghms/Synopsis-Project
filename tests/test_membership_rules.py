"""Membership rules integration; local Firestore emulator only, never production."""
import os
import unittest

import requests

from tests import test_profile_rules as profile_rules

DATABASE, UID = profile_rules.DATABASE, profile_rules.UID
_token, _value = profile_rules._token, profile_rules._value


@unittest.skipUnless(os.environ.get("FIRESTORE_EMULATOR_HOST"), "requires Firestore emulator")
class MembershipRulesTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        profile_rules.ProfileRulesTests.setUpClass.__func__(cls)

    def setUp(self):
        profile_rules.ProfileRulesTests.setUp(self)

    def write(self, path, data, *, admin=False, token=None):
        fields = {key: ({"timestampValue": value} if key in {"guestExpiresAt", "subscriptionExpiresAt"} and value is not None else _value(value))
                  for key, value in data.items()}
        return requests.post(f"{self.base}/v1/{DATABASE}/documents:commit", timeout=10,
                             headers={"Authorization": "Bearer " + ("owner" if admin else token or _token())},
                             json={"writes": [{"update": {"name": f"{DATABASE}/documents/{path}", "fields": fields}}]})

    def read(self, path, token=None):
        return requests.get(f"{self.base}/v1/{DATABASE}/documents/{path}", timeout=10,
                            headers={"Authorization": "Bearer " + (token or _token())})

    def test_client_cannot_grant_or_extend_membership_even_with_admin_claim(self):
        for token in [_token(), _token(admin=True)]:
            self.assertEqual(self.write(f"memberships/{UID}", {"role": "admin"}, token=token).status_code, 403)
            self.assertEqual(self.write(f"memberships/{UID}", {"role": "guest", "guestExpiresAt": "2099-01-01T00:00:00Z"}, token=token).status_code, 403)

    def test_guest_expiry_blocks_direct_bible_and_reference_reads(self):
        content_paths = ["bibles/english/KJV/Matthew/chapters/1/verses/1", "references/english/topics/1"]
        for path in content_paths:
            self.assertEqual(self.write(path, {"label": "English"}, admin=True).status_code, 200)
        member = f"memberships/{UID}"
        self.assertEqual(self.write(member, {"role": "guest", "guestExpiresAt": "2099-01-01T00:00:00Z"}, admin=True).status_code, 200)
        for path in content_paths:
            self.assertEqual(self.read(path).status_code, 200)
        self.write(member, {"role": "guest", "guestExpiresAt": "2000-01-01T00:00:00Z"}, admin=True)
        for path in content_paths:
            self.assertEqual(self.read(path).status_code, 403)
        self.assertEqual(self.read(member).status_code, 200)

    def test_expired_guest_can_read_only_catalog_metadata_for_settings(self):
        self.write(f"memberships/{UID}", {"role": "guest", "guestExpiresAt": "2000-01-01T00:00:00Z"}, admin=True)
        metadata_paths = ["bibles/english", "bibles/english/versions/KJV", "bibles/english/versions/manifest",
                          "bibles/english/metadata/versions", "bibles/english/meta/versions", "bibles/english/version_manifest/index"]
        content_paths = ["bibles/english/KJV/Matthew", "bibles/english/versions/KJV/chapters/1",
                         "bible_revisions/source/books/Matthew/chapters/1/verses/1",
                         "bible_chapter_revisions/edit/verses/1"]
        for path in metadata_paths + content_paths:
            self.assertEqual(self.write(path, {"label": "Catalog"}, admin=True).status_code, 200)
        for path in metadata_paths:
            self.assertEqual(self.read(path).status_code, 200, path)
        for path in content_paths:
            self.assertEqual(self.read(path).status_code, 403, path)

    def test_subscribed_access_and_stale_admin_claim_precedence(self):
        self.write("bibles/english", {"label": "English"}, admin=True)
        self.write("admin_imports/private", {"stage": "Ready"}, admin=True)
        self.write(f"memberships/{UID}", {"role": "subscribed"}, admin=True)
        self.assertEqual(self.read("bibles/english").status_code, 200)
        self.assertEqual(self.read("admin_imports/private", token=_token(admin=True)).status_code, 403)
        self.write(f"memberships/{UID}", {"role": "admin"}, admin=True)
        self.assertEqual(self.read("admin_imports/private").status_code, 200)

    def test_users_cannot_read_other_memberships_or_configuration(self):
        self.write("memberships/other", {"role": "subscribed"}, admin=True)
        self.write("membership_config/default", {"policyVersion": 1}, admin=True)
        self.assertEqual(self.read("memberships/other").status_code, 403)
        self.assertEqual(self.read("membership_config/default", token=_token(admin=True)).status_code, 403)

    def test_timed_subscription_expiry_and_permanent_compatibility(self):
        path = "references/english/topics/1"
        self.write(path, {"label": "Topic"}, admin=True)
        for member, expected in [
            ({"role": "subscribed"}, 200),
            ({"role": "subscribed", "subscriptionPermanent": True}, 200),
            ({"role": "subscribed", "subscriptionPermanent": False, "subscriptionExpiresAt": "2099-01-01T00:00:00Z"}, 200),
            ({"role": "subscribed", "subscriptionPermanent": False, "subscriptionExpiresAt": "2000-01-01T00:00:00Z"}, 403),
            ({"role": "subscribed", "subscriptionPermanent": False}, 403),
        ]:
            self.assertEqual(self.write(f"memberships/{UID}", member, admin=True).status_code, 200)
            self.assertEqual(self.read(path).status_code, expected)

    def test_suspended_and_terminated_admins_lose_direct_content_and_audit_access(self):
        self.write("references/english/topics/1", {"label": "Topic"}, admin=True)
        self.write("admin_imports/private", {"stage": "Ready"}, admin=True)
        for status in ["suspended", "terminated", "deleting", "deleted"]:
            self.write(f"memberships/{UID}", {"role": "admin", "accountStatus": status}, admin=True)
            self.assertEqual(self.read("references/english/topics/1", token=_token(admin=True)).status_code, 403)
            self.assertEqual(self.read("admin_imports/private", token=_token(admin=True)).status_code, 403)

    def test_delete_tombstone_blocks_profile_recreation_and_activity_is_backend_only(self):
        self.write(f"memberships/{UID}", {"role": "guest", "accountStatus": "deleted"}, admin=True)
        self.assertEqual(profile_rules.ProfileRulesTests.write(self, profile_rules._profile()).status_code, 403)
        for path in [f"user_activity/{UID}", f"user_activity/{UID}/sessions/session-1"]:
            self.write(path, {"activeSeconds": 1}, admin=True)
            self.assertEqual(self.read(path, token=_token(admin=True)).status_code, 403)
            self.assertEqual(self.write(path, {"activeSeconds": 100}).status_code, 403)
