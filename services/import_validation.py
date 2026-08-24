from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Iterable


@dataclass(frozen=True)
class ValidationIssue:
    severity: str
    code: str
    message: str
    row: int | None = None
    topic: str | None = None
    field: str | None = None
    filename: str | None = None

    def to_dict(self) -> dict[str, Any]:
        return {
            key: value
            for key, value in {
                "severity": self.severity,
                "code": self.code,
                "message": self.message,
                "row": self.row,
                "topic": self.topic,
                "field": self.field,
                "filename": self.filename,
            }.items()
            if value is not None
        }


@dataclass
class ValidationReport:
    errors: list[ValidationIssue] = field(default_factory=list)
    warnings: list[ValidationIssue] = field(default_factory=list)

    @property
    def valid(self) -> bool:
        return not self.errors

    def error(self, code: str, message: str, **location: Any) -> None:
        self.errors.append(
            ValidationIssue("error", code, message, **location)
        )

    def warning(self, code: str, message: str, **location: Any) -> None:
        self.warnings.append(
            ValidationIssue("warning", code, message, **location)
        )

    def extend(self, issues: Iterable[ValidationIssue]) -> None:
        for issue in issues:
            if issue.severity == "error":
                self.errors.append(issue)
            else:
                self.warnings.append(issue)

    def to_dict(self) -> dict[str, Any]:
        return {
            "valid": self.valid,
            "errors": [issue.to_dict() for issue in self.errors],
            "warnings": [issue.to_dict() for issue in self.warnings],
        }


def decode_legacy_csv(raw: bytes) -> tuple[str, str]:
    """Decode using the exact fallback order used by the legacy CSV script."""
    for encoding in ("utf-8-sig", "utf-8", "cp1252", "latin-1"):
        try:
            return raw.decode(encoding), encoding
        except UnicodeDecodeError:
            continue
    raise UnicodeDecodeError("csv", raw, 0, len(raw), "unsupported encoding")


def decode_usfm(raw: bytes) -> tuple[str, str]:
    """USFM uploads remain UTF-8, matching Storage.download_as_text()."""
    for encoding in ("utf-8-sig", "utf-8"):
        try:
            return raw.decode(encoding), encoding
        except UnicodeDecodeError:
            continue
    raise UnicodeDecodeError("usfm", raw, 0, len(raw), "USFM must be UTF-8")

