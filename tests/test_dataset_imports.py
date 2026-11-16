"""Synthetic fixtures for dataset isolation and publication; no Firebase writes."""
import hashlib
import io
import unittest
from types import SimpleNamespace
from unittest.mock import patch

from flask import Flask

from dataset_api import dataset_api
from services.admin_auth import AdminAuthorizationError
from services.dataset_import_service import parse_dataset_csv
from services.dataset_repository import DatasetRepository, DatasetRevisionConflict, SourceChangedError


# Intentionally synthetic examples; these are not the live Storage CSV contents.
CSV_FIXTURE = ('#,Subject,الموضوع,Type,Matthew,Mark,Luke,John\n'
               '10,Example One,مثال واحد,Parable,"5:1,3-4",4:40-41+5:1,,\n'
               '20,Example Two,مثال اثنان,Figure of Speech,,,10:1;10:3,\n'
               '30,Example One,,,6:2,,,\n').encode()


class _Snapshot:
    def __init__(self, path, data):
        self.id = path.split('/')[-1]
        self.exists = data is not None
        self.data = data
    def to_dict(self):
        return dict(self.data or {})


class _Document:
    def __init__(self, db, path):
        self.db, self.path = db, path
        self.id = path.split('/')[-1]
    def get(self, transaction=None):
        return _Snapshot(self.path, self.db.values.get(self.path))
    def collection(self, name):
        return _Collection(self.db, f'{self.path}/{name}')
    def set(self, value, merge=False):
        self.db.write(self.path, value, merge)


class _Collection:
    def __init__(self, db, path):
        self.db, self.path = db, path
    def document(self, identifier):
        return _Document(self.db, f'{self.path}/{identifier}')
    def stream(self):
        prefix = self.path + '/'
        return [_Snapshot(path, value) for path, value in self.db.values.items() if path.startswith(prefix) and '/' not in path[len(prefix):]]


class _Batch:
    def __init__(self, db):
        self.db, self.pending = db, []
    def set(self, doc, value, merge=False):
        self.pending.append((doc.path, value, merge))
    def commit(self):
        if self.db.fail_batch:
            raise RuntimeError('Synthetic write failure')
        for path, value, merge in self.pending:
            self.db.write(path, value, merge)


class _DB:
    def __init__(self):
        self.values, self.fail_batch = {}, False
    def collection(self, path):
        return _Collection(self, path)
    def batch(self):
        return _Batch(self)
    def transaction(self):
        return _Batch(self)
    def write(self, path, value, merge=False):
        self.values[path] = {**(self.values.get(path, {}) if merge else {}), **value}


def _transactional(function):
    def run(transaction):
        result = function(transaction)
        transaction.commit()
        return result
    return run


class _Blob:
    def __init__(self, bucket, path):
        self.bucket, self.path = bucket, path
    def reload(self):
        raw, generation = self.bucket.values[self.path]
        self.size, self.generation = len(raw), generation
    def upload_from_string(self, raw, **kwargs):
        if kwargs.get('if_generation_match') == 0 and self.path in self.bucket.values:
            raise RuntimeError('Already exists')
        self.bucket.values[self.path] = (raw, 1)
    def download_as_bytes(self, if_generation_match):
        raw, generation = self.bucket.values[self.path]
        if generation != if_generation_match:
            raise RuntimeError('Generation changed')
        return raw


class _Bucket:
    def __init__(self):
        self.values = {'Parables.csv': (CSV_FIXTURE, 1), 'Miracles.csv': (CSV_FIXTURE, 1)}
    def blob(self, path):
        return _Blob(self, path)


