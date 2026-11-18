"""Universal administrator language overlays for Harmony, Miracles and Parables."""
import json
import re

from flask import Blueprint, current_app, request

from dataset_api import _response, _error
from services.admin_auth import verify_admin_authorization
from services.dataset_repository import DatasetRevisionConflict, SourceChangedError
from services.firebase_service import ImportCollisionError, ImportRecordError, new_import_id, safe_filename
from services.table_language_import_service import table_id, language_id, language_metadata, parse_table_language_csv, table_language_template
from services.table_language_repository import TableLanguageRepository


table_language_api = Blueprint("table_language_api", __name__)


def _admin():
    return verify_admin_authorization(request.headers.get("Authorization"))


@table_language_api.get("/admin/table-languages/template")
def language_template():
    _admin()
    try:
        selected_dataset = table_id(request.args.get("datasetId"))
        language = language_id(request.args.get("language"))
        snapshot = TableLanguageRepository().snapshot(selected_dataset, language)
        return _response({"datasetId": selected_dataset, "language": language, "filename": f"{selected_dataset}_{language}_template.csv", "csv": table_language_template(snapshot["items"], snapshot["types"], language, snapshot["translations"]), "revision": snapshot["revision"], "currentRevision": snapshot["revision"], "itemCount": len(snapshot["items"]), "types": snapshot["types"], "replacesExisting": snapshot["replacesExisting"], "languageMetadata": snapshot["languageMetadata"] if snapshot["replacesExisting"] else {}})
    except ValueError as exc:
        return _error("invalid_request", str(exc))
    except ImportRecordError as exc:
        return _error("dataset_not_published", str(exc), 409)


@table_language_api.post("/admin/table-languages/validate")
def validate_table_language():
    admin = _admin()
    try:
        selected_dataset = table_id(request.form.get("datasetId"))
        language = language_id(request.form.get("language"))
        labels = json.loads(request.form.get("gospels") or "{}")
        metadata = language_metadata(dict(request.form), labels)
        upload = request.files.get("file")
        if upload is None:
            raise ValueError("Choose a translated CSV file based on the dataset template.")
        filename = safe_filename(upload.filename or "")
        if not filename.lower().endswith(".csv"):
            raise ValueError("Language files must have the .csv extension (comma or tab delimited).")
    except (ValueError, TypeError) as exc:
        return _error("invalid_language_upload", str(exc))
    repository = TableLanguageRepository()
    import_id = new_import_id()
    try:
        snapshot = repository.snapshot(selected_dataset, language)
        raw = upload.read()
        result = parse_table_language_csv(raw, snapshot["items"], snapshot["types"])
        metadata.update(topicCount=len(snapshot["items"]), canonicalTopicCount=len(snapshot["items"]), complete=result.report.valid)
        source = repository.stage_language_upload(selected_dataset, language, import_id, filename, raw)
        repository.create_import(import_id=import_id, import_type="table_language", language=language, uploaded_by=admin["uid"], filenames=[filename], metadata={"datasetId": selected_dataset, "languageMetadata": metadata})
        summary = result.summary()
        repository.update_import(import_id, datasetId=selected_dataset, language=language, source=source, sourceChecksum=source["checksum"], expectedBase=snapshot["base"], languageMetadata=metadata, status="validated" if result.report.valid else "validation_failed", stage="Ready to publish" if result.report.valid else "Validation failed", errors=summary["errors"], warnings=summary["warnings"], validation=summary["stats"], collision=snapshot["replacesExisting"], storagePaths=[source["path"]], destination=f"{selected_dataset}/languages/{language}")
        return _response({"importId": import_id, "datasetId": selected_dataset, "language": language, "filename": filename, "sourceChecksum": source["checksum"], "sourceGeneration": source["generation"], "replacesExisting": snapshot["replacesExisting"], "revision": snapshot["revision"], "currentRevision": snapshot["revision"], "languageMetadata": metadata, **summary})
    except ValueError as exc:
        return _error("invalid_language_upload", str(exc))
    except ImportRecordError as exc:
        return _error("dataset_not_published", str(exc), 409)
    except Exception:
        current_app.logger.exception("Table language validation failed")
        return _error("validation_failed", "The language upload could not be validated or staged. Active data was not changed.", 503)


@table_language_api.post("/admin/table-languages/publish")
def publish_table_language():
    admin = _admin()
    fields = request.get_json(silent=True)
    if not isinstance(fields, dict):
        return _error("invalid_request", "A JSON object is required.")
    try:
        selected_dataset = table_id(fields.get("datasetId"))
        language = language_id(fields.get("language"))
        import_id = str(fields.get("importId") or "")
        if not re.fullmatch(r"[a-f0-9]{32}", import_id):
            raise ValueError("The import identifier is invalid.")
        if fields.get("confirm") is not True:
            raise ValueError("Explicit publication confirmation is required.")
    except ValueError as exc:
        return _error("invalid_publication", str(exc))
    repository = TableLanguageRepository()
    try:
        record = repository.get_import(import_id)
        if record.get("type") != "table_language" or record.get("datasetId") != selected_dataset or record.get("language") != language:
            return _error("wrong_table_language", "This preview belongs to a different table or language.")
        if record.get("status") == "completed":
            return _response({"importId": import_id, "status": "completed", "datasetId": selected_dataset, "language": language, "revision": record.get("revision"), "revisionId": record.get("revision"), "unchanged": True})
        if record.get("status") not in {"validated", "failed"}:
            return _error("import_not_ready", "Validate a complete language overlay before publishing.", 409)
        if record.get("collision") and fields.get("replace") is not True:
            return _error("replacement_confirmation_required", "Confirm replacing this table's existing target language.", 409)
        raw = repository.checked_language_source(record)
        snapshot = repository.snapshot(selected_dataset, language)
        result = parse_table_language_csv(raw, snapshot["items"], snapshot["types"])
        if not result.report.valid:
            raise DatasetRevisionConflict("The uploaded translations no longer match the published table. Download its current template and revalidate.")
        outcome = repository.activate_language(import_id=import_id, selected_dataset=selected_dataset, language=language, result=result, metadata=record["languageMetadata"], expected_base=record["expectedBase"], source=record["source"], replace=fields.get("replace") is True, confirmed_by=admin["uid"], source_validator=lambda: repository.checked_language_source(record))
        return _response({"status": "completed", "importId": import_id, **outcome})
    except (SourceChangedError, DatasetRevisionConflict) as exc:
        repository.record_failed_attempt(import_id, status="validation_failed", stage="Revalidation required", errors=[{"severity": "error", "code": "source_changed", "message": str(exc)}])
        return _error("source_changed", str(exc), 409)
    except ImportCollisionError as exc:
        return _error("replacement_confirmation_required", str(exc), 409)
    except ImportRecordError as exc:
        return _error("import_not_found", str(exc), 404)
    except Exception:
        current_app.logger.exception("Table language publication failed")
        repository.record_failed_attempt(import_id, status="failed", stage="Publication failed")
        return _error("publication_failed", "Publication failed; the previously published table and languages remain available.", 500)
