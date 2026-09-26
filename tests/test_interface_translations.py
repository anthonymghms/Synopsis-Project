import csv
import io
import unittest
from unittest.mock import patch

from flask import Flask

import admin_api as admin_module
from services.admin_auth import AdminAuthorizationError
from services.interface_translation_service import (
    CATALOG, ENGLISH, interface_csv_template, parse_interface_csv, translation_status,
)
from services.firebase_service import FirebaseImportRepository, ImportCollisionError
from test_firebase_activation import _Database


class InterfaceCsvTests(unittest.TestCase):
    def test_all_bundled_templates_round_trip_and_keep_accents(self):
        for language in CATALOG:
            raw = interface_csv_template(language).encode("utf-8")
            self.assertTrue(raw.startswith(b"\xef\xbb\xbf"))
            result = parse_interface_csv(raw, language)
            self.assertTrue(result.report.valid, result.report.errors)
            self.assertEqual(result.translations, CATALOG[language])
            self.assertTrue(translation_status(language)["complete"])
        self.assertEqual(CATALOG["french"]["gospelTitle"], "Évangile selon {book}")

    def test_bad_keys_duplicates_and_placeholders_are_rejected(self):
        for body, code in [
            ("badKey,Bonjour\n", "unknown_key"),
            ("nextTopic,A\nnextTopic,B\n", "duplicate_key"),
            ("gospelTitle,Évangile selon Marc\n", "invalid_placeholders"),
            ("chapterTitle,{gospel} — Chapitre {num}\n", "invalid_placeholders"),
            ("nextChapter,{broken\n", "invalid_placeholders"),
            ("nextChapter,a,b\n", "invalid_columns"),
        ]:
            with self.subTest(body=body):
                result = parse_interface_csv(("Key,Translation\n" + body).encode(), "french")
                self.assertFalse(result.report.valid)
                self.assertIn(code, [issue.code for issue in result.report.errors])

    def test_excel_semicolon_csv_and_reordered_placeholders(self):
        result = parse_interface_csv(
            "Key;Translation\nchapterTitle;Chapitre {number} — {gospel}\n".encode(), "french")
        self.assertTrue(result.report.valid)
        self.assertEqual(result.summary()["missingKeys"], [])
        self.assertTrue(result.report.warnings)  # Omitted keys still reported.

    def test_partial_new_language_reports_exact_missing_keys(self):
        result = parse_interface_csv(b"Key,Translation\nnextChapter,Seguente\n", "italian")
        self.assertTrue(result.report.valid)
        self.assertNotIn("nextChapter", result.summary()["missingKeys"])
        self.assertIn("chapterTitle", result.summary()["missingKeys"])
        self.assertEqual(result.summary()["stats"]["missing"], len(ENGLISH) - 1)

    def test_binary_non_utf8_oversized_and_empty_uploads_fail(self):
        for raw in [b"", b"PK\x00\x03", b"Key,Translation\nx,\xff", b"a" * (512 * 1024 + 1),
                    b"Key,Translation\nnextChapter,\n"]:
            self.assertFalse(parse_interface_csv(raw, "french").report.valid)

    def test_export_preserves_custom_labels_and_quotes(self):
        content = interface_csv_template("french", {"nextTopic": 'Sujet suivant, "suite"'})
        rows = list(csv.DictReader(io.StringIO(content.lstrip("\ufeff"))))
        self.assertEqual(next(row for row in rows if row["Key"] == "nextTopic")["Translation"],
                         'Sujet suivant, "suite"')


