"""Canonical Harmony-reference grammar shared by CSV validation and imports.

The Flutter client consumes the structured ``referenceCells`` emitted by this
module.  Legacy flat ``entries`` remain available as a compatibility projection,
but are no longer the source of separator semantics.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from enum import Enum
from typing import Any, Callable, Iterable

from .import_validation import ValidationReport


class ReferenceSeparator(str, Enum):
    continuous = "+"
    non_continuous = ";"
    same_chapter = ","


class ReferenceRelation(str, Enum):
    single = "single"
    same_chapter_multiple = "sameChapterMultiple"
    continuous = "continuous"
    non_continuous = "nonContinuous"
    mixed = "mixed"


_REFERENCE_PATTERN = re.compile(
    r"^(?P<chapter>\d+)\s*:\s*(?P<start>\d+)(?:\s*-\s*(?P<end>\d+))?$"
)
_INHERITED_VERSE_PATTERN = re.compile(
    r"^(?P<start>\d+)(?:\s*-\s*(?P<end>\d+))?$"
)
_LEGACY_CROSS_CHAPTER_PATTERN = re.compile(
    r"^(?P<chapter>\d+)\s*:\s*(?P<start>\d+)\s*-\s*(?P<end_chapter>\d+)\s*:\s*(?P<end>\d+)$"
)
_SPREADSHEET_MIDNIGHT_PATTERN = re.compile(
    r"^(?P<chapter>\d+)\s*:\s*(?P<verse>\d+)\s*:\s*00$"
)
_GOSPEL_NAMES = {
    "matthew": "Matthew",
    "mark": "Mark",
    "luke": "Luke",
    "john": "John",
    "متى": "Matthew",
    "متّى": "Matthew",
    "مرقس": "Mark",
    "لوقا": "Luke",
    "يوحنا": "John",
}
_DIGIT_TRANSLATION = str.maketrans(
    "٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹",
    "01234567890123456789",
)


def normalize_reference_text(value: str) -> str:
    return (
        (value or "")
        .translate(_DIGIT_TRANSLATION)
        .replace("\u2013", "-")
        .replace("\u2014", "-")
        .strip()
    )


@dataclass(frozen=True)
class ReferenceSegment:
    chapter: int
    start_verse: int
    end_verse: int | None = None
    separator_before: ReferenceSeparator | None = None

    @property
    def verses(self) -> str:
        return (
            str(self.start_verse)
            if self.end_verse is None
            else f"{self.start_verse}-{self.end_verse}"
        )

    @property
    def final_verse(self) -> int:
        return self.end_verse or self.start_verse

    @property
    def display_reference(self) -> str:
        return f"{self.chapter}:{self.verses}"

    def to_firestore(self) -> dict[str, Any]:
        payload: dict[str, Any] = {
            "chapter": self.chapter,
            "verses": self.verses,
            "startVerse": self.start_verse,
            "endVerse": self.final_verse,
        }
        if self.separator_before is not None:
            payload["separatorBefore"] = self.separator_before.value
        return payload

    @classmethod
    def from_firestore(cls, value: dict[str, Any]) -> "ReferenceSegment | None":
        try:
            chapter = int(value.get("chapter"))
        except (TypeError, ValueError):
            return None
        verses = normalize_reference_text(
            str(value.get("verses") or value.get("verse") or "")
        )
        match = _INHERITED_VERSE_PATTERN.fullmatch(verses)
        if chapter < 1 or match is None:
            return None
        separator_text = str(value.get("separatorBefore") or "").strip()
        try:
            separator = ReferenceSeparator(separator_text) if separator_text else None
        except ValueError:
            separator = None
        end_text = match.group("end")
        return cls(
            chapter=chapter,
            start_verse=int(match.group("start")),
            end_verse=int(end_text) if end_text is not None else None,
            separator_before=separator,
        )


@dataclass(frozen=True)
class ReferenceCell:
    book: str
    raw: str
    segments: tuple[ReferenceSegment, ...]

    @property
    def physical_segment_count(self) -> int:
        return len(self.segments)

    @property
    def logical_selection_count(self) -> int:
        if not self.segments:
            return 0
        return 1 + sum(
            segment.separator_before != ReferenceSeparator.continuous
            for segment in self.segments[1:]
        )

    @property
    def relation(self) -> ReferenceRelation:
        separators = {
            segment.separator_before
            for segment in self.segments[1:]
            if segment.separator_before is not None
        }
        if not separators:
            return ReferenceRelation.single
        if separators == {ReferenceSeparator.continuous}:
            return ReferenceRelation.continuous
        if separators == {ReferenceSeparator.same_chapter}:
            return ReferenceRelation.same_chapter_multiple
        if separators == {ReferenceSeparator.non_continuous}:
            return ReferenceRelation.non_continuous
        return ReferenceRelation.mixed

    @property
    def display_value(self) -> str:
        parts: list[str] = []
        for index, segment in enumerate(self.segments):
            if index > 0:
                separator = segment.separator_before or ReferenceSeparator.non_continuous
                parts.append(f" {separator.value} ")
            parts.append(segment.display_reference)
        return "".join(parts)

    def to_firestore(self) -> dict[str, Any]:
        return {
            "book": self.book,
            "raw": self.raw,
            "relation": self.relation.value,
            "logicalSelectionCount": self.logical_selection_count,
            "segments": [segment.to_firestore() for segment in self.segments],
        }

    def to_legacy_entries(self) -> list[dict[str, Any]]:
        entries: list[dict[str, Any]] = []
        logical_group = 0
        index_in_group = 0
        for source_index, segment in enumerate(self.segments):
            if source_index == 0 or segment.separator_before != ReferenceSeparator.continuous:
                logical_group += 1
                index_in_group = 0
            else:
                index_in_group += 1
            adjacent_separators = {
                segment.separator_before,
                self.segments[source_index + 1].separator_before
                if source_index + 1 < len(self.segments)
                else None,
            }
            if ReferenceSeparator.continuous in adjacent_separators:
                group_relation = ReferenceRelation.continuous
            elif ReferenceSeparator.same_chapter in adjacent_separators:
                group_relation = ReferenceRelation.same_chapter_multiple
            elif ReferenceSeparator.non_continuous in adjacent_separators:
                group_relation = ReferenceRelation.non_continuous
            else:
                group_relation = ReferenceRelation.single
            entry: dict[str, Any] = {
                "book": self.book,
                "chapter": segment.chapter,
                "verses": segment.verses,
                "relation": group_relation.value,
                "groupId": f"{self.book.lower()}-{logical_group}",
                "logicalGroup": logical_group,
                "segmentIndex": index_in_group,
                "sourceOrder": source_index,
            }
            if segment.separator_before is not None:
                entry["separatorBefore"] = segment.separator_before.value
            entries.append(entry)
        return entries

    @classmethod
    def from_firestore(cls, value: dict[str, Any]) -> "ReferenceCell | None":
        book = str(value.get("book") or value.get("gospel") or "").strip()
        raw_segments = value.get("segments")
        if not book or not isinstance(raw_segments, list):
            return None
        segments = tuple(
            segment
            for item in raw_segments
            if isinstance(item, dict)
            if (segment := ReferenceSegment.from_firestore(item)) is not None
        )
        if not segments:
            return None
        return cls(
            book=book,
            raw=str(value.get("raw") or "").strip(),
            segments=segments,
        )


VerseCountResolver = Callable[[str, int], int | None]


def _strip_and_validate_book_prefix(
    piece: str,
    *,
    expected_book: str,
    report: ValidationReport,
    location: dict[str, Any],
) -> str:
    match = re.match(r"^([^\d:+;,]+?)\s+(?=\d)", piece)
    if match is None:
        return piece
    supplied = " ".join(match.group(1).split()).casefold()
    canonical = _GOSPEL_NAMES.get(supplied)
    if canonical is None:
        report.error(
            "invalid_reference_book",
            f'Reference book "{match.group(1).strip()}" is not a supported Gospel.',
            **location,
        )
    elif canonical != expected_book:
        report.error(
            "reference_book_mismatch",
            f"{expected_book} cell contains a {canonical} reference.",
            **location,
        )
    return piece[match.end() :].strip()


def _validate_continuity(
    previous: ReferenceSegment,
    current: ReferenceSegment,
    *,
    book: str,
    report: ValidationReport,
    location: dict[str, Any],
    verse_count_resolver: VerseCountResolver | None,
) -> None:
    invalid_reasons: list[str] = []
    if current.chapter != previous.chapter + 1:
        invalid_reasons.append("chapters are not consecutive")
    if current.start_verse != 1:
        invalid_reasons.append("the next segment does not begin at verse 1")

    final_verse_count = (
        verse_count_resolver(book, previous.chapter)
        if verse_count_resolver is not None
        else None
    )
    if final_verse_count is None:
        report.warning(
            "continuity_unverified",
            f"Could not verify the final verse of {book} {previous.chapter}; '+' structure was preserved.",
            **location,
        )
    elif previous.final_verse != final_verse_count:
        invalid_reasons.append(
            f"the first segment ends at verse {previous.final_verse}, not chapter {previous.chapter}'s final verse {final_verse_count}"
        )

    if invalid_reasons:
        report.error(
            "non_continuous_plus",
            "The references joined with '+' do not appear to be continuous ("
            + "; ".join(invalid_reasons)
            + "). Use ';' for non-contiguous passages.",
            **location,
        )


def _validate_segment_bounds(
    segment: ReferenceSegment,
    *,
    book: str,
    report: ValidationReport,
    location: dict[str, Any],
    verse_count_resolver: VerseCountResolver | None,
) -> None:
    if verse_count_resolver is None:
        return
    final_verse_count = verse_count_resolver(book, segment.chapter)
    if final_verse_count is None:
        return
    if segment.start_verse > final_verse_count or segment.final_verse > final_verse_count:
        report.error(
            "verse_out_of_range",
            f"{book} {segment.display_reference} exceeds chapter {segment.chapter}'s final verse {final_verse_count}.",
            **location,
        )


def parse_reference_cell(
    cell: str,
    *,
    book: str,
    report: ValidationReport,
    row: int | None = None,
    topic: str | None = None,
    field: str | None = None,
    verse_count_resolver: VerseCountResolver | None = None,
) -> ReferenceCell:
    """Parse one Gospel cell while preserving every separator edge.

    Commas inherit and must retain the previous chapter. Semicolons start a new
    non-contiguous logical selection but retain legacy chapter inheritance for
    cells such as ``6:25-34; 19-21``. Plus edges keep adjacent physical segments
    in one logical selection and are continuity-checked when Bible metadata is
    available.
    """

    normalized = normalize_reference_text(cell)
    canonical_book = _GOSPEL_NAMES.get(book.strip().casefold(), book.strip())
    if not normalized or normalized in {"-", "—"}:
        return ReferenceCell(canonical_book, normalized, ())

    location = {
        key: value
        for key, value in {
            "row": row,
            "topic": topic,
            "field": field or canonical_book,
        }.items()
        if value is not None
    }
    tokens = re.split(r"\s*([+;,])\s*", normalized)
    segments: list[ReferenceSegment] = []
    pending_separator: ReferenceSeparator | None = None
    inherited_chapter: int | None = None

    for index, token in enumerate(tokens):
        if index % 2 == 1:
            pending_separator = ReferenceSeparator(token)
            continue

        piece = token.strip()
        if not piece:
            report.error(
                "empty_reference_part",
                f"{canonical_book} contains an empty item between reference separators.",
                **location,
            )
            continue
        piece = _strip_and_validate_book_prefix(
            piece,
            expected_book=canonical_book,
            report=report,
            location=location,
        )
        spreadsheet_match = _SPREADSHEET_MIDNIGHT_PATTERN.fullmatch(piece)
        if spreadsheet_match is not None:
            original_piece = piece
            piece = (
                f'{spreadsheet_match.group("chapter")}:'
                f'{spreadsheet_match.group("verse")}'
            )
            report.warning(
                "spreadsheet_time_normalized",
                f'Normalized spreadsheet-coerced reference "{original_piece}" to "{piece}".',
                **location,
            )

        legacy_cross = _LEGACY_CROSS_CHAPTER_PATTERN.fullmatch(piece)
        if legacy_cross is not None:
            chapter = int(legacy_cross.group("chapter"))
            start = int(legacy_cross.group("start"))
            end_chapter = int(legacy_cross.group("end_chapter"))
            end = int(legacy_cross.group("end"))
            final_verse_count = (
                verse_count_resolver(canonical_book, chapter)
                if verse_count_resolver is not None
                else None
            )
            if end_chapter != chapter + 1 or start < 1 or end < 1:
                report.error(
                    "invalid_cross_chapter_reference",
                    f'Legacy cross-chapter reference "{piece}" must continue into the immediately following chapter at verse 1.',
                    **location,
                )
                pending_separator = None
                continue
            if final_verse_count is None:
                report.error(
                    "cross_chapter_metadata_missing",
                    f'Could not determine the final verse of {canonical_book} {chapter} needed to normalize "{piece}". Use explicit "+" segments.',
                    **location,
                )
                pending_separator = None
                continue
            if start > final_verse_count:
                report.error(
                    "invalid_verse",
                    f"{canonical_book} {chapter}:{start} exceeds the chapter's final verse {final_verse_count}.",
                    **location,
                )
                pending_separator = None
                continue
            if (
                pending_separator == ReferenceSeparator.same_chapter
                and inherited_chapter is not None
                and chapter != inherited_chapter
            ):
                report.error(
                    "comma_crosses_chapter",
                    "A comma may only add verses from the same chapter. Use ';' for a separate chapter or '+' for a continuous chapter boundary.",
                    **location,
                )

            first = ReferenceSegment(
                chapter=chapter,
                start_verse=start,
                end_verse=(
                    final_verse_count if final_verse_count != start else None
                ),
                separator_before=pending_separator if segments else None,
            )
            _validate_segment_bounds(
                first,
                book=canonical_book,
                report=report,
                location=location,
                verse_count_resolver=verse_count_resolver,
            )
            if (
                segments
                and first.separator_before == ReferenceSeparator.continuous
            ):
                _validate_continuity(
                    segments[-1],
                    first,
                    book=canonical_book,
                    report=report,
                    location=location,
                    verse_count_resolver=verse_count_resolver,
                )
            segments.append(first)
            second = ReferenceSegment(
                chapter=end_chapter,
                start_verse=1,
                end_verse=end if end != 1 else None,
                separator_before=ReferenceSeparator.continuous,
            )
            _validate_segment_bounds(
                second,
                book=canonical_book,
                report=report,
                location=location,
                verse_count_resolver=verse_count_resolver,
            )
            _validate_continuity(
                first,
                second,
                book=canonical_book,
                report=report,
                location=location,
                verse_count_resolver=verse_count_resolver,
            )
            segments.append(second)
            report.warning(
                "legacy_cross_chapter_syntax",
                f'Normalized legacy cross-chapter reference "{piece}" to "{first.display_reference} + {second.display_reference}".',
                **location,
            )
            inherited_chapter = end_chapter
            pending_separator = None
            continue

        match = _REFERENCE_PATTERN.fullmatch(piece)
        inherited = False
        if match is None and inherited_chapter is not None:
            inherited_match = _INHERITED_VERSE_PATTERN.fullmatch(piece)
            if inherited_match is not None:
                inherited = True
                match = inherited_match
        if match is None:
            report.error(
                "invalid_reference",
                f'{canonical_book} reference "{piece}" must be chapter:verse or chapter:start-end.',
                **location,
            )
            pending_separator = None
            continue

        chapter = inherited_chapter if inherited else int(match.group("chapter"))
        start = int(match.group("start"))
        end_text = match.group("end")
        end = int(end_text) if end_text is not None else None
        if chapter is None or chapter < 1:
            report.error(
                "invalid_chapter",
                f"{canonical_book} chapter must be greater than zero.",
                **location,
            )
            pending_separator = None
            continue
        if start < 1 or (end is not None and end < 1):
            report.error(
                "invalid_verse",
                f"{canonical_book} verse numbers must be greater than zero.",
                **location,
            )
            pending_separator = None
            continue
        if end is not None and end < start:
            report.error(
                "reversed_verse_range",
                f"{canonical_book} range {start}-{end} ends before it starts.",
                **location,
            )
            pending_separator = None
            continue
        if (
            pending_separator == ReferenceSeparator.same_chapter
            and inherited_chapter is not None
            and chapter != inherited_chapter
        ):
            report.error(
                "comma_crosses_chapter",
                "A comma may only add verses from the same chapter. Use ';' for a separate chapter or '+' for a continuous chapter boundary.",
                **location,
            )

        segment = ReferenceSegment(
            chapter=chapter,
            start_verse=start,
            end_verse=end,
            separator_before=pending_separator if segments else None,
        )
        _validate_segment_bounds(
            segment,
            book=canonical_book,
            report=report,
            location=location,
            verse_count_resolver=verse_count_resolver,
        )
        if (
            segments
            and segment.separator_before == ReferenceSeparator.continuous
        ):
            _validate_continuity(
                segments[-1],
                segment,
                book=canonical_book,
                report=report,
                location=location,
                verse_count_resolver=verse_count_resolver,
            )
        segments.append(segment)
        inherited_chapter = chapter
        pending_separator = None

    seen_segments: set[tuple[int, int, int]] = set()
    for segment in segments:
        signature = (segment.chapter, segment.start_verse, segment.final_verse)
        if signature in seen_segments:
            report.error(
                "duplicate_reference_segment",
                f"{canonical_book} {segment.display_reference} appears more than once in the same cell.",
                **location,
            )
        seen_segments.add(signature)

    return ReferenceCell(canonical_book, normalized, tuple(segments))


def reference_cells_from_firestore(values: Iterable[Any]) -> tuple[ReferenceCell, ...]:
    cells: list[ReferenceCell] = []
    for value in values:
        if not isinstance(value, dict):
            continue
        cell = ReferenceCell.from_firestore(value)
        if cell is not None:
            cells.append(cell)
    return tuple(cells)
