import copy
import unittest
from unittest.mock import patch

import app as app_module
from services.admin_auth import AdminAuthorizationError
from services.admin_content_service import chapter_override_key
from tests.test_topic_language_api import _Collection, _Database, _Document, _Snapshot


class _TrackedDocument(_Document):
    def get(self):
        self.database.document_reads.append(self.path)
        return super().get()

    def collection(self, name):
        return _TrackedCollection(self.database, f"{self.path}/{name}")


class _TrackedCollection(_Collection):
    def document(self, document_id):
        return _TrackedDocument(self.database, f"{self.path}/{document_id}")


class _TrackedDatabase(_Database):
    def __init__(self, documents):
        super().__init__(copy.deepcopy(documents))
        self.document_reads = []
        self.batch_reads = []

    def collection(self, path):
        return _TrackedCollection(self, path)

    def get_all(self, references):
        self.batch_reads.append([reference.path for reference in references])
        # The real SDK does not guarantee request order. Return a reversed batch
        # including missing snapshots so tests exercise the response contract.
        return iter([
            _Snapshot(reference.id, self.documents.get(reference.path))
            for reference in reversed(references)
        ])


class BibleReaderApiTests(unittest.TestCase):
    def setUp(self):
        self.books = "bible_revisions/import/books"
        self.verses = f"{self.books}/John/chapters/1/verses"
        self.database = _TrackedDatabase({
            "bibles/english/versions/kjv": {"activeBooksPath": self.books},
            f"{self.books}/John": {"chapterCount": 1},
            f"{self.verses}/1": {"text": "First"},
            f"{self.verses}/3": {"blocks_before": [{"text": "Third"}]},
            f"{self.verses}/4": {
                "text": "", "textEdited": True,
                "blocks_before": [{"text": "Do not restore cleared text"}],
            },
        })
        self.database_patch = patch.object(app_module, "db", self.database)
        self.database_patch.start()
        self.addCleanup(self.database_patch.stop)
        authorization = patch.object(
            app_module, "verify_reader_authorization", return_value={"uid": "reader"}
        )
        self.guard = authorization.start()
        self.addCleanup(authorization.stop)
        self.client = app_module.app.test_client()

    def read(self, verse="1-4", **changes):
        query = {"language": "english", "version": "kjv", "book": "John",
                 "chapter": "1", "verse": verse, **changes}
        return self.client.get("/get_verse", query_string=query,
                               headers={"Authorization": "Bearer token"})

    def test_range_batches_reads_and_preserves_order_missing_and_edited_text(self):
        response = self.read()
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json, [
            {"verse": 1, "text": "First"}, {"verse": 2, "text": ""},
            {"verse": 3, "text": "Third"}, {"verse": 4, "text": ""},
        ])
        self.assertEqual(response.headers["Cache-Control"], "no-store")
        self.assertEqual(self.database.batch_reads, [
            [f"{self.verses}/{number}" for number in range(1, 5)]
        ])
        # One metadata read for book resolution and one for chapter overrides,
        # regardless of how many verses are requested (formerly one per verse).
        self.assertEqual(self.database.document_reads.count(
            "bibles/english/versions/kjv"), 2)
        self.assertFalse(any("/verses/" in path for path in self.database.document_reads))

    def test_next_request_reads_new_chapter_override_without_stale_cache(self):
        self.assertEqual(self.read("1").json, [{"verse": 1, "text": "First"}])
        override = "bible_chapter_revisions/edited/verses"
        self.database.documents["bibles/english/versions/kjv"]["chapterOverrides"] = {
            chapter_override_key("John", "1"): override,
        }
        self.database.documents[f"{override}/1"] = {"text": "Corrected"}
        self.assertEqual(self.read("1").json, [{"verse": 1, "text": "Corrected"}])
        self.assertEqual(self.guard.call_count, 2)
        self.assertEqual(self.database.batch_reads[-1], [f"{override}/1"])

    def test_next_request_resolves_new_import_and_different_version(self):
        self.assertEqual(self.read("1").json[0]["text"], "First")
        replacement = "bible_revisions/replacement/books"
        self.database.documents["bibles/english/versions/kjv"] = {"activeBooksPath": replacement}
        self.database.documents[f"{replacement}/John"] = {"chapterCount": 1}
        self.database.documents[f"{replacement}/John/chapters/1/verses/1"] = {"text": "Replacement"}
        self.assertEqual(self.read("1").json[0]["text"], "Replacement")
        self.database.documents["bibles/english/other/John"] = {"chapterCount": 1}
        self.database.documents["bibles/english/other/John/chapters/1/verses/1"] = {"text": "Legacy"}
        self.assertEqual(self.read("1", version="other").json[0]["text"], "Legacy")

    def test_arabic_alias_and_default_version_still_resolve_book(self):
        self.database.documents["bibles/arabic/versions/van dyck"] = {"activeBooksPath": self.books}
        response = self.read("1", language="arabic", book="يوحنا")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json, [{"verse": 1, "text": "First"}])

    def test_batched_preview_still_checks_access_before_content_reads(self):
        self.guard.side_effect = AdminAuthorizationError(
            "guest_access_expired", "Guest access has expired.", 403
        )
        response = self.read()
        self.assertEqual(response.status_code, 403)
        self.assertEqual(response.json["error"]["code"], "guest_access_expired")
        self.assertEqual(self.database.document_reads, [])
        self.assertEqual(self.database.batch_reads, [])

    def test_invalid_range_and_unknown_book_do_not_batch_read(self):
        self.assertEqual(self.read("1-2-3").status_code, 400)
        self.assertEqual(self.read(book="Missing Book").status_code, 404)
        self.assertEqual(self.database.batch_reads, [])

    def test_large_range_uses_bounded_batches_with_continuous_order(self):
        response = self.read("1-176")
        self.assertEqual(response.status_code, 200)
        self.assertEqual([item["verse"] for item in response.json], list(range(1, 177)))
        self.assertEqual([len(batch) for batch in self.database.batch_reads], [100, 76])


if __name__ == "__main__":
    unittest.main()
