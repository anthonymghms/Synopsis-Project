from __future__ import annotations

import mimetypes
import os
import posixpath
import re
import uuid
from dataclasses import replace
from datetime import datetime, timezone
from typing import Any, Iterable

import firebase_admin
from firebase_admin import credentials, firestore, storage

from .bible_import_service import BibleParseResult
from .localization_import_service import TopicLocalizationRecord
from .topic_import_service import TopicRecord, records_from_firestore


DEFAULT_SERVICE_ACCOUNT_FILE = "serviceAccountKey.json"
DEFAULT_BUCKET_NAME = "synopsis-224b0.firebasestorage.app"
MAX_BATCH_WRITES = 450


class ImportCollisionError(RuntimeError):
    pass


class ImportRecordError(RuntimeError):
    pass


def initialize_firebase() -> firebase_admin.App:
    if firebase_admin._apps:
        return firebase_admin.get_app()
    bucket_name = os.environ.get(
        "FIREBASE_STORAGE_BUCKET", DEFAULT_BUCKET_NAME
    ).strip()
    configured_path = os.environ.get("FIREBASE_SERVICE_ACCOUNT", "").strip()
    service_account_path = configured_path or DEFAULT_SERVICE_ACCOUNT_FILE
    options = {"storageBucket": bucket_name}
    if os.path.isfile(service_account_path):
        return firebase_admin.initialize_app(
            credentials.Certificate(service_account_path), options
        )
    # Production platforms should use Application Default Credentials rather
    # than copying a JSON private key into the application directory.
    return firebase_admin.initialize_app(options=options)


def firestore_client():
    initialize_firebase()
    return firestore.client()


def storage_bucket():
    initialize_firebase()
    bucket_name = os.environ.get(
        "FIREBASE_STORAGE_BUCKET", DEFAULT_BUCKET_NAME
    ).strip()
    return storage.bucket(bucket_name)


def new_import_id() -> str:
    return uuid.uuid4().hex


def safe_filename(filename: str) -> str:
    raw = (filename or "").strip()
    if not raw or "\x00" in raw:
        raise ValueError("Each uploaded file needs a valid filename.")
    if raw != os.path.basename(raw) or raw != posixpath.basename(raw):
        raise ValueError("Uploaded filenames may not contain directory paths.")
    sanitized = re.sub(r"[^A-Za-z0-9._-]+", "_", raw).strip("._")
    if not sanitized:
        raise ValueError("The uploaded filename contains no safe characters.")
    return sanitized[:160]


def _utc_path_stamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def _subcollection_path(document_ref, collection_name: str) -> str:
    """Build a Firestore collection path without private client attributes."""
    return f"{document_ref.path}/{collection_name}"


