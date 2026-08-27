from __future__ import annotations

import re
import json
import logging
from concurrent.futures import ThreadPoolExecutor
from datetime import date, datetime
from typing import Any

from flask import Blueprint, Response, current_app, request
from firebase_admin import firestore

from services.admin_auth import (
    AdminAuthorizationError,
    verify_admin_authorization,
)
from services.bible_import_service import parse_usfm_files
from services.firebase_service import (
    FirebaseImportRepository,
    ImportCollisionError,
    ImportRecordError,
    new_import_id,
    safe_filename,
)
from services.topic_import_service import (
    add_structural_comparison,
    parse_topic_csv,
)


admin_api = Blueprint("admin_api", __name__)
_executor = ThreadPoolExecutor(max_workers=2, thread_name_prefix="admin-import")
_logger = logging.getLogger(__name__)
_LANGUAGE_ID = re.compile(r"^[a-z][a-z0-9_-]{1,39}$")
_VERSION_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9 _-]{0,79}$")


def _json_safe(value: Any):
    if isinstance(value, (datetime, date)):
        return value.isoformat()
    if hasattr(value, "isoformat"):
        return value.isoformat()
    return str(value)


def _response(payload: dict[str, Any], status: int = 200):
    response = current_app.response_class(
        json.dumps(payload, ensure_ascii=False, default=_json_safe),
        status=status,
        content_type="application/json; charset=utf-8",
    )
    response.headers["Cache-Control"] = "no-store"
    return response


def _error(code: str, message: str, status: int, **details: Any):
    return _response(
        {"error": {"code": code, "message": message, **details}}, status=status
    )


def _admin() -> dict[str, Any]:
    return verify_admin_authorization(request.headers.get("Authorization"))


def _clean_text(value: Any, field: str, *, max_length: int, required: bool = True) -> str:
    text = str(value or "").strip()
    if required and not text:
        raise ValueError(f"{field} is required.")
    if len(text) > max_length:
        raise ValueError(f"{field} must be {max_length} characters or fewer.")
    if any(ord(character) < 32 for character in text):
        raise ValueError(f"{field} contains unsupported control characters.")
    return text


def _language_id(value: Any) -> str:
    language = _clean_text(value, "Language code", max_length=40).lower().replace(" ", "_")
    if not _LANGUAGE_ID.fullmatch(language):
        raise ValueError(
            "Language code must start with a letter and use only lowercase letters, numbers, underscores, or hyphens."
        )
    return language


def _version_id(value: Any, fallback: str) -> str:
    version = str(value or "").strip()
    if not version:
        version = re.sub(r"[^A-Za-z0-9]+", "_", fallback).strip("_").lower()
    if not _VERSION_ID.fullmatch(version) or version in {".", ".."}:
        raise ValueError(
            "Translation identifier may use letters, numbers, spaces, underscores, and hyphens only."
        )
    return version


def _direction(value: Any) -> str:
    direction = str(value or "ltr").strip().lower()
    if direction not in {"ltr", "rtl"}:
        raise ValueError("Text direction must be ltr or rtl.")
    return direction


def _issue_payload(result) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    return (
        [issue.to_dict() for issue in result.report.errors[:200]],
        [issue.to_dict() for issue in result.report.warnings[:200]],
    )


@admin_api.errorhandler(AdminAuthorizationError)
def _authorization_error(exc: AdminAuthorizationError):
    return _error(exc.code, exc.message, exc.status)


@admin_api.route("/admin/overview", methods=["GET"])
def admin_overview():
    _admin()
    overview = FirebaseImportRepository().overview()
    overview["maxUploadBytes"] = int(current_app.config["MAX_CONTENT_LENGTH"])
    return _response(overview)


@admin_api.route("/admin/languages", methods=["GET"])
def admin_languages():
    _admin()
    overview = FirebaseImportRepository().overview()
    return _response(
        {
            "bibleLanguages": overview["bibleLanguages"],
            "topicLanguages": overview["topicLanguages"],
        }
    )


@admin_api.route("/admin/imports", methods=["GET"])
def admin_imports():
    _admin()
    try:
        limit = int(request.args.get("limit", "25"))
    except ValueError:
        return _error("invalid_limit", "Limit must be a number.", 400)
    return _response({"imports": FirebaseImportRepository().list_imports(limit)})


