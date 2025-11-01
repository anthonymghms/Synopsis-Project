#!/usr/bin/env python3
# csv_to_topics_by_language.py

import os, re, csv, io, tempfile, argparse
import firebase_admin
from firebase_admin import credentials, storage, firestore

# ─── CONFIG ─────────────────────────────────────────────────────────────
SERVICE_ACCOUNT_FILE = "serviceAccountKey.json"
# For Admin SDK this should be the bucket *name* (often <project-id>.appspot.com).
BUCKET_NAME = "synopsis-224b0.firebasestorage.app"   # change if your bucket name differs
DEFAULT_REMOTE_CSV = "arabic3.csv"           # can be overridden with --csv
# ────────────────────────────────────────────────────────────────────────

GOSPELS = ["Matthew", "Mark", "Luke", "John"]  # canonical names used in Firestore

def initialize_firebase():
    if not firebase_admin._apps:
        cred = credentials.Certificate(SERVICE_ACCOUNT_FILE)
        firebase_admin.initialize_app(cred, {"storageBucket": BUCKET_NAME})

def download_csv(remote_path: str) -> str:
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
    """'1:6–8;15–28' → [(1,'6-8'), (1,'15-28')] ; also accepts commas/semicolons."""
    out = []
    for piece in re.split(r"[;,]", cell or ""):
        p = (piece or "").strip().replace("–", "-").replace("—", "-")
        if ":" not in p:
            continue
        chap, verses = p.split(":", 1)
        chap = chap.strip()
        if chap.isdigit():
            out.append((int(chap), verses.strip()))
    return out

def read_rows_any_encoding(path: str):
    with open(path, "rb") as fb:
        raw = fb.read()
    for enc in ("utf-8-sig", "utf-8", "cp1252", "latin-1"):
        try:
            txt = raw.decode(enc)
            txt = txt.replace("\u2013", "-").replace("\u2014", "-")
            return list(csv.reader(io.StringIO(txt)))
        except UnicodeDecodeError:
            continue
    raise RuntimeError("Could not decode CSV (tried utf-8-sig, utf-8, cp1252, latin-1)")

def parse_csv_by_position(path: str) -> dict:
    """
    Returns { topic: [ {book, chapter, verses}, ... ], ... }
    Assumes: col A=topic, B=Matthew, C=Mark, D=Luke, E=John (headers can be in any language).
    """
    rows = read_rows_any_encoding(path)
    if len(rows) < 2:
        raise RuntimeError("CSV needs a header + at least one data row")

    result = {}
    # start at row 1 to skip header
    for row in rows[1:]:
        if not row: 
            continue
        # topic in col 0
        topic = (row[0] if len(row) > 0 else "").strip()
        if not topic:
            continue

        entries = []
        # cols 1..4 correspond to Matthew, Mark, Luke, John respectively
        col_indices = [1, 2, 3, 4]
        for book, ci in zip(GOSPELS, col_indices):
            if ci >= len(row):
                continue
            cell = row[ci]
            for chap, verses in parse_refs(cell):
                entries.append({"book": book, "chapter": chap, "verses": verses})

        if entries:
            result[topic] = entries

    total_refs = sum(len(v) for v in result.values())
    print(f"✔ Parsed {total_refs} references across {len(result)} topics")
    return result

def push_to_firestore(language: str, data: dict):
    """
    Writes to Firestore: references/<language>/topics/<1..N>
    """
    initialize_firebase()
    db = firestore.client()
    coll = db.collection("references").document(language).collection("topics")

    count = 1
    for topic, entries in data.items():
        coll.document(str(count)).set({"name": topic, "entries": entries})
        count += 1
    print(f"✔ Wrote {len(data)} documents → references/{language}/topics")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv", default=DEFAULT_REMOTE_CSV, help="Path in bucket to the CSV (e.g., arabic2.csv)")
    ap.add_argument("--language", default=None, help="Language key for Firestore (e.g., arabic, english)")
    args = ap.parse_args()

    # Derive language from filename if not provided (strip extension and trailing digits like 'arabic2' -> 'arabic')
    if args.language:
        language = args.language.strip().lower()
    else:
        stem = os.path.splitext(os.path.basename(args.csv))[0]
        language = re.sub(r"\d+$", "", stem).strip().lower() or "unknown"

    local_csv = download_csv(args.csv)
    data = parse_csv_by_position(local_csv)
    push_to_firestore(language, data)

if __name__ == "__main__":
    main()

