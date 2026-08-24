import unittest

from services.bible_import_service import parse_usfm_files
from services.topic_import_service import (
    add_structural_comparison,
    parse_topic_csv,
)


class TopicImportValidationTests(unittest.TestCase):
    def test_valid_csv_preserves_order_and_multiple_references(self):
        raw = (
            "Topic,Matthew,Mark,Luke,John\n"
            "Prologue,1:1,1:1,1:1-4,1:1\n"
            'Teaching,"5:1-3; 6:4,5-7",,,\n'
        ).encode("utf-8")

        result = parse_topic_csv(raw)

        self.assertTrue(result.report.valid)
        self.assertEqual([record.topic_id for record in result.records], ["1", "2"])
        self.assertEqual(result.records[1].entries[-1]["chapter"], 6)
        self.assertEqual(result.records[1].entries[-1]["verses"], "5-7")

    def test_arabic_utf8_and_bom_are_supported(self):
        raw = "\ufeffالموضوع,متى,مرقس,لوقا,يوحنا\nالمقدمة,1:01,,,1:1-4\n".encode(
            "utf-8"
        )

        result = parse_topic_csv(raw)

        self.assertTrue(result.report.valid)
        self.assertEqual(result.encoding, "utf-8-sig")
        self.assertEqual(result.records[0].name, "المقدمة")
        self.assertEqual(result.records[0].entries[0]["verses"], "1")

    def test_missing_columns_and_invalid_reference_are_errors(self):
        raw = b"Topic,Matthew\nBroken,3:x-12\n"

        result = parse_topic_csv(raw)

        self.assertFalse(result.report.valid)
        self.assertIn("missing_columns", {issue.code for issue in result.report.errors})
        self.assertIn("invalid_reference", {issue.code for issue in result.report.errors})

    def test_duplicate_topic_names_keep_distinct_order_ids_with_warning(self):
        raw = (
            "Topic,Matthew,Mark,Luke,John\n"
            "Light,5:1,,,,\n"
            "Light,6:1,,,,\n"
        ).encode()

        result = parse_topic_csv(raw)

        self.assertTrue(result.report.valid)
        self.assertEqual([record.topic_id for record in result.records], ["1", "2"])
        self.assertIn("duplicate_topic", {issue.code for issue in result.report.warnings})

    def test_structural_mismatch_is_reported_without_silent_fix(self):
        canonical = parse_topic_csv(
            b"Topic,Matthew,Mark,Luke,John\nOne,1:1,,2:1-2,\n"
        )
        translated = parse_topic_csv(
            "Topic,Matthew,Mark,Luke,John\nواحد,1:1,,2:1,\n".encode()
        )

        add_structural_comparison(
            translated, canonical.records, canonical_label="english_kjv"
        )

        self.assertTrue(translated.report.valid)
        self.assertIn(
            "reference_structure_mismatch",
            {issue.code for issue in translated.report.warnings},
        )

    def test_excel_time_and_cross_chapter_values_do_not_reach_firestore(self):
        raw = (
            "Topic,Matthew,Mark,Luke,John\n"
            "Bad,26:30:00,,,18:39-19:16\n"
        ).encode()

        result = parse_topic_csv(raw)

        self.assertFalse(result.report.valid)
        self.assertEqual(
            sum(issue.code == "invalid_reference" for issue in result.report.errors),
            2,
        )


class BibleImportValidationTests(unittest.TestCase):
    def test_valid_multiple_books_and_unicode(self):
        files = [
            (
                "MAT.usfm",
                "\\id MAT Matthew\n\\c 1\n\\s1 النسب\n\\p\n\\v 1 نَصٌّ عربي\n\\v 2 Text\n".encode(),
            ),
            (
                "MRK.usfm",
                b"\\id MRK Mark\n\\c 1\n\\v 1 Beginning\n",
            ),
        ]

        result = parse_usfm_files(files)

        self.assertTrue(result.report.valid)
        self.assertEqual(len(result.books), 2)
        self.assertEqual(result.summary()["stats"]["verses"], 3)
        self.assertTrue(result.contains_diacritics)
        first = result.books[0].chapters["1"][0]
        self.assertEqual(first.blocks_before[0]["marker"], r"\s1")

    def test_malformed_usfm_and_verse_before_chapter_are_rejected(self):
        result = parse_usfm_files(
            [("MAT.usfm", b"\\id MAT\n\\v 1 Before chapter\n")]
        )

        self.assertFalse(result.report.valid)
        codes = {issue.code for issue in result.report.errors}
        self.assertIn("verse_before_chapter", codes)
        self.assertIn("empty_book", codes)

    def test_unrecognized_book_is_rejected(self):
        result = parse_usfm_files(
            [("GEN.usfm", b"\\id GEN Genesis\n\\c 1\n\\v 1 Beginning\n")]
        )

        self.assertFalse(result.report.valid)
        self.assertIn("unrecognized_book", {issue.code for issue in result.report.errors})

    def test_duplicate_books_and_duplicate_verses_are_rejected(self):
        result = parse_usfm_files(
            [
                ("MAT1.usfm", b"\\id MAT\n\\c 1\n\\v 1 One\n\\v 1 Again\n"),
                ("MAT2.usfm", b"\\id MAT\n\\c 1\n\\v 1 One\n"),
            ]
        )

        self.assertFalse(result.report.valid)
        codes = {issue.code for issue in result.report.errors}
        self.assertIn("duplicate_verse", codes)
        self.assertIn("duplicate_book", codes)

    def test_non_utf8_usfm_is_rejected(self):
        result = parse_usfm_files([("MAT.usfm", b"\\id MAT\n\xff")])
        self.assertFalse(result.report.valid)
        self.assertIn("unsupported_encoding", {issue.code for issue in result.report.errors})


if __name__ == "__main__":
    unittest.main()

