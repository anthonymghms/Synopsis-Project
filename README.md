# Synopsis-Project
This repository contains the work for our Synopsis Project.

## Running locally

The Flutter web app reads Gospel topics and Bible text from the Flask backend.
The backend URL is selected at Flutter build/run time with `API_BASE_URL`, so
`gospel_frontend/lib/main.dart` does not need to be edited when switching
between local development and VPS deployment.

### Start Flask locally

From the repository root:

```sh
python3 app.py
```

The local backend listens on:

```text
http://127.0.0.1:8010
```

`serviceAccountKey.json` must exist locally for Firebase Admin SDK access. It is
ignored by git and should not be committed.

### Run Flutter locally

From the Flutter project directory:

```sh
cd gospel_frontend
flutter run -d chrome --web-port 8760 --dart-define=API_BASE_URL=http://127.0.0.1:8010
```

If `API_BASE_URL` is omitted, the app defaults to `http://127.0.0.1:8010`.

## Building for VPS

From the Flutter project directory:

```sh
cd gospel_frontend
flutter build web --release --dart-define=API_BASE_URL=http://164.68.108.181:8010
```

Deploy the generated `gospel_frontend/build/web` files to the VPS frontend host.
The Flask backend should keep serving the existing API routes:

```text
/topics
/get_verse
/get_chapter
```

Serve the Flutter build with Nginx or another static server rather than
`flutter run`. Enable compression and long-lived caching for hashed Flutter
assets:

```nginx
gzip on;
gzip_types text/css application/javascript application/json application/wasm;

location / {
  try_files $uri $uri/ /index.html;
}

location ~* \.(?:js|css|wasm|png|jpg|jpeg|gif|svg|ico)$ {
  expires 30d;
  add_header Cache-Control "public, immutable";
}

location = /index.html {
  add_header Cache-Control "no-cache";
}
```

Run Flask behind a production WSGI server such as gunicorn, and keep debug mode
off unless explicitly testing:

```sh
gunicorn -w 2 -b 0.0.0.0:8010 app:app
```

For local Flask debugging, opt in with:

```sh
FLASK_DEBUG=1 python3 app.py
```

## Backend CORS

`app.py` allows the local Flutter web dev origin and the current VPS frontend
origin by default. If the frontend moves to another host, set a comma-separated
`CORS_ORIGINS` environment variable before starting Flask, for example:

```sh
CORS_ORIGINS=http://localhost:8760,http://164.68.108.181 python3 app.py
```

## Import architecture

### Legacy parser behavior

`csv_parser.py` historically downloaded one CSV object from Firebase Storage.
It ignored header text and treated columns A-E as topic, Matthew, Mark, Luke,
and John. It decoded using UTF-8 with BOM, UTF-8, CP-1252, then Latin-1;
split references on commas or semicolons; normalized en/em dashes; and accepted
numeric `chapter:verses` values. Topic IDs were regenerated as `1..N` after
skipped rows. The script wrote individual documents to
`references/{language}/topics/{id}`. It did not clear stale documents, compare
languages, validate verse syntax, prevent replacement, or roll back partial
writes. Storage was only the source of the CSV.

`usfm_parser.py` historically executed during module import. It downloaded one
hardcoded UTF-8 USFM object, hardcoded Arabic and the translation name, and
recognized only `MAT`, `MRK`, `LUK`, and `JHN`. It handled `\\id`, `\\c`,
`\\v`, `\\s`, `\\p`, and `\\q`, then wrote verses below
`bibles/{language}/{version}/{book}/chapters/{chapter}/verses/{verse}`.
It could not import multiple files in one operation and had no validation,
duplicate protection, progress API, or rollback.

Both files are now safe CLI wrappers. Parsing and validation live in:

```text
services/import_validation.py
services/topic_import_service.py
services/bible_import_service.py
services/firebase_service.py
services/admin_auth.py
```

The CLI and web endpoints therefore use the same parser implementation.

### Safe activation and Firebase schema

Validated source files are retained under unique, server-generated Storage
paths:

```text
imports/topics/{language}/{timestamp}-{importId}/{filename}
imports/bibles/{language}/{version}/{timestamp}-{importId}/{filename}
```

New parsed data is written to an immutable revision first:

```text
reference_revisions/{importId}/topics/{topicId}
bible_revisions/{importId}/books/{book}/chapters/{chapter}/verses/{verse}
```

Only after every batch succeeds is an active pointer switched atomically:

```text
references/{datasetId}.activeTopicsPath
bibles/{language}/versions/{version}.activeBooksPath
```

The Flask read APIs follow these pointers and fall back to the legacy paths, so
existing datasets continue to work. Failed revisions are never activated and
the former production dataset remains unchanged. Replacement never silently
deletes the previous revision.

