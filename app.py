from flask import Flask, request, Response
import json
import re
import firebase_admin
from firebase_admin import credentials, firestore
from flask_cors import CORS


cred = credentials.Certificate('serviceAccountKey.json')
firebase_admin.initialize_app(cred)
db = firestore.client()

app = Flask(__name__)

CORS(app)
'''
@app.route('/<language>/<version>/topics', methods=['GET'])
def get_topics(language, version):
    topics_ref = db.collection('references').document(language).collection(version)
    docs = topics_ref.stream()
    # Collect the topic names (from 'name' field in each doc)
    topics = []
    for doc in docs:
        data = doc.to_dict()
        if data and "name" in data:
            topics.append(data["name"])
    return Response(
        json.dumps(topics, ensure_ascii=False, indent=2),
        content_type="application/json; charset=utf-8"
    )
    '''
  
def _normalize_key(value):
    if value is None:
        return ""
    return re.sub(r"[\s_\-]+", "", str(value).strip().lower())


def _coerce_string(value):
    if value is None:
        return None
    if isinstance(value, (int, float)):
        if int(value) == value:
            value = int(value)
    return str(value).strip()


def _resolve_language_document(language):
    references_collection = db.collection('references')
    target_key = _normalize_key(language)
    for doc_ref in references_collection.list_documents():
        if _normalize_key(doc_ref.id) == target_key:
            return doc_ref
    return references_collection.document(language)


def _resolve_collection(doc_ref, target):
    normalized_target = _normalize_key(target)
    for collection in doc_ref.collections():
        if _normalize_key(collection.id) == normalized_target:
            return collection
    return doc_ref.collection(target)


def _resolve_document(collection_ref, doc_id):
    normalized_target = _normalize_key(doc_id)
    direct_ref = collection_ref.document(doc_id)
    direct_snapshot = direct_ref.get()
    if direct_snapshot.exists:
        return direct_snapshot
    for candidate_ref in collection_ref.list_documents():
        if _normalize_key(candidate_ref.id) == normalized_target:
            candidate_snapshot = candidate_ref.get()
            if candidate_snapshot.exists:
                return candidate_snapshot
    return direct_ref.get()


def _format_verse_range(start, end):
    start_str = _coerce_string(start)
    end_str = _coerce_string(end)
    if not start_str:
        return None
    if not end_str or end_str == start_str:
        return start_str
    return f"{start_str}-{end_str}"


def _normalize_reference_entry(entry, default_book=None):
    if entry is None:
        return None

    if isinstance(entry, str):
        text = entry.strip()
        if not text:
            return None
        book = default_book
        chapter = None
        verses = None
        match = re.match(r"^(?:(?P<book>[0-9A-Za-z '\-]+?)\s+)?(?P<chapter>\d+)(?::(?P<verses>.*))?$", text)
        if match:
            book = match.group('book') or book
            chapter = match.group('chapter')
            verses = match.group('verses')
        elif ':' in text:
            chapter, verses = text.split(':', 1)
        else:
            chapter = text
        if not book:
            book = default_book
        normalized = {
            "book": (book or "").strip(),
            "chapter": _coerce_string(chapter) if chapter else None,
            "verses": _coerce_string(verses) if verses else None,
        }
        if not normalized["book"]:
            return None
        return normalized

    if not isinstance(entry, dict):
        return None

    book = _coerce_string(entry.get('book') or default_book)
    chapter = entry.get('chapter') or entry.get('chap')
    if chapter is None:
        chapter = entry.get('chapterStart') or entry.get('startChapter')
        chapter_end = entry.get('chapterEnd') or entry.get('endChapter')
        if chapter and chapter_end and _coerce_string(chapter_end) != _coerce_string(chapter):
            chapter = f"{_coerce_string(chapter)}-{_coerce_string(chapter_end)}"
    verses = entry.get('verses') or entry.get('verse') or entry.get('versesText')
    if not verses:
        verses = _format_verse_range(
            entry.get('verseStart') or entry.get('startVerse'),
            entry.get('verseEnd') or entry.get('endVerse'),
        )
    title = entry.get('title') or entry.get('label')
    note = entry.get('note') or entry.get('notes') or entry.get('comment')

    normalized = {
        "book": (book or "").strip(),
        "chapter": _coerce_string(chapter) if chapter else None,
        "verses": _coerce_string(verses) if verses else None,
    }
    if not normalized["book"]:
        return None
    if title:
        normalized["title"] = _coerce_string(title)
    if note:
        normalized["note"] = _coerce_string(note)
    return normalized


