from __future__ import annotations

import csv
import io
from dataclasses import dataclass
from typing import Any, Iterable

from .import_validation import ValidationReport, decode_legacy_csv
from .topic_import_service import TopicRecord


_ID_HEADERS = {"topicnumber", "topicid", "id", "number"}
_NAME_HEADERS = {"topicname", "name", "topic", "translation"}


def _header_key(value: str) -> str:
    return "".join(character for character in value.casefold() if character.isalnum())


@dataclass(frozen=True)
class TopicLocalizationRecord:
    topic_id: str
    name: str
    canonical_name: str
    source_row: int

    def to_firestore(self) -> dict[str, Any]:
        return {"name": self.name, "canonicalOrder": int(self.topic_id)}

    def to_preview(self) -> dict[str, str]:
        return {
            "id": self.topic_id,
            "canonicalName": self.canonical_name,
            "localizedName": self.name,
        }


@dataclass
class TopicLocalizationParseResult:
    records: list[TopicLocalizationRecord]
    report: ValidationReport
    encoding: str
    header: list[str]
    source_format: str = "idAndName"

    def summary(self, preview_limit: int = 30) -> dict[str, Any]:
        return {
            **self.report.to_dict(),
            "encoding": self.encoding,
            "header": self.header,
            "sourceFormat": self.source_format,
            "stats": {
                "topics": len(self.records),
                "sourceFormat": self.source_format,
            },
            "preview": [
                record.to_preview() for record in self.records[:preview_limit]
            ],
        }


