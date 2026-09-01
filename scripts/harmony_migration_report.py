#!/usr/bin/env python3
"""Generate a read-only report for legacy Harmony datasets.

This command never writes Firestore.  It compares every legacy
``references/{dataset}`` collection with the active canonical revision (or an
explicit trusted legacy dataset) so an administrator can review mismatches
before deciding whether any later migration or cleanup is appropriate.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from services.firebase_service import FirebaseImportRepository


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--trusted-dataset",
        default="canonical",
        help="Use 'canonical' (default) or a legacy references document id.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        help="Optional JSON file to receive the report. No Firestore writes occur.",
    )
    args = parser.parse_args()

    report = FirebaseImportRepository().harmony_migration_report(
        args.trusted_dataset
    )
    rendered = json.dumps(report, ensure_ascii=False, indent=2, default=str)
    print(rendered)
    if args.output is not None:
        args.output.write_text(rendered + "\n", encoding="utf-8")
    return 0 if report.get("safeToAutoMigrate") else 2


if __name__ == "__main__":
    raise SystemExit(main())
