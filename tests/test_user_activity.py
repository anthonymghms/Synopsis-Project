import base64
import json
import unittest
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from unittest.mock import Mock, patch

from flask import Flask

from services.admin_auth import AdminAuthorizationError, verify_identity
from services.user_activity_service import (
    MAX_SESSION_SECONDS, ActivityRequestError, get_user_activity, record_user_activity,
)
from tests.test_admin_content import (
    Collection as BaseCollection, Database as BaseDatabase,
    Document as BaseDocument, fake_transactional,
)
from user_activity_api import user_activity_api

NOW = datetime(2026, 10, 10, 12, tzinfo=timezone.utc)
IDENTITY = {"uid": "reader", "claims": {"auth_time": int((NOW - timedelta(minutes=2)).timestamp())}}


class Document(BaseDocument):
    def get(self, transaction=None):
        if transaction is not None and transaction.writes:
            raise AssertionError("A transaction read followed a write.")
        return super().get(transaction=transaction)

    def collection(self, name):
        return Query(self.db, f"{self.path}/{name}")


class Query(BaseCollection):
    def __init__(self, db, path, *, ordering=None, cursor=None, maximum=None):
        super().__init__(db, path)
        self.ordering = ordering or []
        self.cursor = cursor
        self.maximum = maximum

    def document(self, name):
        return Document(self.db, f"{self.path}/{name}")

    def _copy(self, **fields):
        return Query(self.db, self.path, ordering=fields.get("ordering", self.ordering),
                     cursor=fields.get("cursor", self.cursor), maximum=fields.get("maximum", self.maximum))

    def order_by(self, field, direction):
        if direction != "DESCENDING":
            raise AssertionError("Expected newest first.")
        return self._copy(ordering=self.ordering + [field])

    def start_after(self, value):
        return self._copy(cursor=value)

    def limit(self, maximum):
        return self._copy(maximum=maximum)

    def stream(self):
        self.db.queries.append({"path": self.path, "maximum": self.maximum, "ordering": self.ordering})
        snapshots = list(super().stream())
        def key(snapshot):
            return tuple(snapshot.id if f == "__name__" else snapshot.to_dict()[f] for f in self.ordering)
        snapshots = sorted(snapshots, key=key, reverse=True)
        if self.cursor is not None:
            boundary = tuple(self.cursor[f].id if f == "__name__" else self.cursor[f] for f in self.ordering)
            snapshots = [snapshot for snapshot in snapshots if key(snapshot) < boundary]
        return iter(snapshots if self.maximum is None else snapshots[:self.maximum])


class Database(BaseDatabase):
    def __init__(self, values):
        super().__init__(values)
        self.queries = []

    def collection(self, path):
        return Query(self, path)


