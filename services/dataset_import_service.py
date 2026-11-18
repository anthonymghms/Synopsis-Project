"""Header-mapped imports for independent tables; never infer Harmony identities."""
from __future__ import annotations

import csv
import hashlib
import io
import re
import unicodedata
from collections import Counter
from dataclasses import dataclass
from typing import Any

from .import_validation import ValidationReport
from .reference_parser import ReferenceCell, VerseCountResolver, parse_reference_cell
from .topic_import_service import GOSPELS

DATASET_FILES = {"miracles": "Miracles.csv", "parables": "Parables.csv"}
DATASET_LABELS = {
    "miracles": {"english": "Miracles", "arabic": "المعجزات"},
    "parables": {"english": "Parables", "arabic": "الأمثال"},
}
HARMONY_LABELS = {"english": "Harmony / All Topics", "arabic": "التوافق / جميع المواضيع"}
GOSPEL_LABELS = {
    "english": dict(zip(GOSPELS, GOSPELS)),
    "arabic": dict(zip(GOSPELS, ("متى", "مرقس", "لوقا", "يوحنا"))),
}


def dataset_id(value: Any) -> str:
    value = value.strip() if isinstance(value, str) else ""
    if value == "harmony":
        raise ValueError("Harmony is protected and uses its separate master workflow.")
    if not 2 <= len(value) <= 48 or not re.fullmatch(r"[a-z][a-z0-9]*(?:-[a-z0-9]+)*", value):
        raise ValueError("Table ID must contain 2–48 lowercase letters, numbers, or single hyphens, starting with a letter.")
    return value


def dataset_labels(value: Any) -> dict[str, str]:
    """Validate administrator-supplied display labels, never infer identity."""
    if not isinstance(value, dict) or set(value) - {"english", "arabic"}:
        raise ValueError("Supply an English table name and, optionally, an Arabic table name.")
    labels = {}
    for language in ("english", "arabic"):
        label = value.get(language, "")
        if not isinstance(label, str):
            raise ValueError("Table names must be text.")
        label = label.strip()
        if (language == "english" and not label) or len(label) > 80 or any(ord(c) < 32 for c in label):
            raise ValueError("Table names must contain 1–80 characters without control characters; the English name is required.")
        if label:
            labels[language] = label
    return labels


def _key(value: str) -> str:
    return "".join(c for c in unicodedata.normalize("NFKC", value).casefold() if c.isalnum())


_ALIASES = {
    "id": {"#", "id", "number", "no", "topicid", "topicnumber", "itemid", "رقم", "الرقم"},
    "order": {"order", "sourceorder", "canonicalorder", "الترتيب"},
    "english": {"subject", "subjects", "topic", "name", "english", "subjectenglish", "subjecten", "nameen", "miracles", "parables"},
    "arabic": {"الموضوع", "موضوع", "المعجزات", "المعجزة", "الأمثال", "المثل", "arabic", "subjectarabic", "subjectar", "namear"},
    "type": {"type", "typeenglish", "typeen", "classification"},
    "typeArabic": {"النوع", "نوع", "typearabic", "typear"},
    "typeId": {"typeid", "classificationid"},
    "typeOrder": {"typeorder"},
    "Matthew": {"matthew", "matt", "mat", "متى"},
    "Mark": {"mark", "mrk", "مرقس"},
    "Luke": {"luke", "luk", "لوقا"},
    "John": {"john", "jhn", "يوحنا"},
}
_ALIAS_MAP = {_key(alias) if alias != "#" else "#": target for target, aliases in _ALIASES.items() for alias in aliases}


def _decode(raw: bytes) -> tuple[str, str]:
    if raw.startswith(b"\xef\xbb\xbf"):
        return raw.decode("utf-8-sig"), "utf-8-sig"
    if raw.startswith((b"\xff\xfe", b"\xfe\xff")):
        return raw.decode("utf-16"), "utf-16"
    for encoding in ("utf-8", "cp1252", "latin-1"):
        try:
            return raw.decode(encoding), encoding
        except UnicodeDecodeError:
            continue
    raise ValueError("The CSV could not be decoded.")


def _type_id(label: str) -> str:
    normalized = unicodedata.normalize("NFKC", label).casefold().strip()
    slug = re.sub(r"[^a-z0-9]+", "-", normalized).strip("-")
    # Non-ASCII labels retain independent identities without inventing translations.
    if not slug or any(ord(c) > 127 for c in normalized):
        return "type-" + hashlib.sha256(normalized.encode()).hexdigest()[:16]
    return slug


