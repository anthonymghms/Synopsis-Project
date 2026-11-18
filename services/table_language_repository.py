"""Atomic locale overlays referencing immutable canonical data, without copies."""
from __future__ import annotations

import hashlib
import json
from typing import Any

from firebase_admin import firestore

from .dataset_repository import DatasetRepository, DatasetRevisionConflict, SourceChangedError, MAX_DATASET_BYTES
from .firebase_service import ImportCollisionError, ImportRecordError, new_import_id
from .table_language_import_service import table_id, default_language_metadata


def _fingerprint(value) -> str:
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False, default=str).encode()).hexdigest()


def _data(ref, transaction=None):
    snapshot = ref.get(transaction=transaction) if transaction is not None else ref.get()
    return (snapshot.to_dict() or {}) if snapshot.exists else {}


def _harmony_overlay_state(target):
    # Other Harmony publishers merge metadata, so an old overlay signature can
    # survive a name edit or a legacy import. Only reuse it while the immutable
    # names pointer and the language metadata it described are still current.
    fields = ("activeRevision", "activeTopicsPath", "id", "label", "direction",
              "subjectsLabel", "gospels", "topicCount", "canonicalTopicCount",
              "complete", "active")
    return _fingerprint({key: target.get(key) for key in fields})


def _harmony_overlay_signature(target):
    return target.get("overlaySignature") if target.get("overlayStateToken") == _harmony_overlay_state(target) else None


