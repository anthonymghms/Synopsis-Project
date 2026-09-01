import unittest

from admin_api import _parse_language_upload
from services.topic_import_service import parse_topic_csv


class _Repository:
    @staticmethod
    def chapter_verse_count(book, chapter):
        return {("Matthew", 1): 25, ("Matthew", 2): 23}.get((book, chapter))


class LanguageUploadContractTests(unittest.TestCase):
    def test_first_five_column_language_upload_bootstraps_canonical_table(self):
        raw = (
            "الموضوع,متى,مرقس,لوقا,يوحنا\n"
            "الأول,1:1,,,\n"
            "الثاني,2:1,,,\n"
        ).encode()

        localization, master, bootstrap = _parse_language_upload(
            raw,
            repository=_Repository(),
            canonical_records=[],
            canonical_active=False,
        )

        self.assertTrue(bootstrap)
        self.assertTrue(localization.report.valid)
        self.assertEqual(localization.source_format, "harmonyTable")
        self.assertEqual(len(master.records), 2)
        self.assertEqual([record.name for record in localization.records], ["الأول", "الثاني"])

    def test_one_column_additional_language_only_overlays_names(self):
        canonical = parse_topic_csv(
            b"Topic,Matthew,Mark,Luke,John\nOne,1:1,,,\nTwo,2:1,,,\n"
        ).records

        localization, master, bootstrap = _parse_language_upload(
            b"Subjects\nEnglish One\nEnglish Two\n",
            repository=_Repository(),
            canonical_records=canonical,
            canonical_active=True,
        )

        self.assertFalse(bootstrap)
        self.assertIsNone(master)
        self.assertTrue(localization.report.valid)
        self.assertEqual(
            [record.name for record in localization.records],
            ["English One", "English Two"],
        )

    def test_full_language_file_cannot_change_active_references(self):
        canonical = parse_topic_csv(
            b"Topic,Matthew,Mark,Luke,John\nOne,1:1,,,\nTwo,2:1,,,\n"
        ).records
        changed = (
            b"Subjects,Matthew,Mark,Luke,John\n"
            b"One translated,1:2,,,\n"
            b"Two translated,2:1,,,\n"
        )

        localization, _, bootstrap = _parse_language_upload(
            changed,
            repository=_Repository(),
            canonical_records=canonical,
            canonical_active=True,
        )

        self.assertFalse(bootstrap)
        self.assertFalse(localization.report.valid)
        self.assertIn(
            "canonical_reference_mismatch",
            {issue.code for issue in localization.report.errors},
        )


if __name__ == "__main__":
    unittest.main()
