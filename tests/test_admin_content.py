import copy
import unittest
from unittest.mock import patch

from flask import Flask

from admin_content_api import admin_content_api
from services.admin_auth import AdminAuthorizationError
from services.admin_content_service import (
    AdminContentRepository,
    ContentConflictError,
    bible_verses_collection,
    chapter_override_key,
)
from services.bible_text_service import extract_verse_text


class Snapshot:
    def __init__(self, db, path):
        self.id = path.rsplit("/", 1)[-1]
        self.exists = path in db.values
        self.value = copy.deepcopy(db.values.get(path))
        self.update_time = db.times.get(path, 0)

    def to_dict(self):
        return copy.deepcopy(self.value)


class Document:
    def __init__(self, db, path):
        self.db, self.path = db, path
        self.id = path.rsplit("/", 1)[-1]

    def get(self, transaction=None):
        return Snapshot(self.db, self.path)

    def set(self, payload, merge=False):
        self.db.write(self.path, payload, merge)

    def collection(self, name):
        return Collection(self.db, f"{self.path}/{name}")


class Collection:
    def __init__(self, db, path):
        self.db, self.path = db, path

    def document(self, name):
        return Document(self.db, f"{self.path}/{name}")

    def list_documents(self):
        prefix = self.path + "/"
        identifiers = sorted({p[len(prefix):].split("/")[0] for p in self.db.values if p.startswith(prefix)})
        return iter([self.document(i) for i in identifiers])

    def stream(self):
        return iter([d.get() for d in self.list_documents() if d.get().exists])

    def limit(self, _limit):
        return self


class Batch:
    def __init__(self, db):
        self.db, self.writes = db, []

    def set(self, ref, payload, merge=False):
        self.writes.append((ref.path, payload, merge))

    def commit(self):
        for path, payload, merge in self.writes:
            self.db.write(path, payload, merge)


class Database:
    def __init__(self, values):
        self.values = copy.deepcopy(values)
        self.times = {key: 1 for key in values}
        self.before_transaction = None
        self.transactions = []

    def collection(self, path):
        return Collection(self, path)

    def batch(self):
        return Batch(self)

    def transaction(self):
        if self.before_transaction:
            self.before_transaction()
            self.before_transaction = None
        result = Batch(self)
        self.transactions.append(result)
        return result

    def write(self, path, payload, merge):
        if merge:
            self.values[path] = {**self.values.get(path, {}), **copy.deepcopy(payload)}
        else:
            self.values[path] = copy.deepcopy(payload)
        self.times[path] = self.times.get(path, 0) + 1


def fake_transactional(function):
    def call(transaction):
        result = function(transaction)
        transaction.commit()
        return result
    return call