@admin_api.route("/admin/imports/<import_id>", methods=["GET"])
def admin_import(import_id: str):
    _admin()
    if not re.fullmatch(r"[a-f0-9]{32}", import_id):
        return _error("invalid_import_id", "Import identifier is invalid.", 400)
    try:
        record = FirebaseImportRepository().get_import(import_id)
    except ImportRecordError as exc:
        return _error("import_not_found", str(exc), 404)
    return _response({"import": record})


@admin_api.route("/admin/topics/template", methods=["GET"])
def topic_template():
    _admin()
    content = "\ufeffTopic,Matthew,Mark,Luke,John\r\nPrologue,1:1,1:1,1:1-4,1:1\r\n"
    response = Response(content, content_type="text/csv; charset=utf-8")
    response.headers["Content-Disposition"] = "attachment; filename=topics_template.csv"
    response.headers["Cache-Control"] = "no-store"
    return response


@admin_api.route("/admin/topics/validate", methods=["POST"])
def validate_topics():
    admin = _admin()
    upload = request.files.get("file")
    if upload is None:
        return _error("missing_file", "Select one CSV file.", 400)
    try:
        filename = safe_filename(upload.filename or "")
        if not filename.lower().endswith(".csv"):
            raise ValueError("Topic uploads must use the .csv extension.")
        language = _language_id(request.form.get("language"))
        display_name = _clean_text(
            request.form.get("displayName") or language.title(),
            "Language display name",
            max_length=80,
        )
        direction = _direction(request.form.get("direction"))
        canonical_id = str(request.form.get("canonicalDataset") or "english_kjv").strip()
        if "/" in canonical_id or len(canonical_id) > 80:
            raise ValueError("Canonical dataset identifier is invalid.")
    except ValueError as exc:
        return _error("invalid_metadata", str(exc), 400)

    raw = upload.read()
    repository = FirebaseImportRepository()
    import_id = new_import_id()
    repository.create_import(
        import_id=import_id,
        import_type="topics",
        language=language,
        uploaded_by=admin["uid"],
        filenames=[filename],
        metadata={
            "displayName": display_name,
            "direction": direction,
            "canonicalDataset": canonical_id,
        },
    )
    try:
        paths = repository.upload_sources(
            import_id=import_id,
            import_type="topics",
            language=language,
            files=[(filename, raw)],
        )
        result = parse_topic_csv(raw)
        destination_id = repository.resolve_reference_dataset_id(language)
        if canonical_id and canonical_id != destination_id:
            canonical_records = repository.load_topics(canonical_id)
            if canonical_records:
                add_structural_comparison(
                    result,
                    canonical_records,
                    canonical_label=canonical_id,
                )
            else:
                result.report.warning(
                    "canonical_dataset_missing",
                    f"Canonical dataset {canonical_id} was not found; structural comparison was skipped.",
                )
        errors, warnings = _issue_payload(result)
        collision = repository.topics_exist(destination_id)
        status = "validated" if result.report.valid else "validation_failed"
        summary = result.summary()
        repository.update_import(
            import_id,
            status=status,
            stage="Ready to import" if result.report.valid else "Validation failed",
            errors=errors,
            warnings=warnings,
            validation=summary["stats"],
            collision=collision,
            destination=f"references/{destination_id}",
            storagePaths=paths,
        )
        return _response(
            {
                "importId": import_id,
                "collision": collision,
                "destination": f"references/{destination_id}",
                **summary,
            }
        )
    except Exception:
        current_app.logger.exception("Topic validation failed")
        repository.update_import(
            import_id,
            status="validation_failed",
            stage="Validation failed",
            errors=[{"severity": "error", "code": "validation_failed", "message": "The upload could not be validated."}],
        )
        return _error("validation_failed", "The upload could not be validated.", 500, importId=import_id)