def _collect_references(data):
    references = []

    for field in ("references", "entries", "refs"):
        if isinstance(data.get(field), list):
            for item in data.get(field):
                normalized = _normalize_reference_entry(item)
                if normalized:
                    references.append(normalized)

    gospel_groups = data.get('gospels') or data.get('gospelRefs')
    if isinstance(gospel_groups, dict):
        for book, items in gospel_groups.items():
            if isinstance(items, list):
                for item in items:
                    normalized = _normalize_reference_entry(item, default_book=book)
                    if normalized:
                        references.append(normalized)

    reference_groups = data.get('referenceGroups')
    if isinstance(reference_groups, list):
        for group in reference_groups:
            if not isinstance(group, dict):
                continue
            book = group.get('book') or group.get('name')
            items = group.get('references') or group.get('entries') or []
            if isinstance(items, list):
                for item in items:
                    normalized = _normalize_reference_entry(item, default_book=book)
                    if normalized:
                        references.append(normalized)

    other_refs = data.get('otherReferences')
    if isinstance(other_refs, list):
        for item in other_refs:
            normalized = _normalize_reference_entry(item)
            if normalized:
                references.append(normalized)

    unique_refs = []
    seen = set()
    for ref in references:
        if not ref or not ref.get('book'):
            continue
        key = (
            _normalize_key(ref.get('book')),
            _coerce_string(ref.get('chapter')) or "",
            _coerce_string(ref.get('verses')) or "",
            _coerce_string(ref.get('title')) or "",
            _coerce_string(ref.get('note')) or "",
        )
        if key in seen:
            continue
        seen.add(key)
        unique_refs.append(ref)
    return unique_refs


def _topic_sort_key(doc, data):
    for key in ("order", "index", "position", "sequence", "sort", "sortOrder", "orderIndex"):
        if key in data and data[key] is not None:
            try:
                return float(data[key])
            except (TypeError, ValueError):
                pass
    try:
        return float(doc.id)
    except (TypeError, ValueError):
        try:
            return float(int(_normalize_key(doc.id) or 0))
        except (TypeError, ValueError):
            return float('inf')


def _serialize_topic(doc, data=None):
    if data is None:
        data = doc.to_dict() or {}
    topic = {
        "id": doc.id,
        "name": _coerce_string(
            data.get('name')
            or data.get('subject')
            or data.get('title')
            or data.get('heading')
            or ""
        ) or "",
        "references": _collect_references(data),
    }

    for field in ("subtitle", "description", "note", "type", "isSectionHeader", "hasReferences"):
        if field in data and data[field] is not None:
            topic[field] = data[field]

    if 'summary' in data and 'description' not in topic:
        topic['description'] = data['summary']

    return topic


def _get_topics_collection(language, version):
    language_doc = _resolve_language_document(language)
    language_snapshot = language_doc.get()
    if not language_snapshot.exists:
        collection = language_doc.collection(version)
        return collection, list(collection.stream())

    collection = _resolve_collection(language_doc, version)
    docs = list(collection.stream())
    if docs:
        return collection, docs

    # Attempt to find a collection named "topics" with embedded version filtering
    topics_collection = _resolve_collection(language_doc, 'topics')
    topics_docs = list(topics_collection.stream())
    if topics_docs:
        filtered = []
        target_version = _normalize_key(version)
        for doc in topics_docs:
            doc_data = doc.to_dict() or {}
            doc_version = doc_data.get('version') or doc_data.get('bibleVersion')
            if not target_version or _normalize_key(doc_version) == target_version:
                filtered.append(doc)
        if filtered:
            return topics_collection, filtered

    return collection, []