class ContentRepositoryTests(unittest.TestCase):
    def setUp(self):
        self.db = Database({
            "harmony/canonical": {"activeTopicsPath": "harmony_revisions/base/topics"},
            "harmony_revisions/base/topics/1": {"entries": [{"book": "Matthew", "chapter": 1, "verses": "1"}]},
            "harmony_localizations/french": {"label": "Français", "direction": "ltr", "activeTopicsPath": "harmony_localization_revisions/base/topics",
                                             "interfaceTranslations": {"close": "Fermer"}},
            "harmony_localization_revisions/base/topics/1": {"name": "Avant", "canonicalName": "Original"},
            "harmony_localization_revisions/base/topics/2": {"name": "Autre"},
            "bibles/ancientgreek": {"label": "Ancient Greek", "direction": "ltr"},
            "bibles/ancientgreek/versions/TR": {"label": "TR", "activeRevision": "base", "activeBooksPath": "bible_revisions/base/books"},
            "bible_revisions/base/books/Matthew": {"chapterCount": 2},
            "bible_revisions/base/books/Matthew/chapters/1": {"verseCount": 2},
            "bible_revisions/base/books/Matthew/chapters/1/verses/1": {"text": "Original Greek", "blocks_before": [{"marker": "p"}, {"marker": "\\s2", "text": "Heading"}, {"marker": "\\q", "text": "Poetry"}]},
            "bible_revisions/base/books/Matthew/chapters/1/verses/2": {"text": "Unchanged", "blocks_before": []},
            "bible_revisions/base/books/Matthew/chapters/2": {"verseCount": 1},
            "bible_revisions/base/books/Matthew/chapters/2/verses/1": {"text": "Chapter two"},
        })
        self.repository = AdminContentRepository(self.db)
        self.transactional = patch("services.admin_content_service.firestore.transactional", fake_transactional)
        self.transactional.start()
        self.addCleanup(self.transactional.stop)

    def test_topic_edits_clone_and_preserve_references_and_interface(self):
        editor = self.repository.topics("french")
        self.assertEqual(editor["topics"][0]["references"]["Matthew"], "1:1")
        result = self.repository.save_topics("french", {"revision": editor["revision"],
                                                      "metadata": {"displayName": "French"},
                                                      "topics": [{"id": "1", "name": "Après"}]}, "administrator")
        metadata = self.db.values["harmony_localizations/french"]
        self.assertEqual(result["topics"][0]["name"], "Après")
        self.assertEqual(result["topics"][1]["name"], "Autre")
        self.assertEqual(metadata["interfaceTranslations"], {"close": "Fermer"})
        self.assertEqual(self.db.values["harmony_localization_revisions/base/topics/1"]["name"], "Avant")
        self.assertEqual(self.db.values[metadata["activeTopicsPath"] + "/1"]["canonicalName"], "Original")
        audits = list(self.db.collection("admin_content_edits").stream())
        self.assertEqual(len(audits), 1)
        self.assertEqual(audits[0].to_dict()["actorUid"], "administrator")
        self.assertNotEqual(editor["revision"], result["revision"])

    def test_canonical_reference_change_invalidates_topic_editor(self):
        editor = self.repository.topics("french")
        self.db.write("harmony/canonical", {"activeTopicsPath": "harmony_revisions/new/topics"}, True)
        with self.assertRaises(ContentConflictError):
            self.repository.save_topics("french", {"revision": editor["revision"], "topics": [{"id": "1", "name": "Later"}]}, "admin")

    def test_topic_editor_supports_localization_reference_fallback(self):
        del self.db.values["harmony_revisions/base/topics/1"]
        self.db.write("harmony_localizations/french", {"canonicalSource": "references/english_kjv"}, True)
        self.db.write("references/english_kjv", {"activeTopicsPath": "reference_revisions/legacy/topics"}, False)
        self.db.write("reference_revisions/legacy/topics/1", {"name": "Original", "entries": [{"book": "Matthew", "chapter": 1, "verses": "2"}]}, False)
        editor = self.repository.topics("french")
        self.assertEqual(editor["topics"][0]["references"]["Matthew"], "1:2")
        self.db.write("references/english_kjv", {"activeTopicsPath": "reference_revisions/new/topics"}, True)
        with self.assertRaises(ContentConflictError):
            self.repository.save_topics("french", {"revision": editor["revision"], "topics": [{"id": "1", "name": "Later"}]}, "admin")

    def test_chapter_edits_are_immutable_and_preserve_non_heading_blocks(self):
        editor = self.repository.chapter("ancientgreek", "TR", "Matthew", "1")
        result = self.repository.save_chapter("ancientgreek", "TR", "Matthew", "1", {
            "revision": editor["revision"], "verses": [{"id": "1", "text": "Ἐν ἀρχῇ", "title": "New heading"}]
        }, "admin")
        self.assertEqual(result["verses"][0]["text"], "Ἐν ἀρχῇ")
        self.assertEqual(result["verses"][1]["text"], "Unchanged")
        original = self.db.values["bible_revisions/base/books/Matthew/chapters/1/verses/1"]
        self.assertEqual(original["text"], "Original Greek")
        edited = bible_verses_collection(self.db, "ancientgreek", "TR", "Matthew", "1").document("1").get().to_dict()
        self.assertEqual(edited["blocks_before"], [{"marker": "p"}, {"marker": "\\s2", "text": "New heading"}, {"marker": "\\q", "text": "Poetry"}])
        self.assertEqual(bible_verses_collection(self.db, "ancientgreek", "TR", "Matthew", "2").document("1").get().to_dict()["text"], "Chapter two")
        self.assertNotIn("harmony_localizations/ancientgreek", self.db.values)

    def test_subsequent_edits_preserve_prior_chapter_and_revision(self):
        one = self.repository.chapter("ancientgreek", "TR", "Matthew", "1")
        self.repository.save_chapter("ancientgreek", "TR", "Matthew", "1", {"revision": one["revision"], "verses": [{"id": "1", "text": "First edit"}]}, "admin")
        old_path = bible_verses_collection(self.db, "ancientgreek", "TR", "Matthew", "1").path
        two = self.repository.chapter("ancientgreek", "TR", "Matthew", "2")
        self.repository.save_chapter("ancientgreek", "TR", "Matthew", "2", {"revision": two["revision"], "verses": [{"id": "1", "text": "Second edit"}]}, "admin")
        self.assertEqual(bible_verses_collection(self.db, "ancientgreek", "TR", "Matthew", "1").path, old_path)
        self.assertEqual(len(self.db.values["bibles/ancientgreek/versions/TR"]["chapterOverrides"]), 2)

    def test_stale_chapter_save_is_rejected_without_writes(self):
        editor = self.repository.chapter("ancientgreek", "TR", "Matthew", "1")
        self.db.write("bibles/ancientgreek/versions/TR", {"activeRevision": "imported_again"}, True)
        before = copy.deepcopy(self.db.values)
        with self.assertRaises(ContentConflictError):
            self.repository.save_chapter("ancientgreek", "TR", "Matthew", "1", {"revision": editor["revision"], "verses": [{"id": "1", "text": "Stale"}]}, "admin")
        self.assertEqual(self.db.values, before)

    def test_concurrent_import_during_clone_cannot_be_overwritten(self):
        editor = self.repository.chapter("ancientgreek", "TR", "Matthew", "1")
        self.db.before_transaction = lambda: self.db.write("bibles/ancientgreek/versions/TR", {"activeRevision": "concurrent_import"}, True)
        with self.assertRaises(ContentConflictError):
            self.repository.save_chapter("ancientgreek", "TR", "Matthew", "1", {"revision": editor["revision"], "verses": [{"id": "1", "text": "Stale"}]}, "admin")
        self.assertNotIn("chapterOverrides", self.db.values["bibles/ancientgreek/versions/TR"])
        self.assertEqual(list(self.db.collection("admin_content_edits").stream()), [])
        self.assertEqual(self.db.transactions[0].writes, [])

    def test_invalid_unknown_duplicate_and_reference_edits_are_rejected(self):
        topic = self.repository.topics("french")
        for rows in [[{"id": "99", "name": "Missing"}], [{"id": "1", "name": "X"}, {"id": "1", "name": "Y"}], [{"id": "1", "name": "X", "references": {}}]]:
            with self.assertRaises(ValueError):
                self.repository.save_topics("french", {"revision": topic["revision"], "topics": rows}, "admin")
        chapter = self.repository.chapter("ancientgreek", "TR", "Matthew", "1")
        for rows in [[{"id": "99", "text": "Missing"}], [{"id": "1", "text": 12}], [{"id": "1", "text": "\u0000"}]]:
            with self.assertRaises(ValueError):
                self.repository.save_chapter("ancientgreek", "TR", "Matthew", "1", {"revision": chapter["revision"], "verses": rows}, "admin")
        self.assertEqual(list(self.db.collection("admin_content_edits").stream()), [])

    def test_metadata_changes_do_not_touch_bible_text_or_topic_localizations(self):
        editor = self.repository.bible("ancientgreek", "TR")
        self.assertEqual(editor["books"], [{"id": "Matthew", "chapters": ["1", "2"]}])
        result = self.repository.save_bible("ancientgreek", "TR", {"revision": editor["revision"],
                                           "metadata": {"displayName": "Textus Receptus", "description": "Greek text", "direction": "ltr"}}, "admin")
        self.assertEqual(result["metadata"]["displayName"], "Textus Receptus")
        self.assertEqual(self.db.values["bibles/ancientgreek/versions/TR"]["activeBooksPath"], "bible_revisions/base/books")
        self.assertNotIn("harmony_localizations/ancientgreek", self.db.values)

    def test_legacy_topic_and_bible_content_can_be_edited(self):
        self.db.write("references/english_kjv/topics/1", {"name": "Original", "entries": [{"book": "Matthew", "chapter": 1, "verses": "1"}]}, False)
        editor = self.repository.topics("english")
        self.assertEqual(editor["source"], "legacy")
        self.repository.save_topics("english", {"revision": editor["revision"], "topics": [{"id": "1", "name": "Changed"}]}, "admin")
        self.assertEqual(self.db.values["references/english_kjv/topics/1"]["name"], "Original")
        self.assertIn("activeTopicsPath", self.db.values["references/english_kjv"])
        self.db.write("bibles/english/KJV/Matthew/chapters/1/verses/1", {"text": "Original"}, False)
        chapter = self.repository.chapter("english", "KJV", "Matthew", "1")
        self.repository.save_chapter("english", "KJV", "Matthew", "1", {"revision": chapter["revision"], "verses": [{"id": "1", "text": "Changed"}]}, "admin")
        self.assertEqual(bible_verses_collection(self.db, "english", "KJV", "Matthew", "1").document("1").get().to_dict()["text"], "Changed")

    def test_unchanged_editor_does_not_create_revisions(self):
        editor = self.repository.chapter("ancientgreek", "TR", "Matthew", "1")
        before = copy.deepcopy(self.db.values)
        self.repository.save_chapter("ancientgreek", "TR", "Matthew", "1", {"revision": editor["revision"], "verses": editor["verses"]}, "admin")
        self.assertEqual(self.db.values, before)

    def test_legacy_block_text_matches_reader_and_no_op_preserves_representation(self):
        path = "bible_revisions/base/books/Matthew/chapters/1/verses/1"
        legacy = {"blocks_before": [{"marker": "\\s", "text": "Title"}, {"marker": "\\q", "text": "Legacy passage"}, {"marker": "p"}], "source": "legacy"}
        self.db.write(path, legacy, False)
        editor = self.repository.chapter("ancientgreek", "TR", "Matthew", "1")
        self.assertEqual(editor["verses"][0]["text"], "Title Legacy passage")
        self.assertEqual(editor["verses"][0]["text"], extract_verse_text(legacy))
        before = copy.deepcopy(self.db.values)
        self.repository.save_chapter("ancientgreek", "TR", "Matthew", "1", {"revision": editor["revision"], "verses": editor["verses"]}, "admin")
        self.assertEqual(self.db.values, before)

    def test_heading_only_edit_keeps_legacy_text_fallback_and_blocks(self):
        path = "bible_revisions/base/books/Matthew/chapters/1/verses/1"
        legacy = {"blocks_before": [{"marker": "\\s", "text": "Title"}, {"marker": "\\q", "text": "Legacy passage"}]}
        self.db.write(path, legacy, False)
        editor = self.repository.chapter("ancientgreek", "TR", "Matthew", "1")
        editor["verses"][0]["title"] = "New title"
        result = self.repository.save_chapter("ancientgreek", "TR", "Matthew", "1", {"revision": editor["revision"], "verses": editor["verses"]}, "admin")
        saved = bible_verses_collection(self.db, "ancientgreek", "TR", "Matthew", "1").document("1").get().to_dict()
        self.assertNotIn("text", saved)
        self.assertEqual(result["verses"][0]["text"], "New title Legacy passage")
        self.assertEqual(saved["blocks_before"][1], legacy["blocks_before"][1])
        self.assertEqual(self.db.values[path], legacy)

    def test_explicitly_cleared_text_stays_blank_in_reader_without_removing_headings(self):
        import app as app_module
        editor = self.repository.chapter("ancientgreek", "TR", "Matthew", "1")
        result = self.repository.save_chapter("ancientgreek", "TR", "Matthew", "1", {
            "revision": editor["revision"], "verses": [{"id": "1", "text": ""}]
        }, "admin")
        self.assertEqual(result["verses"][0]["text"], "")
        self.assertEqual(result["verses"][0]["title"], "Heading")
        with patch.object(app_module, "db", self.db), patch.object(app_module, "verify_reader_authorization", return_value={"uid": "reader"}):
            response = app_module.app.test_client().get("/get_chapter?language=ancientgreek&version=TR&book=Matthew&chapter=1")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json[0]["text"], "")
        self.assertEqual(response.json[1]["text"], "Unchanged")
        self.assertEqual(response.headers["Cache-Control"], "no-store")