class DatasetParsingTests(unittest.TestCase):
    def test_bilingual_type_mapping_and_reference_grammar(self):
        result = parse_dataset_csv(CSV_FIXTURE)
        self.assertTrue(result.report.valid, result.summary())
        self.assertEqual(result.languages, ['english', 'arabic'])
        self.assertEqual(result.records[0].item_id, '10')
        self.assertEqual(result.records[0].names['arabic'], 'مثال واحد')
        self.assertEqual(result.records[0].type_id, 'parable')
        self.assertEqual(result.summary()['stats']['references'], 6)
        self.assertEqual(result.summary()['stats']['physicalSegments'], 7)
        self.assertEqual(result.records[0].reference_cells[0].display_value, '5:1, 3-4')
        self.assertEqual({value['id'] for value in result.types}, {'parable', 'figure-of-speech'})
        self.assertIn('missing_type_values', [issue.code for issue in result.report.warnings])
        self.assertEqual(len(result.records), 3)  # Duplicate names are distinct IDs.

    def test_actual_storage_header_shapes_and_tab_delimiter(self):
        raw = '#\tMiracles\tالمعجزات\tMatthew\tMark\tLuke\tJohn\n1\tSynthetic\tمثال\t5:1,3\t\t\t\n'.encode()
        result = parse_dataset_csv(raw)
        self.assertTrue(result.report.valid)
        self.assertEqual(result.delimiter, '\t')
        self.assertEqual(result.encoding, 'utf-8')
        self.assertFalse(result.has_type_column)
        self.assertEqual(result.types, [])
        self.assertIn('no_type_data', [issue.code for issue in result.report.warnings])
        self.assertEqual(parse_dataset_csv(b'\xef\xbb\xbf' + raw).encoding, 'utf-8-sig')

    def test_mapping_uses_headers_even_when_reordered(self):
        result = parse_dataset_csv(b'John,Type,Subject,#,Luke,Matthew,Mark\n3:1,Other category,Synthetic,a-10,,5:1,\n')
        self.assertTrue(result.report.valid)
        self.assertEqual(result.records[0].type_id, 'other-category')
        self.assertEqual(result.records[0].item_id, 'a-10')
        self.assertEqual([cell.book for cell in result.records[0].reference_cells], ['Matthew', 'John'])

    def test_explicit_source_order_and_type_identifiers(self):
        raw = b'#,Subject,Type,TypeId,TypeOrder,SourceOrder,Matthew,Mark,Luke,John\n10,First,Renamed,stable,2,8,1:1,,,\n20,Second,Another,another,1,3,1:2,,,\n'
        result = parse_dataset_csv(raw)
        self.assertTrue(result.report.valid)
        self.assertEqual([item.item_id for item in result.records], ['20', '10'])
        self.assertEqual([value['id'] for value in result.types], ['another', 'stable'])

    def test_missing_values_unknown_types_and_empty_references_are_preserved(self):
        result = parse_dataset_csv(b'#,Subject,Type,Matthew,Mark,Luke,John\n1,Synthetic,New classification,,,,\n2,Other,,1:1,,,\n')
        self.assertTrue(result.report.valid)
        self.assertEqual(len(result.records), 2)
        self.assertEqual(result.types[0]['id'], 'new-classification')
        self.assertEqual(result.summary()['stats']['missingTypes'], 1)

    def test_bad_references_duplicate_ids_and_csv_width_are_blocking(self):
        for raw, code in [
            (b'#,Subject,Matthew,Mark,Luke,John\n1,X,bogus,,,\n', 'invalid_reference'),
            (b'#,Subject,Matthew,Mark,Luke,John\n1,X,1:1,,,\n01,Y,1:2,,,\n', 'duplicate_item_id'),
            (b'#,Subject,Matthew,Mark,Luke,John\n1,X,1:1,2,,,\n', 'column_count_mismatch'),
        ]:
            result = parse_dataset_csv(raw)
            self.assertFalse(result.report.valid)
            if code != 'invalid_reference':
                self.assertIn(code, [issue.code for issue in result.report.errors])

    def test_gospel_columns_may_not_be_shifted_or_ambiguous(self):
        result = parse_dataset_csv(b'#,Subject,Type,Matthew,Mark,Luke\n1,X,Parable,1:1,,\n')
        self.assertFalse(result.report.valid)
        result = parse_dataset_csv(b'#,Subject,Topic,Matthew,Mark,Luke,John\n1,X,Y,1:1,,,\n')
        self.assertFalse(result.report.valid)