class UserActivityServiceTests(unittest.TestCase):
    def setUp(self):
        self.db = Database({"memberships/reader": {"role": "subscribed", "accountStatus": "active"}})
        self.get_user = Mock(return_value=SimpleNamespace(disabled=False))
        self.transactional = patch("services.user_activity_service.firestore.transactional", fake_transactional)
        self.transactional.start()
        self.addCleanup(self.transactional.stop)

    def record(self, event="start", seconds=0, offset=0, session="session-0001", identity=IDENTITY):
        return record_user_activity(identity, {"sessionId": session, "event": event, "activeSeconds": seconds},
                                    db=self.db, get_user=self.get_user, now=NOW + timedelta(seconds=offset))

    def test_start_retries_and_token_refreshes_do_not_duplicate_sessions_or_logins(self):
        first = self.record()
        repeated = self.record(offset=1)
        refreshed = self.record(event="heartbeat", seconds=50, offset=60,
                                identity={"uid": "reader", "claims": {**IDENTITY["claims"], "iat": int(NOW.timestamp())}})
        self.assertEqual(first["summary"]["sessionCount"], 1)
        self.assertEqual(repeated["summary"]["loginCount"], 1)
        self.assertEqual(refreshed["summary"]["loginCount"], 1)
        self.assertEqual(refreshed["summary"]["totalActiveSeconds"], 50)
        login = self.db.values[f'user_activity/reader/logins/{IDENTITY["claims"]["auth_time"]}']
        self.assertEqual(login["signedInAt"], NOW - timedelta(minutes=2))

    def test_new_visits_count_sessions_and_new_authentication_counts_signins(self):
        self.record()
        reopened = self.record(offset=300, session="session-0002")
        self.assertEqual(reopened["summary"]["sessionCount"], 2)
        self.assertEqual(reopened["summary"]["loginCount"], 1)
        signed_in = self.record(offset=400, session="session-0003",
                                identity={"uid": "reader", "claims": {"auth_time": int((NOW + timedelta(seconds=400)).timestamp())}})
        self.assertEqual(signed_in["summary"]["loginCount"], 2)
        self.assertEqual(len(list(self.db.collection("user_activity").document("reader").collection("logins").stream())), 2)

    def test_replayed_nonmonotonic_and_ended_updates_do_not_add_time(self):
        self.record()
        first = self.record(event="heartbeat", seconds=50, offset=60)
        duplicate = self.record(event="heartbeat", seconds=50, offset=61)
        backwards = self.record(event="heartbeat", seconds=10, offset=62)
        ended = self.record(event="end", seconds=70, offset=90)
        late = self.record(event="heartbeat", seconds=200, offset=200)
        self.assertEqual(first["summary"]["totalActiveSeconds"], 50)
        self.assertEqual(duplicate["summary"]["totalActiveSeconds"], 50)
        self.assertEqual(backwards["summary"]["totalActiveSeconds"], 50)
        self.assertEqual(ended["summary"]["totalActiveSeconds"], 70)
        self.assertEqual(late["summary"]["totalActiveSeconds"], 70)
        self.assertEqual(late["session"]["endedAt"], (NOW + timedelta(seconds=90)).isoformat())

    def test_idle_does_not_advance_last_activity_or_active_seconds(self):
        started = self.record()
        idle = self.record(event="heartbeat", offset=600)
        ended = self.record(event="end", offset=650)
        self.assertEqual(idle["summary"]["lastActiveAt"], started["summary"]["lastActiveAt"])
        self.assertEqual(ended["summary"]["totalActiveSeconds"], 0)
        self.assertEqual(ended["session"]["lastActiveAt"], NOW.isoformat())

    def test_forged_seconds_are_bounded_by_server_time_and_cannot_be_recovered_by_replay(self):
        self.record()
        forged = self.record(event="heartbeat", seconds=8000, offset=10)
        repeated = self.record(event="heartbeat", seconds=8000, offset=8000)
        self.assertEqual(forged["session"]["activeSeconds"], 15)
        self.assertEqual(repeated["summary"]["totalActiveSeconds"], 15)

    def test_per_update_and_lifetime_budgets_stop_a_burst_of_forged_updates(self):
        self.record()
        for seconds in range(1, 41):
            result = self.record(event="heartbeat", seconds=seconds, offset=10)
        self.assertEqual(result["session"]["activeSeconds"], 15)
        self.assertLessEqual(result["summary"]["totalActiveSeconds"], 15)

    def test_idle_report_prevents_crediting_a_late_large_delta(self):
        self.record()
        self.record(event="heartbeat", offset=600)
        result = self.record(event="heartbeat", seconds=600, offset=610)
        self.assertEqual(result["session"]["activeSeconds"], 15)

    def test_concurrent_tabs_do_not_double_summary_active_time(self):
        self.record()
        self.record(session="session-0002")
        self.record(event="heartbeat", seconds=60, offset=60)
        second_tab = self.record(event="heartbeat", seconds=60, offset=60, session="session-0002")
        self.assertEqual(second_tab["session"]["activeSeconds"], 60)
        self.assertLessEqual(second_tab["summary"]["totalActiveSeconds"], 65)
        self.record(event="heartbeat", seconds=120, offset=120)
        second_tab = self.record(event="heartbeat", seconds=120, offset=120, session="session-0002")
        self.assertLessEqual(second_tab["summary"]["totalActiveSeconds"], 125)

    def test_idle_tab_heartbeats_and_new_tab_starts_do_not_consume_an_active_tabs_budget(self):
        self.record()
        self.record(session="session-0002")
        self.record(event="heartbeat", offset=60, session="session-0002")
        active_tab = self.record(event="heartbeat", seconds=60, offset=60)
        self.assertEqual(active_tab["summary"]["totalActiveSeconds"], 60)
        self.record(offset=120, session="session-0003")
        active_tab = self.record(event="heartbeat", seconds=120, offset=120)
        self.assertEqual(active_tab["summary"]["totalActiveSeconds"], 120)

    def test_out_of_order_requests_cannot_move_server_timestamps_backwards(self):
        self.record()
        self.record(event="heartbeat", seconds=50, offset=60)
        delayed = self.record(event="heartbeat", seconds=51, offset=59)
        self.assertEqual(delayed["summary"]["lastActiveAt"], (NOW + timedelta(seconds=60)).isoformat())
        self.assertEqual(delayed["session"]["lastActiveAt"], (NOW + timedelta(seconds=60)).isoformat())
        self.assertEqual(self.db.values["user_activity/reader"]["lastReportedAt"], NOW + timedelta(seconds=60))
        ended = self.record(event="end", seconds=51, offset=58)
        self.assertEqual(ended["session"]["endedAt"], (NOW + timedelta(seconds=60)).isoformat())

    def test_long_session_requires_restart_and_can_still_end(self):
        self.record()
        with self.assertRaises(ActivityRequestError) as raised:
            self.record(event="heartbeat", seconds=MAX_SESSION_SECONDS, offset=MAX_SESSION_SECONDS)
        self.assertEqual(raised.exception.code, "activity_session_expired")
        ended = self.record(event="end", seconds=MAX_SESSION_SECONDS, offset=MAX_SESSION_SECONDS + 60)
        self.assertLessEqual(ended["summary"]["totalActiveSeconds"], MAX_SESSION_SECONDS)
        self.assertIsNotNone(ended["session"]["endedAt"])

    def test_updates_before_start_are_rejected_without_creating_data(self):
        with self.assertRaises(ActivityRequestError) as raised:
            self.record(event="heartbeat", seconds=10)
        self.assertEqual(raised.exception.status, 409)
        self.assertEqual(list(self.db.values), ["memberships/reader"])

    def test_lifecycle_and_auth_disabled_gate_writes(self):
        for status in ("suspended", "terminated", "deleting", "deleted", "bogus", None):
            with self.subTest(status=status):
                self.db.write("memberships/reader", {"accountStatus": status}, False)
                with self.assertRaises(AdminAuthorizationError):
                    self.record()
                self.assertNotIn("user_activity/reader", self.db.values)
        self.db.write("memberships/reader", {"role": "subscribed"}, False)
        self.get_user.return_value = SimpleNamespace(disabled=True)
        with self.assertRaises(AdminAuthorizationError):
            self.record()
        self.assertNotIn("user_activity/reader", self.db.values)

    def test_inflight_deletion_tombstone_is_rechecked_in_transaction(self):
        self.db.before_transaction = lambda: self.db.write("memberships/reader", {"accountStatus": "deleting"}, False)
        with self.assertRaises(AdminAuthorizationError):
            self.record()
        self.assertNotIn("user_activity/reader", self.db.values)

    def test_missing_auth_account_cannot_recreate_activity(self):
        self.get_user.side_effect = RuntimeError("Auth account no longer exists")
        with self.assertRaises(RuntimeError):
            self.record()
        self.assertNotIn("user_activity/reader", self.db.values)

    def test_client_identity_timestamps_and_invalid_counters_are_rejected(self):
        valid = {"sessionId": "session-0001", "event": "start", "activeSeconds": 0}
        invalid = [None, {**valid, "uid": "someone-else"}, {**valid, "startedAt": NOW.isoformat()},
                   {**valid, "activeSeconds": True}, {**valid, "activeSeconds": -1},
                   {**valid, "activeSeconds": 1.5}, {**valid, "activeSeconds": MAX_SESSION_SECONDS + 1},
                   {**valid, "activeSeconds": 1}, {**valid, "event": "online"},
                   {**valid, "sessionId": "../some-document"}, {**valid, "sessionId": "x" * 65}]
        for payload in invalid:
            with self.subTest(payload=payload), self.assertRaises(ActivityRequestError):
                record_user_activity(IDENTITY, payload, db=self.db, get_user=self.get_user, now=NOW)
        self.assertNotIn("user_activity/reader", self.db.values)

    def test_invalid_authentication_time_is_rejected_without_writes(self):
        for value in (None, True, "10", -1, int(NOW.timestamp()) + 301):
            with self.subTest(value=value), self.assertRaises(AdminAuthorizationError):
                self.record(identity={"uid": "reader", "claims": {"auth_time": value}})
        self.assertNotIn("user_activity/reader", self.db.values)

    def test_missing_summary_returns_an_empty_activity_history(self):
        result = get_user_activity("reader", db=self.db, get_user=self.get_user)
        self.assertEqual(result["summary"]["sessionCount"], 0)
        self.assertEqual(result["sessions"], [])
        self.assertEqual(result["logins"], [])
        self.assertIsNone(result["nextPageToken"])

    def test_cursor_pages_equal_timestamps_without_skipping_and_limits_queries(self):
        for identifier in ("session-0001", "session-0002", "session-0003"):
            self.record(session=identifier)
        first = get_user_activity("reader", db=self.db, get_user=self.get_user, page_size=2)
        self.assertEqual([s["id"] for s in first["sessions"]], ["session-0003", "session-0002"])
        second = get_user_activity("reader", db=self.db, get_user=self.get_user, page_size=2,
                                   page_token=first["nextPageToken"])
        self.assertEqual([s["id"] for s in second["sessions"]], ["session-0001"])
        self.assertIsNone(second["nextPageToken"])
        self.assertEqual([q["maximum"] for q in self.db.queries], [3, 3, 3])

    def test_login_history_continues_when_sessions_are_exhausted(self):
        self.record()
        for offset in (1, 2, 3, 4):
            self.record(event="heartbeat", offset=offset,
                        identity={"uid": "reader", "claims": {"auth_time": int((NOW + timedelta(seconds=offset)).timestamp())}})
        first = get_user_activity("reader", db=self.db, get_user=self.get_user, page_size=2)
        second = get_user_activity("reader", db=self.db, get_user=self.get_user, page_size=2,
                                   page_token=first["nextPageToken"])
        third = get_user_activity("reader", db=self.db, get_user=self.get_user, page_size=2,
                                  page_token=second["nextPageToken"])
        self.assertEqual(len(first["sessions"]), 1)
        self.assertEqual(second["sessions"], [])
        self.assertEqual(third["sessions"], [])
        identifiers = [login["id"] for page in (first, second, third) for login in page["logins"]]
        self.assertEqual(len(identifiers), 5)
        self.assertEqual(len(set(identifiers)), 5)
        self.assertIsNone(third["nextPageToken"])

    def test_paging_uses_stable_positions_when_a_cursor_session_is_removed(self):
        for identifier in ("session-0001", "session-0002", "session-0003"):
            self.record(session=identifier)
        first = get_user_activity("reader", db=self.db, get_user=self.get_user, page_size=2)
        del self.db.values["user_activity/reader/sessions/session-0002"]
        second = get_user_activity("reader", db=self.db, get_user=self.get_user, page_size=2,
                                   page_token=first["nextPageToken"])
        self.assertEqual([s["id"] for s in second["sessions"]], ["session-0001"])

    def test_invalid_foreign_and_oversized_cursors_are_rejected(self):
        def token(value):
            return base64.urlsafe_b64encode(json.dumps(value).encode()).decode()
        session = {"id": "session-0001", "startedAt": NOW.isoformat()}
        login = {"id": str(int(NOW.timestamp())), "signedInAt": NOW.isoformat()}
        valid = {"v": 1, "uid": "reader", "sessions": session, "logins": login}
        for value in ("invalid!", "x" * 1025, token({**valid, "uid": "another"}),
                      token({**valid, "sessions": {**session, "id": "../fake"}}), token({**valid, "v": True}),
                      token({**valid, "sessions": {**session, "startedAt": "2026-10-10"}}),
                      token({**valid, "logins": {**login, "id": "123"}}),
                      token({**valid, "sessions": None, "logins": None}), token({**valid, "extra": "field"})):
            with self.subTest(value=value), self.assertRaises(ValueError):
                get_user_activity("reader", page_token=value, db=self.db, get_user=self.get_user)