class ContentApiTests(unittest.TestCase):
    def setUp(self):
        app = Flask(__name__)
        app.register_blueprint(admin_content_api)
        self.client = app.test_client()

    def test_all_editor_endpoints_require_administrator(self):
        for path in ["/admin/content/topics/french", "/admin/content/bibles/ancientgreek/TR", "/admin/content/bibles/ancientgreek/TR/Matthew/1"]:
            for method in ["get", "post"]:
                response = getattr(self.client, method)(path)
                self.assertEqual(response.status_code, 401)
                self.assertEqual(response.headers["Cache-Control"], "no-store")

    @patch("admin_content_api.verify_admin_authorization", return_value={"uid": "admin"})
    @patch("admin_content_api.AdminContentRepository")
    def test_conflicts_and_invalid_payloads_have_actionable_status(self, repository, _auth):
        repository.return_value.save_topics.side_effect = ContentConflictError("Reload the editor.")
        response = self.client.post("/admin/content/topics/french", json={"revision": "old", "topics": []})
        self.assertEqual(response.status_code, 409)
        self.assertEqual(response.json["error"]["code"], "content_conflict")
        self.assertEqual(self.client.post("/admin/content/topics/french", json={"activeTopicsPath": "bad"}).status_code, 400)
        self.assertEqual(self.client.get("/admin/content/bibles/ancientgreek/TR/Matthew/0").status_code, 400)

    @patch("admin_content_api.verify_admin_authorization", side_effect=AdminAuthorizationError("admin_required", "Administrators only.", 403))
    @patch("admin_content_api.AdminContentRepository")
    def test_non_admin_cannot_load_repository(self, repository, _auth):
        self.assertEqual(self.client.get("/admin/content/topics/french").status_code, 403)
        repository.assert_not_called()


if __name__ == "__main__":
    unittest.main()
