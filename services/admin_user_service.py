from __future__ import annotations

import re
import uuid
from datetime import datetime, timezone
from itertools import islice
from math import isfinite
from types import SimpleNamespace
from typing import Any

from firebase_admin import auth, firestore

from .admin_auth import AdminAuthorizationError, effective_assigned_role
from .firebase_service import firestore_client
from .membership_service import (
    PROFILE_FIELDS, ROLES, MembershipConflictError, access_payload,
    account_status, auth_creation_time, initialize_membership_policy, membership_revision,
    parse_guest_expiry, parse_subscription_expiry, resolved_membership, snapshot_data, utc_now,
)


class AccountActionIncompleteError(RuntimeError):
    """The account remains denied while an administrator retries cleanup."""


def _serializable_preferences(value, depth=0):
    if depth > 12:
        return None
    if value is None or isinstance(value, (str, bool, int)):
        return value
    if isinstance(value, float):
        return value if isfinite(value) else None
    if isinstance(value, datetime):
        return value.isoformat()
    if isinstance(value, dict):
        return {str(key): _serializable_preferences(item, depth + 1) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [_serializable_preferences(item, depth + 1) for item in value]
    return None


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
    preferences = profile.get("preferences")
    status = access["accountStatus"]
    return {**access, "displayName": _name(profile, user), "email": user.email or "",
            "disabled": bool(user.disabled), "emailVerified": bool(user.email_verified),
            "createdAt": _timestamp(metadata.creation_timestamp) if metadata else None,
            "lastSignInAt": _timestamp(metadata.last_sign_in_timestamp) if metadata else None,
            "preferences": _serializable_preferences(preferences) if isinstance(preferences, dict) else {},
            "preferencesSource": "saved_profile" if isinstance(preferences, dict) else "not_saved",
            "profileCompleted": profile.get("profileCompleted") is True,
            "isCurrentUser": user.uid == current_user_uid,
            "canEditAccess": user.uid != current_user_uid and status not in {"deleting", "deleted"},
            "canManageAccount": user.uid != current_user_uid and status != "deleted",
            "revision": membership_revision(membership_snapshot, profile_snapshot)}


def _validate_uid(uid):
    if not isinstance(uid, str) or not uid or len(uid) > 128 or "/" in uid or any(ord(c) < 32 for c in uid):
        raise ValueError("User identifier is invalid.")


def _validate_revision(revision):
    if not isinstance(revision, str) or not re.fullmatch(r"[a-f0-9]{64}", revision):
        raise ValueError("Reload the user before changing access; its revision is required.")


def _require_actor(transaction, database, actor):
    member = snapshot_data(database.collection("memberships").document(actor["uid"]).get(transaction=transaction))
    profile = snapshot_data(database.collection("users").document(actor["uid"]).get(transaction=transaction)) or {}
    role, _ = effective_assigned_role(profile, actor.get("claims", {}), member)
    if role != "admin" or account_status(member) != "active":
        raise AdminAuthorizationError("admin_required", "Your administrator access changed. Reload your account.", 403)


def _access_audit(resolved):
    return {key: resolved.get(key) for key in ("role", "guestExpiresAt", "subscriptionPermanent",
                                             "subscriptionExpiresAt", "accountStatus")}


def _deleted_account(uid):
    return SimpleNamespace(uid=uid, email="", display_name="", disabled=True,
                           email_verified=False, custom_claims={}, user_metadata=None)


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
    profile = database.collection("users").document(uid).get()
    membership = database.collection("memberships").document(uid).get()
    try:
        account = (get_user or auth.get_user)(uid)
    except auth.UserNotFoundError:
        if account_status(snapshot_data(membership)) not in {"deleting", "deleted"}:
            raise
        account = _deleted_account(uid)
    policy = initialize_membership_policy(db=database, now=moment)
    return _user_payload(account, profile, membership, policy=policy, current_user_uid=current_user_uid, now=moment)


def update_admin_user(uid, payload, *, actor, db=None, get_user=None, now=None):
    _validate_uid(uid)
    if not isinstance(payload, dict) or set(payload) - {"revision", "role", "guestExpiresAt", "guestExpiresOn",
                                                       "subscriptionPermanent", "subscriptionExpiresAt", "subscriptionExpiresOn"}:
        raise ValueError("Provide role, revision, and the access end date when applicable.")
    role = payload.get("role")
    if not isinstance(role, str) or role not in ROLES:
        raise ValueError("Role must be guest, subscribed, or admin.")
    revision = payload.get("revision")
    _validate_revision(revision)
    if uid == actor["uid"]:
        raise AdminAuthorizationError("self_access_change_forbidden", "You cannot change your own access. Ask another administrator.", 403)
    expiry = parse_guest_expiry(payload) if role == "guest" else None
    if "subscriptionPermanent" in payload and not isinstance(payload["subscriptionPermanent"], bool):
        raise ValueError("Subscription permanent must be true or false.")
    # An older client omitting subscription fields preserves an existing mode;
    # converting a different role to subscribed defaults to permanent.
    permanent = payload.get("subscriptionPermanent") if role == "subscribed" else False
    subscription_expiry = parse_subscription_expiry(payload) if role == "subscribed" and permanent is False else None
    if role == "subscribed" and permanent is not False and any(key in payload for key in ("subscriptionExpiresAt", "subscriptionExpiresOn")):
        raise ValueError("Set subscription permanent to false before providing an access end date.")
    database = db if db is not None else firestore_client()
    moment = now or utc_now()
    target_account = (get_user or auth.get_user)(uid)
    policy = initialize_membership_policy(db=database, now=moment)
    member_ref = database.collection("memberships").document(uid)
    profile_ref = database.collection("users").document(uid)
    audit_ref = database.collection("admin_membership_edits").document(uuid.uuid4().hex)

    @firestore.transactional
    def apply(transaction):
        target_member = member_ref.get(transaction=transaction)
        target_profile = profile_ref.get(transaction=transaction)
        _require_actor(transaction, database, actor)
        if membership_revision(target_member, target_profile) != revision:
            raise MembershipConflictError("This user's access changed. Reload the user before saving.")
        if account_status(snapshot_data(target_member)) in {"deleting", "deleted"}:
            raise MembershipConflictError("This account is being deleted. Complete deletion before making other changes.")
        before = resolved_membership(snapshot_data(target_profile) or {}, target_account.custom_claims or {},
                                     snapshot_data(target_member), created_at=auth_creation_time(target_account), policy=policy, now=moment)
        chosen_permanent = permanent if permanent is not None else before["subscriptionPermanent"] if before["role"] == "subscribed" else True
        chosen_subscription_expiry = before["subscriptionExpiresAt"] if role == "subscribed" and permanent is None and before["role"] == "subscribed" else subscription_expiry
        fields = {"role": role, "guestExpiresAt": expiry, "updatedAt": moment, "updatedBy": actor["uid"],
                  "subscriptionPermanent": chosen_permanent, "subscriptionExpiresAt": chosen_subscription_expiry,
                  "origin": "admin_assignment"}
        if not target_member.exists:
            fields["assignedAt"] = moment
        transaction.set(member_ref, fields, merge=list(fields))
        transaction.set(audit_ref, {"actorUid": actor["uid"], "targetUid": uid, "createdAt": moment,
                                    "action": "update_access", "outcome": "completed",
                                    "before": _access_audit(before),
                                    "after": _access_audit({**before, **fields})})
    apply(database.transaction())
    return _user_payload(target_account, profile_ref.get(), member_ref.get(), policy=policy,
                         current_user_uid=actor["uid"], now=moment)


def _delete_activity(database, uid):
    activity = database.collection("user_activity").document(uid)
    for name in ("sessions", "logins"):
        collection = activity.collection(name)
        while True:
            snapshots = list(islice(collection.limit(200).stream(), 200))
            if not snapshots:
                break
            batch = database.batch()
            for snapshot in snapshots:
                batch.delete(collection.document(snapshot.id))
            batch.commit()
    activity.delete()


def perform_admin_user_action(uid, payload, *, actor, db=None, get_user=None,
                              revoke_tokens=None, delete_user=None, now=None):
    _validate_uid(uid)
    if not isinstance(payload, dict) or set(payload) != {"action", "revision", "confirmation"}:
        raise ValueError("Provide action, revision, and the confirmed user identifier.")
    action = payload.get("action")
    if not isinstance(action, str) or action not in {"suspend", "resume", "terminate", "delete"}:
        raise ValueError("Action must be suspend, resume, terminate, or delete.")
    if payload.get("confirmation") != uid:
        raise ValueError("Confirm the exact user identifier before changing this account.")
    _validate_revision(payload.get("revision"))
    if uid == actor["uid"]:
        raise AdminAuthorizationError("self_account_action_forbidden", "You cannot change your own account. Ask another administrator.", 403)
    database = db if db is not None else firestore_client()
    moment = now or utc_now()
    member_ref = database.collection("memberships").document(uid)
    profile_ref = database.collection("users").document(uid)
    existing = snapshot_data(member_ref.get())
    try:
        account = (get_user or auth.get_user)(uid)
    except auth.UserNotFoundError:
        if action != "delete" or account_status(existing) not in {"deleting", "deleted"}:
            raise
        account = None
    policy = initialize_membership_policy(db=database, now=moment)
    audit_ref = database.collection("admin_membership_edits").document(uuid.uuid4().hex)
    desired_status = {"suspend": "suspended", "resume": "active", "terminate": "terminated", "delete": "deleting"}[action]

    @firestore.transactional
    def reserve(transaction):
        member_snapshot = member_ref.get(transaction=transaction)
        profile_snapshot = profile_ref.get(transaction=transaction)
        _require_actor(transaction, database, actor)
        if membership_revision(member_snapshot, profile_snapshot) != payload["revision"]:
            raise MembershipConflictError("This user's access changed. Reload the user before continuing.")
        member = snapshot_data(member_snapshot)
        status = account_status(member)
        if status in {"deleting", "deleted"} and action != "delete":
            raise MembershipConflictError("Deletion has already started. Only deletion can be retried.")
        if action == "resume" and status == "active":
            raise ValueError("This account is already active.")
        before = resolved_membership(snapshot_data(profile_snapshot) or {}, getattr(account, "custom_claims", {}) or {},
                                     member, created_at=auth_creation_time(account), policy=policy, now=moment)
        fields = {**before, "accountStatus": desired_status, "updatedAt": moment, "updatedBy": actor["uid"],
                  "origin": "admin_account_action"}
        fields.pop("roleSource", None)
        if not member_snapshot.exists:
            fields["assignedAt"] = moment
        if action == "delete":
            fields["deletionOperationId"] = audit_ref.id
        transaction.set(member_ref, fields, merge=list(fields))
        transaction.set(audit_ref, {"actorUid": actor["uid"], "targetUid": uid, "createdAt": moment,
                                    "action": action, "outcome": "pending" if action in {"delete", "terminate"} else "completed",
                                    "before": _access_audit(before), "after": _access_audit(fields)})
    reserve(database.transaction())

    if action in {"delete", "terminate"}:
        try:
            if account is not None:
                (revoke_tokens or auth.revoke_refresh_tokens)(uid)
            if action == "delete":
                # Denial is committed first. Activity transactions read that same
                # membership, so they cannot recreate records during cleanup.
                _delete_activity(database, uid)
                profile_ref.delete()
                try:
                    (delete_user or auth.delete_user)(uid)
                except auth.UserNotFoundError:
                    pass  # A previous attempt or external deletion already removed Auth.
                # Keep a minimal server-owned tombstone to deny cached Firestore
                # tokens and prevent the old profile from being recreated.
                member_ref.set({"role": "guest", "accountStatus": "deleted", "guestExpiresAt": None,
                                "updatedAt": moment, "updatedBy": actor["uid"], "deletedAt": moment})
            audit_ref.set({"outcome": "completed", "completedAt": moment,
                           "after": {"accountStatus": "deleted" if action == "delete" else desired_status}}, merge=True)
        except Exception as exc:
            # Never restore access on an upstream failure. The directory/detail
            # shows deleting, and a fresh confirmed action safely retries cleanup.
            try:
                audit_ref.set({"outcome": "failed", "failedAt": moment}, merge=True)
            except Exception:
                pass
            raise AccountActionIncompleteError("The account is blocked, but the action could not be completed. Reload the user and retry.") from exc
    if action == "delete":
        return {"deleted": True, "uid": uid}
    user = _user_payload(account, profile_ref.get(), member_ref.get(), policy=policy,
                         current_user_uid=actor["uid"], now=moment)
    return {"user": user}
