"""Observed sign-ins and an estimate of foreground interaction time.

The client reports cumulative seconds, never identity or timestamps. Counters
are updated transactionally, so retries and token refreshes do not create extra
sessions or sign-ins. This is engagement telemetry, not an attendance record.
"""
from __future__ import annotations

import base64
import binascii
import json
import math
import re
from dataclasses import dataclass
from datetime import datetime, timezone

from firebase_admin import auth, firestore

from .admin_auth import AdminAuthorizationError
from .firebase_service import firestore_client
from .membership_service import as_datetime, snapshot_data, utc_now

MAX_SESSION_SECONDS = 24 * 60 * 60
CLOCK_ALLOWANCE_SECONDS = 5
SESSION_ID = re.compile(r"[A-Za-z0-9_-]{8,64}")


@dataclass
class ActivityRequestError(ValueError):
    code: str
    message: str
    status: int = 400

    def __str__(self):
        return self.message


def _validate_uid(uid):
    if (not isinstance(uid, str) or not uid or len(uid) > 128 or "/" in uid
            or uid in {".", ".."} or any(ord(c) < 32 for c in uid)):
        raise ValueError("User identifier is invalid.")


def _validate_event(payload):
    if not isinstance(payload, dict) or set(payload) != {"sessionId", "event", "activeSeconds"}:
        raise ActivityRequestError("invalid_activity", "Provide a session identifier, event, and cumulative active seconds.")
    identifier = payload["sessionId"]
    if not isinstance(identifier, str) or SESSION_ID.fullmatch(identifier) is None:
        raise ActivityRequestError("invalid_activity", "The activity session identifier is invalid.")
    event = payload["event"]
    if not isinstance(event, str) or event not in {"start", "heartbeat", "end"}:
        raise ActivityRequestError("invalid_activity", "Activity event must be start, heartbeat, or end.")
    seconds = payload["activeSeconds"]
    if type(seconds) is not int or not 0 <= seconds <= MAX_SESSION_SECONDS:
        raise ActivityRequestError("invalid_activity", "Active seconds must be a whole number between 0 and 86400.")
    if event == "start" and seconds != 0:
        raise ActivityRequestError("invalid_activity", "A new session starts with zero active seconds.")
    return identifier, event, seconds


def _signin(identity, moment):
    stamp = (identity.get("claims") or {}).get("auth_time")
    if type(stamp) is not int or stamp < 0 or stamp > moment.timestamp() + 300:
        raise AdminAuthorizationError("invalid_token", "The authenticated sign-in timestamp is missing or invalid.", 401)
    try:
        return str(stamp), datetime.fromtimestamp(stamp, timezone.utc)
    except (OverflowError, OSError, ValueError) as exc:
        raise AdminAuthorizationError("invalid_token", "The authenticated sign-in timestamp is invalid.", 401) from exc


def _number(data, field):
    value = data.get(field)
    return value if type(value) is int and value >= 0 else 0


def _iso(value):
    moment = as_datetime(value)
    return moment.isoformat() if moment else None


def _summary_payload(data):
    return {"lastActiveAt": _iso(data.get("lastActiveAt")),
            "totalActiveSeconds": _number(data, "totalActiveSeconds"),
            "sessionCount": _number(data, "sessionCount"),
            "loginCount": _number(data, "loginCount"),
            "trackingStartedAt": _iso(data.get("trackingStartedAt"))}


def _session_payload(identifier, data):
    return {"id": identifier, "startedAt": _iso(data.get("startedAt")),
            "lastActiveAt": _iso(data.get("lastActiveAt")),
            "endedAt": _iso(data.get("endedAt")),
            "activeSeconds": _number(data, "activeSeconds")}


