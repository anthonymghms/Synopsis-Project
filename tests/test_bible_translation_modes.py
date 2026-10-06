import io
import unittest
from types import SimpleNamespace
from unittest.mock import Mock, patch

from flask import Flask
from admin_api import admin_api
from tests import test_admin_content as content_tests
Database = content_tests.Database
from services.admin_content_service import AdminContentRepository


class BibleTranslationModesTests(unittest.TestCase):
    def setUp(self):
        app = Flask(__name__)
        app.register_blueprint(admin_api)
        self.client = app.test_client()
        self.repository = Mock()
        self.repository.db = Database({
            'bibles/arabic': {'label': 'العربية', 'direction': 'rtl'},
            'harmony_localizations/french': {'label': 'Français', 'direction': 'ltr'},
        })
        self.repository.resolve_version_id.side_effect = lambda language, version: version
        self.repository.bible_version_exists.return_value = False
        self.repository.available_versions.return_value = []
        self.repository.upload_sources.return_value = ['staged/MAT.usfm']
        self.patches = [patch('admin_api._admin', return_value={'uid': 'admin'}),
                        patch('admin_api.FirebaseImportRepository', return_value=self.repository)]
        for item in self.patches:
            item.start()
            self.addCleanup(item.stop)

    def validate(self, **fields):
        data = {'translationName': 'Textus Receptus', 'versionId': 'TR',
                'files': (io.BytesIO(b'\\id MAT\n\\c 1\n\\v 1 Valid verse\n'), 'MAT.usfm'), **fields}
        return self.client.post('/admin/bibles/validate', data=data)

    def test_standalone_generates_isolated_catalog_without_language_fields(self):
        response = self.validate(languageMode='standalone')
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json['valid'])
        self.assertRegex(response.json['language'], r'^translation_[a-f0-9]{16}$')
        metadata = self.repository.create_import.call_args.kwargs['metadata']
        self.assertTrue(metadata['standalone'])
        self.assertEqual(metadata['languageDisplayName'], 'Textus Receptus')
        self.assertEqual(response.json['stats']['verses'], 1)

    def test_existing_bible_language_uses_authoritative_specs(self):
        response = self.validate(languageMode='existing', language='arabic', languageDisplayName='Wrong label', direction='ltr')
        self.assertEqual(response.status_code, 200)
        metadata = self.repository.create_import.call_args.kwargs['metadata']
        self.assertEqual(metadata['languageDisplayName'], 'العربية')
        self.assertEqual(metadata['direction'], 'rtl')

    def test_existing_topic_only_language_can_receive_first_bible(self):
        response = self.validate(languageMode='existing', language='french')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(self.repository.create_import.call_args.kwargs['metadata']['languageDisplayName'], 'Français')

    def test_legacy_bible_subcollections_are_an_existing_language_without_parent_metadata(self):
        self.repository.available_versions.return_value = ['KJV']
        response = self.validate(languageMode='existing', language='english', languageDisplayName='English')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(self.repository.create_import.call_args.kwargs['language'], 'english')
        self.assertEqual(self.validate(languageMode='new', language='english').status_code, 400)

    def test_new_language_does_not_require_topics(self):
        response = self.validate(languageMode='new', language='ancientgreek', languageDisplayName='Ἑλληνική')
        self.assertEqual(response.status_code, 200)
        self.assertFalse(self.repository.create_import.call_args.kwargs['metadata']['standalone'])

    def test_conflicting_new_or_missing_existing_language_is_rejected(self):
        for mode, language in [('new', 'arabic'), ('existing', 'missing')]:
            self.assertEqual(self.validate(languageMode=mode, language=language).status_code, 400)
        self.repository.create_import.assert_not_called()

    def test_related_translation_must_exist_and_cannot_be_self_or_standalone(self):
        for fields in [dict(languageMode='existing', language='arabic', relatedTranslation='missing'),
                       dict(languageMode='existing', language='arabic', relatedTranslation='TR'),
                       dict(languageMode='standalone', relatedTranslation='other')]:
            self.assertEqual(self.validate(**fields).status_code, 400)
        self.repository.create_import.assert_not_called()


class TranslationSpecificationTests(unittest.TestCase):
    setUp = content_tests.ContentRepositoryTests.setUp
    def test_previous_translation_extra_specifications_are_editable(self):
        self.db.write('bibles/ancientgreek/versions/other', {'label': 'Other'}, False)
        current = self.repository.bible('ancientgreek', 'TR')
        saved = self.repository.save_bible('ancientgreek', 'TR', {
            'revision': current['revision'], 'metadata': {'containsDiacritics': True, 'relatedTranslation': 'other'}}, 'admin')
        self.assertTrue(saved['metadata']['containsDiacritics'])
        self.assertEqual(saved['metadata']['relatedTranslation'], 'other')

    def test_standalone_specification_name_updates_catalog_label(self):
        self.db.write('bibles/ancientgreek', {'standalone': True}, True)
        current = self.repository.bible('ancientgreek', 'TR')
        saved = self.repository.save_bible('ancientgreek', 'TR', {
            'revision': current['revision'], 'metadata': {'displayName': 'Independent text'}}, 'admin')
        self.assertEqual(saved['metadata']['languageDisplayName'], 'Independent text')
        self.assertTrue(saved['metadata']['standalone'])