@dataclass(frozen=True)
class DatasetItem:
    item_id: str
    source_number: str
    source_order: int
    names: dict[str, str]
    type_id: str | None
    reference_cells: tuple[ReferenceCell, ...]
    source_row: int

    def canonical(self) -> dict[str, Any]:
        return {
            "sourceNumber": self.source_number,
            "sourceOrder": self.source_order,
            "canonicalOrder": self.source_order,
            "typeId": self.type_id,
            "entries": [entry for cell in self.reference_cells for entry in cell.to_legacy_entries()],
            "referenceCells": [cell.to_firestore() for cell in self.reference_cells],
            "referenceGrammarVersion": 2,
        }

    def preview(self, types: dict[str, dict]) -> dict[str, Any]:
        labels = types.get(self.type_id, {}).get("labels", {})
        return {
            "id": self.item_id, "sourceNumber": self.source_number,
            "sourceOrder": self.source_order, "names": self.names,
            "name": self.names.get("english") or next(iter(self.names.values()), ""),
            "typeId": self.type_id, "type": labels.get("english") or next(iter(labels.values()), ""),
            "references": {book: next((cell.display_value for cell in self.reference_cells if cell.book == book), "") for book in GOSPELS},
        }


@dataclass
class DatasetParseResult:
    records: list[DatasetItem]
    report: ValidationReport
    header: list[str]
    encoding: str
    delimiter: str
    languages: list[str]
    types: list[dict[str, Any]]
    row_count: int
    has_type_column: bool
    mapping: dict[str, str]

    def summary(self, preview_limit: int = 20) -> dict[str, Any]:
        return {
            **self.report.to_dict(), "header": self.header, "encoding": self.encoding,
            "delimiter": "tab" if self.delimiter == "\t" else "comma",
            "columnMapping": self.mapping, "rowCount": self.row_count,
            "languages": self.languages, "types": self.types,
            "hasTypes": bool(self.types), "hasTypeColumn": self.has_type_column,
            "stats": {
                "items": len(self.records), "topics": len(self.records),
                "references": sum(cell.logical_selection_count for item in self.records for cell in item.reference_cells),
                "physicalSegments": sum(cell.physical_segment_count for item in self.records for cell in item.reference_cells),
                "missingTypes": sum(item.type_id is None for item in self.records),
            },
            "preview": [item.preview({value["id"]: value for value in self.types}) for item in self.records[:preview_limit]],
        }


