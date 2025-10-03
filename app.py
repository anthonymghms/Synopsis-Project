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
  
@app.route('/<language>/<version>/topic/<topic_id>', methods=['GET'])
def get_topic(language, version, topic_id):
    doc_ref = db.collection('references').document(language).collection(version).document(topic_id)
    doc = doc_ref.get()
    if doc.exists:
        data = doc.to_dict()
        data['id'] = doc.id
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
    # Get params (use default if not provided)
    language = request.args.get('language', 'english')
    version = request.args.get('version', 'kjv')

    topics_ref = db.collection('references').document(language).collection(version)
    docs = topics_ref.stream()
    topics = []

    for doc in docs:
        data = doc.to_dict()
        # Format id with zero padding
        padded_id = f"{int(doc.id):02}"
        topic_name = data.get('name') or data.get('topic') or ''
        topic = {
            "id": padded_id,
            "name": topic_name,
            "references": data.get('entries', []) or data.get('references', [])
        }
        topics.append(topic)
    topics.sort(key=lambda x: int(x['id']))

    return Response(json.dumps(topics, ensure_ascii=False, indent=2), content_type="application/json; charset=utf-8")

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8000, debug=True)
