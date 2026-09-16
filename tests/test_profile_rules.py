"""Profile write integration tests against a local Firestore emulator only.

Run with FIRESTORE_EMULATOR_HOST=127.0.0.1:8080. The tests load the repository
rules into a dedicated demo project; no Firebase credentials are needed.
"""

import base64
import copy
import json
import os
from pathlib import Path
import time
import unittest
from urllib.parse import urlparse

import requests


PROJECT = "demo-synopsis-profile"
DATABASE = f"projects/{PROJECT}/databases/(default)"
UID = "profile-owner"
EMAIL = "profile-owner@example.com"
RULES = Path(__file__).resolve().parents[1] / "gospel_frontend/firestore.rules"


def _token(uid=UID):
    def encode(data):
        return base64.urlsafe_b64encode(json.dumps(data).encode()).rstrip(b"=").decode()

    now = int(time.time())
    payload = {
        "sub": uid,
        "user_id": uid,
        "email": EMAIL,
        "aud": PROJECT,
        "iss": f"https://securetoken.google.com/{PROJECT}",
        "iat": now,
        "exp": now + 3600,
        "auth_time": now,
        "firebase": {"sign_in_provider": "password"},
    }
    return f'{encode({"alg": "none", "typ": "JWT"})}.{encode(payload)}.'


def _value(value):
    if value is None:
        return {"nullValue": None}
    if isinstance(value, bool):
        return {"booleanValue": value}
    if isinstance(value, int):
        return {"integerValue": str(value)}
    if isinstance(value, float):
        return {"doubleValue": value}
    if isinstance(value, dict):
        return {"mapValue": {"fields": {k: _value(v) for k, v in value.items()}}}
    return {"stringValue": value}


def _preferences():
    return {
        "menuLanguage": "english",
        "topicLanguage": "english",
        "bibleLanguage": "english",
        "bibleVersion": "kjv",
        "contentLanguage": "english",
        "preferredVersion": "kjv",
        "showDiacritics": False,
        "zoomLevel": 1.0,
        "interlinearEnabled": False,
        "showTopicNamesInChapter": False,
        "showTranslationLabels": False,
    }


def _profile():
    return {
        "firstName": "Admin",
        "lastName": "Admin",
        "displayName": "Admin",
        "email": EMAIL,
        "country": "Lebanon",
        "timezone": "Asia/Beirut",
        "yearOfBirth": 1970,
        "organization": "",
        "bio": "",
        "preferences": _preferences(),
        "profileCompleted": True,
    }


@unittest.skipUnless(os.environ.get("FIRESTORE_EMULATOR_HOST"), "requires Firestore emulator")
class ProfileRulesTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.base = "http://" + os.environ["FIRESTORE_EMULATOR_HOST"]
        if urlparse(cls.base).hostname not in {"localhost", "127.0.0.1", "::1"}:
            raise ValueError("Profile rule tests only run against a local emulator")
        rules = Path(os.environ.get("FIRESTORE_RULES_FILE", str(RULES))).read_text()
        response = requests.put(
            f"{cls.base}/emulator/v1/projects/{PROJECT}:securityRules",
            json={"rules": {"files": [{"name": "firestore.rules", "content": rules}]}},
            timeout=30,
        )
        response.raise_for_status()

    def setUp(self):
        response = requests.delete(
            f"{self.base}/emulator/v1/{DATABASE}/documents", timeout=10
        )
        response.raise_for_status()

    def write(self, data, *, admin=False, uid=UID, merge=False, create_timestamp=True,
              delete_fields=()):
        fields = {key: _value(value) for key, value in data.items()}
        timestamps = ["updatedAt"]
        if create_timestamp:
            timestamps.append("createdAt")
        write = {
            "update": {"name": f"{DATABASE}/documents/users/{UID}", "fields": fields},
            "updateTransforms": [
                {"fieldPath": key, "setToServerValue": "REQUEST_TIME"}
                for key in timestamps
            ],
        }
        if merge:
            write["updateMask"] = {"fieldPaths": list(data) + list(delete_fields)}
        return requests.post(
            f"{self.base}/v1/{DATABASE}/documents:commit",
            headers={"Authorization": "Bearer " + ("owner" if admin else _token(uid))},
            json={"writes": [write]},
            timeout=10,
        )

    def assertAllowed(self, response):
        self.assertEqual(response.status_code, 200, response.text)

    def assertDenied(self, response):
        self.assertEqual(response.status_code, 403, response.text)
        self.assertEqual(response.json()["error"]["status"], "PERMISSION_DENIED")

    def test_new_account_can_create_incomplete_profile(self):
        self.assertAllowed(self.write({
            "email": EMAIL,
            "profileCompleted": False,
            "preferences": _preferences(),
        }))

    def test_bootstrapped_admin_can_complete_profile_without_changing_role(self):
        # set_admin.py creates only role and updatedAt before the first login.
        self.assertAllowed(self.write({"role": "admin"}, admin=True, create_timestamp=False))
        self.assertAllowed(self.write(_profile(), merge=True))
        response = requests.get(
            f"{self.base}/v1/{DATABASE}/documents/users/{UID}",
            headers={"Authorization": "Bearer " + _token()},
            timeout=10,
        )
        self.assertAllowed(response)
        self.assertEqual(response.json()["fields"]["role"], {"stringValue": "admin"})
        self.assertEqual(response.json()["fields"]["profileCompleted"], {"booleanValue": True})

    def test_older_profile_can_enable_and_disable_translation_labels(self):
        profile = _profile()
        del profile["preferences"]["showTranslationLabels"]
        self.assertAllowed(self.write(profile))
        for enabled in (True, False):
            with self.subTest(enabled=enabled):
                profile["preferences"]["showTranslationLabels"] = enabled
                self.assertAllowed(self.write(profile, merge=True, create_timestamp=False))

    def test_legacy_preferences_remain_accepted(self):
        profile = _profile()
        for key in ("showTranslationLabels", "topicLanguage", "bibleLanguage", "bibleVersion"):
            del profile["preferences"][key]
        self.assertAllowed(self.write(profile))

    def test_invalid_translation_label_values_are_rejected(self):
        for value in ("true", 1, None, {}):
            with self.subTest(value=value):
                profile = _profile()
                profile["preferences"]["showTranslationLabels"] = value
                self.assertDenied(self.write(profile))

    def test_unknown_preference_is_rejected(self):
        profile = _profile()
        profile["preferences"]["unexpectedSetting"] = True
        self.assertDenied(self.write(profile))

    def test_other_user_cannot_save_profile(self):
        self.assertDenied(self.write(_profile(), uid="another-user"))

    def test_user_cannot_add_authorization_fields(self):
        for key, value in {"role": "admin", "roles": "admin", "admin": True, "isAdmin": True}.items():
            with self.subTest(field=key):
                profile = _profile()
                profile[key] = value
                self.assertDenied(self.write(profile))
        self.assertAllowed(self.write(_profile()))
        self.assertDenied(self.write({"role": "admin"}, merge=True, create_timestamp=False))

    def test_profile_save_cannot_change_or_remove_admin_role(self):
        profile = _profile()
        profile["role"] = "admin"
        self.assertAllowed(self.write(profile, admin=True))
        changed = copy.deepcopy(profile)
        changed["role"] = "reader"
        self.assertDenied(self.write(changed, merge=True, create_timestamp=False))
        self.assertDenied(self.write(
            _profile(), merge=True, create_timestamp=False, delete_fields=("role",)
        ))
