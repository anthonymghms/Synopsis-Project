# Harmony, Miracles, and Parables

The existing application now reads three independent topic datasets through Flask. Harmony remains the default, with its existing storage and URLs. Miracles and Parables use the same table, reference parser, reading pages, previews, Gospel filters, sorting, column visibility, and export facilities.

All three tables now show a separate **#** column. To add or update a language without replacing canonical data, use the universal **Add / update table language** workflow documented in [TABLE_LANGUAGES.md](TABLE_LANGUAGES.md). It supports table-specific languages independently of the selected Bible language/version and preserves other translations.

## Verified Storage sources

Inspected read-only on 15 November 2026 using the configured backend Firebase Admin connection to `synopsis-224b0.firebasestorage.app`. No live validation/import/publication endpoint was called and no Firebase data was written during development.

Both files are **UTF-8 without a BOM, tab-delimited**, despite their `.csv` extensions. The new parser detects tabs or commas from the header and uses CSV quoting rules. A comma inside a quoted comma-delimited reference remains inside that cell; commas in the actual tab-delimited sources also remain inside their cells.

| Property | Miracles.csv | Parables.csv |
| --- | --- | --- |
| Exact headers | `#`, `Miracles`, `المعجزات`, `Matthew`, `Mark`, `Luke`, `John` | `#`, `Subject`, `الموضوع`, `Type`, `Matthew`, `Mark`, `Luke`, `John` |
| Data rows | 41 | 62 |
| IDs | `#`, consecutive 1–41 | `#`, consecutive 1–62 |
| Default ordering | Physical source row order; no explicit order column | Physical source row order; no explicit order column |
| Subject languages | English and Arabic | English and Arabic |
| Type | No Type column | `Parable`: 39; `Figure of Speech`: 23 |
| Missing classifications | All 41, because Type is absent | None |
| Logical references under the established parser | 87 | 111 |
| Duplicate IDs / missing IDs / missing subject names | None | None |
| Malformed references under the established parser | None | None |
| Rows without any Gospel reference | None | None |
| Empty Gospel cells: Matthew / Mark / Luke / John | 16 / 16 / 16 / 30 | 22 / 46 / 20 / 52 |
| Storage generation | `1758218909509438` | `1758218909421672` |
| SHA-256 | `1255cd5c44e39310f21082fa193ae460410d7c8f09812b59df50b74e939929e6` | `e479990dbac17b7e38cf20fa6aafa71474abe965b0f4b42e4644ff18a7fe7632` |

Empty Gospel cells mean an item has no supplied reference in that Gospel. Validation checks syntax and the existing parser's passage semantics; it does not make editorial claims about the accuracy of a source's chosen verses.

**Parables already contains Type and needs no updated CSV for grouping.** Miracles works immediately in ordinary table mode. To group/filter Miracles by Type, an administrator must supply classifications in an updated file. No classifications were inferred from subject names.

The existing live Harmony metadata was also read: 291 canonical items, with separate 291-item English and Arabic localizations. Its active paths were not modified.

## Storage and compatibility

- Logical item identity is `(datasetId, itemId)`; supported dataset IDs are `harmony`, `miracles`, and `parables`.
- Existing Harmony collections (`harmony`, `harmony_revisions`, `harmony_localizations`, and legacy compatibility paths) are unchanged. The Harmony-master Admin workflow remains separate.
- New active pointers live at `datasets/miracles` and `datasets/parables`.
- Each publication attempt writes an immutable `dataset_revisions/{datasetId}--{uuid}` revision. Canonical references, source number/order, and Type IDs live under `topics/{itemId}`. Names live separately under `localizations/{language}/topics/{itemId}` within the same revision.
- Metadata records languages, Type IDs/display labels/order/counts, source encoding/headers/checksum/generation, and revision information. Import history uses the existing `admin_imports` collection.
- Types use stable IDs derived from their explicit source label, or a supplied `TypeId`. Optional `TypeArabic` / `النوع`, `TypeOrder`, and `SourceOrder` headers are supported. Unknown Type values are preserved. Supply an explicit stable `TypeId` if a later edit changes a Type's source label while retaining its identity.
- Missing names fall back only to an available name for the **same dataset item**, preferring English; missing names are reported in validation. Known English Type labels have bundled Arabic display translations; other labels fall back to their imported label/ID.
- Missing Type rows remain available under Unclassified when other populated Types exist. A dataset with no populated Types has no empty Type column; it explains that Type controls require imported values.
- No references are copied or inferred from Harmony by item number or translated subject name.

New public endpoints are `GET /datasets/{dataset}/topics` and `GET /datasets/{dataset}/localizations/{language}?revision={revision}`. They use the existing server-verified reader authorization. Legacy `/topics` and individual topic endpoints accept `dataset`; omission continues to mean Harmony. Bible storage and Bible endpoints are unchanged.

Browser URLs carry dataset, view mode, selected Type IDs, Gospel filters, sorting, visible columns, and independent table/Bible language/version context. Dataset canonical snapshots are loaded once per cache lifetime; localization cache keys include dataset/revision/language. Filtering and grouping run locally. Successful Admin publication invalidates the existing catalog cache, including the affected dataset; a page refresh also loads a new snapshot. No Storage CSV is fetched by reader visits or hover events.

