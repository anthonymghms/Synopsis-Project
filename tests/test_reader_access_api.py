import unittest
from unittest.mock import patch

import app as app_module
from services.admin_auth import AdminAuthorizationError


class ReaderAccessApiTests(unittest.TestCase):
    def setUp(self):
        self.client = app_module.app.test_client()
        self.read_routes = ['/topics', '/english/kjv/topic/1', '/get_verse', '/get_chapter',
                            '/harmony/topics', '/topic-localizations/english']

    def test_every_reader_route_rejects_missing_authentication(self):
        for path in self.read_routes:
            with self.subTest(path=path):
                response = self.client.get(path)
                self.assertEqual(response.status_code, 401)
                self.assertEqual(response.json['error']['code'], 'authentication_required')
                self.assertEqual(response.headers['Cache-Control'], 'no-store')

    def test_every_reader_route_enforces_guest_expiry_before_reading_data(self):
        with patch.object(app_module, 'verify_reader_authorization', side_effect=AdminAuthorizationError(
            'guest_access_expired', 'Guest access has expired.', 403)) as guard:
            for path in self.read_routes:
                response = self.client.get(path, headers={'Authorization': 'Bearer token'})
                self.assertEqual(response.status_code, 403)
                self.assertEqual(response.json['error']['code'], 'guest_access_expired')
                self.assertEqual(response.headers['Cache-Control'], 'no-store')
            self.assertEqual(guard.call_count, len(self.read_routes))
            guard.assert_called_with('Bearer token')

    def test_catalog_requires_authentication_but_does_not_require_active_reading(self):
        self.assertEqual(self.client.get('/topic-languages').status_code, 401)
        with patch.object(app_module, 'verify_reader_authorization') as reader, \
             patch.object(app_module, 'verify_identity', return_value={'uid': 'expired'}), \
             patch.object(app_module, '_canonical_topics_collection', return_value=None), \
             patch.object(app_module, 'db') as db:
            db.collection.return_value.list_documents.return_value = []
            response = self.client.get('/topic-languages', headers={'Authorization': 'Bearer expired'})
            self.assertEqual(response.status_code, 200)
            reader.assert_not_called()

    def test_cors_preflight_remains_available_without_authentication(self):
        response = self.client.options('/get_chapter', headers={
            'Origin': 'http://localhost:8760', 'Access-Control-Request-Method': 'GET',
            'Access-Control-Request-Headers': 'Authorization'})
        self.assertEqual(response.status_code, 200)
        self.assertIn('Authorization', response.headers['Access-Control-Allow-Headers'])
