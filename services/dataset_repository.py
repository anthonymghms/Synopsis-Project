"""Versioned tables in Firestore, separate from Harmony and Bible collections."""
from __future__ import annotations

import hashlib
import re
from typing import Any

from firebase_admin import firestore

from .dataset_import_service import DATASET_FILES, DATASET_LABELS, GOSPEL_LABELS, dataset_id
from .firebase_service import FirebaseImportRepository, ImportCollisionError, ImportRecordError, firestore_client, storage_bucket, new_import_id

MAX_DATASET_BYTES = 16 * 1024 * 1024


class SourceChangedError(ImportRecordError):
    pass


class DatasetRevisionConflict(ImportCollisionError):
    pass


class DatasetRepository(FirebaseImportRepository):
    def __init__(self, db=None, bucket=None):
        self.db = db if db is not None else firestore_client()
        self._bucket = bucket
        self._chapter_count_cache = {}

    @property
    def bucket(self):
        if self._bucket is None:
            self._bucket = storage_bucket()
        return self._bucket

    def metadata(self, selected_dataset: str) -> dict[str, Any]:
        selected_dataset = dataset_id(selected_dataset)
        snapshot = self.db.collection("datasets").document(selected_dataset).get()
        data = snapshot.to_dict() or {} if snapshot.exists else {}
        return {"datasetId": selected_dataset, "labels": DATASET_LABELS[selected_dataset], **data}

    def storage_sources(self) -> list[dict[str, Any]]:
        sources = []
        for selected_dataset, filename in DATASET_FILES.items():
            item = {"datasetId": selected_dataset, "filename": filename}
            try:
                blob = self.bucket.blob(filename)
                blob.reload()
                item.update(available=True, generation=str(blob.generation), size=blob.size)
            except Exception:
                # No bucket enumeration, arbitrary paths, signed URLs, or backend
                # credentials are exposed through the administrative picker.
                item.update(available=False, error="The configured backend cannot read this Storage file.")
            sources.append(item)
        return sources

    def read_source(self, path: str) -> tuple[bytes, dict[str, Any]]:
        blob = self.bucket.blob(path)
        blob.reload()
        if blob.size is not None and blob.size > MAX_DATASET_BYTES:
            raise ValueError("Dataset files must be 16 MB or smaller.")
        generation = str(blob.generation)
        raw = blob.download_as_bytes(if_generation_match=int(generation))
        if len(raw) > MAX_DATASET_BYTES:
            raise ValueError("Dataset files must be 16 MB or smaller.")
        return raw, {"path": path, "generation": generation, "checksum": hashlib.sha256(raw).hexdigest(), "size": len(raw)}

    def read_storage_source(self, selected_dataset: str, filename: str):
        selected_dataset = dataset_id(selected_dataset)
        if filename != DATASET_FILES[selected_dataset]:
            raise ValueError("Choose the permitted source file for the selected dataset.")
        return self.read_source(filename)

    def checked_source(self, record: dict[str, Any]) -> bytes:
        source = record.get("source") or {}
        selected_dataset = dataset_id(record.get("datasetId"))
        path = str(source.get("path") or "")
        if source.get("kind") == "storage":
            if path != DATASET_FILES[selected_dataset]:
                raise ImportRecordError("This import does not reference a permitted Storage file.")
        elif source.get("kind") == "upload":
            expected = f"imports/datasets/{selected_dataset}/{record['id']}/"
            if not path.startswith(expected) or "/" in path[len(expected):]:
                raise ImportRecordError("The staged upload path is invalid.")
        else:
            raise ImportRecordError("The staged source is missing.")
        try:
            raw, current = self.read_source(path)
        except Exception as exc:
            raise SourceChangedError("The source is unavailable or changed. Validate it again before publishing.") from exc
        if current["generation"] != source.get("generation") or current["checksum"] != source.get("checksum"):
            raise SourceChangedError("The source changed after preview. Validate it again before publishing.")
        return raw

    def stage_upload(self, selected_dataset: str, import_id: str, filename: str, raw: bytes):
        if len(raw) > MAX_DATASET_BYTES:
            raise ValueError("Dataset files must be 16 MB or smaller.")
        path = f"imports/datasets/{dataset_id(selected_dataset)}/{import_id}/{filename}"
        blob = self.bucket.blob(path)
        blob.upload_from_string(raw, content_type="text/csv", if_generation_match=0)
        # Read server metadata after upload; publication checks both generation
        # and SHA-256 against this exact previewed source.
        blob.reload()
        return {"kind": "upload", "path": path, "generation": str(blob.generation), "checksum": hashlib.sha256(raw).hexdigest(), "size": len(raw)}

    def record_failed_attempt(self, import_id: str, **fields):
        """A failed concurrent retry must not erase another attempt's success."""
        ref = self.db.collection("admin_imports").document(import_id)
        @firestore.transactional
        def record(transaction):
            snapshot = ref.get(transaction=transaction)
            current = snapshot.to_dict() or {} if snapshot.exists else {}
            if current.get("status") != "completed":
                transaction.set(ref, {**fields, "updatedAt": firestore.SERVER_TIMESTAMP}, merge=True)
        record(self.db.transaction())

    def activate_dataset(self, *, import_id: str, selected_dataset: str, result, source: dict, expected_revision: str | None, replace: bool, confirmed_by: str, source_validator=None) -> dict[str, Any]:
        selected_dataset = dataset_id(selected_dataset)
        if not result.report.valid:
            raise ImportRecordError("Only a successfully validated dataset can be published.")
        current = self.metadata(selected_dataset)
        checksum = source["checksum"]
        if current.get("activeRevision") and not replace and current.get("sourceChecksum") != checksum:
            raise ImportCollisionError("Confirm replacement of the existing dataset before publishing.")
        if current.get("activeRevision") != expected_revision and current.get("sourceChecksum") != checksum:
            raise DatasetRevisionConflict("The published dataset changed since preview. Validate again before publishing.")
        # Every attempt gets an immutable path. Concurrent publication of the
        # same import must never rewrite a revision another request activated.
        revision_id = f"{selected_dataset}--{new_import_id()}"
        revision_ref = self.db.collection("dataset_revisions").document(revision_id)
        summary = result.summary()
        metadata = {
            "datasetId": selected_dataset, "labels": DATASET_LABELS[selected_dataset],
            "itemCount": len(result.records), "topicCount": len(result.records),
            "languages": result.languages, "types": result.types,
            "hasTypes": bool(result.types), "hasTypeColumn": result.has_type_column,
            "sourceChecksum": checksum, "sourceFilename": source.get("filename"),
            "sourceGeneration": source.get("generation"),
            "encoding": result.encoding, "header": result.header,
            "delimiter": result.delimiter, "stats": summary["stats"],
        }
        if current.get("sourceChecksum") != checksum:
            revision_ref.set({**metadata, "status": "writing", "createdAt": firestore.SERVER_TIMESTAMP})
            writes = []
            for item in result.records:
                writes.append((revision_ref.collection("topics").document(item.item_id), item.canonical()))
                for language, name in item.names.items():
                    writes.append((revision_ref.collection("localizations").document(language).collection("topics").document(item.item_id), {"name": name, "canonicalOrder": item.source_order}))
            self._write_documents(writes)
            revision_ref.set({"status": "ready", "completedAt": firestore.SERVER_TIMESTAMP}, merge=True)
        if source_validator is not None:
            source_validator()
        pointer = self.db.collection("datasets").document(selected_dataset)
        import_ref = self.db.collection("admin_imports").document(import_id)

        @firestore.transactional
        def activate(transaction):
            snapshot = pointer.get(transaction=transaction)
            active = snapshot.to_dict() or {} if snapshot.exists else {}
            if active.get("sourceChecksum") == checksum:
                # Identical sources never create duplicate rows or replace the
                # published revision, even after a fresh validation attempt.
                outcome = {"datasetId": selected_dataset, "revision": active["activeRevision"], "revisionId": active["activeRevision"], "unchanged": True, "itemsProcessed": len(result.records)}
            else:
                if active.get("activeRevision") != expected_revision:
                    raise DatasetRevisionConflict("The published dataset changed since preview. Validate again before publishing.")
                if active.get("activeRevision") and not replace:
                    raise ImportCollisionError("Explicit replacement confirmation is required.")
                transaction.set(pointer, {**metadata, "activeRevision": revision_id, "activeTopicsPath": f"{revision_ref.path}/topics", "active": True, "updatedAt": firestore.SERVER_TIMESTAMP})
                outcome = {"datasetId": selected_dataset, "revision": revision_id, "revisionId": revision_id, "unchanged": False, "itemsProcessed": len(result.records)}
            transaction.set(import_ref, {**outcome, "status": "completed", "stage": "Completed", "confirmedBy": confirmed_by, "recordsProcessed": len(result.records), "topicsProcessed": len(result.records), "referencesProcessed": summary["stats"]["references"], "destination": f"datasets/{selected_dataset}", "completedAt": firestore.SERVER_TIMESTAMP, "updatedAt": firestore.SERVER_TIMESTAMP}, merge=True)
            return outcome

        return activate(self.db.transaction())

    def _revision(self, selected_dataset: str, revision: str | None = None):
        selected_dataset = dataset_id(selected_dataset)
        metadata = self.metadata(selected_dataset)
        revision = revision or metadata.get("activeRevision")
        if not revision:
            return metadata, None
        if not re.fullmatch(rf"{selected_dataset}--[a-f0-9]{{32}}", revision):
            raise ValueError("Invalid dataset revision.")
        ref = self.db.collection("dataset_revisions").document(revision)
        snapshot = ref.get()
        data = snapshot.to_dict() or {} if snapshot.exists else {}
        if data.get("datasetId") != selected_dataset or data.get("status") != "ready":
            raise ImportRecordError("The dataset revision is unavailable.")
        return {**data, "activeRevision": revision, "labels": DATASET_LABELS[selected_dataset]}, ref

    def canonical_payload(self, selected_dataset: str, revision: str | None = None):
        metadata, ref = self._revision(selected_dataset, revision)
        topics = []
        if ref is not None:
            for document in ref.collection("topics").stream():
                data = document.to_dict() or {}
                topics.append({"id": document.id, "datasetId": selected_dataset, **data, "references": data.get("entries", [])})
            topics.sort(key=lambda item: (item.get("sourceOrder", 0), item["id"]))
        return {"datasetId": selected_dataset, "revision": metadata.get("activeRevision"), "source": f"datasets/{selected_dataset}", "published": ref is not None, "metadata": metadata, "topics": topics}

    def localization_payload(self, selected_dataset: str, language: str, revision: str | None = None):
        language = {"en": "english", "ar": "arabic"}.get(language, language)
        metadata, ref = self._revision(selected_dataset, revision)
        available = metadata.get("languages", [])
        ordered_languages = list(dict.fromkeys([language, "english", *available]))
        names = {}
        if ref is not None:
            for candidate in ordered_languages:
                if candidate not in available:
                    continue
                for doc in ref.collection("localizations").document(candidate).collection("topics").stream():
                    data = doc.to_dict() or {}
                    if data.get("name") and doc.id not in names:
                        names[doc.id] = {"id": doc.id, "name": data["name"], "canonicalOrder": data.get("canonicalOrder", 0), "nameLanguage": candidate, "fallback": candidate != language}
        topics = sorted(names.values(), key=lambda item: (item["canonicalOrder"], item["id"]))
        types = metadata.get("types", [])
        # Only mark labels as localized when actually imported in that language.
        # Canonical metadata retains source labels for explicit client fallback.
        type_labels = {value["id"]: value["labels"][language] for value in types if value.get("labels", {}).get(language)}
        return {"datasetId": selected_dataset, "revision": metadata.get("activeRevision"), "typeLabels": type_labels,
                "language": {"id": language, "label": "العربية" if language == "arabic" else language.title(), "direction": "rtl" if language == "arabic" else "ltr", "gospels": GOSPEL_LABELS.get(language, GOSPEL_LABELS["english"]), "active": True, "topicCount": len(topics), "canonicalSource": f"datasets/{selected_dataset}", "canonicalTopicCount": metadata.get("itemCount", 0), "complete": bool(topics) and all(not item["fallback"] for item in topics)}, "topics": topics}

    def localized_topics(self, selected_dataset: str, language: str):
        canonical = self.canonical_payload(selected_dataset)
        localization = self.localization_payload(selected_dataset, language, canonical["revision"])
        names = {item["id"]: item for item in localization["topics"]}
        for item in canonical["topics"]:
            name = names.get(item["id"], {})
            item.update(name=name.get("name", f"#{item['id']}"), nameLanguage=name.get("nameLanguage"), nameFallback=name.get("fallback", True))
        return canonical
