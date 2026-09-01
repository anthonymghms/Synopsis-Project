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
from services.localization_import_service import parse_topic_localization_csv
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
    reference_structure_mismatch_ids,
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


@admin_api.route("/admin/localizations/template", methods=["GET"])
def localization_template():
    _admin()
    content = "\ufeffTopicNumber,TopicName\r\n1,Localized topic 1\r\n2,Localized topic 2\r\n"
    response = Response(content, content_type="text/csv; charset=utf-8")
    response.headers["Content-Disposition"] = "attachment; filename=topic_localization_template.csv"
    response.headers["Cache-Control"] = "no-store"
    return response


@admin_api.route("/admin/harmony/migration-report", methods=["GET"])
def harmony_migration_report():
    _admin()
    trusted = str(request.args.get("trustedDataset") or "canonical").strip()
    if not trusted or "/" in trusted or len(trusted) > 80:
        return _error("invalid_dataset", "Trusted dataset identifier is invalid.", 400)
    return _response(FirebaseImportRepository().harmony_migration_report(trusted))


def _gospel_labels_from_form() -> dict[str, str]:
    labels = {}
    for gospel in ("Matthew", "Mark", "Luke", "John"):
        labels[gospel] = _clean_text(
            request.form.get(f"gospel{gospel}") or gospel,
            f"{gospel} display name",
            max_length=80,
        )
    return labels


def _parse_language_upload(
    raw: bytes,
    *,
    repository: FirebaseImportRepository,
    canonical_records,
    canonical_active: bool,
):
    localization = parse_topic_localization_csv(raw, canonical_records)
    master = None
    bootstrap_canonical = False
    if localization.source_format == "harmonyTable":
        master = parse_topic_csv(
            raw,
            verse_count_resolver=repository.chapter_verse_count,
        )
        bootstrap_canonical = not canonical_active
        if bootstrap_canonical:
            localization = parse_topic_localization_csv(raw, master.records)
        localization.report.extend(master.report.errors)
        localization.report.extend(master.report.warnings)
        if canonical_active and master.report.valid:
            mismatches = reference_structure_mismatch_ids(
                master.records,
                canonical_records,
            )
            if mismatches:
                preview = ", ".join(mismatches[:20])
                suffix = "…" if len(mismatches) > 20 else ""
                localization.report.error(
                    "canonical_reference_mismatch",
                    f"The uploaded full table differs from the active canonical references at topic IDs {preview}{suffix}. Use Update Harmony References for reference changes.",
                    field="References",
                )
            else:
                localization.report.warning(
                    "reference_columns_unchanged",
                    "The five-column file matches the active Harmony references. Add/Edit Language will update only topic and Gospel display names.",
                )
    return localization, master, bootstrap_canonical


@admin_api.route("/admin/localizations/validate", methods=["POST"])
def validate_topic_localization():
    admin = _admin()
    upload = request.files.get("file")
    if upload is None:
        return _error("missing_file", "Select one localization CSV file.", 400)
    try:
        filename = safe_filename(upload.filename or "")
        if not filename.lower().endswith(".csv"):
            raise ValueError("Localization uploads must use the .csv extension.")
        language = _language_id(request.form.get("language"))
        display_name = _clean_text(
            request.form.get("displayName") or language.title(),
            "Language display name",
            max_length=80,
        )
        direction = _direction(request.form.get("direction"))
        gospel_labels = _gospel_labels_from_form()
        canonical_id = str(
            request.form.get("canonicalDataset") or "english_kjv"
        ).strip()
        if "/" in canonical_id or len(canonical_id) > 80:
            raise ValueError("Canonical fallback dataset identifier is invalid.")
    except ValueError as exc:
        return _error("invalid_metadata", str(exc), 400)

    raw = upload.read()
    repository = FirebaseImportRepository()
    canonical_records, canonical_source = repository.load_canonical_topics(
        fallback_dataset_id=canonical_id
    )
    canonical_active = repository.canonical_topics_exist()
    result, master_result, bootstrap_canonical = _parse_language_upload(
        raw,
        repository=repository,
        canonical_records=canonical_records,
        canonical_active=canonical_active,
    )
    if bootstrap_canonical:
        canonical_source = "harmony/canonical"
    import_id = new_import_id()
    metadata = {
        "displayName": display_name,
        "direction": direction,
        "gospels": gospel_labels,
        "canonicalDataset": canonical_id,
        "canonicalSource": canonical_source,
        "bootstrapCanonical": bootstrap_canonical,
        "sourceFormat": result.source_format,
    }
    repository.create_import(
        import_id=import_id,
        import_type="topic_localization",
        language=language,
        uploaded_by=admin["uid"],
        filenames=[filename],
        metadata=metadata,
    )
    try:
        paths = repository.upload_sources(
            import_id=import_id,
            import_type="topic_localization",
            language=language,
            files=[(filename, raw)],
        )
        errors, warnings = _issue_payload(result)
        collision = repository.localization_exists(language) or (
            bootstrap_canonical and repository.canonical_topics_exist()
        )
        status = "validated" if result.report.valid else "validation_failed"
        summary = result.summary(preview_limit=len(result.records))
        if bootstrap_canonical and master_result is not None:
            summary["stats"].update(
                {
                    "canonicalTopics": len(master_result.records),
                    "references": sum(
                        record.logical_reference_count
                        for record in master_result.records
                    ),
                    "physicalSegments": sum(
                        record.physical_segment_count
                        for record in master_result.records
                    ),
                }
            )
        destination = (
            f"harmony/canonical + harmony_localizations/{language}"
            if bootstrap_canonical
            else f"harmony_localizations/{language}"
        )
        repository.update_import(
            import_id,
            status=status,
            stage="Ready to import" if result.report.valid else "Validation failed",
            errors=errors,
            warnings=warnings,
            validation=summary["stats"],
            collision=collision,
            destination=destination,
            storagePaths=paths,
        )
        return _response(
            {
                "importId": import_id,
                "collision": collision,
                "destination": destination,
                "canonicalSource": canonical_source,
                "bootstrapCanonical": bootstrap_canonical,
                **summary,
            }
        )
    except Exception:
        current_app.logger.exception("Topic localization validation failed")
        repository.update_import(
            import_id,
            status="validation_failed",
            stage="Validation failed",
            errors=[{"severity": "error", "code": "validation_failed", "message": "The localization upload could not be validated."}],
        )
        return _error(
            "validation_failed",
            "The localization upload could not be validated.",
            500,
            importId=import_id,
        )


