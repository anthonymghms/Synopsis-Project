"""Synthetic universal overlays; all database and Storage writes are mocked."""
import csv
import hashlib
import io
import unittest
from unittest.mock import patch

from flask import Flask

from services.admin_auth import AdminAuthorizationError
from services.dataset_import_service import parse_dataset_csv
from services.dataset_repository import DatasetRevisionConflict, SourceChangedError
from services.table_language_import_service import language_metadata, parse_table_language_csv, table_language_template
from services.table_language_repository import TableLanguageRepository
from table_language_api import table_language_api
from tests.test_dataset_imports import _DB, _Bucket, _transactional, CSV_FIXTURE

FIELDS = {'datasetId': 'parables', 'language': 'french', 'displayName': 'Français', 'direction': 'ltr', 'subjectsLabel': 'Sujets'}
GOSPELS = {'Matthew': 'Matthieu', 'Mark': 'Marc', 'Luke': 'Luc', 'John': 'Jean'}
CANONICAL = [{'id': '1', 'sourceName': 'Synthetic one', 'canonicalOrder': 1, 'typeId': 'parable'}, {'id': '2', 'sourceName': 'Synthetic two', 'canonicalOrder': 2, 'typeId': 'parable'}]
TYPES = [{'id': 'parable', 'labels': {'english': 'Parable'}}]
VALID = 'ItemId,SourceName,Translation,TypeId,TypeTranslation\n1,Synthetic one,"Un, exemple",parable,Parabole\n2,Synthetic two,Deux,parable,Parabole\n'.encode()


class TableLanguageParsingTests(unittest.TestCase):
    def test_template_and_strict_quoted_parser(self):
        result = parse_table_language_csv(VALID, CANONICAL, TYPES)
        self.assertTrue(result.report.valid, result.summary())
        self.assertEqual(result.records[0]['translation'], 'Un, exemple')
        self.assertEqual(result.type_labels, {'parable': 'Parabole'})
        template = table_language_template(CANONICAL, TYPES, 'french', {'1': 'Un'})
        self.assertEqual(list(csv.reader(io.StringIO(template)))[1][:3], ['1', 'Synthetic one', 'Un'])
        tabbed = b'ItemId\tSourceName\tTranslation\n1\tIgnored guidance\tUn, exemple\n2\tOther\tDeux\n'
        self.assertTrue(parse_table_language_csv(tabbed, CANONICAL, TYPES).report.valid)

    def test_title_names_only_missing_unknown_duplicate_and_blank_rows_fail(self):
        for raw in [b'Title\nUn\nDeux\n', b'Translation\nUn\nDeux\n', b'ItemId,Translation\n1,Un\n', b'ItemId,Translation\n1,Un\n3,Trois\n', b'ItemId,Translation\n1,Un\n1,Deux\n', b'ItemId,Translation\n1,Un\n2,\n', b'ItemId,Translation\n,Un\n2,Deux\n', b'ItemId,Translation\n../other,Un\n2,Deux\n']:
            with self.subTest(raw=raw):
                self.assertFalse(parse_table_language_csv(raw, CANONICAL, TYPES).report.valid)

    def test_classifications_and_reference_columns_cannot_be_changed(self):
        for raw in [VALID.replace(b'parable,Parabole', b'other,Autre', 1), VALID.replace(b'2,Synthetic two,Deux,parable,Parabole', b'2,Synthetic two,Deux,parable,Different'), b'ItemId,Translation,Matthew\n1,Un,1:1\n2,Deux,1:2\n']:
            self.assertFalse(parse_table_language_csv(raw, CANONICAL, TYPES).report.valid)

    def test_source_names_are_guidance_and_ids_are_case_sensitive(self):
        items = [{'id': 'A', 'canonicalOrder': 1, 'typeId': '', 'sourceName': 'One'}, {'id': 'a', 'canonicalOrder': 2, 'typeId': '', 'sourceName': 'Two'}]
        result = parse_table_language_csv(b'ItemId,SourceName,Translation\nA,Changed,Un\na,Changed,Deux\n', items, [])
        self.assertTrue(result.report.valid)
        self.assertEqual([row['id'] for row in result.records], ['A', 'a'])
        self.assertEqual(result.records[0]['sourceName'], 'One')


