from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from firebase_admin import auth

from .firebase_service import firestore_client


@dataclass
class AdminAuthorizationError(RuntimeError):
    code: str
    message: str
    status: int

    def __str__(self) -> str:
        return self.message


def has_admin_role(data: dict[str, Any]) -> bool:
    role = str(data.get("role") or "").strip().lower()
    roles = data.get("roles")
    return (
        data.get("admin") is True
        or data.get("isAdmin") is True
        or role == "admin"
        or (isinstance(roles, (list, tuple, set))
            and any(str(value).strip().lower() == "admin" for value in roles))
    )


def has_stored_admin_role(data: dict[str, Any]) -> bool:
    return str(data.get("role") or "").strip().lower() == "admin"


def effective_assigned_role(profile, claims, membership=None):
    """Server membership overrides old profile roles and stale token claims.

    An existing malformed membership fails closed. Claims are only a bootstrap
    fallback until a server-managed role has been assigned.
    """
    if membership is not None:
        role = str(membership.get("role") or "").strip().lower()
        return (role if role in {"guest", "subscribed", "admin"} else "guest", "membership")
    stored = str((profile or {}).get("role") or "").strip().lower()
    if stored in {"guest", "subscribed", "admin", "user"}:
        return ("subscribed" if stored == "user" else stored, "users_role")
    if has_admin_role(claims or {}):
        return "admin", "custom_claim"
    return None, None


def verify_identity(authorization_header, *, verify_token=auth.verify_id_token):
    header = (authorization_header or "").strip()
    if not header.lower().startswith("bearer ") or not header[7:].strip():
        raise AdminAuthorizationError("authentication_required", "Sign in to continue.", 401)
    try:
        claims = verify_token(header[7:].strip(), check_revoked=True)
    except Exception as exc:
        raise AdminAuthorizationError("invalid_token", "Your session is invalid or expired. Sign in again.", 401) from exc
    uid = str(claims.get("uid") or claims.get("sub") or "").strip()
    if not uid or "/" in uid:
        raise AdminAuthorizationError("invalid_token", "The authenticated user identifier is missing or invalid.", 401)
    return {"uid": uid, "claims": claims}


def verify_admin_authorization(authorization_header, *, verify_token=auth.verify_id_token, db=None):
    identity = verify_identity(authorization_header, verify_token=verify_token)
    database = db if db is not None else firestore_client()
    uid = identity["uid"]
    member = database.collection("memberships").document(uid).get()
    profile = database.collection("users").document(uid).get()
    role, source = effective_assigned_role(
        profile.to_dict() if profile.exists else {}, identity["claims"],
        member.to_dict() if member.exists else None,
    )
    if role == "admin":
        return {**identity, "source": source}
    raise AdminAuthorizationError("admin_required", "This account does not have administrator access.", 403)