def record_user_activity(identity, payload, *, db=None, get_user=None, now=None):
    """Record only the verified account; lifecycle checks share the write transaction.

    Auth must still exist even for a user with a membership document. A retained
    membership tombstone protects against an in-flight request racing deletion.
    Summary time is capped across sessions to avoid counting concurrent tabs
    twice. Individual session estimates remain useful for inspecting each visit.
    """
    uid = identity["uid"]
    _validate_uid(uid)
    identifier, event, reported_seconds = _validate_event(payload)
    moment = as_datetime(now or utc_now())
    login_id, signed_in_at = _signin(identity, moment)
    account = (get_user or auth.get_user)(uid)
    if account.disabled:
        raise AdminAuthorizationError("account_access_denied", "This account is disabled.", 403)
    database = db if db is not None else firestore_client()
    member_ref = database.collection("memberships").document(uid)
    activity_ref = database.collection("user_activity").document(uid)
    session_ref = activity_ref.collection("sessions").document(identifier)
    login_ref = activity_ref.collection("logins").document(login_id)

    @firestore.transactional
    def record(transaction):
        # Firestore requires all reads before the first write.
        member = snapshot_data(member_ref.get(transaction=transaction)) or {}
        summary = snapshot_data(activity_ref.get(transaction=transaction)) or {}
        session = snapshot_data(session_ref.get(transaction=transaction))
        login = snapshot_data(login_ref.get(transaction=transaction))
        status = member.get("accountStatus", "active")
        if status != "active":
            raise AdminAuthorizationError("account_access_denied", "This account cannot record activity.", 403)
        if session is None and event != "start":
            raise ActivityRequestError("activity_session_required", "Start a new activity session before sending updates.", 409)

        is_new_session = session is None
        if is_new_session:
            session = {"startedAt": moment, "lastActiveAt": moment, "endedAt": None,
                       "activeSeconds": 0, "reportedActiveSeconds": 0, "lastReportedAt": moment}
        started_at = as_datetime(session.get("startedAt"))
        if started_at is None:
            raise ActivityRequestError("activity_session_invalid", "Start a new activity session.", 409)
        elapsed = max(0, math.floor((moment - started_at).total_seconds()))
        if elapsed >= MAX_SESSION_SECONDS and event != "end" and not session.get("endedAt"):
            raise ActivityRequestError("activity_session_expired", "Start a new activity session after 24 hours.", 409)

        session_delta = 0
        if not session.get("endedAt") and event != "start":
            previous_reported = _number(session, "reportedActiveSeconds")
            previous_active = _number(session, "activeSeconds")
            report_at = as_datetime(session.get("lastReportedAt")) or started_at
            report_elapsed = max(0, math.floor((moment - report_at).total_seconds()))
            # A high watermark consumes rejected excess too: replaying a forged
            # cumulative value later cannot gradually turn it into credited time.
            requested_delta = max(0, reported_seconds - previous_reported)
            wall_budget = max(0, min(MAX_SESSION_SECONDS, elapsed + CLOCK_ALLOWANCE_SECONDS) - previous_active)
            session_delta = min(requested_delta, report_elapsed + CLOCK_ALLOWANCE_SECONDS, wall_budget)
            session["reportedActiveSeconds"] = max(previous_reported, reported_seconds)
            session["activeSeconds"] = previous_active + session_delta
            session["lastReportedAt"] = max(report_at, moment)
            if session_delta > 0:
                session["lastActiveAt"] = max(as_datetime(session.get("lastActiveAt")) or started_at, moment)
            if event == "end":
                session["endedAt"] = max(session["lastReportedAt"], as_datetime(session.get("lastActiveAt")) or started_at, moment)

        previous_report_at = as_datetime(summary.get("lastReportedAt")) or moment
        user_elapsed = max(0, math.floor((moment - previous_report_at).total_seconds()))
        remaining_allowance = min(CLOCK_ALLOWANCE_SECONDS, _number(summary, "creditAllowanceRemaining")) if summary else CLOCK_ALLOWANCE_SECONDS
        credited_delta = min(session_delta, user_elapsed + remaining_allowance)
        remaining_allowance -= max(0, credited_delta - user_elapsed)
        result_summary = {**summary,
                          "trackingStartedAt": as_datetime(summary.get("trackingStartedAt")) or moment,
                          "totalActiveSeconds": _number(summary, "totalActiveSeconds") + credited_delta,
                          "sessionCount": _number(summary, "sessionCount") + int(is_new_session),
                          "loginCount": _number(summary, "loginCount") + int(login is None),
                          "lastReportedAt": max(moment, previous_report_at) if credited_delta > 0 else previous_report_at,
                          "creditAllowanceRemaining": remaining_allowance}
        if is_new_session or session_delta > 0:
            result_summary["lastActiveAt"] = max(as_datetime(summary.get("lastActiveAt")) or moment, moment)

        transaction.set(activity_ref, result_summary)
        transaction.set(session_ref, session)
        if login is None:
            transaction.set(login_ref, {"signedInAt": signed_in_at, "recordedAt": moment})
        return {"summary": _summary_payload(result_summary),
                "session": _session_payload(identifier, session),
                "maxSessionSeconds": MAX_SESSION_SECONDS}

    return record(database.transaction())


