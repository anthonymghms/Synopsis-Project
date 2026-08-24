from __future__ import annotations

import csv
import io
import re
from dataclasses import dataclass
from typing import Any, Iterable

from .import_validation import ValidationReport, decode_legacy_csv


GOSPELS = ("Matthew", "Mark", "Luke", "John")
_REFERENCE_PATTERN = re.compile(r"^(?P<chapter>\d+)\s*:\s*(?P<start>\d+)(?:\s*-\s*(?P<end>\d+))?$")
_INHERITED_VERSE_PATTERN = re.compile(r"^(?P<start>\d+)(?:\s*-\s*(?P<end>\d+))?$")


@dataclass(frozen=True)
class TopicRecord:
    topic_id: str
    name: str
    entries: tuple[dict[str, Any], ...]
    source_row: int

    def to_firestore(self) -> dict[str, Any]:
        return {
            "name": self.name,
            "entries": [dict(entry) for entry in self.entries],
            "canonicalOrder": int(self.topic_id),
        }

    def to_preview(self) -> dict[str, Any]:
        by_book: dict[str, list[str]] = {book: [] for book in GOSPELS}
        for entry in self.entries:
            by_book[entry["book"]].append(
                f'{entry["chapter"]}:{entry["verses"]}'
            )
        return {
            "id": self.topic_id,
            "name": self.name,
            "references": {
                book: "; ".join(by_book[book]) for book in GOSPELS
            },
        }


@dataclass
class TopicParseResult:
    records: list[TopicRecord]
    report: ValidationReport
    encoding: str
    header: list[str]

    def summary(self, preview_limit: int = 20) -> dict[str, Any]:
        reference_count = sum(len(record.entries) for record in self.records)
        return {
            **self.report.to_dict(),
            "encoding": self.encoding,
            "header": self.header,
            "stats": {
                "topics": len(self.records),
                "references": reference_count,
            },
            "preview": [
                record.to_preview() for record in self.records[:preview_limit]
            ],
        }


def _normalize_dashes(value: str) -> str:
    return (value or "").replace("\u2013", "-").replace("\u2014", "-")


def _parse_reference_cell(
    cell: str,
    *,
    book: str,
    row: int,
    topic: str,
    report: ValidationReport,
) -> list[dict[str, Any]]:
    normalized = _normalize_dashes(cell).strip()
    if not normalized or normalized in {"-", "—"}:
        return []

    entries: list[dict[str, Any]] = []
    inherited_chapter: int | None = None
    for raw_piece in re.split(r"[;,]", normalized):
        piece = raw_piece.strip()
        if not piece:
            report.warning(
                "empty_reference_part",
                f"{book} contains an empty item between reference separators.",
                row=row,
                topic=topic,
                field=book,
            )
            continue
        match = _REFERENCE_PATTERN.fullmatch(piece)
        inherited = False
        if match is None and inherited_chapter is not None:
            inherited_match = _INHERITED_VERSE_PATTERN.fullmatch(piece)
            if inherited_match is not None:
                inherited = True
                match = inherited_match
        if not match:
            report.error(
                "invalid_reference",
                f'{book} reference "{piece}" must be chapter:verse or chapter:start-end.',
                row=row,
                topic=topic,
                field=book,
            )
            continue
        chapter = (
            inherited_chapter
            if inherited
            else int(match.group("chapter"))
        )
        start = int(match.group("start"))
        end_text = match.group("end")
        end = int(end_text) if end_text is not None else None
        if chapter < 1:
            report.error(
                "invalid_chapter",
                f"{book} chapter must be greater than zero.",
                row=row,
                topic=topic,
                field=book,
            )
            continue
        if start < 1 or (end is not None and end < 1):
            report.error(
                "invalid_verse",
                f"{book} verse numbers must be greater than zero.",
                row=row,
                topic=topic,
                field=book,
            )
            continue
        if end is not None and end < start:
            report.error(
                "reversed_verse_range",
                f"{book} range {start}-{end} ends before it starts.",
                row=row,
                topic=topic,
                field=book,
            )
            continue
        verses = str(start) if end is None else f"{start}-{end}"
        entries.append({"book": book, "chapter": chapter, "verses": verses})
        inherited_chapter = chapter
    return entries


