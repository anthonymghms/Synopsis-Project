#!/usr/bin/env python3
"""CLI wrapper for the canonical Harmony importer used by the Admin Portal.

The source CSV may contain the base language topic names, but its Gospel
coordinates are activated once under ``harmony/canonical`` and the names are
activated separately under ``harmony_localizations/{language}``.
"""

from __future__ import annotations

import argparse
import os
import re
import sys

from services.firebase_service import FirebaseImportRepository, new_import_id
from services.localization_import_service import parse_topic_localization_csv
from services.topic_import_service import parse_topic_csv


DEFAULT_REMOTE_CSV = "arabic3.csv"


def download_csv(remote_path: str) -> bytes:
    repository = FirebaseImportRepository()
    blob = repository.bucket.blob(remote_path)
    if not blob.exists():
        raise RuntimeError(f"Remote CSV {remote_path!r} was not found.")
    raw = blob.download_as_bytes()
    print(f"Downloaded {remote_path} ({len(raw)} bytes)")
    return raw


def parse_csv_by_position(path: str) -> dict[str, list[dict]]:
    """Compatibility adapter for callers of the original helper."""
    with open(path, "rb") as source:
        result = parse_topic_csv(source.read())
    if not result.report.valid:
        messages = "; ".join(issue.message for issue in result.report.errors)
        raise RuntimeError(messages)
    return {
        record.name: [dict(entry) for entry in record.entries]
        for record in result.records
    }


def _derived_language(remote_path: str) -> str:
    stem = os.path.splitext(os.path.basename(remote_path))[0]
    return re.sub(r"\d+$", "", stem).strip().lower() or "unknown"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--csv",
        default=DEFAULT_REMOTE_CSV,
        help="Existing CSV object path in Firebase Storage",
    )
    parser.add_argument("--language", default=None)
    parser.add_argument("--display-name", default=None)
    parser.add_argument("--direction", choices=("ltr", "rtl"), default=None)
    parser.add_argument("--gospel-matthew", default=None)
    parser.add_argument("--gospel-mark", default=None)
    parser.add_argument("--gospel-luke", default=None)
    parser.add_argument("--gospel-john", default=None)
    parser.add_argument(
        "--replace",
        action="store_true",
        help="Explicitly replace the active dataset when one exists",
    )
    args = parser.parse_args()

    language = (args.language or _derived_language(args.csv)).strip().lower()
    direction = args.direction or ("rtl" if language == "arabic" else "ltr")
    raw = download_csv(args.csv)
    result = parse_topic_csv(raw)
    for warning in result.report.warnings:
        print(f"WARNING: {warning.message}", file=sys.stderr)
    if not result.report.valid:
        for error in result.report.errors:
            print(f"ERROR: {error.message}", file=sys.stderr)
        return 2

    localization = parse_topic_localization_csv(raw, result.records)
    for warning in localization.report.warnings:
        print(f"WARNING: {warning.message}", file=sys.stderr)
    if not localization.report.valid:
        for error in localization.report.errors:
            print(f"ERROR: {error.message}", file=sys.stderr)
        return 2

    default_gospels = (
        {
            "Matthew": "متى",
            "Mark": "مرقس",
            "Luke": "لوقا",
            "John": "يوحنا",
        }
        if language == "arabic"
        else {book: book for book in ("Matthew", "Mark", "Luke", "John")}
    )
    gospel_labels = {
        "Matthew": args.gospel_matthew or default_gospels["Matthew"],
        "Mark": args.gospel_mark or default_gospels["Mark"],
        "Luke": args.gospel_luke or default_gospels["Luke"],
        "John": args.gospel_john or default_gospels["John"],
    }

    repository = FirebaseImportRepository()
    import_id = new_import_id()
    repository.create_import(
        import_id=import_id,
        import_type="harmony",
        language=language,
        uploaded_by="cli",
        filenames=[os.path.basename(args.csv)],
        metadata={
            "displayName": args.display_name or language.title(),
            "direction": direction,
            "gospels": gospel_labels,
            "legacyStoragePath": args.csv,
        },
    )
    repository.update_import(
        import_id,
        status="importing",
        stage="Writing canonical Harmony and base localization revisions",
        storagePaths=[args.csv],
    )
    outcome = repository.activate_canonical_with_localization(
        import_id=import_id,
        language=language,
        display_name=args.display_name or language.title(),
        direction=direction,
        gospel_labels=gospel_labels,
        canonical_records=result.records,
        records=localization.records,
        replace=args.replace,
    )
    repository.update_import(
        import_id,
        status="completed",
        stage="Completed",
        recordsProcessed=outcome["topicsProcessed"],
        **outcome,
    )
    print(
        f"Imported {outcome['topicsProcessed']} canonical topics and {language} "
        f"localizations to {outcome['destination']} "
        f"(audit id {import_id})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
