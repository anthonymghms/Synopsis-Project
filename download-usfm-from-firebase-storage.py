import firebase_admin
import re
from firebase_admin import credentials, firestore
from google.cloud import storage
from tqdm import tqdm

def parse_usfm(usfm_content):
    book_id = None
    chapters = {}
    current_chapter = None
    
    # For collecting non-verse markers between chapter/verse (e.g., headings, paragraphs, poetry, etc.)
    current_blocks = []

    lines = usfm_content.splitlines()
    for line in lines:
        line = line.strip()
        if line.startswith(r'\id '):
            book_id = line.split(' ', 1)[1]
        elif line.startswith(r'\c '):  # New chapter
            current_chapter = line.split(' ', 1)[1]
            chapters[current_chapter] = {"verses": {}, "blocks": []}
        elif line.startswith(r'\v '):  # New verse
            parts = line.split(' ', 2)
            verse_num = parts[1]
            verse_text = parts[2] if len(parts) > 2 else ""
            # Collect verse and attach current blocks (e.g., headings before the verse)
            chapters[current_chapter]["verses"][verse_num] = {
                "text": verse_text,
                "blocks_before": current_blocks
            }
            current_blocks = []
        elif re.match(r'\\s\d? ', line):  # Section heading
            m = re.match(r'(\\s\d?) (.+)', line)
            if m:
                current_blocks.append({"marker": m.group(1), "text": m.group(2)})
        elif line.startswith(r'\p'):
            current_blocks.append({"marker": "p"})
        elif re.match(r'\\q\d? ', line):  # Poetry/quote
            m = re.match(r'(\\q\d?) (.+)', line)
            if m:
                current_blocks.append({"marker": m.group(1), "text": m.group(2)})
        # Add more marker handlers as needed!

    # Wrap into book structure
    result = {
        "book_id": book_id,
        "chapters": chapters
    }
    return result

SERVICE_ACCOUNT_FILE = 'serviceAccountKey.json'
BUCKET_NAME = 'synopsis-224b0.firebasestorage.app'
USFM_FILE_PATH = '73-JHNarb-vd.usfm'

cred = credentials.Certificate(SERVICE_ACCOUNT_FILE)
firebase_admin.initialize_app(cred, {
    'storageBucket': BUCKET_NAME
})
db = firestore.client()


client = storage.Client.from_service_account_json(SERVICE_ACCOUNT_FILE)
bucket = client.bucket(BUCKET_NAME)
blob = bucket.blob(USFM_FILE_PATH)
usfm_content = blob.download_as_text(encoding='utf-8')

parsed = parse_usfm(usfm_content)

# Get total verses for progress bar (optional)
total_verses = sum(len(ch['verses']) for ch in parsed['chapters'].values())
progress = tqdm(total=total_verses, desc="Uploading verses")

book_id = parsed['book_id']
for chapter_num, chapter_data in parsed['chapters'].items():
    # Reference to chapter doc
    chapter_ref = db.collection('bibles').document(book_id).collection('chapters').document(str(chapter_num))
    chapter_ref.set({})  # Optional: store chapter-level info here
    
    batch = db.batch()
    count = 0
    for verse_num, verse_data in chapter_data['verses'].items():
        verse_ref = chapter_ref.collection('verses').document(str(verse_num))
        batch.set(verse_ref, verse_data)
        count += 1
        progress.update(1)  # Advance progress bar
        if count % 500 == 0:
            batch.commit()
            batch = db.batch()
    if count % 500 != 0:
        batch.commit()
        
progress.close()
print("Upload complete!")