class TableLanguageRepositoryTests(unittest.TestCase):
    def setUp(self):
        self.db, self.bucket = _DB(), _Bucket()
        self.repo = TableLanguageRepository(db=self.db, bucket=self.bucket)
        patcher = patch('services.dataset_repository.firestore.transactional', side_effect=_transactional)
        patcher.start()
        self.addCleanup(patcher.stop)
        for dataset in ('miracles', 'parables'):
            self.repo.activate_dataset(import_id=('a' if dataset == 'parables' else 'b')*32, selected_dataset=dataset, result=parse_dataset_csv(CSV_FIXTURE), source={'checksum': hashlib.sha256(CSV_FIXTURE).hexdigest(), 'filename': 'fixture.csv'}, expected_revision=None, replace=False, confirmed_by='admin')
        self.db.values['harmony/canonical'] = {'activeRevision': 'master1', 'activeTopicsPath': 'harmony_revisions/master1/topics', 'topicCount': 2}
        for index in (1, 2):
            self.db.values[f'harmony_revisions/master1/topics/{index}'] = {'canonicalOrder': index, 'entries': [{'book': 'John', 'chapter': 1, 'verses': str(index)}]}
            self.db.values[f'harmony_localizations/english/topics/{index}'] = {'name': f'English {index}'}
            self.db.values[f'harmony_localizations/arabic/topics/{index}'] = {'name': f'Arabic {index}'}
        self.db.values['harmony_localizations/english'] = {'topicCount': 2, 'label': 'English', 'interfaceTranslations': {'subjects': 'custom'}}

    def translated(self, dataset='parables', language='french'):
        snapshot = self.repo.snapshot(dataset, language)
        raw = table_language_template(snapshot['items'], snapshot['types'], language, {item['id']: f'French {item["id"]}' for item in snapshot['items']}).encode()
        result = parse_table_language_csv(raw, snapshot['items'], snapshot['types'])
        return snapshot, raw, result

    def publish(self, dataset='parables', language='french', import_id='c'*32, hook=lambda: None):
        snapshot, raw, result = self.translated(dataset, language)
        metadata = language_metadata({**FIELDS, 'language': language}, GOSPELS, len(snapshot['items']))
        outcome = self.repo.activate_language(import_id=import_id, selected_dataset=dataset, language=language, result=result, metadata=metadata, expected_base=snapshot['base'], source={'checksum': hashlib.sha256(raw).hexdigest()}, replace=True, confirmed_by='admin', source_validator=hook)
        return outcome

    def test_all_tables_preserve_canonical_identity_references_and_other_languages(self):
        before = dict(self.db.values)
        for dataset in ('harmony', 'miracles', 'parables'):
            self.publish(dataset=dataset)
        for path, value in before.items():
            if '/topics/' in path:
                self.assertEqual(self.db.values[path], value, path)
        self.assertEqual(self.db.values['harmony/canonical'], before['harmony/canonical'])
        self.assertEqual(self.db.values['harmony_localizations/english'], before['harmony_localizations/english'])
        for dataset in ('miracles', 'parables'):
            localized = self.repo.localization_payload(dataset, 'french')
            self.assertEqual(localized['language']['label'], 'Français')
            self.assertEqual(localized['language']['subjectsLabel'], 'Sujets')
            self.assertEqual(localized['language']['gospels'], GOSPELS)
            self.assertTrue(all(item['name'].startswith('French') for item in localized['topics']))
            self.assertEqual(self.repo.localized_topics(dataset, 'english')['topics'][0]['name'], 'Example One')
            metadata = self.repo.metadata(dataset)
            self.assertIn('french', metadata['languages'])
            new_topics = [p for p in self.db.values if p.startswith(f"dataset_revisions/{metadata['activeRevision']}/topics/")]
            self.assertEqual(new_topics, [])  # Locale overlays never copy references.
            self.assertEqual(metadata['canonicalTopicsPath'], before[f'datasets/{dataset}']['activeTopicsPath'])
        self.assertEqual(self.db.values['harmony_localizations/french']['subjectsLabel'], 'Sujets')

    def test_second_language_and_repeated_master_source_preserve_existing_overlay(self):
        french = self.publish()
        self.publish(language='german', import_id='d'*32)
        self.assertEqual(self.repo.localization_payload('parables', 'french')['topics'][0]['name'], 'French 10')
        self.assertEqual(self.repo.localization_payload('parables', 'german')['topics'][0]['nameLanguage'], 'german')
        active = self.repo.metadata('parables')['activeRevision']
        outcome = self.repo.activate_dataset(import_id='f'*32, selected_dataset='parables', result=parse_dataset_csv(CSV_FIXTURE), source={'checksum': hashlib.sha256(CSV_FIXTURE).hexdigest(), 'filename': 'fixture.csv'}, expected_revision=active, replace=True, confirmed_by='admin')
        self.assertTrue(outcome['unchanged'])
        self.assertEqual(outcome['revision'], active)
        self.assertNotEqual(french['revision'], active)
        self.assertIn('french', self.repo.metadata('parables')['languageMetadata'])

    def test_concurrent_same_language_attempt_failure_never_rewrites_active_snapshot(self):
        snapshot, raw, result = self.translated()
        metadata = language_metadata(FIELDS, GOSPELS, 3)
        winner = {}
        original_writer = self.repo._write_documents
        def delayed_writer(writes):
            self.repo._write_documents = original_writer
            winner.update(self.repo.activate_language(import_id='c'*32, selected_dataset='parables', language='french', result=result, metadata=metadata, expected_base=snapshot['base'], source={'checksum': 'fixture'}, replace=True, confirmed_by='admin', source_validator=lambda: None))
            raise RuntimeError('Second concurrent attempt failed')
        self.repo._write_documents = delayed_writer
        with self.assertRaises(RuntimeError):
            self.repo.activate_language(import_id='c'*32, selected_dataset='parables', language='french', result=result, metadata=metadata, expected_base=snapshot['base'], source={'checksum': 'fixture'}, replace=True, confirmed_by='admin', source_validator=lambda: None)
        self.assertEqual(self.repo.metadata('parables')['activeRevision'], winner['revision'])
        self.assertEqual(self.repo.localization_payload('parables', 'french')['topics'][0]['name'], 'French 10')
        self.repo.record_failed_attempt('c'*32, status='failed')
        self.assertEqual(self.repo.get_import('c'*32)['status'], 'completed')

    def test_existing_revision_snapshot_is_coherent_after_language_publication(self):
        previous = self.repo.metadata('parables')['activeRevision']
        before = self.repo.canonical_payload('parables', previous)
        self.publish()
        self.assertEqual(self.repo.canonical_payload('parables')['topics'], before['topics'])
        old = self.repo.localization_payload('parables', 'french', previous)
        self.assertTrue(all(item['fallback'] for item in old['topics']))
        self.assertTrue(all(not item['fallback'] for item in self.repo.localization_payload('parables', 'french')['topics']))

    def test_repeat_is_idempotent_and_failed_stage_preserves_old_revision(self):
        first = self.publish()
        second = self.publish(import_id='d'*32)
        self.assertTrue(second['unchanged'])
        self.assertEqual(first['revision'], second['revision'])
        self.db.fail_batch = True
        with self.assertRaises(RuntimeError):
            self.publish(language='german')
        self.assertEqual(self.repo.metadata('parables')['activeRevision'], first['revision'])
        self.assertEqual(len(self.repo.localization_payload('parables', 'french')['topics']), 3)

    def test_changed_source_and_concurrent_canonical_revision_cannot_activate(self):
        before = self.repo.metadata('parables')['activeRevision']
        def source_changed():
            raise SourceChangedError('changed fixture')
        with self.assertRaises(SourceChangedError):
            self.publish(hook=source_changed)
        self.assertEqual(self.repo.metadata('parables')['activeRevision'], before)
        def revision_changed():
            self.db.values['datasets/parables']['activeRevision'] = 'parables--' + 'e'*32
        with self.assertRaises(DatasetRevisionConflict):
            self.publish(hook=revision_changed)
        self.assertNotIn('french', self.repo.metadata('parables')['languages'])

    def test_harmony_target_changes_during_stage_are_not_overwritten(self):
        def changed():
            self.db.values['harmony_localizations/french'] = {'activeRevision': 'other-admin', 'label': 'Other'}
        with self.assertRaises(DatasetRevisionConflict):
            self.publish(dataset='harmony', hook=changed)
        self.assertEqual(self.db.values['harmony_localizations/french']['activeRevision'], 'other-admin')

    def test_harmony_replacement_preserves_interface_translations(self):
        self.publish(dataset='harmony', language='english')
        self.assertEqual(self.db.values['harmony_localizations/english']['interfaceTranslations'], {'subjects': 'custom'})

    def test_harmony_signature_does_not_hide_intervening_editor_or_metadata_changes(self):
        first = self.publish(dataset='harmony')
        repeat = self.publish(dataset='harmony', import_id='d'*32)
        self.assertTrue(repeat['unchanged'])
        self.assertEqual(repeat['revision'], first['revision'])
        for edit in ({'activeRevision': 'editor-revision', 'activeTopicsPath': 'harmony_localization_revisions/editor-revision/topics'}, {'label': 'Edited label'}):
            with self.subTest(edit=edit):
                snapshot, raw, result = self.translated('harmony')
                metadata = language_metadata(FIELDS, GOSPELS, len(snapshot['items']))
                target = self.db.values['harmony_localizations/french']
                # Existing Harmony editors preserve unrelated metadata keys.
                target.update(edit)
                with self.assertRaises(DatasetRevisionConflict):
                    self.repo.activate_language(import_id='e'*32, selected_dataset='harmony', language='french', result=result, metadata=metadata, expected_base=snapshot['base'], source={'checksum': hashlib.sha256(raw).hexdigest()}, replace=True, confirmed_by='admin', source_validator=lambda: None)
                restored = self.publish(dataset='harmony', import_id='f'*32)
                self.assertFalse(restored['unchanged'])
                restored_path = self.db.values['harmony_localizations/french']['activeTopicsPath']
                self.assertEqual(self.db.values[f'{restored_path}/1']['name'], 'French 1')
                self.assertEqual(self.db.values['harmony_localizations/french']['label'], 'Français')

    def test_type_translation_changes_label_only(self):
        snapshot, raw, _ = self.translated()
        raw = raw.replace(b'parable,\r\n', b'parable,Parabole\r\n')
        result = parse_table_language_csv(raw, snapshot['items'], snapshot['types'])
        before = self.repo.canonical_payload('parables')['topics']
        self.repo.activate_language(import_id='c'*32, selected_dataset='parables', language='french', result=result, metadata=language_metadata(FIELDS, GOSPELS, 3), expected_base=snapshot['base'], source={'checksum': 'fixture'}, replace=True, confirmed_by='admin', source_validator=lambda: None)
        self.assertEqual(self.repo.canonical_payload('parables')['topics'], before)
        self.assertEqual(self.repo.localization_payload('parables', 'french')['typeLabels']['parable'], 'Parabole')