class InterfaceActivationTests(unittest.TestCase):
    def test_atomic_activation_only_updates_interface_fields_and_audit(self):
        database = _Database()
        repository = FirebaseImportRepository(db=database, bucket=object())
        repository.interface_translation_metadata = lambda _: {"activeTopicsPath": "existing/topics"}
        repository.activate_interface_translations(import_id="rev", language="french",
            translations={"nextTopic": "Sujet suivant"}, replace=False)
        writes = {path: (payload, merge) for path, payload, merge in database.batch_writes}
        self.assertEqual(len(writes), 3)
        payload, merge = writes["harmony_localizations/french"]
        self.assertEqual(payload["interfaceTranslations"], {"nextTopic": "Sujet suivant"})
        self.assertIn("interfaceTranslations", merge)
        self.assertNotIn("activeTopicsPath", payload)
        self.assertNotIn("gospels", payload)
        self.assertFalse(any(path.startswith("bibles/") for path in writes))
        self.assertEqual(writes["admin_imports/rev"][0]["status"], "completed")

    def test_collision_does_not_write_without_replacement(self):
        database = _Database()
        repository = FirebaseImportRepository(db=database, bucket=object())
        repository.interface_translation_metadata = lambda _: {"interfaceRevision": "old"}
        with self.assertRaises(ImportCollisionError):
            repository.activate_interface_translations(import_id="rev", language="french",
                translations={"nextTopic": "Suivant"}, replace=False)
        self.assertEqual(database.batch_writes, [])


class _Repository:
    def __init__(self):
        self.records = {}
        self.sources = {}
        self.active = {}

    def interface_translation_metadata(self, language):
        return {"interfaceTranslations": self.active.get(language, {})}

    def create_import(self, **record):
        self.records[record["import_id"]] = {**record, "type": record["import_type"]}

    def update_import(self, import_id, **fields):
        self.records[import_id].update(fields)

    def upload_sources(self, import_id, files, **_):
        self.sources[import_id] = files

    def get_import(self, import_id):
        return self.records[import_id]

    def download_sources(self, record):
        return self.sources[record["import_id"]]

    def activate_interface_translations(self, import_id, language, translations, replace):
        self.active[language] = translations
        self.update_import(import_id, status="completed")


class InterfaceApiTests(unittest.TestCase):
    def setUp(self):
        app = Flask(__name__)
        app.register_blueprint(admin_module.admin_api)
        self.client = app.test_client()
        self.repository = _Repository()
        self.patches = [patch.object(admin_module, "_admin", return_value={"uid": "admin"}),
                        patch.object(admin_module, "FirebaseImportRepository", return_value=self.repository)]
        for mock in self.patches:
            mock.start()
            self.addCleanup(mock.stop)

    def test_download_validate_import_and_export_preserves_translation(self):
        template = self.client.get("/admin/interface-translations/template/french")
        self.assertEqual(template.status_code, 200)
        self.assertIn("Évangile selon", template.get_json()["csv"])
        response = self.client.post("/admin/interface-translations/validate", data={
            "language": "french", "file": (io.BytesIO("Key,Translation\nnextTopic,Sujet après\n".encode()), "ui.csv")})
        self.assertEqual(response.status_code, 200)
        result = response.get_json()
        self.assertTrue(result["valid"])
        self.assertEqual(self.repository.active, {})  # Preview cannot activate labels.
        import_id = result["importId"]
        with patch.object(admin_module._executor, "submit", side_effect=lambda fn, *args: fn(*args)):
            response = self.client.post("/admin/interface-translations/import",
                json={"importId": import_id, "confirm": True, "replace": False})
        self.assertEqual(response.status_code, 202)
        self.assertEqual(self.repository.active["french"]["nextTopic"], "Sujet après")
        self.assertIn("Sujet après", self.client.get(
            "/admin/interface-translations/template/french").get_json()["csv"])

    def test_invalid_upload_is_not_staged(self):
        response = self.client.post("/admin/interface-translations/validate", data={
            "language": "french", "file": (io.BytesIO(b"Key,Translation\nchapterTitle,{bad}\n"), "ui.csv")})
        self.assertFalse(response.get_json()["valid"])
        self.assertEqual(self.repository.sources, {})

    def test_all_interface_routes_require_admin(self):
        with patch.object(admin_module, "_admin", side_effect=AdminAuthorizationError("denied", "Denied", 403)):
            for method, url in [("get", "/admin/interface-translations/template/french"),
                                ("post", "/admin/interface-translations/validate"),
                                ("post", "/admin/interface-translations/import")]:
                self.assertEqual(getattr(self.client, method)(url).status_code, 403)


if __name__ == "__main__":
    unittest.main()
