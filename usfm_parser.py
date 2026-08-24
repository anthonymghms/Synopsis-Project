#!/usr/bin/env python3
"""CLI wrapper for the same USFM import service used by the Admin Portal."""

from __future__ import annotations

import argparse
import os
import sys

from services.bible_import_service import USFM_BOOK_NAMES, parse_usfm, parse_usfm_files
from services.firebase_service import FirebaseImportRepository, new_import_id


DEFAULT_REMOTE_USFM = "arabic/New Arabic Version/Ar-MRK-nav.usfm"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--usfm",
        action="append",
        default=None,
        help="Existing .usfm object path in Firebase Storage; repeat for multiple books",
    )
    parser.add_argument("--language", default="arabic")
    parser.add_argument("--language-display-name", default=None)
    parser.add_argument("--version", default="New Arabic Version")
    parser.add_argument("--version-display-name", default=None)
    parser.add_argument("--description", default="")
    parser.add_argument("--related-translation", default=None)
    parser.add_argument("--direction", choices=("ltr", "rtl"), default="rtl")
    parser.add_argument(
        "--replace",
        action="store_true",
        help="Explicitly replace the active translation when it exists",
    )
    args = parser.parse_args()

    paths = args.usfm or [DEFAULT_REMOTE_USFM]
    repository = FirebaseImportRepository()
    files: list[tuple[str, bytes]] = []
    for path in paths:
        blob = repository.bucket.blob(path)
        if not blob.exists():
            print(f"ERROR: Remote USFM {path!r} was not found.", file=sys.stderr)
            return 2
        files.append((os.path.basename(path), blob.download_as_bytes()))

    result = parse_usfm_files(files)
    for warning in result.report.warnings:
        print(f"WARNING: {warning.message}", file=sys.stderr)
    if not result.report.valid:
        for error in result.report.errors:
            print(f"ERROR: {error.message}", file=sys.stderr)
        return 2

    import_id = new_import_id()
    repository.create_import(
        import_id=import_id,
        import_type="bible",
        language=args.language,
        version=args.version,
        uploaded_by="cli",
        filenames=[name for name, _ in files],
        metadata={
            "languageDisplayName": args.language_display_name or args.language.title(),
            "direction": args.direction,
            "versionDisplayName": args.version_display_name or args.version,
            "description": args.description,
            "relatedTranslation": args.related_translation,
            "legacyStoragePaths": paths,
        },
    )
    repository.update_import(
        import_id,
        status="importing",
        stage="Writing Bible revision",
        storagePaths=paths,
    )
    outcome = repository.activate_bible(
        import_id=import_id,
        language=args.language,
        language_display_name=args.language_display_name or args.language.title(),
        direction=args.direction,
        version=args.version,
        version_display_name=args.version_display_name or args.version,
        description=args.description,
        related_translation=args.related_translation,
        result=result,
        replace=args.replace,
    )
    repository.update_import(
        import_id,
        status="completed",
        stage="Completed",
        recordsProcessed=outcome["versesProcessed"],
        **outcome,
    )
    print(
        f"Imported {outcome['booksProcessed']} books and {outcome['versesProcessed']} "
        f"verses to {outcome['destination']} (audit id {import_id})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
