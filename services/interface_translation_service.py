"""Interface CSV validation and shared, bundled UI translations."""
from __future__ import annotations

import csv
import io
import json
import re
from dataclasses import dataclass
from pathlib import Path

from .import_validation import ValidationReport

CATALOG = json.loads(
    (Path(__file__).resolve().parents[1] / "localization/interface_translations.json")
    .read_text(encoding="utf-8")
)
ENGLISH = CATALOG["english"]
_PLACEHOLDER = re.compile(r"\{([A-Za-z][A-Za-z0-9]*)\}")


def language_key(language: str) -> str:
    code = language.strip().lower()
    return {"fr": "french", "fr-fr": "french", "fr_fr": "french",
            "français": "french", "francais": "french", "en": "english",
            "ar": "arabic"}.get(code, code)


def clean_translations(value) -> dict[str, str]:
    if not isinstance(value, dict):
        return {}
    return {key: text.strip() for key, text in value.items()
            if key in ENGLISH and isinstance(text, str) and text.strip()}


def translated_labels(language: str, overrides=None) -> dict[str, str]:
    return {**CATALOG.get(language_key(language), {}), **clean_translations(overrides)}


def translation_status(language: str, overrides=None) -> dict:
    translated = translated_labels(language, overrides)
    missing = [key for key in ENGLISH if key not in translated]
    return {"translated": len(ENGLISH) - len(missing), "total": len(ENGLISH),
            "missingKeys": missing, "complete": not missing}


def interface_csv_template(language: str, overrides=None) -> str:
    output = io.StringIO(newline="")
    output.write("\ufeff")  # Excel recognizes UTF-8 accents without an import wizard.
    writer = csv.writer(output)
    writer.writerow(["Key", "English", "Translation"])
    translated = translated_labels(language, overrides)
    for key, english in ENGLISH.items():
        writer.writerow([key, english, translated.get(key, "")])
    return output.getvalue()


@dataclass
class InterfaceTranslationResult:
    translations: dict[str, str]
    report: ValidationReport
    language: str

    def summary(self) -> dict:
        status = translation_status(self.language, self.translations)
        return {**self.report.to_dict(), "stats": {
            "labels": len(self.translations), "translated": status["translated"],
            "total": status["total"], "missing": len(status["missingKeys"])},
            "missingKeys": status["missingKeys"],
            "preview": [{"key": key, "english": ENGLISH[key], "translation": text}
                        for key, text in self.translations.items()]}


def parse_interface_csv(raw: bytes, language: str) -> InterfaceTranslationResult:
    report = ValidationReport()
    result = InterfaceTranslationResult({}, report, language)
    if len(raw) > 512 * 1024:
        report.error("interface_file_too_large", "Interface CSV files must be 512 KB or smaller.")
        return result
    try:
        text = raw.decode("utf-8-sig")
    except UnicodeDecodeError:
        report.error("unsupported_encoding", "Save the spreadsheet as CSV UTF-8.")
        return result
    if any(ord(char) < 32 and char not in "\r\n\t" for char in text):
        report.error("invalid_text", "The CSV contains binary or control characters.")
        return result
    # Excel uses semicolons as CSV separators in many French installations.
    first_line = text.splitlines()[0] if text.splitlines() else ""
    delimiter = ";" if ";" in first_line and "," not in first_line else ","
    try:
        rows = list(csv.reader(io.StringIO(text), delimiter=delimiter, strict=True))
    except csv.Error:
        report.error("malformed_csv", "The CSV has invalid quoting.")
        return result
    if not rows:
        report.error("empty_csv", "The CSV is empty.")
        return result
    headers = [cell.strip().lower() for cell in rows[0]]
    if (headers.count("key") != 1 or headers.count("translation") != 1
            or len(headers) != len(set(headers))
            or any(header not in {"key", "english", "translation"} for header in headers)):
        report.error("invalid_columns", "Use Key,Translation or Key,English,Translation columns.")
        return result
    key_index, translation_index = headers.index("key"), headers.index("translation")
    seen = set()
    for number, row in enumerate(rows[1:], 2):
        if not any(cell.strip() for cell in row):
            continue
        if len(row) != len(headers):
            report.error("invalid_columns", "Each row must match the header. Quote text containing separators.", row=number)
            continue
        key, value = row[key_index].strip(), row[translation_index].strip()
        if key not in ENGLISH:
            report.error("unknown_key", f'Unknown interface key "{key}". Download the current template.', row=number)
            continue
        if key in seen:
            report.error("duplicate_key", f'Key "{key}" appears more than once.', row=number, field=key)
            continue
        seen.add(key)
        if not value:
            continue  # Empty cells deliberately use the bundled/English fallback.
        if len(value) > 2000 or any(ord(char) < 32 for char in value):
            report.error("invalid_translation", "Use a single line of at most 2,000 characters.", row=number, field=key)
            continue
        required = set(_PLACEHOLDER.findall(ENGLISH[key]))
        supplied = set(_PLACEHOLDER.findall(value))
        remainder = _PLACEHOLDER.sub("", value)
        if required != supplied or "{" in remainder or "}" in remainder:
            placeholders = ", ".join("{" + name + "}" for name in sorted(required)) or "none"
            report.error("invalid_placeholders", f"Required placeholders: {placeholders}. Keep their spelling unchanged.", row=number, field=key)
            continue
        result.translations[key] = value
    if not result.translations:
        report.error("empty_translations", "Enter at least one interface translation.")
    omitted = [key for key in ENGLISH if key not in result.translations]
    if omitted:
        report.warning("fallback_labels", f"{len(omitted)} labels are blank or absent; bundled translations, then English, will be used. This replaces previous uploaded overrides.")
    return result
