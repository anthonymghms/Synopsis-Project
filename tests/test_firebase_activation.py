import unittest

from services.firebase_service import FirebaseImportRepository
from services.localization_import_service import TopicLocalizationRecord
from services.topic_import_service import parse_topic_csv


class _Document:
    def __init__(self, database, path):
        self.database = database
        self.path = path

    def collection(self, name):
        return _Collection(self.database, f"{self.path}/{name}")

    def set(self, payload, merge=False):
        self.database.direct_writes.append((self.path, payload, merge))


class _Collection:
    """Deliberately has no .path, matching the production Firestore client."""

    def __init__(self, database, base_path):
        self.database = database
        self.base_path = base_path

    def document(self, document_id):
        return _Document(self.database, f"{self.base_path}/{document_id}")


class _Batch:
    def __init__(self, database):
        self.database = database
        self.writes = []

    def set(self, document, payload, merge=False):
        self.writes.append((document.path, payload, merge))

    def commit(self):
        self.database.batch_writes.extend(self.writes)


class _Database:
    def __init__(self):
        self.direct_writes = []
        self.batch_writes = []

    def collection(self, name):
        return _Collection(self, name)

    def batch(self):
        return _Batch(self)


class FirebaseActivationTests(unittest.TestCase):
    def test_bootstrap_uses_explicit_public_collection_paths(self):
        database = _Database()
        repository = FirebaseImportRepository(db=database, bucket=object())
        repository.canonical_topics_exist = lambda: False
        repository.localization_exists = lambda _language: False
        canonical = parse_topic_csv(
            b"Topic,Matthew,Mark,Luke,John\nOne,1:1,,,\n"
        ).records
        localized = [
            TopicLocalizationRecord(
                topic_id="1",
                name="Localized One",
                canonical_name="One",
                source_row=2,
            )
        ]

        outcome = repository.activate_canonical_with_localization(
            import_id="abc123",
            language="arabic",
            display_name="Arabic",
            direction="rtl",
            gospel_labels={
                "Matthew": "متى",
                "Mark": "مرقس",
                "Luke": "لوقا",
                "John": "يوحنا",
            },
            canonical_records=canonical,
            records=localized,
            replace=False,
        )

        self.assertEqual(
            outcome["canonicalTopicsPath"],
            "harmony_revisions/abc123/topics",
        )
        self.assertEqual(
            outcome["localizationTopicsPath"],
            "harmony_localization_revisions/abc123/topics",
        )
        activated = {path: payload for path, payload, _ in database.batch_writes}
        self.assertEqual(
            activated["harmony/canonical"]["activeTopicsPath"],
            "harmony_revisions/abc123/topics",
        )
        self.assertEqual(
            activated["harmony_localizations/arabic"]["activeTopicsPath"],
            "harmony_localization_revisions/abc123/topics",
        )
        self.assertNotIn("bibles/arabic", activated)

    def test_legacy_topic_activation_does_not_modify_bible_catalog(self):
        database = _Database()
        repository = FirebaseImportRepository(db=database, bucket=object())
        repository.resolve_reference_dataset_id = lambda _language: "arabic"
        repository.topics_exist = lambda _dataset: False
        records = parse_topic_csv(
            b"Topic,Matthew,Mark,Luke,John\nOne,1:1,,,\n"
        ).records

        repository.activate_topics(
            import_id="legacy123",
            language="arabic",
            display_name="Arabic",
            direction="rtl",
            records=records,
            replace=False,
        )

        activated_paths = {path for path, _payload, _merge in database.batch_writes}
        self.assertIn("references/arabic", activated_paths)
        self.assertNotIn("bibles/arabic", activated_paths)


if __name__ == "__main__":
    unittest.main()