class TableLanguageApiTests(unittest.TestCase):
    translated = TableLanguageRepositoryTests.translated

    def setUp(self):
        TableLanguageRepositoryTests.setUp(self)
        app = Flask(__name__)
        app.register_blueprint(table_language_api)
        app.register_error_handler(AdminAuthorizationError, lambda exc: ({'error': exc.code}, exc.status))
        self.client = app.test_client()
        for target, value in [('table_language_api.TableLanguageRepository', self.repo), ('table_language_api.verify_admin_authorization', {'uid': 'admin'})]:
            patcher = patch(target, return_value=value)
            patcher.start()
            self.addCleanup(patcher.stop)

    def validate(self, dataset='parables', raw=None):
        import json
        _, translated, _ = self.translated(dataset)
        return self.client.post('/admin/table-languages/validate', data={**FIELDS, 'datasetId': dataset, 'gospels': json.dumps(GOSPELS), 'file': (io.BytesIO(raw or translated), 'synthetic.csv')})

    def test_admin_authorization_protects_every_endpoint(self):
        with patch('table_language_api.verify_admin_authorization', side_effect=AdminAuthorizationError('forbidden', 'Denied', 403)):
            self.assertEqual(self.client.get('/admin/table-languages/template?datasetId=parables&language=french').status_code, 403)
            self.assertEqual(self.client.post('/admin/table-languages/validate').status_code, 403)
            self.assertEqual(self.client.post('/admin/table-languages/publish').status_code, 403)

    def test_path_and_identifier_injection_are_rejected_before_storage_access(self):
        import json
        before = dict(self.db.values)
        before_storage = dict(self.bucket.values)
        with patch.object(self.repo, 'snapshot', side_effect=AssertionError('Invalid identifiers must not reach Firestore')):
            for fields in ({'datasetId': '../harmony', 'language': 'french'}, {'datasetId': 'parables', 'language': '../french'}):
                self.assertEqual(self.client.get('/admin/table-languages/template', query_string=fields).status_code, 400)
                self.assertEqual(self.client.post('/admin/table-languages/validate', data={**FIELDS, **fields, 'gospels': json.dumps(GOSPELS), 'file': (io.BytesIO(VALID), 'fixture.csv')}).status_code, 400)
            self.assertEqual(self.client.post('/admin/table-languages/validate', data={**FIELDS, 'gospels': json.dumps(GOSPELS), 'file': (io.BytesIO(VALID), '../fixture.csv')}).status_code, 400)
            self.assertEqual(self.client.post('/admin/table-languages/publish', json={'datasetId': 'parables', 'language': 'french', 'importId': '../other', 'confirm': True}).status_code, 400)
        self.assertEqual(self.db.values, before)
        self.assertEqual(self.bucket.values, before_storage)

    def test_template_preview_and_publication_require_explicit_confirmation(self):
        for dataset in ('harmony', 'miracles', 'parables'):
            template = self.client.get(f'/admin/table-languages/template?datasetId={dataset}&language=french')
            self.assertEqual(template.status_code, 200)
            self.assertIn('ItemId,SourceName,Translation', template.get_json()['csv'])
            before = dict(self.db.values[f'datasets/{dataset}']) if dataset != 'harmony' else dict(self.db.values['harmony/canonical'])
            validated = self.validate(dataset)
            self.assertEqual(validated.status_code, 200, validated.get_json())
            data = validated.get_json()
            self.assertTrue(data['valid'], data)
            payload = {'importId': data['importId'], 'datasetId': dataset, 'language': 'french'}
            self.assertEqual(self.client.post('/admin/table-languages/publish', json=payload).status_code, 400)
            pointer = self.db.values[f'datasets/{dataset}'] if dataset != 'harmony' else self.db.values['harmony/canonical']
            self.assertEqual(pointer, before)
            response = self.client.post('/admin/table-languages/publish', json={**payload, 'confirm': True})
            self.assertEqual(response.status_code, 200, response.get_json())
            self.assertEqual(response.get_json()['status'], 'completed')

    def test_replacement_and_target_mismatch_require_correct_confirmation(self):
        data = self.validate().get_json()
        payload = {'importId': data['importId'], 'datasetId': 'parables', 'language': 'french', 'confirm': True}
        self.assertEqual(self.client.post('/admin/table-languages/publish', json={**payload, 'datasetId': 'miracles'}).status_code, 400)
        self.assertEqual(self.client.post('/admin/table-languages/publish', json=payload).status_code, 200)
        data = self.validate().get_json()
        self.assertTrue(data['replacesExisting'])
        payload['importId'] = data['importId']
        self.assertEqual(self.client.post('/admin/table-languages/publish', json=payload).status_code, 409)
        self.assertEqual(self.client.post('/admin/table-languages/publish', json={**payload, 'replace': True}).status_code, 200)

    def test_invalid_full_coverage_and_changed_upload_cannot_publish(self):
        data = self.validate(raw=b'ItemId,Translation\n10,Un\n').get_json()
        self.assertFalse(data['valid'])
        self.assertEqual(self.client.post('/admin/table-languages/publish', json={'importId': data['importId'], 'datasetId': 'parables', 'language': 'french', 'confirm': True}).status_code, 409)
        data = self.validate().get_json()
        record = self.repo.get_import(data['importId'])
        path = record['source']['path']
        raw, _ = self.bucket.values[path]
        self.bucket.values[path] = (raw, 2)
        response = self.client.post('/admin/table-languages/publish', json={'importId': data['importId'], 'datasetId': 'parables', 'language': 'french', 'confirm': True})
        self.assertEqual(response.status_code, 409)
        self.assertNotIn('french', self.repo.metadata('parables')['languages'])


if __name__ == '__main__':
    unittest.main()
