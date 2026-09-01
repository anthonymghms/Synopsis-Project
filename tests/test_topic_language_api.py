import unittest

import app as app_module


class _Snapshot:
    def __init__(self, document_id, data):
        self.id = document_id
        self._data = data
        self.exists = data is not None

    def to_dict(self):
        return dict(self._data or {})


class _Document:
    def __init__(self, database, path):
        self.database = database
        self.path = path
        self.id = path.rsplit("/", 1)[-1]

    def get(self):
        return _Snapshot(self.id, self.database.documents.get(self.path))

    def collection(self, name):
        return _Collection(self.database, f"{self.path}/{name}")


class _Collection:
    def __init__(self, database, path):
        self.database = database
        self.path = path

    def document(self, document_id):
        return _Document(self.database, f"{self.path}/{document_id}")

    def stream(self):
        prefix = f"{self.path}/"
        depth = prefix.count("/")
        snapshots = []
        for path, data in self.database.documents.items():
            if path.startswith(prefix) and path.count("/") == depth:
                snapshots.append(_Snapshot(path.rsplit("/", 1)[-1], data))
        return iter(snapshots)

    def list_documents(self):
        return [
            _Document(self.database, f"{self.path}/{snapshot.id}")
            for snapshot in self.stream()
        ]

    def limit(self, _count):
        return self


class _Database:
    def __init__(self, documents):
        self.documents = documents

    def collection(self, path):
        return _Collection(self, path)


class TopicLanguageApiTests(unittest.TestCase):
    def setUp(self):
        self.original_db = app_module.db
        app_module.db = _Database(
            {
                "harmony/canonical": {
                    "activeTopicsPath": "harmony_revisions/rev/topics",
                    "topicCount": 2,
                },
                "harmony_revisions/rev/topics/1": {
                    "canonicalOrder": 1,
                    "entries": [{"book": "Luke", "chapter": 2, "verses": "1-7"}],
                    "referenceCells": [],
                    "referenceGrammarVersion": 2,
                },
                "harmony_revisions/rev/topics/2": {
                    "canonicalOrder": 2,
                    "entries": [{"book": "John", "chapter": 1, "verses": "1"}],
                    "referenceCells": [],
                    "referenceGrammarVersion": 2,
                },
                "harmony_localizations/arabic": {
                    "label": "العربية",
                    "direction": "rtl",
                    "gospels": {
                        "Matthew": "متى",
                        "Mark": "مرقس",
                        "Luke": "لوقا",
                        "John": "يوحنا",
                    },
                    "topicCount": 2,
                    "activeTopicsPath": "harmony_localization_revisions/ar/topics",
                    "active": True,
                },
                "harmony_localization_revisions/ar/topics/1": {
                    "name": "ميلاد يسوع",
                    "canonicalOrder": 1,
                },
                "harmony_localization_revisions/ar/topics/2": {
                    "name": "الكلمة",
                    "canonicalOrder": 2,
                },
                "harmony_localizations/english": {
                    "label": "English",
                    "direction": "ltr",
                    "gospels": {
                        "Matthew": "Matthew",
                        "Mark": "Mark",
                        "Luke": "Luke",
                        "John": "John",
                    },
                    "topicCount": 2,
                    "activeTopicsPath": "harmony_localization_revisions/en/topics",
                    "active": True,
                },
                "harmony_localization_revisions/en/topics/1": {
                    "name": "Birth of Jesus",
                    "canonicalOrder": 1,
                },
                "harmony_localization_revisions/en/topics/2": {
                    "name": "The Word",
                    "canonicalOrder": 2,
                },
            }
        )
        self.client = app_module.app.test_client()

    def tearDown(self):
        app_module.db = self.original_db

    def test_canonical_and_localization_endpoints_are_separate(self):
        canonical = self.client.get("/harmony/topics").get_json()
        self.assertEqual([topic["id"] for topic in canonical["topics"]], ["1", "2"])
        self.assertNotIn("name", canonical["topics"][0])

        english = self.client.get("/topic-localizations/english").get_json()
        self.assertEqual(english["language"]["direction"], "ltr")
        self.assertTrue(english["language"]["complete"])
        self.assertEqual(english["topics"][0]["name"], "Birth of Jesus")

    def test_topic_language_is_independent_from_bible_query(self):
        response = self.client.get(
            "/topics?topicLanguage=english&bibleLanguage=arabic&language=arabic&version=Van%20Dyke"
        ).get_json()
        self.assertEqual(response[0]["name"], "Birth of Jesus")
        self.assertEqual(response[0]["references"][0]["book"], "Luke")

        legacy = self.client.get("/topics?language=arabic&version=Van%20Dyke").get_json()
        self.assertEqual(legacy[0]["name"], "ميلاد يسوع")
        self.assertEqual(legacy[0]["references"], response[0]["references"])

    def test_topic_detail_uses_explicit_topic_language(self):
        response = self.client.get(
            "/arabic/Van%20Dyke/topic/01?topicLanguage=english"
        ).get_json()
        self.assertEqual(response["id"], "1")
        self.assertEqual(response["name"], "Birth of Jesus")


if __name__ == "__main__":
    unittest.main()