class DatasetRepositoryTests(unittest.TestCase):
    def setUp(self):
        self.db, self.bucket = _DB(), _Bucket()
        self.repo = DatasetRepository(db=self.db, bucket=self.bucket)
        self.result = parse_dataset_csv(CSV_FIXTURE)
        self.source = {'kind': 'storage', 'path': 'Parables.csv', 'filename': 'Parables.csv', 'generation': '1', 'checksum': hashlib.sha256(CSV_FIXTURE).hexdigest()}
        patcher = patch('services.dataset_repository.firestore.transactional', side_effect=_transactional)
        patcher.start()
        self.addCleanup(patcher.stop)

    def publish(self, selected_dataset='parables', import_id='a'*32, expected_revision=None, source=None):
        return self.repo.activate_dataset(import_id=import_id, selected_dataset=selected_dataset, result=self.result, source=source or self.source, expected_revision=expected_revision, replace=True, confirmed_by='admin')

    def test_ids_are_isolated_from_harmony_and_each_other(self):
        self.db.values['harmony/canonical'] = {'activeRevision': 'untouched'}
        self.db.values['references/english_kjv/topics/10'] = {'name': 'Harmony item'}
        self.publish('parables')
        self.publish('miracles', import_id='b'*32)
        self.assertEqual(self.db.values['harmony/canonical'], {'activeRevision': 'untouched'})
        self.assertEqual(self.db.values['references/english_kjv/topics/10']['name'], 'Harmony item')
        self.assertNotEqual(self.repo.metadata('parables')['activeTopicsPath'], self.repo.metadata('miracles')['activeTopicsPath'])
        canonical = self.repo.canonical_payload('parables')
        self.assertEqual([item['id'] for item in canonical['topics']], ['10', '20', '30'])
        self.assertNotIn('name', canonical['topics'][0])
        self.assertEqual(self.repo.localization_payload('parables', 'arabic')['topics'][0]['name'], 'مثال واحد')
        self.assertEqual(self.repo.localization_payload('parables', 'arabic')['typeLabels'], {})
        self.assertEqual(self.repo.localization_payload('parables', 'english')['typeLabels']['parable'], 'Parable')
        self.assertEqual(self.repo.localized_topics('parables', 'arabic')['topics'][2]['name'], 'Example One')

    def test_repeat_source_is_idempotent_and_missing_table_stays_empty(self):
        first = self.publish()
        before = len([path for path in self.db.values if path.startswith('dataset_revisions/')])
        repeat = self.publish(import_id='b'*32, expected_revision=first['revision'])
        self.assertTrue(repeat['unchanged'])
        self.assertEqual(first['revision'], repeat['revision'])
        self.assertEqual(before, len([path for path in self.db.values if path.startswith('dataset_revisions/')]))
        self.assertEqual(self.repo.canonical_payload('miracles')['topics'], [])
        self.assertEqual(self.repo.localization_payload('miracles', 'english')['topics'], [])

    def test_failure_never_changes_published_pointer_or_localizations(self):
        first = self.publish()
        source = {**self.source, 'checksum': 'changed'}
        self.db.fail_batch = True
        with self.assertRaises(RuntimeError):
            self.publish(import_id='b'*32, expected_revision=first['revision'], source=source)
        self.assertEqual(self.repo.metadata('parables')['activeRevision'], first['revision'])
        self.assertEqual(len(self.repo.localized_topics('parables', 'arabic')['topics']), 3)

    def test_concurrent_same_import_failure_cannot_rewrite_active_revision(self):
        original_writer = self.repo._write_documents
        competing = DatasetRepository(db=self.db, bucket=self.bucket)
        winner = {}
        def delayed_writer(writes):
            # Both requests observed the old pointer. A completes after B has
            # staged its header but before B attempts its content batches.
            winner.update(competing.activate_dataset(import_id='a'*32, selected_dataset='parables', result=self.result, source=self.source, expected_revision=None, replace=True, confirmed_by='admin'))
            raise RuntimeError('Delayed second request fails')
        self.repo._write_documents = delayed_writer
        with self.assertRaises(RuntimeError):
            self.publish()
        self.repo._write_documents = original_writer
        self.assertEqual(self.repo.metadata('parables')['activeRevision'], winner['revision'])
        self.assertEqual(len(self.repo.canonical_payload('parables')['topics']), 3)
        self.assertEqual(self.db.values[f"dataset_revisions/{winner['revision']}"]['status'], 'ready')
        self.repo.record_failed_attempt('a'*32, status='failed')
        self.assertEqual(self.repo.get_import('a'*32)['status'], 'completed')

    def test_source_changed_during_staging_does_not_publish(self):
        def changed():
            raise SourceChangedError('Changed while writing staged records')
        with self.assertRaises(SourceChangedError):
            self.repo.activate_dataset(import_id='a'*32, selected_dataset='parables', result=self.result, source=self.source, expected_revision=None, replace=True, confirmed_by='admin', source_validator=changed)
        self.assertNotIn('datasets/parables', self.db.values)

    def test_stale_preview_cannot_overwrite_another_published_revision(self):
        self.publish()
        with self.assertRaises(DatasetRevisionConflict):
            self.publish(import_id='b'*32, source={**self.source, 'checksum': 'new'})

    def test_revision_localizations_do_not_mix_with_new_active_data(self):
        first = self.publish()
        self.result = parse_dataset_csv(CSV_FIXTURE.replace(b'Example One', b'Changed'))
        self.publish(import_id='b'*32, expected_revision=first['revision'], source={**self.source, 'checksum': 'new'})
        old = self.repo.localization_payload('parables', 'english', first['revision'])
        self.assertEqual(old['topics'][0]['name'], 'Example One')
        with self.assertRaises(ValueError):
            self.repo.localization_payload('miracles', 'english', first['revision'])

    def test_storage_and_upload_source_checks_detect_replacements(self):
        raw, details = self.repo.read_storage_source('parables', 'Parables.csv')
        self.assertEqual(raw, CSV_FIXTURE)
        record = {'id': 'a'*32, 'datasetId': 'parables', 'source': {'kind': 'storage', **details}}
        self.assertEqual(self.repo.checked_source(record), raw)
        self.bucket.values['Parables.csv'] = (raw, 2)
        with self.assertRaises(SourceChangedError):
            self.repo.checked_source(record)
        staged = self.repo.stage_upload('parables', 'a'*32, 'fixture.csv', raw)
        record['source'] = staged
        self.assertEqual(self.repo.checked_source(record), raw)
        self.bucket.values[staged['path']] = (b'changed', 1)
        with self.assertRaises(SourceChangedError):
            self.repo.checked_source(record)

    def test_storage_source_allowlist(self):
        for filename in ('Miracles.csv', '../Parables.csv', 'https://example.com/Parables.csv', 'other.csv'):
            with self.assertRaises(ValueError):
                self.repo.read_storage_source('parables', filename)


