"""Transaction/query integration against the local demo Firestore emulator."""
import os
import unittest
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from urllib.parse import urlparse

import requests
from google.auth.credentials import AnonymousCredentials
from google.cloud import firestore

from services.user_activity_service import get_user_activity, record_user_activity
from tests.test_profile_rules import DATABASE, PROJECT


@unittest.skipUnless(os.environ.get("FIRESTORE_EMULATOR_HOST"), "requires Firestore emulator")
class UserActivityEmulatorTests(unittest.TestCase):
    def setUp(self):
        host = os.environ["FIRESTORE_EMULATOR_HOST"]
        if urlparse("http://" + host).hostname not in {"localhost", "127.0.0.1", "::1"}:
            raise ValueError("Activity integration tests only run against a local emulator")
        requests.delete(f"http://{host}/emulator/v1/{DATABASE}/documents", timeout=10).raise_for_status()
        self.db = firestore.Client(project=PROJECT, credentials=AnonymousCredentials())
        self.addCleanup(self.db.close)
        self.now = datetime(2026, 10, 11, tzinfo=timezone.utc)
        self.identity = {"uid": "activity-reader", "claims": {"auth_time": int(self.now.timestamp())}}
        self.get_user = lambda uid: SimpleNamespace(uid=uid, disabled=False)
        self.db.collection("memberships").document("activity-reader").set({"role": "subscribed", "accountStatus": "active"})

    def record(self, session, event, seconds, now):
        return record_user_activity(self.identity, {"sessionId": session, "event": event, "activeSeconds": seconds},
                                    db=self.db, get_user=self.get_user, now=now)

    def test_real_transactions_deduplicate_heartbeats_and_page_equal_timestamps(self):
        self.record("session-one", "start", 0, self.now)
        self.record("session-two", "start", 0, self.now)
        later = self.now + timedelta(seconds=60)
        first = self.record("session-one", "heartbeat", 60, later)
        duplicate = self.record("session-one", "heartbeat", 60, later)
        self.assertEqual(first["summary"]["totalActiveSeconds"], 60)
        self.assertEqual(duplicate["summary"]["totalActiveSeconds"], 60)
        self.assertEqual(duplicate["summary"]["sessionCount"], 2)
        self.assertEqual(duplicate["summary"]["loginCount"], 1)
        page1 = get_user_activity("activity-reader", db=self.db, get_user=self.get_user, page_size=1)
        page2 = get_user_activity("activity-reader", db=self.db, get_user=self.get_user,
                                  page_size=1, page_token=page1["nextPageToken"])
        self.assertEqual({page1["sessions"][0]["id"], page2["sessions"][0]["id"]}, {"session-one", "session-two"})
        self.assertEqual(len(page1["logins"]), 1)
        self.assertEqual(page2["logins"], [])
        self.assertIsNone(page2["nextPageToken"])
