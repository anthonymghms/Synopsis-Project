from __future__ import annotations

import mimetypes
import os
import posixpath
import re
import uuid
from datetime import datetime, timezone
from typing import Any, Iterable

import firebase_admin
from firebase_admin import credentials, firestore, storage

from .bible_import_service import BibleParseResult
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


class FirebaseImportRepository:
    def __init__(self, db=None, bucket=None):
        self.db = db or firestore_client()
        self.bucket = bucket or storage_bucket()

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
        prefix_parts = ["imports", "topics" if import_type == "topics" else "bibles", language]
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
        active_path = topics_ref.path
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
        activation.set(
            self.db.collection("bibles").document(language),
            {
                "id": language,
                "label": display_name,
                "direction": direction,
                "active": True,
                "hasTopics": True,
                "topicsDatasetId": dataset_id,
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
                    len(record.entries) for record in records
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
            "referencesProcessed": sum(len(record.entries) for record in records),
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

        active_path = books_ref.path
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
        for reference_ref in self.db.collection("references").list_documents():
            snapshot = reference_ref.get()
            data = snapshot.to_dict() if snapshot.exists else {}
            if data and data.get("topicCount") is not None:
                count = data.get("topicCount")
            else:
                count = sum(1 for _ in reference_ref.collection("topics").stream())
            topic_languages.append(
                {
                    "id": reference_ref.id,
                    "language": (data or {}).get("language", reference_ref.id.split("_")[0]),
                    "name": (data or {}).get("label", reference_ref.id.replace("_", " ").title()),
                    "topics": count,
                    "active": (data or {}).get("active", True),
                    "updatedAt": (data or {}).get("updatedAt"),
                }
            )
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