@admin_api.route("/admin/harmony/validate", methods=["POST"])
def validate_canonical_harmony():
    admin = _admin()
    upload = request.files.get("file")
    if upload is None:
        return _error("missing_file", "Select one canonical Harmony CSV file.", 400)
    try:
        filename = safe_filename(upload.filename or "")
        if not filename.lower().endswith(".csv"):
            raise ValueError("Harmony uploads must use the .csv extension.")
        localization_language = _language_id(
            request.form.get("localizationLanguage") or "arabic"
        )
        localization_display_name = _clean_text(
            request.form.get("localizationDisplayName")
            or request.form.get("displayName")
            or localization_language.title(),
            "Topic language display name",
            max_length=80,
        )
        localization_direction = _direction(
            request.form.get("localizationDirection")
            or request.form.get("direction")
            or ("rtl" if localization_language == "arabic" else "ltr")
        )
        gospel_labels = _gospel_labels_from_form()
    except ValueError as exc:
        return _error("invalid_metadata", str(exc), 400)

    raw = upload.read()
    repository = FirebaseImportRepository()
    import_id = new_import_id()
    repository.create_import(
        import_id=import_id,
        import_type="harmony",
        language=localization_language,
        uploaded_by=admin["uid"],
        filenames=[filename],
        metadata={
            "referenceGrammarVersion": 2,
            "includesLocalization": True,
            "displayName": localization_display_name,
            "direction": localization_direction,
            "gospels": gospel_labels,
        },
    )
    try:
        paths = repository.upload_sources(
            import_id=import_id,
            import_type="harmony",
            language="canonical",
            files=[(filename, raw)],
        )
        result = parse_topic_csv(
            raw,
            verse_count_resolver=repository.chapter_verse_count,
        )
        localization_result = parse_topic_localization_csv(raw, result.records)
        result.report.extend(localization_result.report.errors)
        result.report.extend(localization_result.report.warnings)
        active_records, _ = repository.load_canonical_topics(
            fallback_dataset_id=""
        )
        if active_records and len(active_records) != len(result.records):
            result.report.warning(
                "master_topic_count_change",
                f"The active master contains {len(active_records)} topics and this upload contains {len(result.records)}. Review added or removed topic numbers before confirming replacement.",
                field="TopicNumber",
            )
        errors, warnings = _issue_payload(result)
        collision = repository.canonical_topics_exist() or repository.localization_exists(
            localization_language
        )
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
            destination=(
                "harmony/canonical + "
                f"harmony_localizations/{localization_language}"
            ),
            storagePaths=paths,
        )
        return _response(
            {
                "importId": import_id,
                "collision": collision,
                "destination": (
                    "harmony/canonical + "
                    f"harmony_localizations/{localization_language}"
                ),
                "localizationLanguage": localization_language,
                "localizationPreview": localization_result.summary()["preview"],
                **summary,
            }
        )
    except Exception:
        current_app.logger.exception("Canonical Harmony validation failed")
        repository.update_import(
            import_id,
            status="validation_failed",
            stage="Validation failed",
            errors=[{"severity": "error", "code": "validation_failed", "message": "The canonical Harmony upload could not be validated."}],
        )
        return _error(
            "validation_failed",
            "The canonical Harmony upload could not be validated.",
            500,
            importId=import_id,
        )


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
        result = parse_topic_csv(
            raw,
            verse_count_resolver=repository.chapter_verse_count,
        )
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
    runners = {
        "topics": _run_topic_import,
        "bible": _run_bible_import,
        "harmony": _run_harmony_import,
        "topic_localization": _run_topic_localization_import,
    }
    runner = runners[expected_type]
    _executor.submit(runner, import_id, payload.get("replace") is True)
    return _response({"importId": import_id, "status": "queued"}, status=202)