## Admin import steps

1. Deploy the updated Flask backend and Flutter frontend together, then sign in with an existing server-authorized administrator account.
2. Open **Admin Portal → Import Miracles / Parables** (also available in the Topics section).
3. Choose **Miracles** or **Parables**. This is distinct from importing a Harmony master.
4. Choose **Existing Firebase Storage file** and select the matching `Miracles.csv` / `Parables.csv`. The backend reads the existing file directly. Alternatively choose **Upload CSV** and use the existing file picker for a corrected source.
5. Select **Validate and preview**. Review the target, filename, encoding, header mapping, source checksum, item/reference counts, languages, Type counts/missing classifications, localized sample names/references, warnings/errors, and create-versus-replace status.
6. If replacing an existing dataset, acknowledge replacement. Select **Publish dataset**, then explicitly confirm in the publication dialog.
7. Wait for verified completion. The new active revision becomes available to the table selector; repeat the workflow for the other dataset.

Validation only stages the uploaded source/import record; it never changes the active pointer. Publication verifies the previewed Storage generation and SHA-256, reparses through the same parser, writes the new revision, checks the source again, then transactionally activates the pointer. A changed source or changed active revision requires revalidation. Failures leave the previous active revision usable. Identical-file publication is idempotent, and concurrent attempts cannot rewrite an active revision. Old revisions are retained; no automatic live cleanup is performed.

Every administrative endpoint verifies administrator authorization on the server. Storage selection is restricted to the exact two allowed root filenames in the configured bucket. Upload staging is restricted to the corresponding import prefix. No arbitrary URL download or client-side Admin credentials are introduced.

## Configuration and deployment

No credential, Firestore security-rule, Bible-storage, or composite-index changes are required. Reuse the existing authorized backend connection (`FIREBASE_STORAGE_BUCKET`, `FIREBASE_SERVICE_ACCOUNT` or Application Default Credentials). The deployed backend identity needs its existing Storage read/write and Firestore administrative access for the new revision/import paths. Credentials remain backend-only and ignored by Git.

Dataset sources are limited to 16 MiB. The existing Flask 32 MiB upload limit and Nginx 34 MiB request limit already accommodate them; no limit increase is needed.

Firestore is schemaless: the new collections are created by an **explicit administrator publication**, not by deployment or reader access. Deploy using the existing instructions in `deploy/README.md` and the existing frontend `API_BASE_URL` setting. Then manually publish each dataset using the steps above. No migration or replacement of Harmony is necessary.

## Implementation files

- Deployment manifest: `deploy/install-backend.sh` now includes `dataset_api.py` in its explicit release archive. The existing `services` directory entry includes both new dataset services.
- Backend: `dataset_api.py`, `services/dataset_import_service.py`, `services/dataset_repository.py`; minimal registration and dataset routing in `app.py`.
- Reader: `gospel_frontend/lib/main.dart`, `dataset_reader.dart`, `topic_dataset.dart`, `topics_table_document.dart`.
- Administration: `gospel_frontend/lib/admin_portal.dart`, `dataset_import_wizard.dart`, `admin_import_details.dart`.
- Tests: `tests/test_dataset_imports.py`; Flutter `topic_dataset_test.dart`, `dataset_reader_test.dart`, `dataset_navigation_test.dart`, `dataset_import_wizard_test.dart`, `topics_table_document_test.dart`, `admin_import_details_test.dart`, and browser `dataset_history_browser.dart`.

Existing uncommitted performance changes and their tests were preserved. Synthetic fixtures in the new tests are explicitly identified; they are not fabricated copies of the live datasets.

## Verification

The backend suite ran 211 tests: **193 passed, 18 Firestore-emulator-dependent tests skipped**. Dataset-specific tests cover header mapping/quoting, bilingual names, Types, malformed references, authorized Storage/upload imports, duplicate IDs, failed/repeated/concurrent publication, source changes, and coherent immutable revision reads.

The final full Flutter suite passed **288 tests**, including mobile layout, independent table/Bible languages, returning from a reader, grouping, exports, and Admin imports. Three Chrome browser tests passed for real Back/Forward history, refreshable dataset URL state, existing link behavior, and full-table printing. Static analysis and the production JavaScript web build passed. Flutter's optional Wasm compatibility check reports the existing `desktop_drop` dependency's use of `dart:html`; the normal release build succeeds.

Verification commands (Flutter commands run from `gospel_frontend`):

```sh
python3 -m unittest discover -s tests
flutter test --no-pub --reporter expanded
flutter test --no-pub --platform chrome --reporter expanded test/browser/dataset_history_browser.dart test/browser/topics_table_browser.dart
flutter analyze --no-pub
flutter build web --release --no-pub
bash -n deploy/install-backend.sh
git diff --check
```

No live import, publication, deployment, or Harmony overwrite was executed. Firestore-emulator checks and a deployed end-to-end administrator publication remain deployment verification steps.
