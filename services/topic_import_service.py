from __future__ import annotations

import csv
import io
from dataclasses import dataclass
from typing import Any, Iterable

from .import_validation import ValidationReport, decode_legacy_csv
from .reference_parser import (
    ReferenceCell,
    VerseCountResolver,
    parse_reference_cell,
    reference_cells_from_firestore,
)


GOSPELS = ("Matthew", "Mark", "Luke", "John")
_ID_HEADERS = {"topicnumber", "topicid", "id", "number"}


def _header_key(value: str) -> str:
    return "".join(character for character in value.casefold() if character.isalnum())


@dataclass(frozen=True)
class TopicRecord:
    topic_id: str
    name: str
    entries: tuple[dict[str, Any], ...]
    source_row: int
    reference_cells: tuple[ReferenceCell, ...] = ()

    @property
    def logical_reference_count(self) -> int:
        if self.reference_cells:
            return sum(cell.logical_selection_count for cell in self.reference_cells)
        return len(self.entries)

    @property
    def physical_segment_count(self) -> int:
        if self.reference_cells:
            return sum(cell.physical_segment_count for cell in self.reference_cells)
        return len(self.entries)

    def to_firestore(self) -> dict[str, Any]:
        return {
            "name": self.name,
            **self.to_canonical_firestore(),
        }

    def to_canonical_firestore(self) -> dict[str, Any]:
        return {
            "entries": [dict(entry) for entry in self.entries],
            "referenceCells": [
                cell.to_firestore() for cell in self.reference_cells
            ],
            "referenceGrammarVersion": 2,
            "canonicalOrder": int(self.topic_id),
        }

    def to_preview(self) -> dict[str, Any]:
        by_book: dict[str, list[str]] = {book: [] for book in GOSPELS}
        if self.reference_cells:
            for cell in self.reference_cells:
                by_book.setdefault(cell.book, []).append(cell.display_value)
        else:
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
        reference_count = sum(
            record.logical_reference_count for record in self.records
        )
        physical_segment_count = sum(
            record.physical_segment_count for record in self.records
        )
        return {
            **self.report.to_dict(),
            "encoding": self.encoding,
            "header": self.header,
            "stats": {
                "topics": len(self.records),
                "references": reference_count,
                "physicalSegments": physical_segment_count,
            },
            "preview": [
                record.to_preview() for record in self.records[:preview_limit]
            ],
        }


def _normalize_dashes(value: str) -> str:
    return (value or "").replace("\u2013", "-").replace("\u2014", "-")


def parse_topic_csv(
    raw: bytes,
    *,
    verse_count_resolver: VerseCountResolver | None = None,
) -> TopicParseResult:
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
    has_explicit_id = bool(header) and _header_key(header[0]) in _ID_HEADERS
    expected_columns = 6 if has_explicit_id else 5
    topic_index = 1 if has_explicit_id else 0
    gospel_start = topic_index + 1
    if len(header) < expected_columns:
        report.error(
            "missing_columns",
            "The CSV needs Topic, Matthew, Mark, Luke, and John columns, with an optional leading TopicNumber/TopicId column.",
            row=1,
        )
    elif len(header) > expected_columns:
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
    seen_topic_ids: dict[str, int] = {}
    for row_number, row in enumerate(rows[1:], start=2):
        if not row or not any(value.strip() for value in row):
            report.error(
                "missing_topic_row",
                "Blank rows are not allowed in a master Harmony table because they make positional topic IDs unsafe.",
                row=row_number,
            )
            continue
        if len(row) > expected_columns and any(
            value.strip() for value in row[expected_columns:]
        ):
            report.error(
                "unexpected_row_values",
                "Values after the John column are not allowed. If a reference cell contains ',', wrap that cell in CSV quotes.",
                row=row_number,
            )
        if has_explicit_id:
            raw_topic_id = row[0].strip() if row else ""
            try:
                topic_id = str(int(raw_topic_id))
                if int(topic_id) < 1:
                    raise ValueError
            except (TypeError, ValueError):
                report.error(
                    "invalid_topic_id",
                    f'Topic identifier "{raw_topic_id}" must be a positive number.',
                    row=row_number,
                    field=header[0] if header else "TopicNumber",
                )
                continue
            if topic_id in seen_topic_ids:
                report.error(
                    "duplicate_topic_id",
                    f"Topic {topic_id} also appears on row {seen_topic_ids[topic_id]}.",
                    row=row_number,
                    topic=topic_id,
                    field=header[0] if header else "TopicNumber",
                )
                continue
            seen_topic_ids[topic_id] = row_number
        else:
            topic_id = str(row_number - 1)

        topic = (row[topic_index] if topic_index < len(row) else "").strip()
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
        reference_cells: list[ReferenceCell] = []
        for index, book in enumerate(GOSPELS, start=gospel_start):
            cell = row[index] if index < len(row) else ""
            parsed_cell = parse_reference_cell(
                cell,
                book=book,
                row=row_number,
                topic=topic,
                field=book,
                report=report,
                verse_count_resolver=verse_count_resolver,
            )
            if parsed_cell.segments:
                reference_cells.append(parsed_cell)
                entries.extend(parsed_cell.to_legacy_entries())
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
                topic_id=topic_id,
                name=topic,
                entries=tuple(entries),
                source_row=row_number,
                reference_cells=tuple(reference_cells),
            )
        )

    if has_explicit_id and seen_topic_ids:
        highest_topic_id = max(map(int, seen_topic_ids))
        missing = [
            str(topic_id)
            for topic_id in range(1, highest_topic_id + 1)
            if str(topic_id) not in seen_topic_ids
        ]
        if missing:
            preview = ", ".join(missing[:20])
            suffix = "…" if len(missing) > 20 else ""
            report.error(
                "missing_topic_numbers",
                f"The master table is missing topic numbers {preview}{suffix}.",
                field=header[0] if header else "TopicNumber",
            )
        records.sort(key=lambda record: int(record.topic_id))

    if not records:
        report.error("empty_dataset", "No importable topics were found.")
    return TopicParseResult(records, report, encoding, header)


def _reference_signature(entries: Iterable[dict[str, Any]]) -> tuple[str, ...]:
    return tuple(
        f'{entry.get("book")}:{entry.get("chapter")}:{entry.get("verses")}:{entry.get("separatorBefore", "")}'
        for entry in entries
    )


def reference_structure_mismatch_ids(
    uploaded_records: Iterable[TopicRecord],
    canonical_records: Iterable[TopicRecord],
) -> list[str]:
    uploaded = {record.topic_id: record for record in uploaded_records}
    canonical = {record.topic_id: record for record in canonical_records}
    topic_ids = sorted(
        set(uploaded) | set(canonical),
        key=lambda value: (0, int(value)) if value.isdigit() else (1, value),
    )
    return [
        topic_id
        for topic_id in topic_ids
        if topic_id not in uploaded
        or topic_id not in canonical
        or _reference_signature(uploaded[topic_id].entries)
        != _reference_signature(canonical[topic_id].entries)
    ]


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
        raw_cells = data.get("referenceCells")
        reference_cells = reference_cells_from_firestore(
            raw_cells if isinstance(raw_cells, list) else []
        )
        if not entries and reference_cells:
            entries = [
                entry
                for cell in reference_cells
                for entry in cell.to_legacy_entries()
            ]
        records.append(
            TopicRecord(
                topic_id=str(order),
                name=str(data.get("name") or ""),
                entries=tuple(dict(entry) for entry in entries if isinstance(entry, dict)),
                source_row=order + 1,
                reference_cells=reference_cells,
            )
        )
    records.sort(key=lambda record: int(record.topic_id))
    return records
