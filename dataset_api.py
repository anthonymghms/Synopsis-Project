"""Authenticated reads and explicitly confirmed imports for separate topic tables."""
from __future__ import annotations

import json
import re
from datetime import date, datetime

from flask import Blueprint, current_app, request

from services.admin_auth import verify_admin_authorization
from services.membership_service import verify_reader_authorization
from services.dataset_import_service import DATASET_FILES, dataset_id, parse_dataset_csv
from services.dataset_repository import DatasetRepository, DatasetRevisionConflict, SourceChangedError
from services.firebase_service import ImportCollisionError, ImportRecordError, new_import_id, safe_filename


dataset_api = Blueprint("dataset_api", __name__)


def _json_default(value):
    return value.isoformat() if isinstance(value, (date, datetime)) else str(value)


def _response(payload, status=200):
    response = current_app.response_class(json.dumps(payload, ensure_ascii=False, default=_json_default), status=status, content_type="application/json; charset=utf-8")
    # The frontend caches immutable revisions; active pointers must be fresh.
    response.headers["Cache-Control"] = "no-store"
    return response


def _error(code, message, status=400):
    return _response({"error": {"code": code, "message": message}}, status)


@dataset_api.before_request
def authorize_dataset_request():
    if request.method != "OPTIONS" and not request.path.startswith("/admin/"):
        verify_reader_authorization(request.headers.get("Authorization"))


def _admin():
    return verify_admin_authorization(request.headers.get("Authorization"))


@dataset_api.get("/datasets")
def dataset_catalog():
    return _response({"datasets": DatasetRepository().catalog()})


@dataset_api.get("/admin/datasets")
def admin_dataset_catalog():
    _admin()
    return _response({"datasets": DatasetRepository().catalog()})


@dataset_api.get("/admin/datasets/template")
def admin_dataset_template():
    _admin()
    return _response({"filename": "table_template.csv", "csv": "#,Subject,الموضوع,Type,Matthew,Mark,Luke,John\r\n"})


@dataset_api.get("/admin/datasets/sources")
def admin_dataset_sources():
    _admin()
    try:
        return _response({"sources": DatasetRepository().storage_sources()})
    except Exception:
        current_app.logger.exception("Dataset Storage sources could not be inspected")
        return _error("storage_unavailable", "The backend Storage connection is unavailable. Upload a CSV instead or check the server's authorized Storage configuration.", 503)


@dataset_api.post("/admin/datasets/validate")
def admin_validate_dataset():
    admin = _admin()
    fields = request.form if request.mimetype == "multipart/form-data" else (request.get_json(silent=True) or {})
    if not isinstance(fields, dict) and request.mimetype != "multipart/form-data":
        return _error("invalid_request", "A JSON object is required.")
    try:
        selected_dataset = dataset_id(fields.get("datasetId"))
        flag = fields.get("createNew", False)
        if request.mimetype == "multipart/form-data":
            if flag not in (False, "true", "false"):
                raise ValueError("createNew must be true or false.")
            create_new = flag == "true"
        else:
            if not isinstance(flag, bool):
                raise ValueError("createNew must be a boolean.")
            create_new = flag
        labels = fields.get("labels")
        if create_new and request.mimetype == "multipart/form-data":
            labels = json.loads(labels or "{}")
        kind = fields.get("source")
        if not isinstance(kind, str) or kind not in {"storage", "upload"}:
            raise ValueError("Choose Storage or upload as the source.")
        if kind == "storage":
            if selected_dataset not in DATASET_FILES:
                raise ValueError("Custom tables require an uploaded CSV. Existing Storage sources are limited to Miracles.csv and Parables.csv.")
            filename = str(fields.get("filename") or "")
            if filename != DATASET_FILES[selected_dataset]:
                raise ValueError("Choose the permitted source file for the selected dataset.")
        else:
            upload = request.files.get("file")
            if upload is None:
                raise ValueError("Choose a CSV file to upload.")
            filename = safe_filename(upload.filename or "")
            if not filename.lower().endswith(".csv"):
                raise ValueError("Dataset uploads must use the .csv extension.")
    except ValueError as exc:
        return _error("invalid_dataset_source", str(exc))
    repository = DatasetRepository()
    import_id = new_import_id()
    created = False
    try:
        active = repository.import_target(selected_dataset, create_new=create_new, labels=labels)
        if kind == "storage":
            raw, source = repository.read_storage_source(selected_dataset, filename)
            source["kind"] = "storage"
        else:
            raw = upload.read()
            source = repository.stage_upload(selected_dataset, import_id, filename, raw)
        source["filename"] = filename
        result = parse_dataset_csv(raw, verse_count_resolver=repository.chapter_verse_count)
        summary = result.summary()
        repository.create_import(import_id=import_id, import_type="dataset", language="multilingual", uploaded_by=admin["uid"], filenames=[filename], metadata={"datasetId": selected_dataset, "labels": active["labels"], "createNew": create_new})
        created = True
        repository.update_import(import_id, datasetId=selected_dataset, labels=active["labels"], createNew=create_new, source=source, sourceChecksum=source["checksum"], expectedRevision=active.get("activeRevision"), status="validated" if result.report.valid else "validation_failed", stage="Ready to publish" if result.report.valid else "Validation failed", errors=summary["errors"], warnings=summary["warnings"], validation=summary["stats"], collision=bool(active.get("activeRevision")), destination=f"datasets/{selected_dataset}", storagePaths=[source["path"]])
        return _response({"importId": import_id, "datasetId": selected_dataset, "labels": active["labels"], "createNew": create_new, "filename": filename, "source": kind, "sourceChecksum": source["checksum"], "sourceGeneration": source["generation"], "replacesExisting": bool(active.get("activeRevision")), "currentRevision": active.get("activeRevision"), "collision": bool(active.get("activeRevision")), "destination": f"datasets/{selected_dataset}", **summary})
    except DatasetRevisionConflict as exc:
        return _error("dataset_exists", str(exc), 409)
    except ValueError as exc:
        return _error("invalid_dataset_source", str(exc))
    except Exception:
        current_app.logger.exception("Dataset source validation failed")
        if created:
            repository.update_import(import_id, status="validation_failed", stage="Validation failed")
        return _error("validation_failed", "The source could not be validated through the backend. Check file access and try again; active data was not modified.", 503)


