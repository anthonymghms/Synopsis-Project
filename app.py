from flask import Flask, request, Response
import json
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
  
def _topics_collection(language: str, collection: str):
    """Return a reference to the requested topics collection."""
    language = language.strip()
    collection = collection.strip() or 'topics'
    return db.collection('references').document(language).collection(collection)


def _serialize_topic_doc(doc):
    data = doc.to_dict() or {}
    padded_id = data.get('id') or f"{doc.id:0>2}"
    topic = {
        "id": padded_id,
        "name": data.get('name', ''),
        "references": data.get('entries') or data.get('references') or [],
    }
    # Optional metadata to help build grouped tables on the frontend.
    for key in ['group', 'category', 'subtitle', 'order', 'description']:
        if key in data:
            topic[key] = data[key]
    return topic


@app.route('/<language>/topics/<topic_id>', methods=['GET'])
def get_topic(language, topic_id):
    collection_name = request.args.get('collection', 'topics')
    doc_ref = _topics_collection(language, collection_name).document(topic_id)
    doc = doc_ref.get()
    if doc.exists:
        data = _serialize_topic_doc(doc)
        return Response(
            json.dumps(data, ensure_ascii=False, indent=2),
            content_type="application/json; charset=utf-8"
        )
    else:
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


@app.route('/topics', methods=['GET'])
def get_topics():
    language = request.args.get('language', 'arabic')
    collection_name = request.args.get('collection', 'topics')

    topics_ref = _topics_collection(language, collection_name)
    docs = topics_ref.stream()

    topics = [_serialize_topic_doc(doc) for doc in docs]

    def _sort_key(item):
        order = item.get('order')
        try:
            return (int(order), item.get('name', ''))
        except (TypeError, ValueError):
            pass
        try:
            return (int(item.get('id')), item.get('name', ''))
        except (TypeError, ValueError):
            return (9999, item.get('name', ''))

    topics.sort(key=_sort_key)

    return Response(
        json.dumps(topics, ensure_ascii=False, indent=2),
        content_type="application/json; charset=utf-8"
    )

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8000, debug=True)