@admin_api.route("/admin/bibles/validate", methods=["POST"])
def validate_bible():
    admin = _admin()
    uploads = request.files.getlist("files") or request.files.getlist("file")
    if not uploads:
        return _error("missing_files", "Select at least one USFM file.", 400)
    if len(uploads) > 10:
        return _error("too_many_files", "This importer supports at most 10 USFM files per upload.", 400)
    try:
        language = _language_id(request.form.get("language"))
        language_display_name = _clean_text(
            request.form.get("languageDisplayName") or language.title(),
            "Language display name",
            max_length=80,
        )
        direction = _direction(request.form.get("direction"))
        translation_name = _clean_text(
            request.form.get("translationName"), "Translation name", max_length=120
        )
        version = _version_id(request.form.get("versionId"), translation_name)
        version_display_name = _clean_text(
            request.form.get("versionDisplayName") or translation_name,
            "Translation display name",
            max_length=120,
        )
        description = _clean_text(
            request.form.get("description"), "Description", max_length=500, required=False
        )
        related_translation = _clean_text(
            request.form.get("relatedTranslation"),
            "Related translation",
            max_length=80,
            required=False,
        ) or None
        declared_diacritics = str(request.form.get("containsDiacritics") or "auto").lower()
        if declared_diacritics not in {"auto", "true", "false"}:
            raise ValueError("Contains diacritics must be auto, true, or false.")
        files = []
        for upload in uploads:
            filename = safe_filename(upload.filename or "")
            if not filename.lower().endswith(".usfm"):
                raise ValueError(f"{filename} is not a .usfm file.")
            files.append((filename, upload.read()))
        normalized_filenames = [name.casefold() for name, _ in files]
        if len(normalized_filenames) != len(set(normalized_filenames)):
            raise ValueError("Each uploaded USFM file must have a unique filename.")
    except ValueError as exc:
        return _error("invalid_metadata", str(exc), 400)

    repository = FirebaseImportRepository()
    version = repository.resolve_version_id(language, version)
    import_id = new_import_id()
    repository.create_import(
        import_id=import_id,
        import_type="bible",
        language=language,
        version=version,
        uploaded_by=admin["uid"],
        filenames=[name for name, _ in files],
        metadata={
            "languageDisplayName": language_display_name,
            "direction": direction,
            "translationName": translation_name,
            "versionDisplayName": version_display_name,
            "description": description,
            "relatedTranslation": related_translation,
            "declaredDiacritics": declared_diacritics,
        },
    )
    try:
        paths = repository.upload_sources(
            import_id=import_id,
            import_type="bible",
            language=language,
            version=version,
            files=files,
        )
        result = parse_usfm_files(files)
        if declared_diacritics != "auto":
            expected = declared_diacritics == "true"
            if expected != result.contains_diacritics:
                result.report.warning(
                    "diacritics_metadata_mismatch",
                    "The selected diacritics metadata does not match the uploaded text. The detected value will be stored.",
                )
        errors, warnings = _issue_payload(result)
        collision = repository.bible_version_exists(language, version)
        status = "validated" if result.report.valid else "validation_failed"
        summary = result.summary()
        repository.update_import(
            import_id,
            status=status,
            stage="Ready to import" if result.report.valid else "Validation failed",
            errors=errors,
            warnings=warnings,
            validation=summary["stats"],
            containsDiacritics=result.contains_diacritics,
            collision=collision,
            destination=f"bibles/{language}/versions/{version}",
            storagePaths=paths,
        )
        return _response(
            {
                "importId": import_id,
                "language": language,
                "version": version,
                "collision": collision,
                "destination": f"bibles/{language}/versions/{version}",
                **summary,
            }
        )
    except Exception:
        current_app.logger.exception("Bible validation failed")
        repository.update_import(
            import_id,
            status="validation_failed",
            stage="Validation failed",
            errors=[{"severity": "error", "code": "validation_failed", "message": "The upload could not be validated."}],
        )
        return _error("validation_failed", "The upload could not be validated.", 500, importId=import_id)


def _start_import(expected_type: str):
    admin = _admin()
    payload = request.get_json(silent=True) or {}
    import_id = str(payload.get("importId") or "").strip()
    if not re.fullmatch(r"[a-f0-9]{32}", import_id):
        return _error("invalid_import_id", "Import identifier is invalid.", 400)
    if payload.get("confirm") is not True:
        return _error("confirmation_required", "Explicit import confirmation is required.", 400)
    repository = FirebaseImportRepository()
    try:
        record = repository.get_import(import_id)
    except ImportRecordError as exc:
        return _error("import_not_found", str(exc), 404)
    if record.get("type") != expected_type:
        return _error("wrong_import_type", "Import type does not match this endpoint.", 400)
    if record.get("status") == "completed":
        return _response({"importId": import_id, "status": "completed"})
    if record.get("status") not in {"validated", "failed"}:
        return _error(
            "import_not_ready",
            f'Import is currently {record.get("status", "not ready")}.',
            409,
        )
    if record.get("collision") is True and payload.get("replace") is not True:
        return _error(
            "replacement_confirmation_required",
            "An existing dataset would be replaced. Confirm replacement to continue.",
            409,
        )
    repository.update_import(
        import_id,
        status="queued",
        stage="Preparing import",
        confirmedBy=admin["uid"],
        replace=payload.get("replace") is True,
        errors=[],
    )
    runner = _run_topic_import if expected_type == "topics" else _run_bible_import
    _executor.submit(runner, import_id, payload.get("replace") is True)
    return _response({"importId": import_id, "status": "queued"}, status=202)


