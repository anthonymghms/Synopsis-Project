import unittest

from services.reference_parser import (
    ReferenceRelation,
    ReferenceSeparator,
    parse_reference_cell,
)
from services.import_validation import ValidationReport
from services.topic_import_service import parse_topic_csv, records_from_firestore


class _Document:
    id = "1"

    def to_dict(self):
        return {
            "name": "Continuous",
            "canonicalOrder": 1,
            "referenceCells": [
                {
                    "book": "Luke",
                    "raw": "1:78-80 + 2:1-7",
                    "segments": [
                        {"chapter": 1, "verses": "78-80"},
                        {
                            "chapter": 2,
                            "verses": "1-7",
                            "separatorBefore": "+",
                        },
                    ],
                }
            ],
        }


class ReferenceParserTests(unittest.TestCase):
    def parse(self, value, *, verse_counts=None):
        report = ValidationReport()
        counts = verse_counts or {}
        cell = parse_reference_cell(
            value,
            book="John" if value.lstrip().startswith("John") else (
                "Matthew" if value.lstrip().startswith("Matthew") else "Luke"
            ),
            report=report,
            row=2,
            topic="Test",
            verse_count_resolver=lambda book, chapter: counts.get((book, chapter)),
        )
        return cell, report

    def test_single_reference_is_one_segment_and_selection(self):
        cell, report = self.parse("John 8:1")

        self.assertTrue(report.valid)
        self.assertEqual(cell.physical_segment_count, 1)
        self.assertEqual(cell.logical_selection_count, 1)
        self.assertEqual(cell.relation, ReferenceRelation.single)
        self.assertEqual(cell.segments[0].display_reference, "8:1")

    def test_comma_inherits_same_chapter_for_single_verses(self):
        cell, report = self.parse("John 8:1,34")

        self.assertTrue(report.valid)
        self.assertEqual(
            [segment.display_reference for segment in cell.segments],
            ["8:1", "8:34"],
        )
        self.assertEqual(cell.relation, ReferenceRelation.same_chapter_multiple)
        self.assertEqual(cell.logical_selection_count, 2)
        self.assertEqual(
            cell.segments[1].separator_before,
            ReferenceSeparator.same_chapter,
        )

    def test_comma_inherits_same_chapter_for_ranges(self):
        cell, report = self.parse("John 8:1-12,20-25")

        self.assertTrue(report.valid)
        self.assertEqual(
            [segment.display_reference for segment in cell.segments],
            ["8:1-12", "8:20-25"],
        )
        self.assertEqual(cell.logical_selection_count, 2)

    def test_semicolon_creates_non_contiguous_selections(self):
        cell, report = self.parse("Matthew 5:31-32;19:9")

        self.assertTrue(report.valid)
        self.assertEqual(
            [segment.display_reference for segment in cell.segments],
            ["5:31-32", "19:9"],
        )
        self.assertEqual(cell.relation, ReferenceRelation.non_continuous)
        self.assertEqual(cell.logical_selection_count, 2)

    def test_plus_creates_one_continuous_logical_selection(self):
        cell, report = self.parse(
            "Luke 1:78-80+2:1-7",
            verse_counts={("Luke", 1): 80},
        )

        self.assertTrue(report.valid)
        self.assertEqual(cell.physical_segment_count, 2)
        self.assertEqual(cell.logical_selection_count, 1)
        self.assertEqual(cell.relation, ReferenceRelation.continuous)
        self.assertEqual(
            [segment.display_reference for segment in cell.segments],
            ["1:78-80", "2:1-7"],
        )

    def test_plus_reports_provably_non_continuous_ranges(self):
        cell, report = self.parse(
            "Luke 1:78-79 + 2:2-7",
            verse_counts={("Luke", 1): 80},
        )

        self.assertEqual(cell.physical_segment_count, 2)
        self.assertFalse(report.valid)
        self.assertIn(
            "non_continuous_plus",
            {issue.code for issue in report.errors},
        )

    def test_duplicate_segments_and_out_of_range_verses_are_rejected(self):
        cell, report = self.parse(
            "John 8:1,1,40",
            verse_counts={("John", 8): 39},
        )

        self.assertEqual(cell.physical_segment_count, 3)
        self.assertFalse(report.valid)
        codes = {issue.code for issue in report.errors}
        self.assertIn("duplicate_reference_segment", codes)
        self.assertIn("verse_out_of_range", codes)

    def test_legacy_cross_chapter_range_normalizes_to_continuous_segments(self):
        cell, report = self.parse(
            "Matthew 10:40-11:1",
            verse_counts={("Matthew", 10): 42},
        )

        self.assertTrue(report.valid)
        self.assertEqual(
            [segment.display_reference for segment in cell.segments],
            ["10:40-42", "11:1"],
        )
        self.assertEqual(cell.relation, ReferenceRelation.continuous)
        self.assertEqual(cell.logical_selection_count, 1)
        self.assertIn(
            "legacy_cross_chapter_syntax",
            {issue.code for issue in report.warnings},
        )

    def test_spreadsheet_midnight_suffix_normalizes_with_warning(self):
        cell, report = self.parse("Matthew 26:30:00")

        self.assertTrue(report.valid)
        self.assertEqual(cell.segments[0].display_reference, "26:30")
        self.assertIn(
            "spreadsheet_time_normalized",
            {issue.code for issue in report.warnings},
        )

    def test_whitespace_variants_parse_consistently(self):
        variants = {
            "John 8:1, 34": ["8:1", "8:34"],
            "John 8:1 , 34": ["8:1", "8:34"],
            "John 8:1-12, 20-25": ["8:1-12", "8:20-25"],
            "Matthew 5:31-32 ; 19:9": ["5:31-32", "19:9"],
            "Luke 1:78-80 + 2:1-7": ["1:78-80", "2:1-7"],
        }

        for value, expected in variants.items():
            with self.subTest(value=value):
                counts = {("Luke", 1): 80} if value.startswith("Luke") else None
                cell, report = self.parse(value, verse_counts=counts)
                self.assertTrue(report.valid)
                self.assertEqual(
                    [segment.display_reference for segment in cell.segments],
                    expected,
                )

    def test_mixed_separators_preserve_every_edge(self):
        cell, report = self.parse(
            "Luke 1:78-80 + 2:1-7; 6:17-19, 27-36",
            verse_counts={("Luke", 1): 80},
        )

        self.assertTrue(report.valid)
        self.assertEqual(cell.relation, ReferenceRelation.mixed)
        self.assertEqual(cell.physical_segment_count, 4)
        self.assertEqual(cell.logical_selection_count, 3)
        self.assertEqual(
            [segment.separator_before for segment in cell.segments],
            [
                None,
                ReferenceSeparator.continuous,
                ReferenceSeparator.non_continuous,
                ReferenceSeparator.same_chapter,
            ],
        )

    def test_structured_only_firestore_documents_get_a_legacy_projection(self):
        record = records_from_firestore([_Document()])[0]

        self.assertEqual(record.logical_reference_count, 1)
        self.assertEqual(record.physical_segment_count, 2)
        self.assertEqual(len(record.entries), 2)
        self.assertEqual(record.entries[1]["separatorBefore"], "+")

    def test_unquoted_csv_comma_cannot_be_silently_truncated(self):
        result = parse_topic_csv(
            b"Topic,Matthew,Mark,Luke,John\nComma,,,,8:1,34\n"
        )

        self.assertFalse(result.report.valid)
        self.assertIn(
            "unexpected_row_values",
            {issue.code for issue in result.report.errors},
        )


if __name__ == "__main__":
    unittest.main()