class UserActivityApiTests(unittest.TestCase):
    def setUp(self):
        self.app = Flask(__name__)
        self.app.register_blueprint(user_activity_api)
        self.client = self.app.test_client()

    def test_record_uses_verified_identity_and_nostore(self):
        payload = {"sessionId": "session-0001", "event": "start", "activeSeconds": 0}
        with patch("user_activity_api.verify_identity", return_value=IDENTITY) as identity, \
                patch("user_activity_api.record_user_activity", return_value={"summary": {}}) as record:
            response = self.client.post("/account/activity", json=payload, headers={"Authorization": "Bearer signed-token"})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.headers["Cache-Control"], "no-store")
        identity.assert_called_once_with("Bearer signed-token")
        record.assert_called_once_with(IDENTITY, payload)

    def test_telemetry_identity_requires_revocation_checks(self):
        verify = Mock(return_value=IDENTITY["claims"] | {"uid": "reader"})
        verify_identity("Bearer signed-token", verify_token=verify)
        verify.assert_called_once_with("signed-token", check_revoked=True)

    def test_unauthenticated_record_and_nonadmin_history_are_denied(self):
        with patch("user_activity_api.verify_identity", side_effect=AdminAuthorizationError("invalid_token", "Sign in.", 401)), \
                patch("user_activity_api.record_user_activity") as record:
            response = self.client.post("/account/activity", json={})
        self.assertEqual(response.status_code, 401)
        record.assert_not_called()
        with patch("user_activity_api.verify_admin_authorization", side_effect=AdminAuthorizationError("admin_required", "Admins only.", 403)), \
                patch("user_activity_api.get_user_activity") as history:
            response = self.client.get("/admin/users/reader/activity")
        self.assertEqual(response.status_code, 403)
        history.assert_not_called()

    def test_admin_history_forwards_cursor_and_caps_page_size(self):
        with patch("user_activity_api.verify_admin_authorization", return_value={"uid": "admin"}), \
                patch("user_activity_api.get_user_activity", return_value={"sessions": []}) as history:
            response = self.client.get("/admin/users/reader/activity?pageSize=12&pageToken=next-page")
        self.assertEqual(response.status_code, 200)
        history.assert_called_once_with("reader", page_size=12, page_token="next-page")
        with patch("user_activity_api.verify_admin_authorization", return_value={"uid": "admin"}):
            for value in ("0", "101", "abc"):
                response = self.client.get(f"/admin/users/reader/activity?pageSize={value}")
                self.assertEqual(response.status_code, 400)

    def test_activity_conflict_and_denied_status_keep_structured_errors(self):
        with patch("user_activity_api.verify_identity", return_value=IDENTITY), \
                patch("user_activity_api.record_user_activity", side_effect=ActivityRequestError("activity_session_required", "Start first.", 409)):
            response = self.client.post("/account/activity", json={})
        self.assertEqual(response.status_code, 409)
        self.assertEqual(response.json["error"]["code"], "activity_session_required")
        with patch("user_activity_api.verify_identity", return_value=IDENTITY), \
                patch("user_activity_api.record_user_activity", side_effect=AdminAuthorizationError("account_access_denied", "Suspended.", 403)):
            response = self.client.post("/account/activity", json={})
        self.assertEqual(response.status_code, 403)


if __name__ == "__main__":
    unittest.main()
