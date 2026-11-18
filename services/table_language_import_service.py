"""Strict, identity-based language overlays for all public topic tables."""
from __future__ import annotations

import csv
import io
import re
from dataclasses import dataclass
from typing import Any

from .dataset_import_service import GOSPEL_LABELS, _decode, dataset_id
from .import_validation import ValidationReport
from .topic_import_service import GOSPELS

def table_id(value: Any) -> str:
    identifier = value.strip() if isinstance(value, str) else ""
    return identifier if identifier == "harmony" else dataset_id(identifier)


def language_id(value: Any) -> str:
    identifier = str(value or "").strip().lower()
    if not re.fullmatch(r"[a-z][a-z0-9_-]{1,39}", identifier):
        raise ValueError("Language must be a stable lowercase identifier, such as french or fr.")
    return {"en": "english", "ar": "arabic"}.get(identifier, identifier)


def _text(value: Any, field: str, maximum: int, *, required=True) -> str:
    value = str(value or "").strip()
    if (required and not value) or len(value) > maximum or any(ord(c) < 32 for c in value):
        raise ValueError(f"{field} must contain {'1' if required else '0'}–{maximum} characters without control characters.")
    return value


def language_metadata(fields: dict, gospels: dict, item_count: int = 0) -> dict:
    language = language_id(fields.get("language"))
    direction = fields.get("direction")
    if direction not in ("ltr", "rtl"):
        raise ValueError("Direction must be ltr or rtl.")
    if not isinstance(gospels, dict) or set(gospels) != set(GOSPELS):
        raise ValueError("Supply display labels for Matthew, Mark, Luke, and John.")
    return {
        "id": language, "label": _text(fields.get("displayName"), "Language display name", 80),
        "direction": direction, "subjectsLabel": _text(fields.get("subjectsLabel"), "Subjects label", 80),
        "gospels": {book: _text(gospels[book], f"{book} label", 80) for book in GOSPELS},
        "topicCount": item_count, "canonicalTopicCount": item_count,
        "complete": item_count > 0, "active": True,
    }


def default_language_metadata(language: str, count: int) -> dict:
    return {"id": language, "label": "العربية" if language == "arabic" else language.title(),
            "direction": "rtl" if language == "arabic" else "ltr", "subjectsLabel": "المواضيع" if language == "arabic" else "Subjects",
            "gospels": GOSPEL_LABELS.get(language, GOSPEL_LABELS["english"]),
            "topicCount": count, "canonicalTopicCount": count, "complete": count > 0, "active": True}


@dataclass
class TableLanguageParseResult:
    records: list[dict]
    type_labels: dict[str, str]
    report: ValidationReport
    header: list[str]
    encoding: str
    delimiter: str

    def summary(self):
        return {**self.report.to_dict(), "encoding": self.encoding, "header": self.header,
                "delimiter": "tab" if self.delimiter == "\t" else "comma",
                "stats": {"items": len(self.records), "topics": len(self.records), "translations": len(self.records), "types": len(self.type_labels)},
                "preview": [{key: value for key, value in row.items() if key != "canonicalOrder"} for row in self.records[:30]]}