@app.route('/<language>/<version>/topic/<topic_id>', methods=['GET'])
def get_topic(language, version, topic_id):
    collection, _ = _get_topics_collection(language, version)
    doc_snapshot = _resolve_document(collection, topic_id)
    if doc_snapshot.exists:
        topic = _serialize_topic(doc_snapshot)
        return Response(
            json.dumps(topic, ensure_ascii=False, indent=2),
            content_type="application/json; charset=utf-8"
        )
    return Response(
        json.dumps({"error": "Topic not found"}, ensure_ascii=False, indent=2),
        status=404,
        content_type="application/json; charset=utf-8"
    )
        
@app.route('/get_verse', methods=['GET'])
def get_verse():
    language = request.args.get('language')
    version = request.args.get('version')
    book = request.args.get('book')
    chapter = request.args.get('chapter')
    verse = request.args.get('verse')  # Can be "1" or "1-3"

    if not all([language, version, book, chapter, verse]):
        return Response(json.dumps({"error": "Missing params"}), status=400, content_type="application/json")

    bible_language_doc = _resolve_document(db.collection('bibles'), language)
    if not bible_language_doc.exists:
        return Response(
            json.dumps([], ensure_ascii=False, indent=2),
            content_type="application/json; charset=utf-8"
        )

    version_collection = _resolve_collection(bible_language_doc.reference, version)
    book_doc = _resolve_document(version_collection, book)
    if not book_doc.exists:
        return Response(
            json.dumps([], ensure_ascii=False, indent=2),
            content_type="application/json; charset=utf-8"
        )

    chapters_collection = _resolve_collection(book_doc.reference, 'chapters')
    chapter_doc = _resolve_document(chapters_collection, chapter)
    if not chapter_doc.exists:
        return Response(
            json.dumps([], ensure_ascii=False, indent=2),
            content_type="application/json; charset=utf-8"
        )

    verses_collection = _resolve_collection(chapter_doc.reference, 'verses')

    def get_actual_verse_text(verse_num):
        verse_doc = _resolve_document(verses_collection, str(verse_num))
        if not verse_doc.exists:
            return {"verse": verse_num, "text": ""}
        data = verse_doc.to_dict()
        text = ""
        # Try to get text from blocks_before if it has any non-empty text
        if "blocks_before" in data and isinstance(data["blocks_before"], list) and len(data["blocks_before"]) > 0:
            # Collect all non-empty "text" fields from blocks_before
            text_parts = [block.get("text", "").strip() for block in data["blocks_before"] if block.get("text", "").strip()]
            text = " ".join(text_parts).strip()
        # If still empty, use the top-level "text" field
        if not text and "text" in data:
            text = data["text"].strip()
        return {"verse": verse_num, "text": text}


    results = []
    if '-' in verse:
        start, end = map(int, verse.split('-'))
        for i in range(start, end + 1):
            results.append(get_actual_verse_text(i))
    else:
        results.append(get_actual_verse_text(verse))

    return Response(
        json.dumps(results, ensure_ascii=False, indent=2),
        content_type="application/json; charset=utf-8"
    )


@app.route('/topics', methods=['GET'])
def get_topics():
    # Get params (use default if not provided)
    language = request.args.get('language', 'english')
    version = request.args.get('version', 'kjv')

    topics_collection, docs = _get_topics_collection(language, version)

    if not docs:
        docs = list(topics_collection.stream())

    topics_with_sort = []
    for idx, doc in enumerate(docs):
        data = doc.to_dict() or {}
        topic = _serialize_topic(doc, data=data)
        sort_key = _topic_sort_key(doc, data)
        topics_with_sort.append((sort_key, idx, topic))

    topics_with_sort.sort(key=lambda item: (item[0], item[1]))
    topics = [item[2] for item in topics_with_sort]

    return Response(json.dumps(topics, ensure_ascii=False, indent=2), content_type="application/json; charset=utf-8")

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8000, debug=True)
