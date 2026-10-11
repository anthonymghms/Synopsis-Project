"""Server-owned access roles, guest expiry, and deterministic rollout policy."""
from __future__ import annotations

import hashlib
import json
import os
from datetime import date, datetime, time, timedelta, timezone
from typing import Any
from zoneinfo import ZoneInfo

from firebase_admin import auth, firestore

from .admin_auth import AdminAuthorizationError, effective_assigned_role, verify_identity
from .firebase_service import firestore_client

DEFAULT_GUEST_DAYS = 30
ROLES = {"guest", "subscribed", "admin"}
PROFILE_FIELDS = ["displayName", "firstName", "lastName", "fullName", "role", "preferences", "profileCompleted"]
ACCOUNT_STATUSES = {"active", "suspended", "terminated", "deleting", "deleted"}


class MembershipConflictError(ValueError):
    pass


def utc_now():
    return datetime.now(timezone.utc)


def as_datetime(value):
    if isinstance(value, datetime):
        return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value.astimezone(timezone.utc)
    if isinstance(value, str):
        try:
            parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
            return parsed.astimezone(timezone.utc) if parsed.tzinfo else None
        except (ValueError, OverflowError):
            return None
    return None


def snapshot_data(snapshot):
    return (snapshot.to_dict() or {}) if snapshot.exists else None


def _snapshot_token(snapshot):
    return {"exists": snapshot.exists, "data": snapshot_data(snapshot),
            "updatedAt": str(getattr(snapshot, "update_time", ""))}


def membership_revision(member_snapshot, profile_snapshot):
    # Profile projection must match listing/get/update, even when profile data
    # unrelated to permissions changes. Use role only and the full member doc.
    value = {"membership": _snapshot_token(member_snapshot),
             "profileRole": (snapshot_data(profile_snapshot) or {}).get("role")}
    return hashlib.sha256(json.dumps(value, sort_keys=True, default=str).encode()).hexdigest()


def expiry_timezone():
    return ZoneInfo(os.environ.get("MEMBERSHIP_TIMEZONE", "Asia/Beirut"))


def initialize_membership_policy(*, db=None, now=None):
    """Persist a single rollout boundary; server restarts never move it.

    Deployments may set MEMBERSHIP_LEGACY_CUTOFF to an explicit offset-aware
    ISO timestamp before first use, or call this helper at rollout. Otherwise
    the first account-access/user-directory request establishes the boundary.
    """
    database = db if db is not None else firestore_client()
    reference = database.collection("membership_config").document("default")
    snapshot = reference.get()
    existing = snapshot_data(snapshot)
    if existing and as_datetime(existing.get("rolloutAt")):
        return existing
    moment = now or utc_now()
    configured = os.environ.get("MEMBERSHIP_LEGACY_CUTOFF")
    cutoff = as_datetime(configured) if configured else moment
    if cutoff is None:
        raise ValueError("MEMBERSHIP_LEGACY_CUTOFF must be an ISO timestamp with a timezone.")

    @firestore.transactional
    def initialize(transaction):
        current = snapshot_data(reference.get(transaction=transaction))
        if current:
            if as_datetime(current.get("rolloutAt")) is None:
                raise ValueError("Membership rollout policy is invalid; administrator repair is required.")
            return current
        policy = {"rolloutAt": cutoff, "defaultGuestDays": DEFAULT_GUEST_DAYS,
                  "createdAt": moment, "policyVersion": 1}
        transaction.set(reference, policy)
        return policy
    return initialize(database.transaction())


def auth_creation_time(user):
    metadata = getattr(user, "user_metadata", None)
    stamp = getattr(metadata, "creation_timestamp", None)
    return datetime.fromtimestamp(stamp / 1000, timezone.utc) if stamp is not None else None


def account_status(membership):
    status = (membership or {}).get("accountStatus", "active")
    return status if isinstance(status, str) and status in ACCOUNT_STATUSES else "terminated"


def resolved_membership(profile, claims, membership, *, created_at, policy, now):
    role, source = effective_assigned_role(profile, claims, membership)
    expiration = as_datetime((membership or {}).get("guestExpiresAt"))
    if role is None:
        rollout = as_datetime(policy.get("rolloutAt"))
        if created_at is not None and rollout is not None and created_at <= rollout:
            role, source = "subscribed", "legacy_account"
        else:
            role, source = "guest", "new_account"
    if role == "guest" and membership is None:
        # Never start a fresh trial on each login. Auth creation is server-owned.
        expiration = as_datetime((profile or {}).get("guestExpiresAt")) or ((created_at or now) + timedelta(days=DEFAULT_GUEST_DAYS))
    permanent = (membership or {}).get("subscriptionPermanent", True) is True
    return {"role": role, "roleSource": source, "guestExpiresAt": expiration if role == "guest" else None,
            "subscriptionPermanent": permanent if role == "subscribed" else False,
            "subscriptionExpiresAt": as_datetime((membership or {}).get("subscriptionExpiresAt")) if role == "subscribed" and not permanent else None,
            "accountStatus": account_status(membership)}


