#!/usr/bin/env python3
# csv_to_gospel_topics_with_firebase.py

import os
import re
import csv
import tempfile

import firebase_admin
from firebase_admin import credentials, storage, firestore

# ─── CONFIGURATION ─────────────────────────────────────────────────────────────
# 1) Download your service-account key from:
#    Firebase Console → Project Settings → Service Accounts → Generate new private key
SERVICE_ACCOUNT_FILE = "serviceAccountKey.json"

# 2) Your bucket name (see Firebase Console → Storage)
BUCKET_NAME = "synopsis-224b0.firebasestorage.app"

# 3) The CSV you’ve already uploaded into the *root* of that bucket:
REMOTE_CSV = "arabic_van-dyck.csv"
# ────────────────────────────────────────────────────────────────────────────────

def initialize_firebase():
    """Initialize Firebase Admin SDK (Storage + Firestore)."""
    if not firebase_admin._apps:
        cred = credentials.Certificate(SERVICE_ACCOUNT_FILE)
        firebase_admin.initialize_app(cred, {
            "storageBucket": BUCKET_NAME
        })

def download_csv(remote_path: str) -> str:
    """
    Downloads `remote_path` from your Firebase Storage bucket into
    a local temp file. Returns the filename.
    """
    initialize_firebase()
    bucket = storage.bucket()
    blob = bucket.blob(remote_path)
    if not blob.exists():
        raise RuntimeError(f"Remote file {remote_path!r} not found in bucket {BUCKET_NAME!r}")
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".csv")
    blob.download_to_filename(tmp.name)
    size = os.path.getsize(tmp.name)
    print(f"✔ Downloaded “{remote_path}” ({size} bytes) → {tmp.name}")
    return tmp.name

def parse_refs(cell: str):
    """
    Given a cell like “1:6–8;15–28” or “2:39”, split on [;,],
    normalize the dash, and return a list of (chapter:int, verses:str).
    """
    out = []
    for piece in re.split(r"[;,]", cell or ""):
        p = piece.strip().replace("–", "-")
        if not p or ":" not in p:
            continue
        chap, verses = p.split(":", 1)
        chap, verses = chap.strip(), verses.strip()
        if not chap.isdigit():
            continue
        out.append((int(chap), verses))
    return out

def parse_csv(path: str) -> dict:
    """
    Reads the CSV and returns a dict:
      { topic1: [ {book,chapter,verses}, … ],
        topic2: [ … ], … }
    where the 4 Gospel-columns map (in order) to
    ["Matthew","Mark","Luke","John"].
    """
    gospel_names = ["Matthew","Mark","Luke","John"]
    result = {}

    with open(path, newline="", encoding="utf-8-sig") as f:
        reader = csv.reader(f)
        rows = list(reader)

    if len(rows) < 2:
        raise RuntimeError("CSV needs at least a header row + one data row")

    for row in rows[1:]:
        if not row or not row[0].strip():
            continue
        topic = row[0].strip()
        entries = []
        for idx, book in enumerate(gospel_names, start=1):
            if idx >= len(row):
                break
            for chap, verses in parse_refs(row[idx]):
                entries.append({
                    "book":    book,
                    "chapter": chap,
                    "verses":  verses
                })
        if entries:
            result[topic] = entries

    total_refs = sum(len(v) for v in result.values())
    print(f"✔ Parsed {total_refs} references across {len(result)} topics")
    return result

def push_to_firestore(data: dict):
    """
    Pushes `data` into Firestore under collection `collection_name`.
    Each key in `data` becomes a document ID, with an 'entries' field.
    """
    parts = os.path.basename(REMOTE_CSV).replace('.csv', '').split('_')

    if len(parts) == 2:
        language = parts[0].replace('-', ' ')
        version = parts[1].replace('-', ' ')
    else:
        language = "unknown"
        version = "unknown"
    
    initialize_firebase()
    db = firestore.client()
    coll = db.collection("references").document(language).collection(version)

    count = 1
    for topic, entries in data.items():
        doc_data = {
            "name": topic,
            "entries": entries
        }
        doc_ref = coll.document(str(count))
        doc_ref.set(doc_data)
        count +=1
    print(f"✔ Wrote {len(data)} documents into Firestore collection “references”")



def main():
    # 1) Download the remote CSV locally.
    local_csv = download_csv(REMOTE_CSV)

    # 2) Parse it into our JSON-friendly dict.
    data = parse_csv(local_csv)

    # 3) Push those same entries into Firestore under collection "Book".
    push_to_firestore(data)

if __name__ == "__main__":
    main()