def _decode_cursor(token, uid):
    if not isinstance(token, str) or not token or len(token) > 1024:
        raise ValueError("The activity page token is invalid. Reload activity.")
    try:
        raw = base64.b64decode(token + "=" * (-len(token) % 4), altchars=b"-_", validate=True)
        value = json.loads(raw.decode("utf-8"))
        if (not isinstance(value, dict) or set(value) != {"v", "uid", "sessions", "logins"}
                or type(value["v"]) is not int or value["v"] != 1 or value["uid"] != uid):
            raise ValueError()
        positions = {}
        for collection, field in (("sessions", "startedAt"), ("logins", "signedInAt")):
            cursor = value[collection]
            # A null position marks a fully consumed collection so an exhausted
            # login history does not restart while sessions continue paging.
            if cursor is None:
                positions[collection] = None
                continue
            if (not isinstance(cursor, dict) or set(cursor) != {"id", field}
                    or not isinstance(cursor["id"], str)
                    or not isinstance(cursor[field], str) or len(cursor[field]) > 40):
                raise ValueError()
            identifier = cursor["id"]
            if collection == "sessions":
                if SESSION_ID.fullmatch(identifier) is None:
                    raise ValueError()
            elif re.fullmatch(r"[0-9]{1,12}", identifier) is None:
                raise ValueError()
            moment = as_datetime(cursor[field])
            if moment is None:
                raise ValueError()
            if collection == "logins" and moment.timestamp() != int(identifier):
                raise ValueError()
            positions[collection] = (identifier, moment)
        if all(position is None for position in positions.values()):
            raise ValueError()
        return positions
    except (ValueError, TypeError, UnicodeError, binascii.Error, OverflowError) as exc:
        raise ValueError("The activity page token is invalid. Reload activity.") from exc


def _encode_cursor(uid, positions):
    value = {"v": 1, "uid": uid, **positions}
    return base64.urlsafe_b64encode(json.dumps(value, separators=(",", ":")).encode()).decode().rstrip("=")


def get_user_activity(uid, *, page_size=20, page_token=None, db=None, get_user=None):
    _validate_uid(uid)
    if type(page_size) is not int or not 1 <= page_size <= 100:
        raise ValueError("Page size must be between 1 and 100.")
    cursor = _decode_cursor(page_token, uid) if page_token is not None else None
    (get_user or auth.get_user)(uid)
    database = db if db is not None else firestore_client()
    activity_ref = database.collection("user_activity").document(uid)
    summary = snapshot_data(activity_ref.get()) or {}
    pages, positions = {}, {}
    for collection, field in (("sessions", "startedAt"), ("logins", "signedInAt")):
        if cursor is not None and cursor[collection] is None:
            pages[collection] = []
            positions[collection] = None
            continue
        reference = activity_ref.collection(collection)
        # The document-name tie breaker follows the field's direction, using
        # the automatic descending single-field index for equal timestamps.
        query = reference.order_by(field, direction=firestore.Query.DESCENDING).order_by(
            "__name__", direction=firestore.Query.DESCENDING)
        if cursor is not None:
            identifier, moment = cursor[collection]
            query = query.start_after({field: moment, "__name__": reference.document(identifier)})
        snapshots = list(query.limit(page_size + 1).stream())
        visible = snapshots[:page_size]
        pages[collection] = visible
        positions[collection] = ({"id": visible[-1].id, field: _iso(visible[-1].to_dict().get(field))}
                                 if len(snapshots) > page_size else None)
    return {"summary": _summary_payload(summary),
            "sessions": [_session_payload(s.id, s.to_dict() or {}) for s in pages["sessions"]],
            "logins": [{"id": s.id, "signedInAt": _iso((s.to_dict() or {}).get("signedInAt"))} for s in pages["logins"]],
            "nextPageToken": _encode_cursor(uid, positions) if any(positions.values()) else None}
