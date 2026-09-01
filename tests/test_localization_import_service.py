import unittest

from services.localization_import_service import parse_topic_localization_csv
from services.topic_import_service import parse_topic_csv


class TopicLocalizationImportTests(unittest.TestCase):
    def setUp(self):
        self.canonical = parse_topic_csv(
            b"Topic,Matthew,Mark,Luke,John\nPrologue,1:1,,,\nTeaching,5:1,,,\n"
        ).records

    def test_localization_csv_requires_only_stable_id_and_name(self):
        result = parse_topic_localization_csv(
            "TopicNumber,TopicName\n1,المقدمة\n2,التعليم\n".encode(),
            self.canonical,
        )

        self.assertTrue(result.report.valid)
        self.assertEqual([record.topic_id for record in result.records], ["1", "2"])
        self.assertEqual(result.records[0].name, "المقدمة")
        self.assertEqual(
            result.summary()["preview"][0],
            {
                "id": "1",
                "canonicalName": "Prologue",
                "localizedName": "المقدمة",
            },
        )

    def test_ordered_single_column_subjects_map_to_canonical_topic_order(self):
        result = parse_topic_localization_csv(
            b"Subjects\nEnglish Prologue\nEnglish Teaching\n",
            self.canonical,
        )

        self.assertTrue(result.report.valid)
        self.assertEqual(result.source_format, "orderedNames")
        self.assertIn(
            "positional_alignment",
            {issue.code for issue in result.report.warnings},
        )
        self.assertEqual(
            [(record.topic_id, record.name) for record in result.records],
            [("1", "English Prologue"), ("2", "English Teaching")],
        )

    def test_five_column_master_can_supply_ordered_base_language_names(self):
        result = parse_topic_localization_csv(
            (
                "الموضوع,متى,مرقس,لوقا,يوحنا\n"
                "المقدمة,1:1,,,\n"
                "التعليم,5:1,,,\n"
            ).encode(),
            self.canonical,
        )

        self.assertTrue(result.report.valid)
        self.assertEqual(result.source_format, "harmonyTable")
        self.assertEqual([record.name for record in result.records], ["المقدمة", "التعليم"])

    def test_numbered_master_uses_topic_name_not_number_for_localization(self):
        raw = (
            "TopicNumber,TopicName,Matthew,Mark,Luke,John\n"
            "10,Localized Ten,1:1,,,\n"
            "20,Localized Twenty,,1:2,,\n"
        ).encode()
        canonical = parse_topic_csv(raw).records

        result = parse_topic_localization_csv(raw, canonical)

        self.assertTrue(result.report.valid)
        self.assertEqual([record.topic_id for record in result.records], ["10", "20"])
        self.assertEqual(
            [record.name for record in result.records],
            ["Localized Ten", "Localized Twenty"],
        )

    def test_ordered_names_require_exactly_one_name_per_canonical_topic(self):
        result = parse_topic_localization_csv(
            b"Subjects\nOnly one\n",
            self.canonical,
        )

        self.assertFalse(result.report.valid)
        self.assertIn(
            "topic_count_mismatch",
            {issue.code for issue in result.report.errors},
        )

    def test_missing_unknown_and_duplicate_topic_ids_are_reported(self):
        result = parse_topic_localization_csv(
            b"TopicId,TopicName\n1,One\n1,Again\n3,Unknown\n",
            self.canonical,
        )

        self.assertFalse(result.report.valid)
        codes = {issue.code for issue in result.report.errors}
        self.assertIn("duplicate_topic_id", codes)
        self.assertIn("unknown_topic_id", codes)
        self.assertIn("missing_topic_translation", codes)

    def test_binary_or_control_character_input_is_rejected(self):
        result = parse_topic_localization_csv(
            b"Subjects\nGood\x00Bad\nSecond\n",
            self.canonical,
        )

        self.assertFalse(result.report.valid)
        self.assertIn(
            "invalid_text_encoding",
            {issue.code for issue in result.report.errors},
        )


if __name__ == "__main__":
    unittest.main()
