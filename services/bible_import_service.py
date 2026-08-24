from __future__ import annotations

import os
import re
from dataclasses import dataclass
from typing import Any, Iterable

from .import_validation import ValidationReport, decode_usfm


# The legacy importer and the current application are Gospel-focused. Keeping
# this map explicit prevents an upload from appearing successful when the
# application cannot resolve the resulting book identifiers.
USFM_BOOK_NAMES = {
    "MAT": "Matthew",
    "MRK": "Mark",
    "LUK": "Luke",
    "JHN": "John",
}

_ARABIC_DIACRITICS = re.compile(r"[\u0610-\u061a\u064b-\u065f\u0670\u06d6-\u06ed]")
_SECTION_MARKER = re.compile(r"^(\\s\d?)\s+(.+)$")
_QUOTE_MARKER = re.compile(r"^(\\q\d?)\s+(.+)$")


@dataclass(frozen=True)
class ParsedVerse:
    number: str
    text: str
    blocks_before: tuple[dict[str, Any], ...]
    source_line: int

    def to_firestore(self) -> dict[str, Any]:
        return {
            "text": self.text,
            "blocks_before": [dict(block) for block in self.blocks_before],
        }


@dataclass(frozen=True)
class ParsedBook:
    code: str
    name: str
    filename: str
    chapters: dict[str, tuple[ParsedVerse, ...]]

    @property
    def chapter_count(self) -> int:
        return len(self.chapters)

    @property
    def verse_count(self) -> int:
        return sum(len(verses) for verses in self.chapters.values())


@dataclass
class BibleParseResult:
    books: list[ParsedBook]
    report: ValidationReport
    encodings: dict[str, str]
    contains_diacritics: bool

    def summary(self, preview_limit: int = 8) -> dict[str, Any]:
        samples: list[dict[str, Any]] = []
        for book in self.books:
            for chapter, verses in book.chapters.items():
                for verse in verses:
                    samples.append(
                        {
                            "book": book.name,
                            "chapter": int(chapter),
                            "verse": int(verse.number),
                            "text": verse.text,
                        }
                    )
                    if len(samples) >= preview_limit:
                        break
                if len(samples) >= preview_limit:
                    break
            if len(samples) >= preview_limit:
                break
        return {
            **self.report.to_dict(),
            "encodings": dict(self.encodings),
            "containsDiacritics": self.contains_diacritics,
            "stats": {
                "books": len(self.books),
                "chapters": sum(book.chapter_count for book in self.books),
                "verses": sum(book.verse_count for book in self.books),
                "bookNames": [book.name for book in self.books],
            },
            "preview": samples,
        }


def _book_code_from_filename(filename: str) -> str | None:
    upper = os.path.basename(filename).upper()
    for code in USFM_BOOK_NAMES:
        if re.search(rf"(?:^|[^A-Z]){re.escape(code)}(?:[^A-Z]|$)", upper):
            return code
    return None