@admin_api.route("/admin/topics/import", methods=["POST"])
def import_topics():
    return _start_import("topics")


@admin_api.route("/admin/bibles/import", methods=["POST"])
def import_bible():
    return _start_import("bible")


def _run_topic_import(import_id: str, replace: bool) -> None:
    repository = FirebaseImportRepository()
    try:
        record = repository.get_import(import_id)
        metadata = record.get("metadata") or {}
        repository.update_import(import_id, status="importing", stage="Parsing CSV")
        files = repository.download_sources(record)
        result = parse_topic_csv(files[0][1])
        canonical_id = str(metadata.get("canonicalDataset") or "english_kjv")
        destination_id = repository.resolve_reference_dataset_id(record["language"])
        if canonical_id and canonical_id != destination_id:
            canonical = repository.load_topics(canonical_id)
            if canonical:
                add_structural_comparison(result, canonical, canonical_label=canonical_id)
        if not result.report.valid:
            raise ImportRecordError("The staged CSV no longer passes validation.")
        repository.update_import(import_id, stage="Uploading topics")
        outcome = repository.activate_topics(
            import_id=import_id,
            language=record["language"],
            display_name=str(metadata.get("displayName") or record["language"].title()),
            direction=str(metadata.get("direction") or "ltr"),
            records=result.records,
            replace=replace,
        )
        repository.update_import(
            import_id,
            status="completed",
            stage="Completed",
            completedAt=firestore.SERVER_TIMESTAMP,
            recordsProcessed=outcome["topicsProcessed"],
            **outcome,
        )
    except (ImportCollisionError, ImportRecordError) as exc:
        repository.update_import(
            import_id,
            status="failed",
            stage="Failed",
            errors=[{"severity": "error", "code": "import_failed", "message": str(exc)}],
        )
    except Exception:
        _logger.exception("Topic import failed")
        repository.update_import(
            import_id,
            status="failed",
            stage="Failed",
            errors=[{"severity": "error", "code": "import_failed", "message": "The topic import failed. The previous active dataset was not changed."}],
        )


def _run_bible_import(import_id: str, replace: bool) -> None:
    repository = FirebaseImportRepository()
    try:
        record = repository.get_import(import_id)
        metadata = record.get("metadata") or {}
        repository.update_import(import_id, status="importing", stage="Parsing USFM files")
        files = repository.download_sources(record)
        result = parse_usfm_files(files)
        if not result.report.valid:
            raise ImportRecordError("The staged USFM files no longer pass validation.")
        repository.update_import(import_id, stage="Writing Bible revision")
        outcome = repository.activate_bible(
            import_id=import_id,
            language=record["language"],
            language_display_name=str(metadata.get("languageDisplayName") or record["language"].title()),
            direction=str(metadata.get("direction") or "ltr"),
            version=record["version"],
            version_display_name=str(metadata.get("versionDisplayName") or metadata.get("translationName") or record["version"]),
            description=str(metadata.get("description") or ""),
            related_translation=metadata.get("relatedTranslation"),
            result=result,
            replace=replace,
            progress=lambda book: repository.update_import(
                import_id, stage=f"Uploading {book}"
            ),
        )
        repository.update_import(
            import_id,
            status="completed",
            stage="Completed",
            completedAt=firestore.SERVER_TIMESTAMP,
            recordsProcessed=outcome["versesProcessed"],
            **outcome,
        )
    except (ImportCollisionError, ImportRecordError) as exc:
        repository.update_import(
            import_id,
            status="failed",
            stage="Failed",
            errors=[{"severity": "error", "code": "import_failed", "message": str(exc)}],
        )
    except Exception:
        _logger.exception("Bible import failed")
        repository.update_import(
            import_id,
            status="failed",
            stage="Failed",
            errors=[{"severity": "error", "code": "import_failed", "message": "The Bible import failed. The previous active translation was not changed."}],
        )
