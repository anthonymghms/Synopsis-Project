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
services/reference_parser.py
services/localization_import_service.py
```

The CLI and web endpoints therefore use the same parser implementation.
`csv_parser.py` now activates a canonical Harmony revision plus the base topic
localization; it no longer creates a duplicated reference dataset for each
topic language.

### Harmony reference grammar

`services/reference_parser.py` is the canonical CSV/import parser. Flutter
consumes its structured `referenceCells` projection from `/topics`; it does not
reinterpret the original CSV independently. Each separator is an ordered edge
between physical segments:

```text
+  continuous: consecutive chapter boundary, one logical selection
;  non-continuous: separate logical selection in the same Gospel cell
,  same chapter: another verse/range inheriting the preceding chapter
```

For example, `Luke 1:78-80 + 2:1-7` has two physical segments and one logical
selection; `John 8:1,34` and `Matthew 5:31-32;19:9` each have two physical
segments and two logical selections. The toolbar's **references** count uses
logical selections. This keeps a continuous `+` reading at one while counting
comma and semicolon selections separately.

The parser accepts optional Gospel-name prefixes, Arabic/Persian digits,
en/em dashes, and whitespace around separators. Comma must remain in the same
chapter. Semicolon retains legacy chapter inheritance for values such as
`6:25-34;19-21`. Plus must move to the immediately following chapter at verse
1; Admin validation also checks that the previous segment reaches the actual
last verse using Bible metadata. When chapter metadata is unavailable the
structure is preserved with a warning, not silently changed.

For compatibility with the established Arabic master file, legacy direct
cross-chapter ranges such as `10:40-11:1` are expanded to `10:40-42 + 11:1`
using verified chapter metadata. Spreadsheet midnight suffixes such as
`26:30:00` are normalized to `26:30`. Both transformations produce visible
Admin warnings; new edits should use the explicit `+` grammar and ordinary
`chapter:verse` notation.

The table renders the stored grammar in compact synopsis notation: a continuous
`10:40-42 + 11:1-10` passage appears as `10:40 11:10`, same-chapter selections
appear as `7:13–14, 21–23`, and non-contiguous passages use a semicolon.

Because the file itself is comma-delimited, a Gospel cell containing the comma
operator must use normal CSV quoting, for example `"8:1-12,20-25"`. Validation
rejects non-empty overflow columns so an unquoted comma cannot be truncated or
shifted silently.

Canonical topic documents contain both representations during the
compatibility period:

```text
entries[]          flat physical segments for legacy readers
referenceCells[]   lossless cells, segments, separators, and relation metadata
referenceGrammarVersion: 2
```

Legacy documents containing only `entries` remain readable.

### Safe activation and Firebase schema

Validated source files are retained under unique, server-generated Storage
paths:

```text
imports/topics/{language}/{timestamp}-{importId}/{filename}
imports/harmony/canonical/{timestamp}-{importId}/{filename}
imports/localizations/{language}/{timestamp}-{importId}/{filename}
imports/bibles/{language}/{version}/{timestamp}-{importId}/{filename}
```

New parsed data is written to an immutable revision first:

```text
reference_revisions/{importId}/topics/{topicId}
harmony_revisions/{importId}/topics/{topicId}
harmony_localization_revisions/{importId}/topics/{topicId}
bible_revisions/{importId}/books/{book}/chapters/{chapter}/verses/{verse}
```

Only after every batch succeeds is an active pointer switched atomically:

```text
references/{datasetId}.activeTopicsPath
harmony/canonical.activeTopicsPath
harmony_localizations/{language}.activeTopicsPath
bibles/{language}/versions/{version}.activeBooksPath
```

The Flask read APIs follow these pointers and fall back to the legacy paths, so
existing datasets continue to work. Failed revisions are never activated and
the former production dataset remains unchanged. Replacement never silently
deletes the previous revision.

The storage model keeps three independently deployable datasets:

```text
harmony/canonical                         one Gospel-reference mapping
harmony_localizations/{topicLanguage}    topic names, direction, Gospel labels
bibles/{bibleLanguage}/versions/{version} Bible text and translation metadata
```

`/harmony/topics` returns canonical coordinates only, while
`/topic-localizations/{language}` returns table names and metadata. Flutter
caches and composes those responses. In the reader-facing client, one primary
language now controls the entire experience: application menus, topic names,
Gospel headers, layout direction, reference links, and the main Bible text.
Changing Language is an atomic operation and then prompts for a compatible
translation when necessary. A different language is allowed only through the
explicit Add translation/interlinear comparison flow.

For deployed-client compatibility, the primary language is still serialized
to `menuLanguage`, `topicLanguage`, and `bibleLanguage`; those keys are mirrors,
not independent preferences. The matching translation remains in
`bibleVersion`. Older mixed profiles and URLs are normalized with the Bible
content language taking precedence.

During migration, `/topics` and the historic topic route compose the same data
server-side and retain legacy `language` query handling. Missing canonical or
localization pointers can still fall back to the old `references/*` paths. No
import deletes those paths or immutable revisions.

Bible language metadata remains under `bibles/{language}` and version metadata
under `bibles/{language}/versions/{version}`. Topic localization activation
never writes into the Bible catalog. Newly imported Bible languages can appear
as comparison translations without a Dart source change. Promoting a language
to the primary selector additionally requires shipped UI strings, a complete
topic localization, and at least one compatible Bible version, preventing a
partially translated interface.

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
GET  /admin/localizations/template
GET  /admin/harmony/migration-report
GET  /harmony/topics
GET  /topic-languages
GET  /topic-localizations/{language}
POST /admin/topics/validate
POST /admin/topics/import
POST /admin/localizations/validate
POST /admin/localizations/import
POST /admin/harmony/validate
POST /admin/harmony/import
POST /admin/bibles/validate
POST /admin/bibles/import
```

Validation endpoints accept multipart uploads and never write parsed data to an
active collection. Import endpoints require both `confirm: true` and
`replace: true` when validation detected a collision. Import work runs outside
the request and the Flutter portal polls the import record for real stage-based
progress.

`/admin/topics/*` is retained for old clients, but it is not the normal
workflow. The portal separates **Master Harmony** from **Topic Languages**.
The master flow uses `/admin/harmony/*`; adding or updating a table language
uses `/admin/localizations/*` and accepts these formats:

```text
First/base language: Topic, Matthew, Mark, Luke, John
Additional language: one ordered topic-name column, for example Subjects
```

On the master upload, canonical references and the selected base language's
topic/Gospel labels are written to separate immutable revisions and activated
together in one batch. A later one-column upload must contain exactly one name
for every canonical topic, in the same row order, and changes only localized
names and Gospel labels. The safer `TopicNumber,TopicName` format is preferred.
Once canonical references exist, a five-column Topic Language upload must match
them exactly; intentional reference changes use **Update Master**.

### Canonical migration policy

No existing `references/*` collection is deleted or overwritten by these
workflows. Before activating a trusted canonical source, an administrator can
run:

```text
GET /admin/harmony/migration-report?trustedDataset=canonical
```

The report compares topic IDs, counts, physical reference ranges, and separator
metadata across every legacy dataset. During the 2026-09-01 read-only
inspection, the active canonical dataset and the supplied 289-row Arabic
master matched after the five reported legacy cross-chapter normalizations.
The old `english_kjv` dataset contained only 288 topics and diverged after its
missing row, so it is not a safe authority for English alignment.
`safeToAutoMigrate` therefore remains false until the supplied English names
are validated against the canonical IDs/order and reviewed in full. Old
collections and immutable revisions should remain available through the
verification period; their later removal is a separate, deliberate operation.

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

### Import or replace Master Harmony

1. Sign in with the bootstrapped administrator and open **Account → Admin**.
2. Open **Harmony Topics → Master Harmony → Update Master**.
3. Enter Arabic language metadata, RTL direction, and the four Arabic Gospel
   display names.
4. Select the UTF-8 five-column Arabic main table. Its positional columns are
   topic name, Matthew, Mark, Luke, and John; localized header text is accepted.
5. Validate and review the **Main Harmony table detected** notice, topic count,
   logical/physical reference counts, normalization warnings, and preview.
6. Select **Import Master Harmony & Language**. Canonical references and Arabic
   localization become active atomically; legacy datasets are not deleted.

### Add another topic language

1. Open **Harmony Topics → Topic Languages → Add Topic Language** and enter the new language metadata,
   direction, and four Gospel display names.
2. Upload a UTF-8 CSV containing one ordered topic-name column such as
   `Subjects`. Row 2 translates canonical topic 1, row 3 translates topic 2,
   and so on.
3. The file must have exactly one non-empty name for every canonical topic.
   Quote a topic name if it contains a comma.
4. Validate the canonical-to-localized preview, import, then confirm language
   switching, Gospel labels, topic names, RTL/LTR, filters, and routes.

### Update canonical Harmony references

1. Review `/admin/harmony/migration-report` and choose the intended trusted
   source; do not infer equivalence from language names.
2. Choose **Master Harmony → Update Master**.
3. Select a five-column CSV whose positional columns are Topic, Matthew, Mark,
   Luke, and John.
4. Exercise at least these reference cases in validation/preview:

   ```text
   John 8:1
   John 8:1,34
   John 8:1-12,20-25
   Matthew 5:31-32;19:9
   Luke 1:78-80+2:1-7
   ```

5. Select **Validate upload**. Inspect every row/field error, structural warning,
   logical/physical count, and the first 20 preview rows. An invalid plus such
   as `Luke 1:78-79+2:2-7` must fail and recommend semicolon.
6. If replacing an existing dataset, select the explicit replacement checkbox.
7. Select **Import Canonical References**, confirm, and wait for **Completed**.
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
- Several historical CSV cells contain spreadsheet-coerced times or ambiguous
  direct cross-chapter strings. Use the explicit `+` grammar for a verified
  continuous boundary. The portal reports other ambiguous values with
  row/topic/field context instead of silently importing broken references.