def access_payload(uid, resolved, *, now=None, disabled=False):
    moment = now or utc_now()
    expiry = as_datetime(resolved.get("guestExpiresAt"))
    role = resolved["role"]
    expired = role == "guest" and (expiry is None or expiry <= moment)
    permanent = resolved.get("subscriptionPermanent", True) is True
    subscription_expiry = as_datetime(resolved.get("subscriptionExpiresAt")) if role == "subscribed" and not permanent else None
    subscription_expired = role == "subscribed" and not permanent and (subscription_expiry is None or subscription_expiry <= moment)
    status = account_status(resolved)
    can_read = not disabled and status == "active" and not expired and not subscription_expired and role in ROLES
    permissions = [] if disabled or status in {"deleting", "deleted"} else ["manage_own_profile"]
    if can_read:
        permissions.insert(0, "read_content")
    if can_read and role == "admin":
        permissions += ["manage_content", "view_import_history", "view_users", "manage_users"]
    zone = expiry_timezone()
    last_day = (expiry - timedelta(microseconds=1)).astimezone(zone).date().isoformat() if expiry else None
    subscription_last_day = (subscription_expiry - timedelta(microseconds=1)).astimezone(zone).date().isoformat() if subscription_expiry else None
    suggested = (moment.astimezone(zone).date() + timedelta(days=DEFAULT_GUEST_DAYS)).isoformat()
    return {"uid": uid, "role": role, "roleSource": resolved.get("roleSource", "membership"),
            "guestExpiresAt": expiry.isoformat() if expiry else None, "guestExpiresOn": last_day,
            "guestExpired": expired, "canRead": can_read,
            "subscriptionPermanent": permanent if role == "subscribed" else False,
            "subscriptionExpiresAt": subscription_expiry.isoformat() if subscription_expiry else None,
            "subscriptionExpiresOn": subscription_last_day, "subscriptionExpired": subscription_expired,
            "accountStatus": status,
            "accessStatus": status if status != "active" else "disabled" if disabled else "expired" if expired or subscription_expired else "active",
            "permissions": permissions, "serverTime": moment.isoformat(),
            "expiryTimezone": str(zone),
            "suggestedGuestExpiresOn": suggested, "suggestedSubscriptionExpiresOn": suggested}


def get_account_access(identity, *, db=None, get_user=None, now=None):
    database = db if db is not None else firestore_client()
    moment = now or utc_now()
    uid = identity["uid"]
    # Check Auth on every access request, including initialized memberships.
    # This prevents disabled/deleted accounts using an otherwise valid role.
    user = (get_user or auth.get_user)(uid)
    member_ref = database.collection("memberships").document(uid)
    member_snapshot = member_ref.get()
    member = snapshot_data(member_snapshot)
    if member is not None:
        role, source = effective_assigned_role({}, {}, member)
        return access_payload(uid, {**member, "role": role, "roleSource": source}, now=moment, disabled=bool(user.disabled))
    policy = initialize_membership_policy(db=database, now=moment)
    profile_ref = database.collection("users").document(uid)

    @firestore.transactional
    def initialize(transaction):
        current = snapshot_data(member_ref.get(transaction=transaction))
        profile = snapshot_data(profile_ref.get(transaction=transaction)) or {}
        if current is not None:
            role, source = effective_assigned_role({}, {}, current)
            return {**current, "role": role, "roleSource": source}
        # Auth's current claims are used for initialization, not a stale ID token.
        resolved = resolved_membership(profile, user.custom_claims or {}, None,
                                       created_at=auth_creation_time(user), policy=policy, now=moment)
        fields = {"role": resolved["role"], "guestExpiresAt": resolved["guestExpiresAt"],
                  "subscriptionPermanent": resolved["subscriptionPermanent"],
                  "subscriptionExpiresAt": resolved["subscriptionExpiresAt"], "accountStatus": "active",
                  "assignedAt": moment, "updatedAt": moment, "updatedBy": "membership_initialization",
                  "origin": resolved["roleSource"]}
        transaction.set(member_ref, fields)
        return {**fields, "roleSource": resolved["roleSource"]}
    resolved = initialize(database.transaction())
    return access_payload(uid, resolved, now=moment, disabled=bool(user.disabled))


def verify_reader_authorization(authorization_header, *, verify_token=auth.verify_id_token, db=None, get_user=None, now=None):
    identity = verify_identity(authorization_header, verify_token=verify_token)
    access = get_account_access(identity, db=db, get_user=get_user, now=now)
    if not access["canRead"]:
        if access["accountStatus"] != "active" or access["accessStatus"] == "disabled":
            code, message = "account_access_denied", "This account does not have access. Contact an administrator."
        elif access["subscriptionExpired"]:
            code, message = "subscription_access_expired", "Subscription access has expired. Contact an administrator to extend access."
        else:
            code, message = "guest_access_expired", "Guest access has expired. Contact an administrator to extend access."
        raise AdminAuthorizationError(code, message, 403)
    return {**identity, "access": access}


def _parse_expiry(payload, prefix, label):
    date_field, timestamp_field = f"{prefix}ExpiresOn", f"{prefix}ExpiresAt"
    if date_field in payload and timestamp_field in payload:
        raise ValueError("Provide either a last access date or an expiry timestamp, not both.")
    if date_field in payload:
        value = payload[date_field]
        if not isinstance(value, str):
            raise ValueError(f"{label} access end date is required.")
        try:
            day = date.fromisoformat(value)
            return datetime.combine(day + timedelta(days=1), time.min, expiry_timezone()).astimezone(timezone.utc)
        except (ValueError, OverflowError) as exc:
            raise ValueError(f"{label} access end date must be YYYY-MM-DD.") from exc
    expiration = as_datetime(payload.get(timestamp_field))
    if expiration is None:
        raise ValueError(f"Provide a {label.lower()} access end date or an ISO expiry timestamp with timezone.")
    return expiration


def parse_guest_expiry(payload):
    return _parse_expiry(payload, "guest", "Guest")


def parse_subscription_expiry(payload):
    return _parse_expiry(payload, "subscription", "Subscription")
