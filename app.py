from flask import Flask, Response
import json
import firebase_admin
from firebase_admin import credentials, firestore

cred = credentials.Certificate('serviceAccountKey.json')
firebase_admin.initialize_app(cred)
db = firestore.client()

app = Flask(__name__)

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

if __name__ == '__main__':
    app.run(debug=True)