def parse_table_language_csv(raw: bytes, canonical: list[dict], types: list[dict]) -> TableLanguageParseResult:
    report = ValidationReport()
    result = TableLanguageParseResult([], {}, report, [], "unknown", ",")
    try:
        text, result.encoding = _decode(raw)
        if any(ord(c) < 32 and c not in "\r\n\t" for c in text):
            raise ValueError("The file contains binary/control characters; save it as UTF-8 CSV.")
        if result.encoding not in ("utf-8", "utf-8-sig"):
            report.warning("legacy_encoding", f"Decoded as {result.encoding}; UTF-8 is recommended.")
        first_line = text.splitlines()[0] if text.splitlines() else ""
        result.delimiter = "\t" if "\t" in first_line else ","
        rows = list(csv.reader(io.StringIO(text, newline=""), delimiter=result.delimiter, strict=True))
    except (ValueError, UnicodeError, csv.Error) as exc:
        report.error("malformed_csv", str(exc))
        return result
    if not rows:
        report.error("empty_csv", "The CSV is empty. Download the dataset's translation template.")
        return result
    result.header = [cell.strip() for cell in rows[0]]
    aliases = {"itemid": "id", "topicid": "id", "topicnumber": "id", "id": "id", "#": "id", "sourcename": "sourceName", "translation": "translation", "topicname": "translation", "typeid": "typeId", "typetranslation": "typeTranslation"}
    columns = {}
    for index, header in enumerate(result.header):
        key = "#" if header == "#" else "".join(c for c in header.casefold() if c.isalnum())
        target = aliases.get(key)
        if target is None:
            report.error("unsupported_column", f'Column "{header}" is not a language-overlay column. Use the downloaded template; references and classifications cannot be edited here.', row=1, field=header)
        elif target in columns:
            report.error("duplicate_header", f'Two columns map to "{target}".', row=1, field=header)
        else:
            columns[target] = index
    if "id" not in columns or "translation" not in columns:
        report.error("explicit_ids_required", "The first row must be the header ItemId,SourceName,Translation. Remove title rows and include explicit IDs; names-only files cannot be aligned safely.", row=1)
    if "typeTranslation" in columns and "typeId" not in columns:
        report.error("type_id_required", "TypeTranslation requires the TypeId column from the template.", row=1)
    if report.errors:
        return result
    by_id = {str(item["id"]): item for item in canonical}
    known_types = {str(item["id"]) for item in types}
    if not by_id:
        report.error("dataset_not_published", "Publish the canonical dataset before adding a table language.")
        return result
    seen = set()
    for row_number, row in enumerate(rows[1:], start=2):
        if not any(value.strip() for value in row):
            report.error("blank_translation_row", "Blank translation rows are not allowed; retain every template ItemId.", row=row_number)
            continue
        if len(row) != len(result.header):
            report.error("column_count_mismatch", "The row width differs from the header. Quote translated names containing commas.", row=row_number)
            continue
        def cell(key):
            return row[columns[key]].strip() if key in columns else ""
        identifier = cell("id")
        # Explicit string IDs are case-sensitive; numeric leading zeros match
        # the canonical importer normalization without positional alignment.
        identifier = str(int(identifier)) if identifier.isdecimal() else identifier
        if not identifier:
            report.error("missing_item_id", "Every translation needs the explicit ItemId from the template.", row=row_number)
            continue
        if identifier in seen:
            report.error("duplicate_item_id", f'ItemId "{identifier}" appears more than once.', row=row_number)
            continue
        seen.add(identifier)
        original = by_id.get(identifier)
        if original is None:
            report.error("unknown_item_id", f'ItemId "{identifier}" is not in the selected dataset. Download its template; title rows and unrelated IDs are not translations.', row=row_number)
            continue
        translation = cell("translation")
        if not translation or len(translation) > 1500 or any(ord(c) < 32 for c in translation):
            report.error("missing_or_invalid_translation", "Supply a translated subject of 1–1500 characters without control characters.", row=row_number, topic=identifier)
        type_id = str(original.get("typeId") or "")
        if "typeId" in columns and cell("typeId") != type_id:
            report.error("type_identity_mismatch", f'Item {identifier} must retain TypeId "{type_id}" from the template. This workflow cannot reclassify items.', row=row_number)
        translated_type = cell("typeTranslation")
        if translated_type:
            if not type_id or type_id not in known_types:
                report.error("unknown_type_id", "Only an existing populated TypeId can receive a Type translation.", row=row_number)
            elif len(translated_type) > 160 or any(ord(c) < 32 for c in translated_type):
                report.error("invalid_type_translation", "Type translations must contain 1–160 characters without control characters.", row=row_number)
            elif result.type_labels.get(type_id, translated_type) != translated_type:
                report.error("conflicting_type_translation", f'All translated labels for TypeId "{type_id}" must agree.', row=row_number)
            else:
                result.type_labels[type_id] = translated_type
        result.records.append({"id": identifier, "sourceName": str(original.get("sourceName") or ""), "translation": translation, "typeId": type_id, "typeTranslation": translated_type, "canonicalOrder": original.get("canonicalOrder", 0)})
    missing = sorted(set(by_id) - seen)
    if missing:
        report.error("missing_item_translations", f"Missing {len(missing)} ItemIds: {', '.join(missing[:30])}. Supply a translation for every item.")
    result.records.sort(key=lambda item: (item["canonicalOrder"], item["id"]))
    if known_types - set(result.type_labels):
        report.warning("missing_type_translations", "Some Types have no supplied translation; their existing labels or source labels remain available.")
    return result


def table_language_template(canonical: list[dict], types: list[dict], language: str, translations: dict[str, str]) -> str:
    output = io.StringIO(newline="")
    writer = csv.writer(output)
    header = ["ItemId", "SourceName", "Translation"]
    if types:
        header += ["TypeId", "TypeTranslation"]
    writer.writerow(header)
    labels = {item["id"]: item.get("labels", {}).get(language, "") for item in types}
    for item in canonical:
        row = [item["id"], item.get("sourceName", ""), translations.get(item["id"], "")]
        if types:
            row += [item.get("typeId") or "", labels.get(item.get("typeId"), "")]
        writer.writerow(row)
    return output.getvalue()