class FirebaseImportRepository:
    def __init__(self, db=None, bucket=None):
        self.db = db or firestore_client()
        self.bucket = bucket or storage_bucket()
        self._chapter_count_cache: dict[tuple[str, str, str, int], int | None] = {}

    def create_import(
        self,
        *,
        import_id: str,
        import_type: str,
        language: str,
        uploaded_by: str,
        filenames: list[str],
        version: str | None = None,
        metadata: dict[str, Any] | None = None,
    ) -> None:
        payload: dict[str, Any] = {
            "type": import_type,
            "language": language,
            "filenames": filenames,
            "filename": filenames[0] if len(filenames) == 1 else None,
            "uploadedBy": uploaded_by,
            "uploadedAt": firestore.SERVER_TIMESTAMP,
            "updatedAt": firestore.SERVER_TIMESTAMP,
            "status": "validating",
            "stage": "Validating upload",
            "warnings": [],
            "errors": [],
            "recordsProcessed": 0,
        }
        if version:
            payload["version"] = version
        if metadata:
            payload["metadata"] = metadata
        self.db.collection("admin_imports").document(import_id).set(payload)

    def update_import(self, import_id: str, **fields: Any) -> None:
        fields["updatedAt"] = firestore.SERVER_TIMESTAMP
        self.db.collection("admin_imports").document(import_id).set(
            fields, merge=True
        )

    def get_import(self, import_id: str) -> dict[str, Any]:
        snapshot = self.db.collection("admin_imports").document(import_id).get()
        if not snapshot.exists:
            raise ImportRecordError("Import record not found.")
        data = snapshot.to_dict() or {}
        data["id"] = snapshot.id
        return data

    def list_imports(self, limit: int = 25) -> list[dict[str, Any]]:
        query = (
            self.db.collection("admin_imports")
            .order_by("uploadedAt", direction=firestore.Query.DESCENDING)
            .limit(max(1, min(limit, 100)))
        )
        records = []
        for document in query.stream():
            data = document.to_dict() or {}
            data["id"] = document.id
            records.append(data)
        return records

    def upload_sources(
        self,
        *,
        import_id: str,
        import_type: str,
        language: str,
        files: Iterable[tuple[str, bytes]],
        version: str | None = None,
    ) -> list[str]:
        import_folder = {
            "topics": "topics",
            "harmony": "harmony",
            "topic_localization": "localizations",
            "bible": "bibles",
        }.get(import_type, import_type)
        prefix_parts = ["imports", import_folder, language]
        if version:
            prefix_parts.append(version)
        prefix_parts.append(f"{_utc_path_stamp()}-{import_id}")
        prefix = "/".join(prefix_parts)
        paths: list[str] = []
        for filename, content in files:
            clean_name = safe_filename(filename)
            path = f"{prefix}/{clean_name}"
            content_type = mimetypes.guess_type(clean_name)[0] or "application/octet-stream"
            self.bucket.blob(path).upload_from_string(
                content, content_type=content_type
            )
            paths.append(path)
        self.update_import(import_id, storagePaths=paths)
        return paths

    def download_sources(self, import_record: dict[str, Any]) -> list[tuple[str, bytes]]:
        paths = import_record.get("storagePaths")
        if not isinstance(paths, list) or not paths:
            raise ImportRecordError("The staged source upload is missing.")
        files: list[tuple[str, bytes]] = []
        for path in paths:
            if not isinstance(path, str) or not path.startswith("imports/"):
                raise ImportRecordError("The stored source path is invalid.")
            blob = self.bucket.blob(path)
            if not blob.exists():
                raise ImportRecordError(f"Staged source file {os.path.basename(path)} is missing.")
            files.append((os.path.basename(path), blob.download_as_bytes()))
        return files

    def resolve_reference_dataset_id(self, language: str) -> str:
        normalized = language.strip().lower().replace(" ", "_")
        exact = self.db.collection("references").document(normalized)
        exact_snapshot = exact.get()
        if exact_snapshot.exists or next(exact.collection("topics").limit(1).stream(), None):
            return normalized
        candidates = []
        for document in self.db.collection("references").list_documents():
            candidate = document.id.strip().lower().replace(" ", "_")
            if candidate == normalized or candidate.startswith(f"{normalized}_"):
                candidates.append(document.id)
        if candidates:
            candidates.sort(key=lambda item: (len(item), item))
            return candidates[0]
        return normalized

    def topics_exist(self, dataset_id: str) -> bool:
        document = self.db.collection("references").document(dataset_id)
        snapshot = document.get()
        if snapshot.exists and (snapshot.to_dict() or {}).get("activeTopicsPath"):
            return True
        return next(document.collection("topics").limit(1).stream(), None) is not None

    def load_topics(self, dataset_id: str) -> list[TopicRecord]:
        document = self.db.collection("references").document(dataset_id)
        snapshot = document.get()
        data = snapshot.to_dict() if snapshot.exists else {}
        active_path = (data or {}).get("activeTopicsPath")
        collection = (
            self.db.collection(active_path)
            if isinstance(active_path, str) and active_path
            else document.collection("topics")
        )
        return records_from_firestore(collection.stream())

    def load_canonical_topics(
        self, *, fallback_dataset_id: str = "english_kjv"
    ) -> tuple[list[TopicRecord], str]:
        canonical_ref = self.db.collection("harmony").document("canonical")
        snapshot = canonical_ref.get()
        data = snapshot.to_dict() if snapshot.exists else {}
        active_path = (data or {}).get("activeTopicsPath")
        collection = (
            self.db.collection(active_path)
            if isinstance(active_path, str) and active_path
            else canonical_ref.collection("topics")
        )
        records = records_from_firestore(collection.stream())
        if records:
            base_language = os.environ.get(
                "HARMONY_BASE_LOCALIZATION", "arabic"
            ).strip()
            if base_language:
                names = self.load_topic_localizations(base_language)
                if names:
                    records = [
                        replace(record, name=names.get(record.topic_id, record.name))
                        for record in records
                    ]
            return records, "harmony/canonical"
        if not fallback_dataset_id:
            return [], ""
        return self.load_topics(fallback_dataset_id), f"references/{fallback_dataset_id}"

    def canonical_topics_exist(self) -> bool:
        records, source = self.load_canonical_topics(fallback_dataset_id="")
        return bool(records) and source == "harmony/canonical"

    def localization_exists(self, language: str) -> bool:
        document = self.db.collection("harmony_localizations").document(language)
        snapshot = document.get()
        if snapshot.exists and (snapshot.to_dict() or {}).get("activeTopicsPath"):
            return True
        return next(document.collection("topics").limit(1).stream(), None) is not None

    def load_topic_localizations(self, language: str) -> dict[str, str]:
        document = self.db.collection("harmony_localizations").document(language)
        snapshot = document.get()
        data = snapshot.to_dict() if snapshot.exists else {}
        active_path = (data or {}).get("activeTopicsPath")
        collection = (
            self.db.collection(active_path)
            if isinstance(active_path, str) and active_path
            else document.collection("topics")
        )
        return {
            topic.id: str((topic.to_dict() or {}).get("name") or "").strip()
            for topic in collection.stream()
        }

    def chapter_verse_count(
        self,
        book: str,
        chapter: int,
        *,
        language: str = "english",
        version: str = "kjv",
    ) -> int | None:
        key = (language, version, book, chapter)
        if key in self._chapter_count_cache:
            return self._chapter_count_cache[key]
        language_ref = self.db.collection("bibles").document(language)
        version_meta = language_ref.collection("versions").document(version).get()
        active_path = (
            (version_meta.to_dict() or {}).get("activeBooksPath")
            if version_meta.exists
            else None
        )
        books = (
            self.db.collection(active_path)
            if isinstance(active_path, str) and active_path
            else language_ref.collection(version)
        )
        codes = {
            "Matthew": "MAT",
            "Mark": "MRK",
            "Luke": "LUK",
            "John": "JHN",
        }
        candidates = [book]
        code = codes.get(book)
        for document in books.list_documents():
            normalized = document.id.strip().casefold()
            if normalized == book.casefold() or (
                code is not None and normalized.startswith(code.casefold())
            ):
                candidates.insert(0, document.id)
                break
        count: int | None = None
        for candidate in candidates:
            chapter_ref = (
                books.document(candidate)
                .collection("chapters")
                .document(str(chapter))
            )
            snapshot = chapter_ref.get()
            if snapshot.exists:
                stored = (snapshot.to_dict() or {}).get("verseCount")
                if isinstance(stored, int) and stored > 0:
                    count = stored
                else:
                    count = sum(1 for _ in chapter_ref.collection("verses").stream())
                break
        self._chapter_count_cache[key] = count
        return count

    def activate_canonical_topics(
        self,
        *,
        import_id: str,
        records: list[TopicRecord],
        replace: bool,
    ) -> dict[str, Any]:
        if self.canonical_topics_exist() and not replace:
            raise ImportCollisionError(
                "Canonical Harmony references already exist. Confirm replacement to continue."
            )
        revision_ref = self.db.collection("harmony_revisions").document(import_id)
        topics_ref = revision_ref.collection("topics")
        revision_ref.set(
            {
                "topicCount": len(records),
                "status": "writing",
                "createdAt": firestore.SERVER_TIMESTAMP,
                "referenceGrammarVersion": 2,
            }
        )
        self._write_documents(
            (
                topics_ref.document(record.topic_id),
                record.to_canonical_firestore(),
            )
            for record in records
        )
        revision_ref.set(
            {"status": "ready", "completedAt": firestore.SERVER_TIMESTAMP},
            merge=True,
        )
        active_path = _subcollection_path(revision_ref, "topics")
        activation = self.db.batch()
        activation.set(
            self.db.collection("harmony").document("canonical"),
            {
                "activeRevision": import_id,
                "activeTopicsPath": active_path,
                "topicCount": len(records),
                "referenceGrammarVersion": 2,
                "updatedAt": firestore.SERVER_TIMESTAMP,
            },
            merge=True,
        )
        activation.set(
            self.db.collection("admin_imports").document(import_id),
            {
                "status": "completed",
                "stage": "Completed",
                "recordsProcessed": len(records),
                "topicsProcessed": len(records),
                "referencesProcessed": sum(
                    record.logical_reference_count for record in records
                ),
                "physicalSegmentsProcessed": sum(
                    record.physical_segment_count for record in records
                ),
                "destination": "harmony/canonical",
                "activeTopicsPath": active_path,
                "completedAt": firestore.SERVER_TIMESTAMP,
                "updatedAt": firestore.SERVER_TIMESTAMP,
            },
            merge=True,
        )
        activation.commit()
        return {
            "destination": "harmony/canonical",
            "activeTopicsPath": active_path,
            "topicsProcessed": len(records),
            "referencesProcessed": sum(
                record.logical_reference_count for record in records
            ),
            "physicalSegmentsProcessed": sum(
                record.physical_segment_count for record in records
            ),
        }

    def activate_topic_localization(
        self,
        *,
        import_id: str,
        language: str,
        display_name: str,
        direction: str,
        gospel_labels: dict[str, str],
        canonical_source: str,
        records: list[TopicLocalizationRecord],
        replace: bool,
    ) -> dict[str, Any]:
        if self.localization_exists(language) and not replace:
            raise ImportCollisionError(
                f"A Harmony localization for {language} already exists. Confirm replacement to continue."
            )
        revision_ref = self.db.collection(
            "harmony_localization_revisions"
        ).document(import_id)
        topics_ref = revision_ref.collection("topics")
        revision_ref.set(
            {
                "language": language,
                "topicCount": len(records),
                "status": "writing",
                "createdAt": firestore.SERVER_TIMESTAMP,
            }
        )
        self._write_documents(
            (topics_ref.document(record.topic_id), record.to_firestore())
            for record in records
        )
        revision_ref.set(
            {"status": "ready", "completedAt": firestore.SERVER_TIMESTAMP},
            merge=True,
        )
        active_path = _subcollection_path(revision_ref, "topics")
        metadata = {
            "language": language,
            "label": display_name,
            "direction": direction,
            "gospels": gospel_labels,
            "activeRevision": import_id,
            "activeTopicsPath": active_path,
            "topicCount": len(records),
            "canonicalSource": canonical_source,
            "active": True,
            "updatedAt": firestore.SERVER_TIMESTAMP,
        }
        activation = self.db.batch()
        activation.set(
            self.db.collection("harmony_localizations").document(language),
            metadata,
            merge=True,
        )
        activation.set(
            self.db.collection("admin_imports").document(import_id),
            {
                "status": "completed",
                "stage": "Completed",
                "recordsProcessed": len(records),
                "topicsProcessed": len(records),
                "destination": f"harmony_localizations/{language}",
                "activeTopicsPath": active_path,
                "completedAt": firestore.SERVER_TIMESTAMP,
                "updatedAt": firestore.SERVER_TIMESTAMP,
            },
            merge=True,
        )
        activation.commit()
        return {
            "destination": f"harmony_localizations/{language}",
            "activeTopicsPath": active_path,
            "topicsProcessed": len(records),
        }

    def activate_canonical_with_localization(
        self,
        *,
        import_id: str,
        language: str,
        display_name: str,
        direction: str,
        gospel_labels: dict[str, str],
        canonical_records: list[TopicRecord],
        records: list[TopicLocalizationRecord],
        replace: bool,
    ) -> dict[str, Any]:
        canonical_exists = self.canonical_topics_exist()
        localization_exists = self.localization_exists(language)
        if (canonical_exists or localization_exists) and not replace:
            raise ImportCollisionError(
                "Canonical Harmony references or this language localization already exist. Confirm replacement to continue."
            )

        canonical_revision = self.db.collection("harmony_revisions").document(
            import_id
        )
        canonical_topics = canonical_revision.collection("topics")
        localization_revision = self.db.collection(
            "harmony_localization_revisions"
        ).document(import_id)
        localization_topics = localization_revision.collection("topics")

        canonical_revision.set(
            {
                "topicCount": len(canonical_records),
                "status": "writing",
                "createdAt": firestore.SERVER_TIMESTAMP,
                "referenceGrammarVersion": 2,
                "sourceLanguage": language,
            }
        )
        localization_revision.set(
            {
                "language": language,
                "topicCount": len(records),
                "status": "writing",
                "createdAt": firestore.SERVER_TIMESTAMP,
            }
        )
        self._write_documents(
            (
                canonical_topics.document(record.topic_id),
                record.to_canonical_firestore(),
            )
            for record in canonical_records
        )
        self._write_documents(
            (
                localization_topics.document(record.topic_id),
                record.to_firestore(),
            )
            for record in records
        )
        ready = {
            "status": "ready",
            "completedAt": firestore.SERVER_TIMESTAMP,
        }
        canonical_revision.set(ready, merge=True)
        localization_revision.set(ready, merge=True)

        canonical_path = _subcollection_path(canonical_revision, "topics")
        localization_path = _subcollection_path(localization_revision, "topics")
        localization_metadata = {
            "language": language,
            "label": display_name,
            "direction": direction,
            "gospels": gospel_labels,
            "activeRevision": import_id,
            "activeTopicsPath": localization_path,
            "topicCount": len(records),
            "canonicalSource": "harmony/canonical",
            "active": True,
            "updatedAt": firestore.SERVER_TIMESTAMP,
        }
        logical_references = sum(
            record.logical_reference_count for record in canonical_records
        )
        physical_segments = sum(
            record.physical_segment_count for record in canonical_records
        )
        activation = self.db.batch()
        activation.set(
            self.db.collection("harmony").document("canonical"),
            {
                "activeRevision": import_id,
                "activeTopicsPath": canonical_path,
                "topicCount": len(canonical_records),
                "referenceGrammarVersion": 2,
                "sourceLanguage": language,
                "updatedAt": firestore.SERVER_TIMESTAMP,
            },
            merge=True,
        )
        activation.set(
            self.db.collection("harmony_localizations").document(language),
            localization_metadata,
            merge=True,
        )
        activation.set(
            self.db.collection("admin_imports").document(import_id),
            {
                "status": "completed",
                "stage": "Completed",
                "recordsProcessed": len(canonical_records),
                "topicsProcessed": len(canonical_records),
                "referencesProcessed": logical_references,
                "physicalSegmentsProcessed": physical_segments,
                "destination": (
                    f"harmony/canonical + harmony_localizations/{language}"
                ),
                "canonicalTopicsPath": canonical_path,
                "localizationTopicsPath": localization_path,
                "completedAt": firestore.SERVER_TIMESTAMP,
                "updatedAt": firestore.SERVER_TIMESTAMP,
            },
            merge=True,
        )
        activation.commit()
        return {
            "destination": (
                f"harmony/canonical + harmony_localizations/{language}"
            ),
            "canonicalTopicsPath": canonical_path,
            "localizationTopicsPath": localization_path,
            "topicsProcessed": len(canonical_records),
            "referencesProcessed": logical_references,
            "physicalSegmentsProcessed": physical_segments,
        }

    def harmony_migration_report(self, trusted_dataset: str = "canonical") -> dict[str, Any]:
        if trusted_dataset == "canonical":
            trusted, trusted_source = self.load_canonical_topics(
                fallback_dataset_id="english_kjv"
            )
        else:
            trusted = self.load_topics(trusted_dataset)
            trusted_source = f"references/{trusted_dataset}"

        def signature(record: TopicRecord) -> tuple[tuple[Any, ...], ...]:
            return tuple(
                (
                    entry.get("book"),
                    entry.get("chapter"),
                    entry.get("verses"),
                    entry.get("separatorBefore", ""),
                )
                for entry in record.entries
            )

        trusted_signatures = {
            record.topic_id: signature(record)
            for record in trusted
        }
        datasets = []
        for reference_ref in self.db.collection("references").list_documents():
            records = self.load_topics(reference_ref.id)
            mismatches = []
            for record in records:
                actual = signature(record)
                if trusted_signatures.get(record.topic_id) != actual:
                    mismatches.append(record.topic_id)
            missing = sorted(
                set(trusted_signatures) - {record.topic_id for record in records},
                key=int,
            )
            additional = sorted(
                {record.topic_id for record in records} - set(trusted_signatures),
                key=int,
            )
            datasets.append(
                {
                    "id": reference_ref.id,
                    "topicCount": len(records),
                    "referenceMismatchCount": len(mismatches),
                    "firstReferenceMismatches": mismatches[:50],
                    "missingTopicIds": missing[:50],
                    "additionalTopicIds": additional[:50],
                    "matchesTrustedReferences": not mismatches and not missing and not additional,
                }
            )
        return {
            "trustedDataset": trusted_dataset,
            "trustedSource": trusted_source,
            "trustedTopicCount": len(trusted),
            "canonicalActive": self.canonical_topics_exist(),
            "datasets": datasets,
            "safeToAutoMigrate": bool(trusted)
            and all(item["matchesTrustedReferences"] for item in datasets),
        }

    def bible_version_exists(self, language: str, version: str) -> bool:
        version = self.resolve_version_id(language, version)
        language_ref = self.db.collection("bibles").document(language)
        version_meta = language_ref.collection("versions").document(version).get()
        if version_meta.exists and (version_meta.to_dict() or {}).get("activeBooksPath"):
            return True
        return next(language_ref.collection(version).list_documents(), None) is not None

    def resolve_version_id(self, language: str, version: str) -> str:
        requested = version.strip()
        normalized = requested.casefold()
        for existing in self.available_versions(language):
            if existing.casefold() == normalized:
                return existing
        return requested

    def available_versions(self, language: str) -> list[str]:
        language_ref = self.db.collection("bibles").document(language)
        versions: set[str] = set()
        snapshot = language_ref.get()
        if snapshot.exists:
            field = (snapshot.to_dict() or {}).get("versions")
            if isinstance(field, list):
                versions.update(str(value) for value in field if str(value).strip())
        for document in language_ref.collection("versions").list_documents():
            if document.id not in {"manifest", "_index"}:
                versions.add(document.id)
        for collection in language_ref.collections():
            if collection.id != "versions":
                versions.add(collection.id)
        return sorted(versions, key=str.casefold)

    def activate_topics(
        self,
        *,
        import_id: str,
        language: str,
        display_name: str,
        direction: str,
        records: list[TopicRecord],
        replace: bool,
    ) -> dict[str, Any]:
        dataset_id = self.resolve_reference_dataset_id(language)
        if self.topics_exist(dataset_id) and not replace:
            raise ImportCollisionError(
                f"A topic dataset for {language} already exists. Confirm replacement to continue."
            )
        revision_ref = self.db.collection("reference_revisions").document(import_id)
        topics_ref = revision_ref.collection("topics")
        revision_ref.set(
            {
                "language": language,
                "datasetId": dataset_id,
                "topicCount": len(records),
                "status": "writing",
                "createdAt": firestore.SERVER_TIMESTAMP,
            }
        )
        self._write_documents(
            (topics_ref.document(record.topic_id), record.to_firestore())
            for record in records
        )
        revision_ref.set(
            {"status": "ready", "completedAt": firestore.SERVER_TIMESTAMP},
            merge=True,
        )
        active_path = _subcollection_path(revision_ref, "topics")
        activation = self.db.batch()
        activation.set(
            self.db.collection("references").document(dataset_id),
            {
                "language": language,
                "label": display_name,
                "direction": direction,
                "activeRevision": import_id,
                "activeTopicsPath": active_path,
                "topicCount": len(records),
                "active": True,
                "updatedAt": firestore.SERVER_TIMESTAMP,
            },
            merge=True,
        )
        # This legacy writer is retained only for old clients that still call
        # /admin/topics. Topic-table metadata must not be copied into
        # bibles/{language}; Bible discovery and Harmony localization are now
        # independent dimensions.
        activation.set(
            self.db.collection("admin_imports").document(import_id),
            {
                "status": "completed",
                "stage": "Completed",
                "recordsProcessed": len(records),
                "topicsProcessed": len(records),
                "referencesProcessed": sum(
                    record.logical_reference_count for record in records
                ),
                "physicalSegmentsProcessed": sum(
                    record.physical_segment_count for record in records
                ),
                "destination": f"references/{dataset_id}",
                "activeTopicsPath": active_path,
                "completedAt": firestore.SERVER_TIMESTAMP,
                "updatedAt": firestore.SERVER_TIMESTAMP,
            },
            merge=True,
        )
        activation.commit()
        return {
            "datasetId": dataset_id,
            "destination": f"references/{dataset_id}",
            "activeTopicsPath": active_path,
            "topicsProcessed": len(records),
            "referencesProcessed": sum(
                record.logical_reference_count for record in records
            ),
            "physicalSegmentsProcessed": sum(
                record.physical_segment_count for record in records
            ),
        }

    def activate_bible(
        self,
        *,
        import_id: str,
        language: str,
        language_display_name: str,
        direction: str,
        version: str,
        version_display_name: str,
        description: str,
        related_translation: str | None,
        result: BibleParseResult,
        replace: bool,
        progress=None,
    ) -> dict[str, Any]:
        if self.bible_version_exists(language, version) and not replace:
            raise ImportCollisionError(
                f"Bible translation {language} / {version} already exists. Confirm replacement to continue."
            )
        revision_ref = self.db.collection("bible_revisions").document(import_id)
        books_ref = revision_ref.collection("books")
        stats = result.summary()["stats"]
        revision_ref.set(
            {
                "language": language,
                "version": version,
                "status": "writing",
                "createdAt": firestore.SERVER_TIMESTAMP,
                **stats,
            }
        )

        for book in result.books:
            if progress is not None:
                progress(book.name)
            writes: list[tuple[Any, dict[str, Any]]] = []
            book_ref = books_ref.document(book.name)
            writes.append(
                (
                    book_ref,
                    {
                        "code": book.code,
                        "name": book.name,
                        "chapterCount": book.chapter_count,
                        "verseCount": book.verse_count,
                    },
                )
            )
            for chapter, verses in book.chapters.items():
                chapter_ref = book_ref.collection("chapters").document(chapter)
                writes.append((chapter_ref, {"verseCount": len(verses)}))
                for verse in verses:
                    writes.append(
                        (
                            chapter_ref.collection("verses").document(verse.number),
                            verse.to_firestore(),
                        )
                    )
            self._write_documents(writes)
        revision_ref.set(
            {"status": "ready", "completedAt": firestore.SERVER_TIMESTAMP},
            merge=True,
        )

        active_path = _subcollection_path(revision_ref, "books")
        language_ref = self.db.collection("bibles").document(language)
        versions = set(self.available_versions(language))
        versions.add(version)
        activation = self.db.batch()
        activation.set(
            language_ref,
            {
                "id": language,
                "label": language_display_name,
                "direction": direction,
                "active": True,
                "versions": sorted(versions, key=str.casefold),
                "defaultVersion": version,
                "updatedAt": firestore.SERVER_TIMESTAMP,
            },
            merge=True,
        )
        activation.set(
            language_ref.collection("versions").document(version),
            {
                "id": version,
                "name": version_display_name,
                "label": version_display_name,
                "description": description,
                "active": True,
                "activeRevision": import_id,
                "activeBooksPath": active_path,
                "containsDiacritics": result.contains_diacritics,
                "relatedTranslation": related_translation,
                "bookCount": stats["books"],
                "chapterCount": stats["chapters"],
                "verseCount": stats["verses"],
                "updatedAt": firestore.SERVER_TIMESTAMP,
            },
            merge=True,
        )
        activation.set(
            self.db.collection("admin_imports").document(import_id),
            {
                "status": "completed",
                "stage": "Completed",
                "recordsProcessed": stats["verses"],
                "booksProcessed": stats["books"],
                "chaptersProcessed": stats["chapters"],
                "versesProcessed": stats["verses"],
                "destination": f"bibles/{language}/versions/{version}",
                "activeBooksPath": active_path,
                "completedAt": firestore.SERVER_TIMESTAMP,
                "updatedAt": firestore.SERVER_TIMESTAMP,
            },
            merge=True,
        )
        activation.commit()
        return {
            "destination": f"bibles/{language}/versions/{version}",
            "activeBooksPath": active_path,
            "booksProcessed": stats["books"],
            "chaptersProcessed": stats["chapters"],
            "versesProcessed": stats["verses"],
        }

    def overview(self) -> dict[str, Any]:
        bible_languages: list[dict[str, Any]] = []
        for language_ref in self.db.collection("bibles").list_documents():
            snapshot = language_ref.get()
            data = snapshot.to_dict() if snapshot.exists else {}
            versions = self.available_versions(language_ref.id)
            version_items: list[dict[str, Any]] = []
            for version in versions:
                version_snapshot = language_ref.collection("versions").document(version).get()
                version_data = version_snapshot.to_dict() if version_snapshot.exists else {}
                version_items.append(
                    {
                        "id": version,
                        "name": (version_data or {}).get("label", version),
                        "active": (version_data or {}).get("active", True),
                        "books": (version_data or {}).get("bookCount"),
                        "chapters": (version_data or {}).get("chapterCount"),
                        "verses": (version_data or {}).get("verseCount"),
                        "updatedAt": (version_data or {}).get("updatedAt"),
                    }
                )
            bible_languages.append(
                {
                    "id": language_ref.id,
                    "name": (data or {}).get("label", language_ref.id.title()),
                    "direction": (data or {}).get("direction", "rtl" if language_ref.id == "arabic" else "ltr"),
                    "versions": version_items,
                }
            )

        topic_languages: list[dict[str, Any]] = []
        legacy_topic_datasets: list[dict[str, Any]] = []
        localized_language_ids: set[str] = set()
        for localization_ref in self.db.collection(
            "harmony_localizations"
        ).list_documents():
            snapshot = localization_ref.get()
            data = snapshot.to_dict() if snapshot.exists else {}
            localized_language_ids.add(localization_ref.id)
            topic_languages.append(
                {
                    "id": localization_ref.id,
                    "language": localization_ref.id,
                    "name": (data or {}).get("label", localization_ref.id.title()),
                    "topics": (data or {}).get("topicCount", 0),
                    "direction": (data or {}).get("direction", "ltr"),
                    "gospels": (data or {}).get("gospels", {}),
                    "active": (data or {}).get("active", True),
                    "updatedAt": (data or {}).get("updatedAt"),
                    "source": "canonical-localization",
                }
            )
        for reference_ref in self.db.collection("references").list_documents():
            snapshot = reference_ref.get()
            data = snapshot.to_dict() if snapshot.exists else {}
            if data and data.get("topicCount") is not None:
                count = data.get("topicCount")
            else:
                count = sum(1 for _ in reference_ref.collection("topics").stream())
            legacy_topic_datasets.append(
                {
                    "id": reference_ref.id,
                    "language": (data or {}).get("language", reference_ref.id.split("_")[0]),
                    "name": (data or {}).get("label", reference_ref.id.replace("_", " ").title()),
                    "topics": count,
                    "active": (data or {}).get("active", True),
                    "updatedAt": (data or {}).get("updatedAt"),
                    "source": "legacy-duplicated-references",
                }
            )
        canonical_snapshot = self.db.collection("harmony").document("canonical").get()
        canonical_data = canonical_snapshot.to_dict() if canonical_snapshot.exists else {}
        recent = self.list_imports(limit=10)
        return {
            "counts": {
                "bibleLanguages": len(bible_languages),
                "bibleVersions": sum(len(item["versions"]) for item in bible_languages),
                "topicLanguages": len(topic_languages),
                "failedImports": sum(1 for item in recent if item.get("status") in {"failed", "validation_failed"}),
            },
            "bibleLanguages": bible_languages,
            "topicLanguages": topic_languages,
            "legacyTopicDatasets": legacy_topic_datasets,
            "harmony": {
                "canonicalActive": bool(
                    (canonical_data or {}).get("activeTopicsPath")
                ),
                "canonicalTopicCount": (canonical_data or {}).get("topicCount", 0),
                "localizationCount": len(localized_language_ids),
                "legacyDatasetCount": len(legacy_topic_datasets),
                "updatedAt": (canonical_data or {}).get("updatedAt"),
            },
            "recentImports": recent,
        }

    def _write_documents(
        self, writes: Iterable[tuple[Any, dict[str, Any]]]
    ) -> None:
        batch = self.db.batch()
        count = 0
        for document, payload in writes:
            batch.set(document, payload)
            count += 1
            if count == MAX_BATCH_WRITES:
                batch.commit()
                batch = self.db.batch()
                count = 0
        if count:
            batch.commit()
