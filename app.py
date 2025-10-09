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
  
@app.route('/<language>/<version>/topic/<topic_id>', methods=['GET'])
def get_topic(language, version, topic_id):
    doc_ref = _topics_collection(language, version).document(topic_id)
    doc = doc_ref.get()
    if not doc.exists:
        return Response(json.dumps({"error": "Topic not found"}, ensure_ascii=False, indent=2),
                        status=404, content_type="application/json; charset=utf-8")

    data = doc.to_dict() or {}
    data['id'] = doc.id
    return Response(json.dumps(data, ensure_ascii=False, indent=2),
                    content_type="application/json; charset=utf-8")

        
def _normalize_book_token(value: str) -> str:
    return ''.join(ch.lower() for ch in (value or '') if ch.isalnum())


_ORDINAL_WORDS = {
    'first': '1',
    'second': '2',
    'third': '3',
    'fourth': '4',
}


_ROMAN_NUMERALS = {
    'i': '1',
    'ii': '2',
    'iii': '3',
    'iv': '4',
    'v': '5',
    'vi': '6',
    'vii': '7',
    'viii': '8',
}


_BOOK_SYNONYMS = {
    'canticles': ['songofsongs', 'songofsolomon'],
    'songofsongs': ['songofsolomon', 'canticles'],
    'songofsolomon': ['songofsongs', 'canticles'],
    'psalm': ['psalms'],
    'psalms': ['psalm'],
}


def _expand_with_synonyms(tokens):
    expanded = set()
    stack = list(tokens)
    while stack:
        token = stack.pop()
        if not token or token in expanded:
            continue
        expanded.add(token)
        for synonym in _BOOK_SYNONYMS.get(token, []):
            stack.append(synonym)
    return expanded


def _book_name_candidates(name: str):
    if not name:
        return set()
    tokens = set()
    normalized = _normalize_book_token(name)
    tokens.add(normalized)
    tokens.add(re.sub(r'^[0-9]+', '', normalized))

    for word, digit in _ORDINAL_WORDS.items():
        if normalized.startswith(word):
            remainder = normalized[len(word):]
            tokens.add(digit + remainder)
            tokens.add(remainder)

    for roman, digit in _ROMAN_NUMERALS.items():
        if normalized.startswith(roman):
            remainder = normalized[len(roman):]
            tokens.add(digit + remainder)
            tokens.add(remainder)

    return {token for token in _expand_with_synonyms(tokens) if token}


def _document_book_tokens(doc_id: str):
    parts = (doc_id or '').split(' ')
    tokens = set()
    tokens.add(_normalize_book_token(doc_id))
    if len(parts) > 1:
        tokens.add(_normalize_book_token(' '.join(parts[1:])))
    tokens.add(_normalize_book_token(parts[0]))
    tokens.add(_normalize_book_token(parts[-1]))
    return {token for token in _expand_with_synonyms(tokens) if token}


def _resolve_book_document_id(language: str, version: str, book: str):
    collection = db.collection('bibles').document(language).collection(version)
    direct_doc = collection.document(book)
    if direct_doc.get().exists:
        return book

    candidates = _book_name_candidates(book)
    if not candidates:
        return None

    documents = list(collection.list_documents())
    for doc in documents:
        prefix = _normalize_book_token(doc.id.split(' ')[0])
        if prefix and prefix in candidates:
            return doc.id

    tokenized_docs = [(doc.id, _document_book_tokens(doc.id)) for doc in documents]
    for doc_id, tokens in tokenized_docs:
        for candidate in candidates:
            for token in tokens:
                if not token or not candidate:
                    continue
                if candidate == token or candidate in token or token in candidate:
                    return doc_id

    return None


@app.route('/get_verse', methods=['GET'])
def get_verse():
    language = request.args.get('language')
    version = request.args.get('version')
    requested_book = request.args.get('book')
    chapter = request.args.get('chapter')
    verse = request.args.get('verse')  # Can be "1" or "1-3"

    if not all([language, version, requested_book, chapter, verse]):
        return Response(json.dumps({"error": "Missing params"}), status=400, content_type="application/json")

    book = _resolve_book_document_id(language, version, requested_book)
    if not book:
        return Response(json.dumps({"error": f"Unknown book '{requested_book}'"}), status=404, content_type="application/json")

    def get_actual_verse_text(verse_num):
        verse_ref = (
            db.collection('bibles')
            .document(language)
            .collection(version)
            .document(book)
            .collection('chapters')
            .document(chapter)
            .collection('verses')
            .document(str(verse_num))
        )
        verse_doc = verse_ref.get()
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

def _topics_collection(language: str, version: str):
    # match your Firestore doc id: english_kjv, arabic_van_dyck, etc.
    doc_id = f"{language}_{version}".replace(" ", "_").lower()
    return db.collection('references').document(doc_id).collection('topics')


@app.route('/topics', methods=['GET'])
def get_topics():
    language = request.args.get('language', 'english')
    version  = request.args.get('version',  'kjv')

    topics_ref = _topics_collection(language, version)
    topics = []
    for doc in topics_ref.stream():
        data = doc.to_dict() or {}
        # zero-pad numeric ids, but don't crash if not numeric
        try:
            padded_id = f"{int(doc.id):02}"
        except ValueError:
            padded_id = doc.id
        topics.append({
            "id": padded_id,
            "name": data.get("name", ""),
            "references": data.get("entries", [])
        })

    topics.sort(key=lambda x: int(x['id']) if x['id'].isdigit() else x['id'])
    return Response(json.dumps(topics, ensure_ascii=False, indent=2),
                    content_type="application/json; charset=utf-8")


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8000, debug=True)
