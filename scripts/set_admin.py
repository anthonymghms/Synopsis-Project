#!/usr/bin/env python3
"""One-time trusted bootstrap for granting or removing Admin Portal access."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from firebase_admin import auth, firestore

from services.firebase_service import firestore_client, initialize_firebase


def main() -> int:
    parser = argparse.ArgumentParser()
    identity = parser.add_mutually_exclusive_group(required=True)
    identity.add_argument("--uid")
    identity.add_argument("--email")
    parser.add_argument(
        "--remove", action="store_true", help="Remove administrator access"
    )
    args = parser.parse_args()

    initialize_firebase()
    user = auth.get_user(args.uid) if args.uid else auth.get_user_by_email(args.email)
    claims = dict(user.custom_claims or {})
    db = firestore_client()
    user_ref = db.collection("users").document(user.uid)
    membership_ref = db.collection("memberships").document(user.uid)
    if args.remove:
        claims.pop("admin", None)
        claims.pop("isAdmin", None)
        if str(claims.get("role") or "").strip().lower() == "admin":
            claims.pop("role", None)
        if isinstance(claims.get("roles"), list):
            claims["roles"] = [value for value in claims["roles"] if str(value).strip().lower() != "admin"]
        role = "subscribed"
    else:
        claims["admin"] = True
        claims["role"] = "admin"
        role = "admin"
    batch = db.batch()
    batch.set(user_ref, {"role": role, "updatedAt": firestore.SERVER_TIMESTAMP}, merge=True)
    batch.set(membership_ref, {"role": role, "guestExpiresAt": None,
                              "updatedAt": firestore.SERVER_TIMESTAMP, "updatedBy": "trusted_bootstrap",
                              "origin": "trusted_bootstrap"}, merge=True)
    batch.commit()
    # Membership is authoritative even while a client retains old token claims.
    # Preserve claims unrelated to administrator access.
    auth.set_custom_user_claims(user.uid, claims or None)
    if args.remove:
        print(f"Removed administrator access for UID {user.uid}.")
    else:
        print(
            f"Granted administrator access to UID {user.uid}. "
            "Access takes effect on the next account access check."
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