Language metadata is stored on `bibles/{language}` and version metadata on
`bibles/{language}/versions/{version}`. Flutter merges this catalog with the two
bundled legacy fallbacks, so a successful Bible import is discoverable without
editing a Dart language constant. A topic-only language can display its Harmony
table; Bible previews become available after a translation for that language is
also imported.

Every validation/import attempt has an `admin_imports/{importId}` audit record
with the type, destination, filenames, uploader UID, timestamps, stage, status,
counts, warnings, and safe error details. Credentials and tokens are never
stored there.

## Admin API

All endpoints below require `Authorization: Bearer <Firebase ID token>` and a
server-verified custom claim or `users/{uid}.role == "admin"`:

```text
GET  /admin/overview
GET  /admin/languages
GET  /admin/imports
GET  /admin/imports/{importId}
GET  /admin/topics/template
POST /admin/topics/validate
POST /admin/topics/import
POST /admin/bibles/validate
POST /admin/bibles/import
```

Validation endpoints accept multipart uploads and never write parsed data to an
active collection. Import endpoints require both `confirm: true` and
`replace: true` when validation detected a collision. Import work runs outside
the request and the Flutter portal polls the import record for real stage-based
progress.

The default upload limit is 32 MB. Override it with
`MAX_ADMIN_UPLOAD_BYTES`. Set `FIREBASE_SERVICE_ACCOUNT` to a backend-only key
path when local development needs an explicit key, and set
`FIREBASE_STORAGE_BUCKET` when using a different bucket. Production should use
Application Default Credentials or a managed secret rather than placing a JSON
key beside the application.

## One-time administrator bootstrap

No account in the inspected Firebase project currently has an admin role or
custom claim. From a trusted backend machine, grant the first administrator:

```sh
./venv/bin/python scripts/set_admin.py --email admin@example.com
```

The user must sign out and sign back in afterward. Remove access with:

```sh
./venv/bin/python scripts/set_admin.py --email admin@example.com --remove
```

Do not expose this script or the service account on a public host. Deploy the
tightened client rules before relying on a `users/{uid}.role` fallback:

```sh
cd gospel_frontend
firebase deploy --only firestore:rules,storage
```

The new rules prevent users from creating or modifying their own authorization
fields, keep all data writes behind the Admin SDK, limit import-history reads to
admins, and make staged source uploads backend-only.

## Testing an Admin Portal import

### Topic CSV

1. Sign in with the bootstrapped administrator and open **Account → Admin**.
2. Choose **Add Topic Dataset**.
3. Enter the language code/display name and direction.
4. Select a comma-delimited CSV whose five positional columns are Topic,
   Matthew, Mark, Luke, and John. Save Arabic as UTF-8. Multiple same-chapter
   references may use `1:6-8;15-28` or `1:6-8,15-28`.
5. Select **Validate upload**. Inspect every row/field error, structural warning,
   count, and the first 20 preview rows.
6. If replacing an existing dataset, select the explicit replacement checkbox.
7. Select **Import Topic Dataset**, confirm, and wait for **Completed**.
8. Return to the Harmony table and select the language. Confirm topic order,
   all four Gospel columns, filtering/sorting, hover previews, and topic routes.

### Bible USFM

1. Open **Admin → Add Bible Translation**.
2. Enter language metadata, translation name, safe identifier, display name,
   optional description/relationship, direction, and diacritics choice.
3. Select one or more UTF-8 `.usfm` files. The current application/parser
   contract supports `MAT`, `MRK`, `LUK`, and `JHN`; upload each book only once.
4. Select **Validate upload**. Inspect detected books, chapters, verses,
   diacritics, warnings/errors, and sample verses.
5. Confirm replacement only when intentionally replacing the exact identifier.
6. Select **Import Bible Translation**, confirm, and follow book-by-book stages.
7. Return to the application, select the new language/version, and verify verse
   hover, chapter/reference pages, interlinear view, and Arabic diacritics.

## Automated checks

```sh
./venv/bin/python -m unittest discover -s tests -v
cd gospel_frontend
flutter analyze
flutter test
flutter build web --release --dart-define=API_BASE_URL=http://127.0.0.1:8010
```

## Security findings

- `serviceAccountKey.json` exists locally with restrictive permissions, is
  ignored by `.gitignore`, and has no tracked history in this repository. Keep
  it backend-only and migrate production to a managed secret/ADC.
- The former Firestore rules allowed a malicious client to add an authorization
  field while creating its own profile. The updated rules close this privilege
  escalation path; they must be deployed.
- The existing Storage source files include working USFM/CSV inputs. New source
  paths are never derived from untrusted directory components and uploads are
  parsed strictly as data.
- Several historical CSV cells contain spreadsheet-coerced times or
  cross-chapter ranges that the current application data shape cannot safely
  resolve. The portal reports these with row/topic/field context instead of
  silently importing broken references.
