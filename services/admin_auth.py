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
        or (
            isinstance(roles, (list, tuple, set))
            and any(str(value).strip().lower() == "admin" for value in roles)
        )
    )


def has_stored_admin_role(data: dict[str, Any]) -> bool:
    """Profile fallback intentionally accepts only the server-managed role."""
    return str(data.get("role") or "").strip().lower() == "admin"


def verify_admin_authorization(
    authorization_header: str | None,
    *,
    verify_token=auth.verify_id_token,
    db=None,
) -> dict[str, Any]:
    header = (authorization_header or "").strip()
    if not header.lower().startswith("bearer "):
        raise AdminAuthorizationError(
            "authentication_required",
            "Sign in with an administrator account to continue.",
            401,
        )
    token = header[7:].strip()
    if not token:
        raise AdminAuthorizationError(
            "authentication_required",
            "The Firebase ID token is missing.",
            401,
        )
    try:
        claims = verify_token(token, check_revoked=True)
    except Exception as exc:
        raise AdminAuthorizationError(
            "invalid_token",
            "Your session is invalid or expired. Sign in again.",
            401,
        ) from exc
    uid = str(claims.get("uid") or claims.get("sub") or "").strip()
    if not uid:
        raise AdminAuthorizationError(
            "invalid_token",
            "The authenticated user identifier is missing.",
            401,
        )
    if has_admin_role(claims):
        return {"uid": uid, "claims": claims, "source": "custom_claim"}

    database = db or firestore_client()
    snapshot = database.collection("users").document(uid).get()
    profile = snapshot.to_dict() if snapshot.exists else {}
    if profile and has_stored_admin_role(profile):
        return {"uid": uid, "claims": claims, "source": "users_role"}
    raise AdminAuthorizationError(
        "admin_required",
        "This account does not have administrator access.",
        403,
    )