def _parse_one_usfm(
    filename: str,
    text: str,
    report: ValidationReport,
) -> ParsedBook | None:
    book_code: str | None = None
    chapters: dict[str, list[ParsedVerse]] = {}
    current_chapter: str | None = None
    current_blocks: list[dict[str, Any]] = []
    seen_verses: dict[str, set[str]] = {}
    last_chapter = 0
    last_verse_by_chapter: dict[str, int] = {}

    for line_number, raw_line in enumerate(text.splitlines(), start=1):
        line = raw_line.strip()
        if not line:
            continue
        if line.startswith(r"\id "):
            raw_id = line.split(" ", 1)[1].strip()
            candidate = raw_id.split()[0].upper() if raw_id else ""
            if book_code is not None and candidate != book_code:
                report.error(
                    "duplicate_book_marker",
                    "A USFM file may contain only one \\id book marker.",
                    row=line_number,
                    filename=filename,
                    field="\\id",
                )
            book_code = candidate
            continue
        if line.startswith(r"\c "):
            value = line.split(" ", 1)[1].strip().split()[0]
            if not value.isdigit() or int(value) < 1:
                report.error(
                    "invalid_chapter",
                    f'Chapter marker "{value}" must contain a positive integer.',
                    row=line_number,
                    filename=filename,
                    field="\\c",
                )
                current_chapter = None
                continue
            number = int(value)
            current_chapter = str(number)
            if current_chapter in chapters:
                report.error(
                    "duplicate_chapter",
                    f"Chapter {number} occurs more than once.",
                    row=line_number,
                    filename=filename,
                    field="\\c",
                )
            else:
                chapters[current_chapter] = []
                seen_verses[current_chapter] = set()
                if last_chapter and number <= last_chapter:
                    report.warning(
                        "chapter_order",
                        f"Chapter {number} is out of sequence after chapter {last_chapter}.",
                        row=line_number,
                        filename=filename,
                        field="\\c",
                    )
                elif last_chapter and number > last_chapter + 1:
                    report.warning(
                        "chapter_gap",
                        f"Chapter {last_chapter + 1} through {number - 1} are missing.",
                        row=line_number,
                        filename=filename,
                        field="\\c",
                    )
                last_chapter = max(last_chapter, number)
            continue
        if line.startswith(r"\v "):
            parts = line.split(" ", 2)
            verse_number = parts[1].strip() if len(parts) > 1 else ""
            verse_text = parts[2].strip() if len(parts) > 2 else ""
            if current_chapter is None or current_chapter not in chapters:
                report.error(
                    "verse_before_chapter",
                    "A \\v marker appears before a valid \\c marker.",
                    row=line_number,
                    filename=filename,
                    field="\\v",
                )
                current_blocks = []
                continue
            if not verse_number.isdigit() or int(verse_number) < 1:
                report.error(
                    "invalid_verse",
                    f'Verse marker "{verse_number}" must contain a positive integer.',
                    row=line_number,
                    filename=filename,
                    field="\\v",
                )
                current_blocks = []
                continue
            normalized_verse = str(int(verse_number))
            if normalized_verse in seen_verses[current_chapter]:
                report.error(
                    "duplicate_verse",
                    f"Chapter {current_chapter}, verse {normalized_verse} occurs more than once.",
                    row=line_number,
                    filename=filename,
                    field="\\v",
                )
                current_blocks = []
                continue
            seen_verses[current_chapter].add(normalized_verse)
            last_verse = last_verse_by_chapter.get(current_chapter, 0)
            verse_int = int(normalized_verse)
            if last_verse and verse_int <= last_verse:
                report.warning(
                    "verse_order",
                    f"Chapter {current_chapter}, verse {verse_int} is out of sequence.",
                    row=line_number,
                    filename=filename,
                    field="\\v",
                )
            elif last_verse and verse_int > last_verse + 1:
                report.warning(
                    "verse_gap",
                    f"Chapter {current_chapter} skips from verse {last_verse} to {verse_int}.",
                    row=line_number,
                    filename=filename,
                    field="\\v",
                )
            last_verse_by_chapter[current_chapter] = max(last_verse, verse_int)
            if not verse_text:
                report.warning(
                    "empty_verse_text",
                    f"Chapter {current_chapter}, verse {verse_int} has no text.",
                    row=line_number,
                    filename=filename,
                    field="\\v",
                )
            chapters[current_chapter].append(
                ParsedVerse(
                    number=normalized_verse,
                    text=verse_text,
                    blocks_before=tuple(dict(block) for block in current_blocks),
                    source_line=line_number,
                )
            )
            current_blocks = []
            continue

        section_match = _SECTION_MARKER.match(line)
        if section_match:
            current_blocks.append(
                {"marker": section_match.group(1), "text": section_match.group(2)}
            )
            continue
        if line.startswith(r"\p"):
            current_blocks.append({"marker": "p"})
            continue
        quote_match = _QUOTE_MARKER.match(line)
        if quote_match:
            current_blocks.append(
                {"marker": quote_match.group(1), "text": quote_match.group(2)}
            )

    if book_code is None:
        book_code = _book_code_from_filename(filename)
        if book_code is None:
            report.error(
                "missing_book_id",
                "No \\id marker was found and the filename has no recognized book code.",
                filename=filename,
                field="\\id",
            )
            return None
        report.warning(
            "book_id_from_filename",
            f"Book code {book_code} was inferred from the filename.",
            filename=filename,
            field="\\id",
        )
    if book_code not in USFM_BOOK_NAMES:
        report.error(
            "unrecognized_book",
            f'Book code "{book_code}" is not supported. Supported codes: {", ".join(USFM_BOOK_NAMES)}.',
            filename=filename,
            field="\\id",
        )
        return None
    if not chapters or not any(chapters.values()):
        report.error(
            "empty_book",
            f"{USFM_BOOK_NAMES[book_code]} contains no importable verses.",
            filename=filename,
        )
    return ParsedBook(
        code=book_code,
        name=USFM_BOOK_NAMES[book_code],
        filename=filename,
        chapters={
            chapter: tuple(verses) for chapter, verses in chapters.items()
        },
    )


def parse_usfm_files(files: Iterable[tuple[str, bytes]]) -> BibleParseResult:
    report = ValidationReport()
    books: list[ParsedBook] = []
    encodings: dict[str, str] = {}
    seen_codes: dict[str, str] = {}
    contains_diacritics = False
    file_list = list(files)
    if not file_list:
        report.error("missing_files", "Select at least one USFM file.")
        return BibleParseResult([], report, encodings, False)

    for filename, raw in file_list:
        if not filename.lower().endswith(".usfm"):
            report.error(
                "invalid_file_type",
                "Bible uploads must use the .usfm extension.",
                filename=filename,
            )
            continue
        try:
            text, encoding = decode_usfm(raw)
        except UnicodeDecodeError:
            report.error(
                "unsupported_encoding",
                "USFM files must be UTF-8 encoded.",
                filename=filename,
            )
            continue
        encodings[filename] = encoding
        contains_diacritics = contains_diacritics or bool(
            _ARABIC_DIACRITICS.search(text)
        )
        book = _parse_one_usfm(filename, text, report)
        if book is None:
            continue
        if book.code in seen_codes:
            report.error(
                "duplicate_book",
                f"{book.name} is present in both {seen_codes[book.code]} and {filename}.",
                filename=filename,
                field="\\id",
            )
            continue
        seen_codes[book.code] = filename
        books.append(book)

    books.sort(key=lambda book: list(USFM_BOOK_NAMES).index(book.code))
    if not books:
        report.error("empty_bible", "No importable Bible books were found.")
    return BibleParseResult(books, report, encodings, contains_diacritics)


def parse_usfm(usfm_content: str) -> dict[str, Any]:
    """Compatibility adapter matching the useful part of the old API."""
    result = parse_usfm_files([("upload.usfm", usfm_content.encode("utf-8"))])
    if not result.books:
        return {"book_id": None, "chapters": {}}
    book = result.books[0]
    return {
        "book_id": book.code,
        "chapters": {
            chapter: {
                "verses": {
                    verse.number: verse.to_firestore() for verse in verses
                },
                "blocks": [],
            }
            for chapter, verses in book.chapters.items()
        },
    }
