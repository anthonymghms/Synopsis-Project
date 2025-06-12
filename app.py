from flask import Flask, Response
import firebase_admin
from firebase_admin import credentials, firestore
import json

# CONFIGURATION
SERVICE_ACCOUNT_FILE = "serviceAccountKey.json"

def initialize_firebase():
    if not firebase_admin._apps:
        cred = credentials.Certificate(SERVICE_ACCOUNT_FILE)
        firebase_admin.initialize_app(cred)

initialize_firebase()
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

if __name__ == "__main__":
    app.run(debug=True)