def parse_topic_localization_csv(
    raw: bytes,
    canonical_records: Iterable[TopicRecord],
) -> TopicLocalizationParseResult:
    report = ValidationReport()
    canonical = {record.topic_id: record for record in canonical_records}

    try:
        text, encoding = decode_legacy_csv(raw)
    except UnicodeDecodeError:
        report.error(
            "unsupported_encoding",
            "The CSV could not be decoded. Save localized names as UTF-8.",
        )
        return TopicLocalizationParseResult([], report, "unknown", [])

    if "\x00" in text or any(
        ord(character) < 32 and character not in "\r\n\t"
        for character in text
    ):
        report.error(
            "invalid_text_encoding",
            "The localization file contains binary/control characters. Save it as UTF-8 CSV.",
        )
        return TopicLocalizationParseResult([], report, encoding, [])
    if encoding not in {"utf-8", "utf-8-sig"}:
        report.warning(
            "legacy_text_encoding",
            f"The file was decoded as {encoding}; UTF-8 is recommended for reliable multilingual text.",
        )

    try:
        rows = list(csv.reader(io.StringIO(text)))
    except csv.Error as exc:
        report.error("malformed_csv", f"The CSV is malformed: {exc}.")
        return TopicLocalizationParseResult([], report, encoding, [])
    if not rows:
        report.error("empty_csv", "The CSV is empty.")
        return TopicLocalizationParseResult([], report, encoding, [])

    header = [value.strip() for value in rows[0]]
    source_format = (
        "orderedNames"
        if len(header) == 1
        else "harmonyTable"
        if len(header) >= 5
        else "idAndName"
    )
    if not canonical:
        report.error(
            "canonical_topics_missing",
            "No canonical Harmony topics are available. Upload the five-column main Harmony table first.",
        )
        return TopicLocalizationParseResult(
            [], report, encoding, header, source_format
        )

    if source_format in {"orderedNames", "harmonyTable"}:
        ordered_canonical = sorted(
            canonical.values(), key=lambda record: int(record.topic_id)
        )
        name_column = (
            1
            if source_format == "harmonyTable"
            and header
            and _header_key(header[0]) in _ID_HEADERS
            else 0
        )
        data_rows = rows[1:]
        if source_format == "orderedNames":
            report.warning(
                "positional_alignment",
                "This one-column file is aligned by row position. Review the full preview before importing; TopicNumber,TopicName is safer for future updates.",
                row=1,
            )
        if len(data_rows) != len(ordered_canonical):
            report.error(
                "topic_count_mismatch",
                f"The ordered name file contains {len(data_rows)} topic rows; the canonical Harmony table contains {len(ordered_canonical)}.",
            )

        records: list[TopicLocalizationRecord] = []
        for index, canonical_record in enumerate(ordered_canonical):
            row_number = index + 2
            if index >= len(data_rows):
                report.error(
                    "missing_topic_translation",
                    f"Canonical topic {canonical_record.topic_id} ({canonical_record.name}) is missing.",
                    topic=canonical_record.topic_id,
                )
                continue
            row = data_rows[index]
            if source_format == "orderedNames" and len(row) > 1 and any(
                value.strip() for value in row[1:]
            ):
                report.error(
                    "unexpected_localization_columns",
                    "The language overlay must contain one topic-name column. Quote names that contain commas.",
                    row=row_number,
                )
            name = row[name_column].strip() if len(row) > name_column else ""
            if not name:
                report.error(
                    "missing_topic_name",
                    f"Topic {canonical_record.topic_id} needs a localized name.",
                    row=row_number,
                    topic=canonical_record.topic_id,
                    field=header[0] if header else "TopicName",
                )
                continue
            records.append(
                TopicLocalizationRecord(
                    topic_id=canonical_record.topic_id,
                    name=name,
                    canonical_name=canonical_record.name,
                    source_row=row_number,
                )
            )

        for index in range(len(ordered_canonical), len(data_rows)):
            row = data_rows[index]
            name = row[name_column].strip() if len(row) > name_column else ""
            report.error(
                "unknown_topic_position",
                f'Extra topic name "{name}" has no corresponding canonical topic.',
                row=index + 2,
            )
        return TopicLocalizationParseResult(
            records,
            report,
            encoding,
            header,
            source_format,
        )

    header_keys = [_header_key(value) for value in header]
    id_indexes = [index for index, value in enumerate(header_keys) if value in _ID_HEADERS]
    name_indexes = [
        index for index, value in enumerate(header_keys) if value in _NAME_HEADERS
    ]
    if not id_indexes or not name_indexes:
        report.error(
            "missing_localization_columns",
            "The CSV needs TopicNumber (or TopicId) and TopicName columns.",
            row=1,
        )
        return TopicLocalizationParseResult([], report, encoding, header)
    id_index = id_indexes[0]
    name_index = name_indexes[0]

    records: list[TopicLocalizationRecord] = []
    seen: set[str] = set()
    for row_number, row in enumerate(rows[1:], start=2):
        if not row or not any(value.strip() for value in row):
            continue
        topic_id = row[id_index].strip() if id_index < len(row) else ""
        name = row[name_index].strip() if name_index < len(row) else ""
        try:
            normalized_id = str(int(topic_id))
        except (TypeError, ValueError):
            report.error(
                "invalid_topic_id",
                f'Topic identifier "{topic_id}" must be a number.',
                row=row_number,
                field=header[id_index],
            )
            continue
        if normalized_id in seen:
            report.error(
                "duplicate_topic_id",
                f"Topic {normalized_id} appears more than once.",
                row=row_number,
                topic=normalized_id,
            )
            continue
        seen.add(normalized_id)
        canonical_record = canonical.get(normalized_id)
        if canonical_record is None:
            report.error(
                "unknown_topic_id",
                f"Topic {normalized_id} is not in the canonical Harmony dataset.",
                row=row_number,
                topic=normalized_id,
            )
            continue
        if not name:
            report.error(
                "missing_topic_name",
                f"Topic {normalized_id} needs a localized name.",
                row=row_number,
                topic=normalized_id,
                field=header[name_index],
            )
            continue
        records.append(
            TopicLocalizationRecord(
                topic_id=normalized_id,
                name=name,
                canonical_name=canonical_record.name,
                source_row=row_number,
            )
        )

    for topic_id in sorted(canonical, key=int):
        if topic_id not in seen:
            report.error(
                "missing_topic_translation",
                f"Canonical topic {topic_id} ({canonical[topic_id].name}) is missing.",
                topic=topic_id,
            )
    records.sort(key=lambda record: int(record.topic_id))
    return TopicLocalizationParseResult(records, report, encoding, header)