@admin_api.route("/admin/topics/import", methods=["POST"])
def import_topics():
    return _start_import("topics")


@admin_api.route("/admin/bibles/import", methods=["POST"])
def import_bible():
    return _start_import("bible")


@admin_api.route("/admin/harmony/import", methods=["POST"])
def import_canonical_harmony():
    return _start_import("harmony")


@admin_api.route("/admin/localizations/import", methods=["POST"])
def import_topic_localization():
    return _start_import("topic_localization")


def _run_topic_import(import_id: str, replace: bool) -> None:
    repository = FirebaseImportRepository()
    try:
        record = repository.get_import(import_id)
        metadata = record.get("metadata") or {}
        repository.update_import(import_id, status="importing", stage="Parsing CSV")
        files = repository.download_sources(record)
        result = parse_topic_csv(
            files[0][1],
            verse_count_resolver=repository.chapter_verse_count,
        )
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


def _run_harmony_import(import_id: str, replace: bool) -> None:
    repository = FirebaseImportRepository()
    try:
        record = repository.get_import(import_id)
        repository.update_import(
            import_id, status="importing", stage="Parsing canonical Harmony CSV"
        )
        files = repository.download_sources(record)
        result = parse_topic_csv(
            files[0][1],
            verse_count_resolver=repository.chapter_verse_count,
        )
        if not result.report.valid:
            raise ImportRecordError("The staged canonical CSV no longer passes validation.")
        metadata = record.get("metadata") or {}
        localization = parse_topic_localization_csv(files[0][1], result.records)
        if not localization.report.valid:
            raise ImportRecordError(
                "The topic-language names in the staged master CSV no longer pass validation."
            )
        repository.update_import(
            import_id,
            stage="Writing canonical Harmony and base-language revisions",
        )
        raw_gospels = metadata.get("gospels")
        gospel_labels = (
            {str(key): str(value) for key, value in raw_gospels.items()}
            if isinstance(raw_gospels, dict)
            else {gospel: gospel for gospel in ("Matthew", "Mark", "Luke", "John")}
        )
        outcome = repository.activate_canonical_with_localization(
            import_id=import_id,
            language=record["language"],
            display_name=str(metadata.get("displayName") or record["language"].title()),
            direction=str(metadata.get("direction") or "ltr"),
            gospel_labels=gospel_labels,
            canonical_records=result.records,
            records=localization.records,
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
        _logger.exception("Canonical Harmony import failed")
        repository.update_import(
            import_id,
            status="failed",
            stage="Failed",
            errors=[{"severity": "error", "code": "import_failed", "message": "The canonical Harmony import failed. The previous active revision was not changed."}],
        )


def _run_topic_localization_import(import_id: str, replace: bool) -> None:
    repository = FirebaseImportRepository()
    try:
        record = repository.get_import(import_id)
        metadata = record.get("metadata") or {}
        repository.update_import(
            import_id, status="importing", stage="Parsing topic localization CSV"
        )
        files = repository.download_sources(record)
        canonical_records, canonical_source = repository.load_canonical_topics(
            fallback_dataset_id=str(
                metadata.get("canonicalDataset") or "english_kjv"
            )
        )
        bootstrap_canonical = metadata.get("bootstrapCanonical") is True
        if bootstrap_canonical:
            master_result = parse_topic_csv(
                files[0][1],
                verse_count_resolver=repository.chapter_verse_count,
            )
            result = parse_topic_localization_csv(
                files[0][1],
                master_result.records,
            )
            result.report.extend(master_result.report.errors)
            result.report.extend(master_result.report.warnings)
            canonical_source = "harmony/canonical"
        else:
            result, _, _ = _parse_language_upload(
                files[0][1],
                repository=repository,
                canonical_records=canonical_records,
                canonical_active=True,
            )
        if not result.report.valid:
            raise ImportRecordError(
                "The staged localization CSV no longer passes validation."
            )
        repository.update_import(import_id, stage="Writing localization revision")
        raw_gospels = metadata.get("gospels")
        gospel_labels = (
            {str(key): str(value) for key, value in raw_gospels.items()}
            if isinstance(raw_gospels, dict)
            else {gospel: gospel for gospel in ("Matthew", "Mark", "Luke", "John")}
        )
        activation_arguments = {
            "import_id": import_id,
            "language": record["language"],
            "display_name": str(
                metadata.get("displayName") or record["language"].title()
            ),
            "direction": str(metadata.get("direction") or "ltr"),
            "gospel_labels": gospel_labels,
            "records": result.records,
            "replace": replace,
        }
        if bootstrap_canonical:
            outcome = repository.activate_canonical_with_localization(
                canonical_records=master_result.records,
                **activation_arguments,
            )
        else:
            outcome = repository.activate_topic_localization(
                canonical_source=canonical_source,
                **activation_arguments,
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
        _logger.exception("Topic localization import failed")
        repository.update_import(
            import_id,
            status="failed",
            stage="Failed",
            errors=[{"severity": "error", "code": "import_failed", "message": "The topic localization import failed. The previous active localization was not changed."}],
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