def parse_dataset_csv(raw: bytes, *, verse_count_resolver: VerseCountResolver | None = None) -> DatasetParseResult:
    report = ValidationReport()
    result = DatasetParseResult([], report, [], "unknown", ",", [], [], 0, False, {})
    try:
        text, result.encoding = _decode(raw)
        # Storage's .csv files are TSV. Select only a header delimiter, so quoted
        # commas in passage selections can never change the column mapping.
        header_line = text.splitlines()[0] if text.splitlines() else ""
        result.delimiter = "\t" if "\t" in header_line else ","
        rows = list(csv.reader(io.StringIO(text, newline=""), delimiter=result.delimiter, strict=True))
    except (csv.Error, UnicodeError, ValueError) as exc:
        report.error("malformed_csv", f"The CSV could not be parsed: {exc}")
        return result
    if not rows:
        report.error("empty_csv", "The CSV is empty.")
        return result
    result.header = [value.strip() for value in rows[0]]
    columns: dict[str, int] = {}
    for index, header in enumerate(result.header):
        target = _ALIAS_MAP.get("#" if header == "#" else _key(header))
        if not target:
            report.warning("unknown_column", f'Column "{header}" is not imported.', row=1, field=header)
        elif target in columns:
            report.error("ambiguous_columns", f'Two columns map to "{target}". Rename or remove one before import.', row=1, field=header)
        else:
            columns[target] = index
            result.mapping[target] = header
    for book in GOSPELS:
        if book not in columns:
            report.error("missing_gospel_column", f"The {book} column is required (cells may be empty).", row=1, field=book)
    result.languages = [language for language in ("english", "arabic") if language in columns]
    if not result.languages:
        report.error("missing_subject_column", "Include Subject / Miracles and/or الموضوع / المعجزات.", row=1)
    result.has_type_column = any(key in columns for key in ("type", "typeArabic", "typeId"))
    if "id" not in columns:
        report.warning("positional_item_ids", "No ID column was found. Physical source row numbers are used as IDs; add a # or ItemId column before reordering future imports.")
    if report.errors:
        return result
    seen_ids: dict[str, int] = {}
    seen_names: dict[tuple[str, str], int] = {}
    type_values: dict[str, dict] = {}
    for source_row, row in enumerate(rows[1:], start=2):
        if not any(value.strip() for value in row):
            report.warning("blank_row", "Blank source row ignored; physical source row numbering is retained.", row=source_row)
            continue
        result.row_count += 1
        if len(row) != len(result.header):
            report.error("column_count_mismatch", f"Expected {len(result.header)} columns but found {len(row)}. Quote cells containing commas in comma-delimited CSV.", row=source_row)
            continue
        def value(field: str) -> str:
            return row[columns[field]].strip() if field in columns else ""
        raw_id = value("id") if "id" in columns else str(source_row - 1)
        item_id = str(int(raw_id)) if raw_id.isdecimal() else raw_id
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]{0,79}", item_id) or (item_id.isdecimal() and int(item_id) < 1):
            report.error("invalid_item_id", "Each ID must be a positive number or a simple stable identifier (letters, digits, underscore, hyphen).", row=source_row, field=result.mapping.get("id", "#"))
            continue
        if item_id in seen_ids:
            report.error("duplicate_item_id", f'ID "{item_id}" also appears on row {seen_ids[item_id]}.', row=source_row)
            continue
        seen_ids[item_id] = source_row
        try:
            order = int(value("order")) if "order" in columns else source_row - 1
            if order < 1:
                raise ValueError
        except ValueError:
            report.error("invalid_source_order", "Source order must be a positive integer.", row=source_row)
            continue
        names = {language: value(language) for language in result.languages if value(language)}
        if not names:
            report.error("missing_subject", "At least one subject name is required.", row=source_row)
            continue
        for language in result.languages:
            if language not in names:
                report.warning("missing_localized_name", f"Missing {language} subject; readers will fall back to this item's available name.", row=source_row, field=result.mapping[language])
            else:
                key = (language, names[language].casefold())
                if key in seen_names:
                    report.warning("duplicate_subject", f"The {language} subject also appears on row {seen_names[key]}; both IDs are preserved.", row=source_row)
                seen_names[key] = source_row
        labels = {language: label for language, label in (("english", value("type")), ("arabic", value("typeArabic"))) if label}
        classification = value("typeId") or (_type_id(value("type") or value("typeArabic")) if labels else None)
        if classification:
            if not re.fullmatch(r"[a-z0-9][a-z0-9_-]{0,99}", classification) or classification == "unclassified":
                report.error("invalid_type_id", "TypeId must be a stable lowercase identifier; 'unclassified' is reserved for missing values.", row=source_row)
                continue
            try:
                type_order = int(value("typeOrder")) if value("typeOrder") else None
            except ValueError:
                report.error("invalid_type_order", "TypeOrder must be an integer.", row=source_row)
                continue
            existing = type_values.setdefault(classification, {"id": classification, "labels": {}, "order": type_order})
            if type_order is not None and existing["order"] not in (None, type_order):
                report.error("inconsistent_type_order", f'Type "{classification}" has conflicting ordering values.', row=source_row)
            if type_order is not None:
                existing["order"] = type_order
            for language, label in labels.items():
                previous = existing["labels"].get(language)
                if previous and previous != label:
                    report.error("conflicting_type_labels", f'Type "{classification}" has conflicting {language} labels. Use consistent labels or distinct explicit TypeId values.', row=source_row)
                existing["labels"][language] = label
        cells = []
        for book in GOSPELS:
            cell = parse_reference_cell(value(book), book=book, row=source_row, topic=names.get("english") or next(iter(names.values())), field=result.mapping[book], report=report, verse_count_resolver=verse_count_resolver)
            if cell.segments:
                cells.append(cell)
        if not cells:
            report.warning("item_without_references", "This item has no Gospel references; visible-column filtering will hide it until references are supplied.", row=source_row)
        result.records.append(DatasetItem(item_id, raw_id, order, names, classification, tuple(cells), source_row))
    result.records.sort(key=lambda item: (item.source_order, item.item_id))
    counts = Counter(item.type_id for item in result.records)
    result.types = sorted(({**value, "count": counts[key]} for key, value in type_values.items()), key=lambda value: (value["order"] is None, value["order"] or 0, value["id"]))
    if not result.types:
        report.warning("no_type_data", "No populated Type values were found. The table remains usable; grouping and Type filtering require an updated source with Type values.")
    elif counts[None]:
        report.warning("missing_type_values", f"{counts[None]} items have no Type; these remain available as Unclassified.")
    if not result.records:
        report.error("empty_dataset", "No importable items were found.")
    return result