class DatasetApiTests(unittest.TestCase):
    def setUp(self):
        self.db, self.bucket = _DB(), _Bucket()
        self.repo = DatasetRepository(db=self.db, bucket=self.bucket)
        self.repo.chapter_verse_count = lambda book, chapter: 41 if (book, chapter) == ('Mark', 4) else 100
        app = Flask(__name__)
        app.register_blueprint(dataset_api)
        app.register_error_handler(AdminAuthorizationError, lambda error: ({'error': {'code': error.code}}, error.status))
        self.client = app.test_client()
        for name, value in [('dataset_api.DatasetRepository', self.repo), ('dataset_api.verify_admin_authorization', {'uid': 'admin'}), ('dataset_api.verify_reader_authorization', {'uid': 'reader'})]:
            patcher = patch(name, return_value=value)
            patcher.start()
            self.addCleanup(patcher.stop)
        patcher = patch('services.dataset_repository.firestore.transactional', side_effect=_transactional)
        patcher.start()
        self.addCleanup(patcher.stop)

    def validate(self):
        return self.client.post('/admin/datasets/validate', json={'datasetId': 'parables', 'source': 'storage', 'filename': 'Parables.csv'}).get_json()

    def test_storage_and_uploaded_csv_share_validation_preview(self):
        storage = self.validate()
        upload = self.client.post('/admin/datasets/validate', data={'datasetId': 'parables', 'source': 'upload', 'file': (io.BytesIO(CSV_FIXTURE), 'fixture.csv')}, content_type='multipart/form-data').get_json()
        for key in ('valid', 'stats', 'preview', 'types', 'languages', 'sourceChecksum'):
            self.assertEqual(storage[key], upload[key])
        self.assertNotIn('datasets/parables', self.db.values)
        self.assertTrue(all(not path.startswith('harmony/') for path in self.db.values))

    def test_publish_requires_confirmation_and_is_idempotent(self):
        validation = self.validate()
        payload = {'datasetId': 'parables', 'importId': validation['importId']}
        self.assertEqual(self.client.post('/admin/datasets/publish', json=payload).status_code, 400)
        payload['confirm'] = True
        response = self.client.post('/admin/datasets/publish', json=payload)
        self.assertEqual(response.status_code, 200, response.get_json())
        self.assertEqual(response.get_json()['status'], 'completed')
        first = self.repo.metadata('parables')['activeRevision']
        self.assertEqual(self.client.post('/admin/datasets/publish', json=payload).status_code, 200)
        self.assertEqual(self.repo.metadata('parables')['activeRevision'], first)

    def test_changed_source_requires_revalidation(self):
        validation = self.validate()
        self.bucket.values['Parables.csv'] = (CSV_FIXTURE, 2)
        response = self.client.post('/admin/datasets/publish', json={'datasetId': 'parables', 'importId': validation['importId'], 'confirm': True})
        self.assertEqual(response.status_code, 409)
        self.assertEqual(response.get_json()['error']['code'], 'source_changed')
        self.assertNotIn('datasets/parables', self.db.values)

    def test_every_admin_action_and_read_require_verified_authorization(self):
        denied = AdminAuthorizationError('forbidden', 'Denied', 403)
        with patch('dataset_api.verify_admin_authorization', side_effect=denied):
            for method, path in [('get', '/admin/datasets/sources'), ('post', '/admin/datasets/validate'), ('post', '/admin/datasets/publish')]:
                self.assertEqual(getattr(self.client, method)(path).status_code, 403)
        with patch('dataset_api.verify_reader_authorization', side_effect=denied):
            for path in ['/datasets/parables/topics', '/datasets/miracles/localizations/arabic']:
                self.assertEqual(self.client.get(path).status_code, 403)

    def test_legacy_reader_routes_preserve_dataset_and_table_language(self):
        import importlib
        with patch('services.firebase_service.firestore_client', return_value=self.db):
            module = importlib.import_module('app')
        validation = self.validate()
        self.client.post('/admin/datasets/publish', json={'datasetId': 'parables', 'importId': validation['importId'], 'confirm': True})
        with patch.object(module, 'db', self.db), patch.object(module, 'verify_reader_authorization', return_value={'uid': 'reader'}):
            client = module.app.test_client()
            response = client.get('/english/kjv/topic/10?dataset=parables&topicLanguage=arabic')
            self.assertEqual(response.status_code, 200)
            self.assertEqual(response.get_json()['name'], 'مثال واحد')
            self.assertEqual(response.get_json()['datasetId'], 'parables')
            self.assertEqual(client.get('/english/kjv/topic/10?dataset=miracles').status_code, 404)
            listing = client.get('/topics?dataset=parables&topicLanguage=english').get_json()
            self.assertEqual([item['id'] for item in listing], ['10', '20', '30'])
            self.assertEqual(listing[0]['name'], 'Example One')

    def test_wrong_dataset_and_arbitrary_storage_paths_are_rejected(self):
        self.assertEqual(self.client.post('/admin/datasets/validate', json={'datasetId': 'harmony', 'source': 'storage', 'filename': 'Parables.csv'}).status_code, 400)
        self.assertEqual(self.client.post('/admin/datasets/validate', json={'datasetId': 'parables', 'source': 'storage', 'filename': 'gs://elsewhere/Parables.csv'}).status_code, 400)
        validation = self.validate()
        response = self.client.post('/admin/datasets/publish', json={'datasetId': 'miracles', 'importId': validation['importId'], 'confirm': True})
        self.assertEqual(response.status_code, 400)


if __name__ == '__main__':
    unittest.main()