class TableLanguageRepository(DatasetRepository):
    def _names(self, path):
        return {doc.id: str((doc.to_dict() or {}).get("name") or "") for doc in self.db.collection(path).stream()}

    def snapshot(self, selected_dataset: str, language: str) -> dict[str, Any]:
        selected_dataset = table_id(selected_dataset)
        if selected_dataset == "harmony":
            pointer = self.db.collection("harmony").document("canonical")
            master = _data(pointer)
            canonical_path = master.get("activeTopicsPath")
            if not canonical_path:
                raise ImportRecordError("Publish the canonical Harmony master before using the identity-based table-language template.")
            target = _data(self.db.collection("harmony_localizations").document(language))
            english = _data(self.db.collection("harmony_localizations").document("english"))
            arabic = _data(self.db.collection("harmony_localizations").document("arabic"))
            sources = self._names(english.get("activeTopicsPath") or "harmony_localizations/english/topics")
            fallback = self._names(arabic.get("activeTopicsPath") or "harmony_localizations/arabic/topics")
            translations = self._names(target.get("activeTopicsPath") or f"harmony_localizations/{language}/topics")
            items = []
            for doc in self.db.collection(canonical_path).stream():
                data = doc.to_dict() or {}
                items.append({"id": doc.id, "sourceName": sources.get(doc.id) or fallback.get(doc.id) or data.get("name") or f"#{doc.id}", "typeId": "", "canonicalOrder": data.get("canonicalOrder", int(doc.id) if doc.id.isdecimal() else 0)})
            revision = _fingerprint(master)
            base = {"canonicalToken": revision, "localizationToken": _fingerprint(target)}
            types = []
            metadata = {"languageMetadata": {language: target} if target else {}}
        else:
            metadata, ref = self._revision(selected_dataset)
            if ref is None:
                raise ImportRecordError("Publish the selected dataset before adding a table language.")
            revision = metadata["activeRevision"]
            canonical_path = metadata.get("canonicalTopicsPath") or f"{ref.path}/topics"
            # Pin the source view to the same snapshot if a concurrent publisher
            # advances the pointer while guidance names are being loaded.
            names_payload = self.localization_payload(selected_dataset, "english", revision)
            names = {item["id"]: item["name"] for item in names_payload["topics"]}
            canonical = self.canonical_payload(selected_dataset, revision)
            items = [{"id": item["id"], "sourceName": names.get(item["id"], f"#{item['id']}"), "typeId": item.get("typeId") or "", "canonicalOrder": item.get("canonicalOrder", 0)} for item in canonical["topics"]]
            target_path = metadata.get("localizationPaths", {}).get(language) or f"{ref.path}/localizations/{language}/topics"
            translations = self._names(target_path) if language in metadata.get("languages", []) else {}
            target = metadata.get("languageMetadata", {}).get(language, {})
            if language in metadata.get("languages", []) and not target:
                target = default_language_metadata(language, len(translations))
            base = {"canonicalToken": canonical_path, "datasetRevision": revision}
            types = metadata.get("types", [])
        items.sort(key=lambda item: (item["canonicalOrder"], item["id"]))
        if not items:
            raise ImportRecordError("The selected dataset has no published items to translate.")
        return {"datasetId": selected_dataset, "revision": revision, "base": base, "canonicalPath": canonical_path,
                "items": items, "types": types, "translations": translations,
                "replacesExisting": bool(translations or target), "languageMetadata": target or default_language_metadata(language, 0), "metadata": metadata}

    def stage_language_upload(self, selected_dataset, language, import_id, filename, raw):
        if len(raw) > MAX_DATASET_BYTES:
            raise ValueError("Language CSV files must be 16 MiB or smaller.")
        path = f"imports/table_languages/{table_id(selected_dataset)}/{language}/{import_id}/{filename}"
        blob = self.bucket.blob(path)
        blob.upload_from_string(raw, content_type="text/csv", if_generation_match=0)
        blob.reload()
        return {"path": path, "filename": filename, "generation": str(blob.generation), "checksum": hashlib.sha256(raw).hexdigest()}

    def checked_language_source(self, record):
        source = record.get("source") or {}
        prefix = f"imports/table_languages/{table_id(record['datasetId'])}/{record['language']}/{record['id']}/"
        path = str(source.get("path") or "")
        if not path.startswith(prefix) or "/" in path[len(prefix):] or not path[len(prefix):]:
            raise ImportRecordError("The language upload path is invalid.")
        try:
            raw, details = self.read_source(path)
        except Exception as exc:
            raise SourceChangedError("The staged source is unavailable or changed. Validate it again.") from exc
        if details["generation"] != source.get("generation") or details["checksum"] != source.get("checksum"):
            raise SourceChangedError("The source changed after preview. Validate it again.")
        return raw

    def activate_language(self, *, import_id, selected_dataset, language, result, metadata, expected_base, source, replace, confirmed_by, source_validator):
        selected_dataset = table_id(selected_dataset)
        if not result.report.valid:
            raise ImportRecordError("Only a valid full language overlay can be published.")
        current = self.snapshot(selected_dataset, language)
        signature = _fingerprint({"canonical": expected_base["canonicalToken"], "metadata": metadata, "names": {row["id"]: row["translation"] for row in result.records}, "types": result.type_labels})
        locale_ref = self.db.collection("harmony_localizations").document(language)
        old_signature = (_harmony_overlay_signature(current["languageMetadata"]) if selected_dataset == "harmony" else current["metadata"].get("languageSignatures", {}).get(language))
        unchanged = old_signature == signature
        if current["base"]["canonicalToken"] != expected_base["canonicalToken"]:
            raise DatasetRevisionConflict("The canonical table changed after preview. Download its current template and validate again.")
        if not unchanged and current["base"] != expected_base:
            raise DatasetRevisionConflict("The table or target language changed after preview. Download a current template and validate again.")
        if current["replacesExisting"] and not replace:
            raise ImportCollisionError("Confirm replacement of the selected table language.")
        revision_id = new_import_id()
        if selected_dataset == "harmony":
            localization_ref = self.db.collection("harmony_localization_revisions").document(revision_id)
        else:
            localization_ref = self.db.collection("dataset_localization_revisions").document(f"{selected_dataset}--{revision_id}")
        localization_path = f"{localization_ref.path}/topics"
        revision_meta = None
        if not unchanged:
            localization_ref.set({"datasetId": selected_dataset, "language": language, "status": "writing", "createdAt": firestore.SERVER_TIMESTAMP, "sourceChecksum": source["checksum"]})
            self._write_documents((localization_ref.collection("topics").document(row["id"]), {"name": row["translation"], "canonicalOrder": row["canonicalOrder"]}) for row in result.records)
            localization_ref.set({"status": "ready", "completedAt": firestore.SERVER_TIMESTAMP}, merge=True)
            if selected_dataset != "harmony":
                old = current["metadata"]
                paths = {code: old.get("localizationPaths", {}).get(code) or f"dataset_revisions/{old['activeRevision']}/localizations/{code}/topics" for code in old.get("languages", [])}
                paths[language] = localization_path
                types = [{**item, "labels": {**item.get("labels", {}), **({language: result.type_labels[item['id']]} if item['id'] in result.type_labels else {})}} for item in old.get("types", [])]
                revision_id = f"{selected_dataset}--{new_import_id()}"
                revision_meta = {**old, "activeRevision": revision_id, "canonicalTopicsPath": current["canonicalPath"], "activeTopicsPath": current["canonicalPath"],
                                 "localizationPaths": paths, "languages": list(dict.fromkeys([*old.get("languages", []), language])),
                                 "languageMetadata": {**{code: default_language_metadata(code, old.get("itemCount", 0)) for code in old.get("languages", [])}, **old.get("languageMetadata", {}), language: metadata},
                                 "languageSignatures": {**old.get("languageSignatures", {}), language: signature}, "types": types,
                                 "status": "ready", "updatedAt": firestore.SERVER_TIMESTAMP, "createdAt": firestore.SERVER_TIMESTAMP}
                self.db.collection("dataset_revisions").document(revision_id).set(revision_meta)
        source_validator()
        import_ref = self.db.collection("admin_imports").document(import_id)
        pointer = self.db.collection("harmony").document("canonical") if selected_dataset == "harmony" else self.db.collection("datasets").document(selected_dataset)
        @firestore.transactional
        def activate(transaction):
            active = _data(pointer, transaction)
            target = _data(locale_ref, transaction) if selected_dataset == "harmony" else active
            active_signature = _harmony_overlay_signature(target) if selected_dataset == "harmony" else target.get("languageSignatures", {}).get(language)
            actual_canonical = _fingerprint(active) if selected_dataset == "harmony" else active.get("canonicalTopicsPath") or f"dataset_revisions/{active.get('activeRevision')}/topics"
            if actual_canonical != expected_base["canonicalToken"]:
                raise DatasetRevisionConflict("The canonical table changed during publication. Revalidate.")
            no_change = active_signature == signature
            if not no_change:
                actual_base = {"canonicalToken": _fingerprint(active), "localizationToken": _fingerprint(target)} if selected_dataset == "harmony" else {"canonicalToken": active.get("canonicalTopicsPath") or f"dataset_revisions/{active.get('activeRevision')}/topics", "datasetRevision": active.get("activeRevision")}
                if actual_base != expected_base:
                    raise DatasetRevisionConflict("The table or language changed while publication was staged. Revalidate before publishing.")
                if unchanged:
                    raise DatasetRevisionConflict("The target language changed during publication. Revalidate.")
                if selected_dataset == "harmony":
                    locale_metadata = {**metadata, "language": language, "activeRevision": revision_id, "activeTopicsPath": localization_path, "canonicalSource": "harmony/canonical", "overlaySignature": signature, "sourceChecksum": source["checksum"], "updatedAt": firestore.SERVER_TIMESTAMP}
                    locale_metadata["overlayStateToken"] = _harmony_overlay_state(locale_metadata)
                    transaction.set(locale_ref, locale_metadata, merge=True)
                else:
                    transaction.set(pointer, revision_meta)
            active_revision = (target.get("activeRevision") if selected_dataset == "harmony" else active.get("activeRevision")) if no_change else revision_id
            outcome = {"datasetId": selected_dataset, "language": language, "revision": active_revision, "revisionId": active_revision, "unchanged": no_change, "itemsProcessed": len(result.records)}
            transaction.set(import_ref, {**outcome, "status": "completed", "stage": "Completed", "confirmedBy": confirmed_by, "recordsProcessed": len(result.records), "destination": f"harmony_localizations/{language}" if selected_dataset == "harmony" else f"datasets/{selected_dataset}/languages/{language}", "completedAt": firestore.SERVER_TIMESTAMP, "updatedAt": firestore.SERVER_TIMESTAMP}, merge=True)
            return outcome
        return activate(self.db.transaction())
