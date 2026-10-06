#!/usr/bin/env python3
"""Set the persistent membership rollout cutoff before reopening signups.

Run from the deployment host with its normal Firebase credentials. Existing
policy is never overwritten; existing accounts keep subscribed access while
accounts created after this boundary receive 30-day guest access.
"""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from services.membership_service import initialize_membership_policy


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cutoff", help="Optional ISO UTC/offset rollout timestamp; default is now.")
    args = parser.parse_args()
    if args.cutoff:
        os.environ["MEMBERSHIP_LEGACY_CUTOFF"] = args.cutoff
    policy = initialize_membership_policy()
    print(f"Membership rollout cutoff: {policy['rolloutAt']}")
    print("New accounts receive 30 days of guest access. Existing policy is preserved.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
