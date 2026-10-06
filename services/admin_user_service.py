from __future__ import annotations

import re
import uuid
from datetime import datetime, timezone
from typing import Any

from firebase_admin import auth, firestore

from .admin_auth import AdminAuthorizationError, effective_assigned_role
from .firebase_service import firestore_client
from .membership_service import (
    PROFILE_FIELDS, ROLES, MembershipConflictError, access_payload,
    auth_creation_time, initialize_membership_policy, membership_revision,
    parse_guest_expiry, resolved_membership, snapshot_data, utc_now,
)


def _timestamp(milliseconds):
    return datetime.fromtimestamp(milliseconds / 1000, timezone.utc).isoformat() if milliseconds is not None else None


def _name(profile: dict[str, Any], user) -> str:
    for value in (profile.get("displayName"),
                  " ".join(str(profile.get(k) or "").strip() for k in ("firstName", "lastName")),
                  profile.get("fullName"), user.display_name):
        if isinstance(value, str) and value.strip():
            return value.strip()
    return ""


def _user_payload(user, profile_snapshot, membership_snapshot, *, policy, current_user_uid, now):
    profile = snapshot_data(profile_snapshot) or {}
    resolved = resolved_membership(profile, user.custom_claims or {}, snapshot_data(membership_snapshot),
                                   created_at=auth_creation_time(user), policy=policy, now=now)
    access = access_payload(user.uid, resolved, now=now, disabled=bool(user.disabled))
    metadata = user.user_metadata
    return {**access, "displayName": _name(profile, user), "email": user.email or "",
            "disabled": bool(user.disabled), "emailVerified": bool(user.email_verified),
            "createdAt": _timestamp(metadata.creation_timestamp) if metadata else None,
            "lastSignInAt": _timestamp(metadata.last_sign_in_timestamp) if metadata else None,
            "isCurrentUser": user.uid == current_user_uid, "canEditAccess": user.uid != current_user_uid,
            "revision": membership_revision(membership_snapshot, profile_snapshot)}


def _validate_uid(uid):
    if not isinstance(uid, str) or not uid or len(uid) > 128 or "/" in uid or any(ord(c) < 32 for c in uid):
        raise ValueError("User identifier is invalid.")


def list_admin_users(*, page_size=50, page_token=None, current_user_uid, db=None, fetch_users=None, now=None):
    if not 1 <= page_size <= 100:
        raise ValueError("Page size must be between 1 and 100.")
    if page_token is not None and (not page_token or len(page_token) > 4096):
        raise ValueError("The page token is invalid. Refresh the user list.")
    database = db if db is not None else firestore_client()
    moment = now or utc_now()
    policy = initialize_membership_policy(db=database, now=moment)
    page = (fetch_users or auth.list_users)(page_token=page_token, max_results=page_size)
    accounts = list(page.users)
    profiles, members = {}, {}
    if accounts:
        profiles = {s.id: s for s in database.get_all(
            [database.collection("users").document(u.uid) for u in accounts], field_paths=PROFILE_FIELDS)}
        members = {s.id: s for s in database.get_all(
            [database.collection("memberships").document(u.uid) for u in accounts])}
    users = [_user_payload(u, profiles[u.uid], members[u.uid], policy=policy,
                           current_user_uid=current_user_uid, now=moment) for u in accounts]
    return {"users": users, "nextPageToken": page.next_page_token or None,
            "rolloutAt": policy["rolloutAt"].isoformat() if isinstance(policy["rolloutAt"], datetime) else str(policy["rolloutAt"])}


def get_admin_user(uid, *, current_user_uid, db=None, get_user=None, now=None):
    _validate_uid(uid)
    database = db if db is not None else firestore_client()
    moment = now or utc_now()
    account = (get_user or auth.get_user)(uid)
    profile = database.collection("users").document(uid).get()
    membership = database.collection("memberships").document(uid).get()
    policy = initialize_membership_policy(db=database, now=moment)
    return _user_payload(account, profile, membership, policy=policy, current_user_uid=current_user_uid, now=moment)


def update_admin_user(uid, payload, *, actor, db=None, get_user=None, now=None):
    _validate_uid(uid)
    if not isinstance(payload, dict) or set(payload) - {"revision", "role", "guestExpiresAt", "guestExpiresOn"}:
        raise ValueError("Provide role, revision, and the guest end date when applicable.")
    role = payload.get("role")
    if not isinstance(role, str) or role not in ROLES:
        raise ValueError("Role must be guest, subscribed, or admin.")
    revision = payload.get("revision")
    if not isinstance(revision, str) or not re.fullmatch(r"[a-f0-9]{64}", revision):
        raise ValueError("Reload the user before changing access; its revision is required.")
    if uid == actor["uid"]:
        raise AdminAuthorizationError("self_access_change_forbidden", "You cannot change your own access. Ask another administrator.", 403)
    expiry = parse_guest_expiry(payload) if role == "guest" else None
    database = db if db is not None else firestore_client()
    moment = now or utc_now()
    target_account = (get_user or auth.get_user)(uid)
    policy = initialize_membership_policy(db=database, now=moment)
    member_ref = database.collection("memberships").document(uid)
    profile_ref = database.collection("users").document(uid)
    actor_member_ref = database.collection("memberships").document(actor["uid"])
    actor_profile_ref = database.collection("users").document(actor["uid"])
    audit_ref = database.collection("admin_membership_edits").document(uuid.uuid4().hex)

    @firestore.transactional
    def apply(transaction):
        target_member = member_ref.get(transaction=transaction)
        target_profile = profile_ref.get(transaction=transaction)
        actor_member = snapshot_data(actor_member_ref.get(transaction=transaction))
        actor_profile = snapshot_data(actor_profile_ref.get(transaction=transaction)) or {}
        actor_role, _ = effective_assigned_role(actor_profile, actor.get("claims", {}), actor_member)
        if actor_role != "admin":
            raise AdminAuthorizationError("admin_required", "Your administrator access changed. Reload your account.", 403)
        if membership_revision(target_member, target_profile) != revision:
            raise MembershipConflictError("This user's access changed. Reload the user before saving.")
        before = resolved_membership(snapshot_data(target_profile) or {}, target_account.custom_claims or {},
                                     snapshot_data(target_member), created_at=auth_creation_time(target_account), policy=policy, now=moment)
        fields = {"role": role, "guestExpiresAt": expiry, "updatedAt": moment, "updatedBy": actor["uid"],
                  "origin": "admin_assignment"}
        if not target_member.exists:
            fields["assignedAt"] = moment
        transaction.set(member_ref, fields, merge=list(fields))
        transaction.set(audit_ref, {"actorUid": actor["uid"], "targetUid": uid, "createdAt": moment,
                                    "before": {"role": before["role"], "guestExpiresAt": before["guestExpiresAt"]},
                                    "after": {"role": role, "guestExpiresAt": expiry}})
    apply(database.transaction())
    return _user_payload(target_account, profile_ref.get(), member_ref.get(), policy=policy,
                         current_user_uid=actor["uid"], now=moment)