def parse_topic_csv(raw: bytes) -> TopicParseResult:
    report = ValidationReport()
    try:
        text, encoding = decode_legacy_csv(raw)
    except UnicodeDecodeError:
        report.error(
            "unsupported_encoding",
            "The CSV could not be decoded. Use UTF-8, CP-1252, or Latin-1.",
        )
        return TopicParseResult([], report, "unknown", [])

    text = _normalize_dashes(text)
    try:
        rows = list(csv.reader(io.StringIO(text)))
    except csv.Error as exc:
        report.error("malformed_csv", f"The CSV is malformed: {exc}.")
        return TopicParseResult([], report, encoding, [])

    if not rows:
        report.error("empty_csv", "The CSV is empty.")
        return TopicParseResult([], report, encoding, [])

    header = [value.strip() for value in rows[0]]
    if len(header) < 5:
        report.error(
            "missing_columns",
            "The CSV needs five columns: Topic, Matthew, Mark, Luke, and John.",
            row=1,
        )
    elif len(header) > 5:
        report.warning(
            "unexpected_columns",
            f"The CSV has {len(header)} columns; columns after John are ignored.",
            row=1,
        )
    if len(rows) < 2:
        report.error("no_data_rows", "The CSV needs a header and at least one data row.")
        return TopicParseResult([], report, encoding, header)

    records: list[TopicRecord] = []
    seen_names: dict[str, int] = {}
    for row_number, row in enumerate(rows[1:], start=2):
        if not row or not any(value.strip() for value in row):
            report.warning(
                "blank_row",
                "Blank row ignored.",
                row=row_number,
            )
            continue
        if len(row) > 5 and any(value.strip() for value in row[5:]):
            report.warning(
                "unexpected_row_values",
                "Values after the John column are ignored.",
                row=row_number,
            )
        topic = (row[0] if row else "").strip()
        if not topic:
            report.error(
                "missing_topic_name",
                "Topic name is required.",
                row=row_number,
                field="Topic",
            )
            continue
        normalized_name = topic.casefold()
        if normalized_name in seen_names:
            report.warning(
                "duplicate_topic",
                f'Topic name "{topic}" also appears on row {seen_names[normalized_name]}; order-based IDs keep both rows.',
                row=row_number,
                topic=topic,
                field="Topic",
            )
        else:
            seen_names[normalized_name] = row_number

        entries: list[dict[str, Any]] = []
        for index, book in enumerate(GOSPELS, start=1):
            cell = row[index] if index < len(row) else ""
            entries.extend(
                _parse_reference_cell(
                    cell,
                    book=book,
                    row=row_number,
                    topic=topic,
                    report=report,
                )
            )
        if not entries:
            report.error(
                "topic_without_references",
                f'Topic "{topic}" has no valid Gospel references.',
                row=row_number,
                topic=topic,
            )
            continue
        records.append(
            TopicRecord(
                topic_id=str(len(records) + 1),
                name=topic,
                entries=tuple(entries),
                source_row=row_number,
            )
        )

    if not records:
        report.error("empty_dataset", "No importable topics were found.")
    return TopicParseResult(records, report, encoding, header)


def _reference_signature(entries: Iterable[dict[str, Any]]) -> tuple[str, ...]:
    return tuple(
        f'{entry.get("book")}:{entry.get("chapter")}:{entry.get("verses")}'
        for entry in entries
    )


def add_structural_comparison(
    result: TopicParseResult,
    canonical_records: Iterable[TopicRecord],
    *,
    canonical_label: str,
) -> TopicParseResult:
    canonical = list(canonical_records)
    uploaded = result.records
    if len(uploaded) != len(canonical):
        result.report.warning(
            "topic_count_mismatch",
            f"Uploaded dataset has {len(uploaded)} topics; {canonical_label} has {len(canonical)}.",
        )
    for index in range(max(len(uploaded), len(canonical))):
        topic_id = str(index + 1)
        if index >= len(uploaded):
            result.report.warning(
                "missing_canonical_topic",
                f"Topic {topic_id} is missing compared with {canonical_label}.",
                topic=topic_id,
            )
            continue
        if index >= len(canonical):
            result.report.warning(
                "additional_topic",
                f"Topic {topic_id} does not exist in {canonical_label}.",
                topic=uploaded[index].name,
                row=uploaded[index].source_row,
            )
            continue
        actual = _reference_signature(uploaded[index].entries)
        expected = _reference_signature(canonical[index].entries)
        if actual != expected:
            result.report.warning(
                "reference_structure_mismatch",
                f"Topic {topic_id} references differ from {canonical_label}. Expected {', '.join(expected)}; uploaded {', '.join(actual)}.",
                topic=uploaded[index].name,
                row=uploaded[index].source_row,
                field="References",
            )
    return result


def records_from_firestore(documents: Iterable[Any]) -> list[TopicRecord]:
    records: list[TopicRecord] = []
    for document in documents:
        data = document.to_dict() or {}
        try:
            order = int(data.get("canonicalOrder", document.id))
        except (TypeError, ValueError):
            continue
        entries = data.get("entries")
        if not isinstance(entries, list):
            entries = []
        records.append(
            TopicRecord(
                topic_id=str(order),
                name=str(data.get("name") or ""),
                entries=tuple(dict(entry) for entry in entries if isinstance(entry, dict)),
                source_row=order + 1,
            )
        )
    records.sort(key=lambda record: int(record.topic_id))
    return records
