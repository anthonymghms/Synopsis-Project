"""Administrator content editing with immutable revisions and atomic activation.

Topic edits clone the small localization table. Bible edits clone just one chapter,
then atomically point that translation at it. Original imports are never changed.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import uuid
from typing import Any

from firebase_admin import firestore

from .firebase_service import firestore_client
from .bible_text_service import extract_verse_text
from .topic_import_service import GOSPELS, records_from_firestore


class ContentNotFoundError(ValueError):
    pass


class ContentConflictError(ValueError):
    pass


def _data(snapshot) -> dict[str, Any]:
    return (snapshot.to_dict() or {}) if snapshot.exists else {}


def _snapshot_token(snapshot) -> str:
    value = {"exists": snapshot.exists, "data": _data(snapshot),
             "updated": str(getattr(snapshot, "update_time", ""))}
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False, default=str).encode()).hexdigest()


def _revision(snapshots) -> str:
    return hashlib.sha256("|".join(_snapshot_token(s) for s in snapshots).encode()).hexdigest()


def _require_revision(value: Any, snapshots) -> None:
    if not isinstance(value, str) or not re.fullmatch(r"[a-f0-9]{64}", value):
        raise ValueError("Load the editor before saving; its revision is required.")
    if value != _revision(snapshots):
        raise ContentConflictError("This content changed after you opened it. Reload the editor before saving.")


def _text(value: Any, name: str, limit: int, *, required: bool = True) -> str:
    if not isinstance(value, str):
        raise ValueError(f"{name} must be text.")
    value = value.strip()
    if required and not value:
        raise ValueError(f"{name} is required.")
    if len(value) > limit:
        raise ValueError(f"{name} must be {limit} characters or fewer.")
    if any(ord(c) < 32 and c not in "\n\t" for c in value):
        raise ValueError(f"{name} contains unsupported control characters.")
    return value


def _direction(value: Any) -> str:
    if not isinstance(value, str) or value not in {"ltr", "rtl"}:
        raise ValueError("Text direction must be ltr or rtl.")
    return value


def _sort_id(value: str):
    return (0, int(value)) if value.isdigit() else (1, value.casefold())


def chapter_override_key(book: str, chapter: str) -> str:
    # Hashing keeps legacy book names containing spaces/dots safe as map keys.
    return hashlib.sha256(f"{book}\0{chapter}".encode()).hexdigest()


def bible_verses_collection(db, language: str, version: str, book: str, chapter: str):
    language_ref = db.collection("bibles").document(language)
    metadata = _data(language_ref.collection("versions").document(version).get())
    overrides = metadata.get("chapterOverrides") or {}
    override = overrides.get(chapter_override_key(book, str(chapter))) if isinstance(overrides, dict) else None
    if isinstance(override, str) and override.startswith("bible_chapter_revisions/"):
        return db.collection(override)
    path = metadata.get("activeBooksPath")
    books = db.collection(path) if isinstance(path, str) and path else language_ref.collection(version)
    return books.document(book).collection("chapters").document(str(chapter)).collection("verses")


class AdminContentRepository:
    def __init__(self, db=None):
        self.db = db or firestore_client()

    def _write_documents(self, writes):
        batch = self.db.batch()
        count = 0
        for reference, fields in writes:
            batch.set(reference, fields)
            count += 1
            if count == 400:
                batch.commit()
                batch = self.db.batch()
                count = 0
        if count:
            batch.commit()

    def _activate(self, guards, writes, audit):
        """Compare every read token again inside the same transaction as activation."""
        @firestore.transactional
        def activate(transaction):
            for reference, expected in guards:
                current = reference.get(transaction=transaction)
                if _snapshot_token(current) != _snapshot_token(expected):
                    raise ContentConflictError("This content changed while saving. Reload the editor before saving.")
            for reference, fields in writes:
                # Explicit top-level merge masks replace maps instead of recursively
                # retaining deleted keys (notably headings and chapter overrides).
                transaction.set(reference, fields, merge=list(fields))
            transaction.set(self.db.collection("admin_content_edits").document(audit["id"]), audit)
        activate(self.db.transaction())

    def _topic_state(self, language):
        ref = self.db.collection("harmony_localizations").document(language)
        snapshot = ref.get()
        metadata = _data(snapshot)
        legacy = False
        if not snapshot.exists:
            # Support existing installations whose language rows predate canonical
            # Harmony localizations, including identifiers such as english_kjv.
            candidates = list(self.db.collection("references").list_documents())
            candidates.sort(key=lambda item: (item.id != language, len(item.id), item.id))
            ref = next((item for item in candidates if item.id == language or item.id.startswith(language + "_")), None)
            if ref is None:
                raise ContentNotFoundError("Topic language not found.")
            snapshot = ref.get()
            metadata = _data(snapshot)
            legacy = True
        path = metadata.get("activeTopicsPath") or f"{ref.path}/topics"
        rows = {s.id: _data(s) for s in self.db.collection(path).stream()}
        if not rows:
            raise ContentNotFoundError("This topic language has no imported topics to edit.")
        guards = [(ref, snapshot)]
        if legacy:
            canonical = records_from_firestore(self.db.collection(path).stream())
        else:
            canonical_ref = self.db.collection("harmony").document("canonical")
            canonical_snapshot = canonical_ref.get()
            guards.append((canonical_ref, canonical_snapshot))
            canonical_path = _data(canonical_snapshot).get("activeTopicsPath") or "harmony/canonical/topics"
            canonical = records_from_firestore(self.db.collection(canonical_path).stream())
            if not canonical:
                source = metadata.get("canonicalSource") or "references/" + os.environ.get("HARMONY_CANONICAL_FALLBACK", "english_kjv")
                match = re.fullmatch(r"references/([A-Za-z0-9_-]{1,80})", source)
                if match:
                    source_ref = self.db.collection("references").document(match.group(1))
                    source_snapshot = source_ref.get()
                    guards.append((source_ref, source_snapshot))
                    source_path = _data(source_snapshot).get("activeTopicsPath") or f"{source_ref.path}/topics"
                    canonical = records_from_firestore(self.db.collection(source_path).stream())
        previews = {r.topic_id: r.to_preview()["references"] for r in canonical}
        return ref, metadata, rows, guards, previews, legacy, path

    def topics(self, language):
        ref, metadata, rows, guards, previews, legacy, _ = self._topic_state(language)
        return {"language": language, "source": "legacy" if legacy else "canonical-localization",
                "revision": _revision([s for _, s in guards]),
                "metadata": {"displayName": metadata.get("label") or language.replace("_", " ").title(),
                             "direction": metadata.get("direction") or ("rtl" if language.startswith("arabic") else "ltr"),
                             "gospels": metadata.get("gospels") or {b: b for b in GOSPELS}},
                "topics": [{"id": topic_id, "name": str(rows[topic_id].get("name") or ""),
                            "references": previews.get(topic_id, {b: "" for b in GOSPELS})}
                           for topic_id in sorted(rows, key=_sort_id)]}

    def save_topics(self, language, payload, actor):
        ref, metadata, rows, guards, _, legacy, old_path = self._topic_state(language)
        _require_revision(payload.get("revision"), [s for _, s in guards])
        proposed = payload.get("metadata", {})
        if not isinstance(proposed, dict) or set(proposed) - {"displayName", "direction", "gospels"}:
            raise ValueError("Topic metadata may contain displayName, direction, and gospels only.")
        fields = {}
        if "displayName" in proposed:
            fields["label"] = _text(proposed["displayName"], "Language display name", 120)
        if "direction" in proposed:
            fields["direction"] = _direction(proposed["direction"])
        if "gospels" in proposed:
            if not isinstance(proposed["gospels"], dict) or set(proposed["gospels"]) != set(GOSPELS):
                raise ValueError("Provide a display name for each of the four Gospels.")
            fields["gospels"] = {b: _text(proposed["gospels"][b], b, 120) for b in GOSPELS}
        updates = payload.get("topics", [])
        if not isinstance(updates, list) or len(updates) > len(rows):
            raise ValueError("Topics must be a list of existing topic names.")
        changed = []
        seen = set()
        for row in updates:
            if not isinstance(row, dict) or set(row) - {"id", "name"}:
                raise ValueError("Only a topic's id and name may be edited; canonical references are shared by every language.")
            identifier = row.get("id")
            if not isinstance(identifier, str) or identifier not in rows or identifier in seen:
                raise ValueError("Each topic must refer to a unique existing topic identifier.")
            seen.add(identifier)
            name = _text(row.get("name"), "Topic name", 1000)
            if name != rows[identifier].get("name"):
                changed.append(identifier)
                rows[identifier] = {**rows[identifier], "name": name}
        if not changed and all(metadata.get(k) == v for k, v in fields.items()):
            return self.topics(language)
        edit_id = uuid.uuid4().hex
        revision_ref = self.db.collection("reference_revisions" if legacy else "harmony_localization_revisions").document(edit_id)
        new_path = f"{revision_ref.path}/topics"
        revision_ref.set({"language": language, "topicCount": len(rows), "status": "writing",
                          "source": "admin_editor", "createdBy": actor, "createdAt": firestore.SERVER_TIMESTAMP})
        self._write_documents((revision_ref.collection("topics").document(k), v) for k, v in rows.items())
        revision_ref.set({"status": "ready"}, merge=True)
        before_metadata = {k: metadata.get(k) for k in fields}
        after_metadata = dict(fields)
        fields.update({"activeRevision": edit_id, "activeTopicsPath": new_path, "topicCount": len(rows),
                       "updatedAt": firestore.SERVER_TIMESTAMP})
        self._activate(guards, [(ref, fields)], {
            "id": edit_id, "type": "topic_edit", "language": language, "actorUid": actor,
            "createdAt": firestore.SERVER_TIMESTAMP, "destination": ref.path, "changedTopicIds": changed,
            "previousTopicsPath": old_path, "activeTopicsPath": new_path,
            "metadataBefore": before_metadata, "metadataAfter": after_metadata,
        })
        return self.topics(language)

    def _bible_state(self, language, version):
        language_ref = self.db.collection("bibles").document(language)
        language_snapshot = language_ref.get()
        version_ref = language_ref.collection("versions").document(version)
        version_snapshot = version_ref.get()
        metadata = _data(version_snapshot)
        path = metadata.get("activeBooksPath")
        books = self.db.collection(path) if isinstance(path, str) and path else language_ref.collection(version)
        if not version_snapshot.exists and not next(books.limit(1).stream(), None) and not next(books.list_documents(), None):
            raise ContentNotFoundError("Bible translation not found.")
        return language_ref, version_ref, language_snapshot, version_snapshot, books

    def bible(self, language, version):
        _, _, language_snapshot, version_snapshot, books_ref = self._bible_state(language, version)
        language_data, metadata = _data(language_snapshot), _data(version_snapshot)
        books = [{"id": book.id,
                  "chapters": sorted([c.id for c in book.collection("chapters").list_documents()], key=_sort_id)}
                 for book in books_ref.list_documents()]
        books.sort(key=lambda b: (list(GOSPELS).index(b["id"]) if b["id"] in GOSPELS else 4, b["id"]))
        return {"language": language, "version": version, "revision": _revision([language_snapshot, version_snapshot]),
                "metadata": {"languageDisplayName": language_data.get("label") or language.title(),
                             "direction": language_data.get("direction") or ("rtl" if language.startswith("arabic") else "ltr"),
                             "displayName": metadata.get("label") or metadata.get("name") or version,
                             "description": metadata.get("description") or "",
                             "containsDiacritics": metadata.get("containsDiacritics") is True,
                             "relatedTranslation": metadata.get("relatedTranslation") or "",
                             "standalone": language_data.get("standalone") is True}, "books": books}

    def save_bible(self, language, version, payload, actor):
        language_ref, version_ref, language_snapshot, version_snapshot, _ = self._bible_state(language, version)
        _require_revision(payload.get("revision"), [language_snapshot, version_snapshot])
        proposed = payload.get("metadata")
        if not isinstance(proposed, dict) or set(proposed) - {"languageDisplayName", "direction", "displayName", "description", "containsDiacritics", "relatedTranslation"}:
            raise ValueError("Provide valid Bible translation metadata.")
        language_fields, version_fields = {}, {}
        if "languageDisplayName" in proposed:
            language_fields["label"] = _text(proposed["languageDisplayName"], "Language display name", 120)
        if "direction" in proposed:
            language_fields["direction"] = _direction(proposed["direction"])
        if "displayName" in proposed:
            version_fields["label"] = _text(proposed["displayName"], "Translation display name", 160)
            version_fields["name"] = version_fields["label"]
        if "description" in proposed:
            version_fields["description"] = _text(proposed["description"], "Description", 2000, required=False)
        if "containsDiacritics" in proposed:
            if not isinstance(proposed["containsDiacritics"], bool):
                raise ValueError("Contains diacritics must be true or false.")
            version_fields["containsDiacritics"] = proposed["containsDiacritics"]
        if "relatedTranslation" in proposed:
            related = _text(proposed["relatedTranslation"], "Related translation", 80, required=False)
            if related:
                if related.casefold() == version.casefold():
                    raise ValueError("A translation cannot relate to itself.")
                if _data(language_snapshot).get("standalone") is True:
                    raise ValueError("A standalone translation cannot relate to another translation.")
                self._bible_state(language, related)
            version_fields["relatedTranslation"] = related or None
        if _data(language_snapshot).get("standalone") is True and "label" in version_fields:
            language_fields["label"] = version_fields["label"]
        if not language_fields and not version_fields:            raise ValueError("Provide at least one metadata field to update.")
        edit_id = uuid.uuid4().hex
        audit = {"id": edit_id, "type": "bible_metadata_edit", "language": language, "version": version,
                 "actorUid": actor, "createdAt": firestore.SERVER_TIMESTAMP,
                 "metadataBefore": {"language": {k: _data(language_snapshot).get(k) for k in language_fields},
                                    "version": {k: _data(version_snapshot).get(k) for k in version_fields}},
                 "metadataAfter": {"language": dict(language_fields), "version": dict(version_fields)}}
        writes = []
        for ref, fields in [(language_ref, language_fields), (version_ref, version_fields)]:
            if fields:
                fields["updatedAt"] = firestore.SERVER_TIMESTAMP
                writes.append((ref, fields))
        self._activate([(language_ref, language_snapshot), (version_ref, version_snapshot)], writes, audit)
        return self.bible(language, version)

    def _chapter_state(self, language, version, book, chapter):
        language_ref, version_ref, language_snapshot, version_snapshot, books = self._bible_state(language, version)
        metadata = _data(version_snapshot)
        overrides = metadata.get("chapterOverrides") or {}
        key = chapter_override_key(book, chapter)
        path = overrides.get(key) if isinstance(overrides, dict) else None
        if not isinstance(path, str) or not path.startswith("bible_chapter_revisions/"):
            path = f"{books.document(book).path}/chapters/{chapter}/verses"
        verses = {s.id: _data(s) for s in self.db.collection(path).stream()}
        if not verses:
            raise ContentNotFoundError("This chapter has no imported verses to edit.")
        return language_ref, version_ref, language_snapshot, version_snapshot, path, verses

    @staticmethod
    def _heading(block):
        return isinstance(block, dict) and re.fullmatch(r"\\?s[0-9]?", str(block.get("marker", ""))) is not None

    def chapter(self, language, version, book, chapter):
        _, _, language_snapshot, version_snapshot, _, verses = self._chapter_state(language, version, book, chapter)
        return {"language": language, "version": version, "book": book, "chapter": chapter,
                "revision": _revision([language_snapshot, version_snapshot]),
                "verses": [{"id": identifier, "text": extract_verse_text(verses[identifier]),
                            "title": "\n".join(str(b.get("text") or "") for b in (verses[identifier].get("blocks_before") or [])
                                                if self._heading(b))}
                           for identifier in sorted(verses, key=_sort_id)]}

    def save_chapter(self, language, version, book, chapter, payload, actor):
        language_ref, version_ref, language_snapshot, version_snapshot, old_path, verses = self._chapter_state(language, version, book, chapter)
        _require_revision(payload.get("revision"), [language_snapshot, version_snapshot])
        updates = payload.get("verses")
        if not isinstance(updates, list) or not updates or len(updates) > len(verses):
            raise ValueError("Provide a list of existing verses to update.")
        changed, seen = [], set()
        for row in updates:
            if not isinstance(row, dict) or set(row) - {"id", "text", "title"}:
                raise ValueError("Only verse text and section headings can be edited.")
            identifier = row.get("id")
            if not isinstance(identifier, str) or identifier not in verses or identifier in seen:
                raise ValueError("Each verse must refer to a unique existing verse identifier.")
            seen.add(identifier)
            before = verses[identifier]
            after = dict(before)
            if "text" in row:
                text = _text(row["text"], "Verse text", 20000, required=False)
                if text != extract_verse_text(before):
                    after["text"] = text
                    after["textEdited"] = True
            if "title" in row:
                title = _text(row["title"], "Section heading", 2000, required=False)
                old_blocks = before.get("blocks_before") or []
                existing_title = "\n".join(str(b.get("text") or "") for b in old_blocks if self._heading(b))
                if title != existing_title:
                    # Keep paragraph/poetry blocks and their ordering intact. A
                    # multi-line title retains each existing section level.
                    headings = iter([line for line in title.splitlines() if line.strip()])
                    blocks = []
                    for block in old_blocks:
                        if self._heading(block):
                            replacement = next(headings, None)
                            if replacement is not None:
                                blocks.append({**block, "text": replacement})
                        else:
                            blocks.append(block)
                    blocks.extend({"marker": "\\s", "text": line} for line in headings)
                    after["blocks_before"] = blocks
            if after != before:
                changed.append(identifier)
                verses[identifier] = after
        if not changed:
            return self.chapter(language, version, book, chapter)
        edit_id = uuid.uuid4().hex
        revision_ref = self.db.collection("bible_chapter_revisions").document(edit_id)
        path = f"{revision_ref.path}/verses"
        revision_ref.set({"language": language, "version": version, "book": book, "chapter": chapter,
                          "sourceBooksRevision": _data(version_snapshot).get("activeRevision"),
                          "previousVersesPath": old_path, "createdBy": actor,
                          "createdAt": firestore.SERVER_TIMESTAMP, "status": "writing", "verseCount": len(verses)})
        self._write_documents((revision_ref.collection("verses").document(k), v) for k, v in verses.items())
        revision_ref.set({"status": "ready"}, merge=True)
        overrides = dict(_data(version_snapshot).get("chapterOverrides") or {})
        overrides[chapter_override_key(book, chapter)] = path
        self._activate([(language_ref, language_snapshot), (version_ref, version_snapshot)], [
            (version_ref, {"chapterOverrides": overrides, "contentEditRevision": edit_id, "updatedAt": firestore.SERVER_TIMESTAMP})
        ], {"id": edit_id, "type": "bible_chapter_edit", "language": language, "version": version,
            "book": book, "chapter": chapter, "actorUid": actor, "createdAt": firestore.SERVER_TIMESTAMP,
            "changedVerseIds": changed, "previousVersesPath": old_path, "activeVersesPath": path})
        return self.chapter(language, version, book, chapter)