@dataset_api.post("/admin/datasets/publish")
def admin_publish_dataset():
    admin = _admin()
    fields = request.get_json(silent=True) or {}
    if not isinstance(fields, dict):
        return _error("invalid_request", "A JSON object is required.")
    try:
        selected_dataset = dataset_id(fields.get("datasetId"))
    except ValueError as exc:
        return _error("invalid_dataset", str(exc))
    import_id = str(fields.get("importId") or "")
    if not re.fullmatch(r"[a-f0-9]{32}", import_id):
        return _error("invalid_import_id", "Import identifier is invalid.")
    if fields.get("confirm") is not True:
        return _error("confirmation_required", "Explicit publication confirmation is required.")
    repository = DatasetRepository()
    try:
        record = repository.get_import(import_id)
        if record.get("type") != "dataset" or record.get("datasetId") != selected_dataset:
            return _error("wrong_dataset", "The preview belongs to a different dataset.")
        if record.get("status") == "completed":
            return _response({"importId": import_id, "datasetId": selected_dataset, "status": "completed", "revision": record.get("revision"), "import": record})
        if record.get("status") not in {"validated", "failed"}:
            return _error("import_not_ready", "Validate this source successfully before publication.", 409)
        if record.get("collision") and fields.get("replace") is not True:
            return _error("replacement_confirmation_required", "Explicit replacement confirmation is required.", 409)
        raw = repository.checked_source(record)
        result = parse_dataset_csv(raw, verse_count_resolver=repository.chapter_verse_count)
        if not result.report.valid:
            repository.record_failed_attempt(import_id, status="validation_failed", errors=result.summary()["errors"])
            return _error("revalidation_failed", "The source no longer passes validation. Validate again before publishing.", 409)
        outcome = repository.activate_dataset(import_id=import_id, selected_dataset=selected_dataset, result=result, source=record["source"], expected_revision=record.get("expectedRevision"), replace=fields.get("replace") is True, confirmed_by=admin["uid"], source_validator=lambda: repository.checked_source(record), create_new=record.get("createNew") is True, labels=record.get("labels"))
        return _response({"importId": import_id, "status": "completed", **outcome, "import": {"id": import_id, "type": "dataset", "status": "completed", **outcome}})
    except (SourceChangedError, DatasetRevisionConflict) as exc:
        repository.record_failed_attempt(import_id, status="validation_failed", stage="Revalidation required", errors=[{"severity": "error", "code": "source_changed", "message": str(exc)}])
        return _error("source_changed", str(exc), 409)
    except ImportCollisionError as exc:
        return _error("replacement_confirmation_required", str(exc), 409)
    except ImportRecordError as exc:
        return _error("import_not_found", str(exc), 404)
    except Exception:
        current_app.logger.exception("Dataset publication failed")
        repository.record_failed_attempt(import_id, status="failed", stage="Publication failed", errors=[{"severity": "error", "code": "publication_failed", "message": "Publication failed; the previous revision remains available."}])
        return _error("publication_failed", "Publication failed; the previous revision remains available.", 500)


@dataset_api.get("/datasets/<selected_dataset>/topics")
def dataset_topics(selected_dataset):
    try:
        return _response(DatasetRepository().canonical_payload(dataset_id(selected_dataset)))
    except ValueError as exc:
        return _error("invalid_dataset", str(exc))
    except ImportRecordError as exc:
        return _error("revision_unavailable", str(exc), 409)


@dataset_api.get("/datasets/<selected_dataset>/localizations/<language>")
def dataset_localization(selected_dataset, language):
    if not re.fullmatch(r"[a-z][a-z0-9_-]{1,39}", language):
        return _error("invalid_language", "The table language identifier is invalid.")
    try:
        return _response(DatasetRepository().localization_payload(dataset_id(selected_dataset), language, request.args.get("revision")))
    except ValueError as exc:
        return _error("invalid_dataset", str(exc))
    except ImportRecordError as exc:
        return _error("revision_unavailable", str(exc), 409)


def legacy_dataset_topics(selected_dataset: str, language: str, topic_id: str | None = None, *, db=None):
    """Adapter preserving old /topics and Bible-reader response contracts."""
    try:
        payload = DatasetRepository(db=db).localized_topics(dataset_id(selected_dataset), language)
        if topic_id is None:
            return _response(payload["topics"])
        normalized_id = str(int(topic_id)) if topic_id.isdecimal() else topic_id
        item = next((item for item in payload["topics"] if item["id"] == normalized_id), None)
        if item is None:
            return _error("topic_not_found", "The item does not exist in this dataset.", 404)
        return _response(item)
    except ValueError as exc:
        return _error("invalid_dataset", str(exc))
    except ImportRecordError as exc:
        return _error("revision_unavailable", str(exc), 409)
