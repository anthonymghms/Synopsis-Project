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
    if args.remove:
        claims.pop("admin", None)
        if claims.get("role") == "admin":
            claims.pop("role", None)
        auth.set_custom_user_claims(user.uid, claims or None)
        user_ref.set(
            {"role": firestore.DELETE_FIELD, "updatedAt": firestore.SERVER_TIMESTAMP},
            merge=True,
        )
        print(f"Removed administrator access for UID {user.uid}.")
    else:
        claims["admin"] = True
        claims["role"] = "admin"
        auth.set_custom_user_claims(user.uid, claims)
        user_ref.set(
            {"role": "admin", "updatedAt": firestore.SERVER_TIMESTAMP},
            merge=True,
        )
        print(
            f"Granted administrator access to UID {user.uid}. "
            "The user must sign out and sign back in to refresh claims."
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
