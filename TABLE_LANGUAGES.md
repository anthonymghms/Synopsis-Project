# Add or update a table language

The **Add / update table language** workflow translates one table at a time: **Harmony / All Topics**, **Miracles**, or **Parables**. It updates subject names, optional Type display labels, and the selected language's column headings. It preserves canonical references, item IDs, source order, Type classifications, and every other language.

All three reader tables display a separate **#** column followed by **Subject**, optional **Type**, and the visible Gospel columns. The number identifies the original item; translating a subject does not create a new item.

## Table language and Bible language

**Table language** controls subject names, Gospel headers, Type labels, table direction, and displayed reference/number notation. **Bible language** and its version control the verse text in previews and reading pages. For example, a Miracles table can display French subjects and Gospel headings while previews use English KJV. Changing one selection does not replace the other.

A language can be available for just one table. Publishing French for Miracles does not require a French Harmony translation or a French Bible, and does not add French names to either other table. Imported dataset language metadata is resolved independently of Harmony's language catalog. Links retain the originating dataset and both language choices.

When switching to a table without the selected language, the reader uses English if available, otherwise that table's first available language. It remembers the previous table's language for switching back and preserves the Bible language/version throughout.

## Administrative steps

1. Deploy the updated backend and frontend together and sign in as an authorized administrator. The selected table must already have published canonical items.
2. Open **Admin Portal → Add / update table language**.
3. In **Table and language**, choose the table, then English, العربية, Français, or **Other language**. Review **Language code**, **Native language name**, and **Text direction**. Use the existing language code when updating a language; for French use `french`.
4. Review **Translated column headings**: the subject heading plus Matthew, Mark, Luke, and John. Enter the labels in the target language. For an existing translation, downloading its template restores the currently published metadata so that these labels can be retained or edited deliberately.
5. In **Download and translate**, select **Download CSV template**. The template comes from the selected table's current published items. Keep the item IDs intact and fill every subject translation.
6. In **Upload and validate**, select the completed CSV with **Select CSV file**, then choose **Validate and preview**.
7. In **Preview and publish**, check the table, language, item/Type counts, source revision, checksum, samples, warnings, and blocking errors. If updating a language, select **Replace only this table's … translations** after checking the destination.
8. Choose **Publish table language** and confirm **Publish**. Wait for successful completion before treating the language as available. The reader's Table language selector then includes the new language; other sessions can refresh to load it.

To edit the downloaded template in Excel, open the CSV and preserve `ItemId` and `TypeId` as **Text** so Excel does not change identifiers or remove leading zeros. Keep the first row as the original column headers; do not insert a title row. After entering the translations, use **Save As → CSV UTF-8 (.csv)**, then upload that CSV. Excel workbooks (`.xlsx`) are not accepted.

Changing the chosen table, language, metadata, or upload invalidates the preview. If the underlying table changes after validation, download a current template and validate again before publishing.

## Template columns

| Column | What to do |
| --- | --- |
| `ItemId` | Keep the supplied identifier exactly. IDs belong to the chosen table; do not replace them with Harmony IDs, translated names, or new row numbers. |
| `SourceName` | Prefilled source-language guidance for identifying the item. It does not determine identity and is not imported as the translation. |
| `Translation` | Supply the target-language subject name for every item. Existing target names are prefilled when updating a language. |
| `TypeId` | Present only when the table has classifications. Keep each supplied Type ID unchanged; it is checked against that item's existing classification. |
| `TypeTranslation` | Optional localized display label for the existing Type. Use the same translation everywhere that Type ID appears. Leaving it blank preserves the existing target label, or uses the established source-label fallback. |

The Type columns are omitted when the table has no populated classifications. This language workflow cannot assign new classifications. Use the separate canonical dataset workflow if the actual references or classifications need an editorial change.

The validator requires an explicit, unique existing item ID for every published item and a populated `Translation`. Unknown/duplicate IDs, incomplete item coverage, conflicting Type translations, mismatched Type IDs, and reference columns block publication. CSV quoting is preserved, including commas and quotation marks within names. Do not append Bible verses or Gospel reference columns to this template.

## Using the supplied `Miracles FRENCH.csv`

The supplied local file was inspected read-only on **18 November 2026**. It is UTF-8 without a BOM and contains **40 nonblank rows** with two headers: `Categorie` and `Miracles`. It has no item IDs or Gospel-reference columns. The previously inspected canonical `Miracles.csv` had 41 items; the freshly downloaded template is authoritative for the currently published table.

Use this file as translation source material, not as a directly publishable table-language template:

1. Download the **Miracles → French** template.
2. Compare each French subject with the template's source guidance and the actual published item/reference context. Establish the correct item identity explicitly before copying its French text into `Translation`.
3. Keep every `ItemId` and, where present, `TypeId` supplied by the template. A matching row position or similar translated name is not proof of identity.
4. Resolve omitted, extra, or ambiguous subjects before validation. Supply a reviewed translation for every template item; do not invent a missing translation to make the row count match.
5. Treat `Categorie` as source material to review. Do not infer new classifications or overwrite existing Type IDs from it. A French category label can be used as `TypeTranslation` only after confirming that it translates the corresponding existing Type ID.

Renaming `Miracles` to `Translation` by itself is insufficient: the file still lacks verified item IDs and complete coverage of the published template. The full dataset importer is also the wrong workflow for adding a language because it replaces canonical dataset revisions instead of adding only French names.

## Publication and storage guarantees

Validation stages a source file and records a preview without changing active reader content. Publication rechecks the staged source generation/checksum and the table/language revisions, then activates an immutable translation revision transactionally. A failed or stale import leaves the previous published state usable. Repeating an identical overlay is a no-op rather than duplicating items.

For Miracles and Parables, the new dataset metadata snapshot reuses the existing canonical topics path and all other localization paths; only the selected language's names are written. For Harmony, the workflow uses the existing Harmony localization revision and pointer mechanism. Neither path changes Bible storage, canonical references, source order, item IDs, or Type identities.

The administrative API is:

- `GET /admin/table-languages/template?datasetId=miracles&language=french` — returns the CSV, filename, current revision, item/Type metadata, and existing language metadata.
- `POST /admin/table-languages/validate` — multipart upload with `datasetId`, `language`, `displayName`, `direction`, `subjectsLabel`, Gospel labels as JSON in `gospels`, and `file`.
- `POST /admin/table-languages/publish` — uses the validated `importId`, matching `datasetId` and `language`, explicit `confirm`, and `replace` when updating existing target translations.

Every endpoint verifies administrator authorization on the server. Staged uploads stay under `imports/table_languages/{dataset}/{language}/{importId}/`; credentials remain on the backend. No service account credentials need to be uploaded through chat or committed to Git.

This guide describes the implemented workflow. It does not claim that the supplied French file has been mapped, uploaded, or published. Deployment and an explicitly confirmed administrator publication are separate steps.
