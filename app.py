from flask import Flask, request, Response
import json
import re
import firebase_admin
from firebase_admin import credentials, firestore
from flask_cors import CORS


cred = credentials.Certificate("serviceAccountKey.json")
firebase_admin.initialize_app(cred)
db = firestore.client()

app = Flask(__name__)

CORS(app)
"""
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
    """


@app.route("/<language>/<version>/topic/<topic_id>", methods=["GET"])
def get_topic(language, version, topic_id):
    doc_ref = _topics_collection(language, version).document(topic_id)
    doc = doc_ref.get()
    if not doc.exists:
        return Response(
            json.dumps({"error": "Topic not found"}, ensure_ascii=False, indent=2),
            status=404,
            content_type="application/json; charset=utf-8",
        )

    data = doc.to_dict() or {}
    data["id"] = doc.id
    return Response(
        json.dumps(data, ensure_ascii=False, indent=2),
        content_type="application/json; charset=utf-8",
    )


_ARABIC_INDIC_DIGIT_TRANSLATION = str.maketrans(
    {
        "٠": "0",
        "١": "1",
        "٢": "2",
        "٣": "3",
        "٤": "4",
        "٥": "5",
        "٦": "6",
        "٧": "7",
        "٨": "8",
        "٩": "9",
    }
)


def _normalize_book_token(value: str) -> str:
    normalized = (value or "").translate(_ARABIC_INDIC_DIGIT_TRANSLATION)
    return "".join(ch.lower() for ch in normalized if ch.isalnum())


def _select_bible_language(language: str) -> str:
    normalized = (language or "").strip()
    if normalized.lower().startswith("arabic"):
        return "arabic"
    return normalized


def _select_bible_version(language: str, version: str) -> str:
    normalized_language = (language or "").strip().lower()
    requested_version = (version or "").strip()

    if normalized_language.startswith("arabic"):
        if not requested_version or requested_version.lower() == "kjv":
            return "van dyck"

    return requested_version


_ORDINAL_WORDS = {
    "first": "1",
    "second": "2",
    "third": "3",
    "fourth": "4",
}


_ROMAN_NUMERALS = {
    "i": "1",
    "ii": "2",
    "iii": "3",
    "iv": "4",
    "v": "5",
    "vi": "6",
    "vii": "7",
    "viii": "8",
}


_BOOK_SYNONYMS = {
    "canticles": ["songofsongs", "songofsolomon"],
    "songofsongs": ["songofsolomon", "canticles"],
    "songofsolomon": ["songofsongs", "canticles"],
    "psalm": ["psalms"],
    "psalms": ["psalm"],
    # Arabic gospel book names used by the frontend.
    "متى": ["matthew", "mathew"],
    "متّى": ["matthew", "mathew"],
    "مرقس": ["mark"],
    "لوقا": ["luke"],
    "يوحنا": ["john"],
    "يوحنّا": ["john"],
    # Provide reverse lookups so English documents can match Arabic requests.
    "matthew": ["متى", "متّى"],
    "mathew": ["متى", "متّى"],
    "mark": ["مرقس"],
    "luke": ["لوقا"],
    "john": ["يوحنا", "يوحنّا"],
}


def _register_book_synonyms(base_name, *variants):
    base_token = _normalize_book_token(base_name)
    if not base_token:
        return
    base_synonyms = _BOOK_SYNONYMS.setdefault(base_token, [])
    for variant in variants:
        token = _normalize_book_token(variant)
        if not token or token == base_token:
            continue
        if token not in base_synonyms:
            base_synonyms.append(token)
        reciprocal = _BOOK_SYNONYMS.setdefault(token, [])
        if base_token not in reciprocal:
            reciprocal.append(base_token)


_ARABIC_BOOK_DOCUMENT_OVERRIDE_SOURCES = {
    "Genesis": ["التكوين", "سفر التكوين"],
    "Exodus": ["الخروج", "سفر الخروج"],
    "Leviticus": ["اللاويين"],
    "Numbers": ["العدد"],
    "Deuteronomy": ["التثنية"],
    "Joshua": ["يشوع"],
    "Judges": ["القضاة"],
    "Ruth": ["راعوث"],
    "1 Samuel": [
        "صموئيل الاول",
        "صموئيل الأول",
        "أول صموئيل",
        "رسالة صموئيل الاول",
        "١ صموئيل",
        "1 صموئيل",
    ],
    "2 Samuel": [
        "صموئيل الثاني",
        "صموئيل الثاني",
        "ثاني صموئيل",
        "٢ صموئيل",
        "2 صموئيل",
    ],
    "1 Kings": ["الملوك الاول", "الملوك الأول", "١ الملوك", "1 الملوك"],
    "2 Kings": ["الملوك الثاني", "الملوك الثاني", "٢ الملوك", "2 الملوك"],
    "1 Chronicles": [
        "أخبار الأيام الأول",
        "اخبار الايام الاول",
        "١ أخبار الأيام",
        "1 أخبار الأيام",
    ],
    "2 Chronicles": [
        "أخبار الأيام الثاني",
        "اخبار الايام الثاني",
        "٢ أخبار الأيام",
        "2 أخبار الأيام",
    ],
    "Ezra": ["عزرا"],
    "Nehemiah": ["نحميا"],
    "Esther": ["أستير", "استير"],
    "Job": ["أيوب"],
    "Psalms": ["المزامير", "مزامير"],
    "Proverbs": ["الأمثال", "امثال"],
    "Ecclesiastes": ["الجامعة"],
    "Song of Solomon": ["نشيد الأنشاد", "نشيد الانشاد", "نشيد"],
    "Isaiah": ["إشعياء", "اشعياء"],
    "Jeremiah": ["إرميا", "ارميا"],
    "Lamentations": ["مراثي إرميا", "مراثي ارميا", "المراثي"],
    "Ezekiel": ["حزقيال"],
    "Daniel": ["دانيال"],
    "Hosea": ["هوشع"],
    "Joel": ["يوئيل"],
    "Amos": ["عاموس"],
    "Obadiah": ["عوبديا"],
    "Jonah": ["يونان"],
    "Micah": ["ميخا"],
    "Nahum": ["ناحوم"],
    "Habakkuk": ["حبقوق"],
    "Zephaniah": ["صفنيا"],
    "Haggai": ["حجّي", "حجي"],
    "Zechariah": ["زكريا"],
    "Malachi": ["ملاخي"],
    "Matthew": ["متى", "متّى"],
    "Mark": ["مرقس"],
    "Luke": ["لوقا"],
    "John": ["يوحنا", "يوحنّا"],
    "Acts": ["أعمال الرسل", "اعمال الرسل"],
    "Romans": ["رومية", "رسالة رومية"],
    "1 Corinthians": [
        "كورنثوس الاولى",
        "كورنثوس الأولى",
        "١ كورنثوس",
        "1 كورنثوس",
        "رسالة كورنثوس الاولى",
    ],
    "2 Corinthians": [
        "كورنثوس الثانية",
        "كورنثوس الثانيه",
        "٢ كورنثوس",
        "2 كورنثوس",
        "رسالة كورنثوس الثانية",
    ],
    "Galatians": ["غلاطية", "رسالة غلاطية"],
    "Ephesians": ["أفسس", "افسس", "رسالة أفسس"],
    "Philippians": ["فيلبي", "رسالة فيلبي"],
    "Colossians": ["كولوسي", "رسالة كولوسي"],
    "1 Thessalonians": [
        "تسالونيكي الاولى",
        "تسالونيكي الأولى",
        "١ تسالونيكي",
        "1 تسالونيكي",
    ],
    "2 Thessalonians": [
        "تسالونيكي الثانية",
        "تسالونيكي الثانيه",
        "٢ تسالونيكي",
        "2 تسالونيكي",
    ],
    "1 Timothy": [
        "تيموثاوس الاولى",
        "تيموثاوس الأولى",
        "١ تيموثاوس",
        "1 تيموثاوس",
    ],
    "2 Timothy": [
        "تيموثاوس الثانية",
        "تيموثاوس الثانيه",
        "٢ تيموثاوس",
        "2 تيموثاوس",
    ],
    "Titus": ["تيطس"],
    "Philemon": ["فيلمون"],
    "Hebrews": ["العبرانيين", "رسالة العبرانيين"],
    "James": ["يعقوب", "رسالة يعقوب"],
    "1 Peter": [
        "بطرس الاولى",
        "بطرس الأولى",
        "١ بطرس",
        "1 بطرس",
    ],
    "2 Peter": [
        "بطرس الثانية",
        "بطرس الثانيه",
        "٢ بطرس",
        "2 بطرس",
    ],
    "1 John": [
        "يوحنا الاولى",
        "يوحنا الأولى",
        "١ يوحنا",
        "1 يوحنا",
        "رسالة يوحنا الاولى",
    ],
    "2 John": [
        "يوحنا الثانية",
        "يوحنا الثانيه",
        "٢ يوحنا",
        "2 يوحنا",
        "رسالة يوحنا الثانية",
    ],
    "3 John": [
        "يوحنا الثالثة",
        "يوحنا الثالثه",
        "٣ يوحنا",
        "3 يوحنا",
        "رسالة يوحنا الثالثة",
    ],
    "Jude": ["يهوذا", "رسالة يهوذا"],
    "Revelation": ["رؤيا يوحنا", "سفر الرؤيا", "الرؤيا"],
}


for english_name, variants in _ARABIC_BOOK_DOCUMENT_OVERRIDE_SOURCES.items():
    _register_book_synonyms(english_name, *variants)


_ARABIC_BOOK_DOCUMENT_OVERRIDES = {}
for english_name, variants in _ARABIC_BOOK_DOCUMENT_OVERRIDE_SOURCES.items():
    doc_id = english_name
    tokens = {_normalize_book_token(english_name)}
    tokens.update(_normalize_book_token(variant) for variant in variants)
    for token in tokens:
        if token:
            _ARABIC_BOOK_DOCUMENT_OVERRIDES[token] = doc_id


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
    tokens.add(re.sub(r"^[0-9]+", "", normalized))

    for word, digit in _ORDINAL_WORDS.items():
        if normalized.startswith(word):
            remainder = normalized[len(word) :]
            tokens.add(digit + remainder)
            tokens.add(remainder)

    for roman, digit in _ROMAN_NUMERALS.items():
        if normalized.startswith(roman):
            remainder = normalized[len(roman) :]
            tokens.add(digit + remainder)
            tokens.add(remainder)

    return {token for token in _expand_with_synonyms(tokens) if token}


def _document_book_tokens(doc_id: str):
    parts = (doc_id or "").split(" ")
    tokens = set()
    tokens.add(_normalize_book_token(doc_id))
    if len(parts) > 1:
        tokens.add(_normalize_book_token(" ".join(parts[1:])))
    tokens.add(_normalize_book_token(parts[0]))
    tokens.add(_normalize_book_token(parts[-1]))
    return {token for token in _expand_with_synonyms(tokens) if token}


def _resolve_book_document_id(language: str, version: str, book: str):
    collection = db.collection("bibles").document(language).collection(version)
    direct_doc = collection.document(book)
    if direct_doc.get().exists:
        return book

    normalized_book = _normalize_book_token(book)
    if language and language.lower().startswith("arabic"):
        override = _ARABIC_BOOK_DOCUMENT_OVERRIDES.get(normalized_book)
        if override:
            override_doc = collection.document(override)
            if override_doc.get().exists:
                return override

    candidates = _book_name_candidates(book)
    if not candidates:
        return None

    documents = list(collection.list_documents())
    for doc in documents:
        prefix = _normalize_book_token(doc.id.split(" ")[0])
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


def _extract_verse_text(data):
    text = ""
    if isinstance(data, dict):
        blocks_before = data.get("blocks_before")
        if isinstance(blocks_before, list):
            text_parts = []
            for block in blocks_before:
                if not isinstance(block, dict):
                    continue
                part = (block.get("text") or "").strip()
                if part:
                    text_parts.append(part)
            if text_parts:
                text = " ".join(text_parts).strip()
        if not text:
            text = (data.get("text") or "").strip()
    return text


def _build_verse_payload(verse_identifier, data):
    try:
        verse_number = int(verse_identifier)
    except (TypeError, ValueError):
        verse_number = verse_identifier
    return {
        "verse": verse_number,
        "text": _extract_verse_text(data),
    }


def _load_single_verse(language, version, book_doc_id, chapter, verse_identifier):
    verse_ref = (
        db.collection("bibles")
        .document(language)
        .collection(version)
        .document(book_doc_id)
        .collection("chapters")
        .document(str(chapter))
        .collection("verses")
        .document(str(verse_identifier))
    )
    verse_doc = verse_ref.get()
    data = verse_doc.to_dict() if verse_doc.exists else {}
    return _build_verse_payload(verse_identifier, data)


@app.route("/get_verse", methods=["GET"])
def get_verse():
    language = request.args.get("language")
    version = request.args.get("version")
    requested_book = request.args.get("book")
    chapter = request.args.get("chapter")
    verse = request.args.get("verse")  # Can be "1" or "1-3"

    language = _select_bible_language(language)
    version = _select_bible_version(language, version)

    if not all([language, version, requested_book, chapter, verse]):
        return Response(
            json.dumps({"error": "Missing params"}),
            status=400,
            content_type="application/json",
        )

    book = _resolve_book_document_id(language, version, requested_book)
    if not book:
        return Response(
            json.dumps({"error": f"Unknown book '{requested_book}'"}),
            status=404,
            content_type="application/json",
        )

    results = []
    if "-" in verse:
        try:
            start, end = map(int, verse.split("-"))
        except ValueError:
            return Response(
                json.dumps({"error": "Invalid verse range"}),
                status=400,
                content_type="application/json",
            )
        for i in range(start, end + 1):
            results.append(_load_single_verse(language, version, book, chapter, i))
    else:
        results.append(_load_single_verse(language, version, book, chapter, verse))

    return Response(
        json.dumps(results, ensure_ascii=False, indent=2),
        content_type="application/json; charset=utf-8",
    )


@app.route("/get_chapter", methods=["GET"])
def get_chapter():
    language = request.args.get("language")
    version = request.args.get("version")
    requested_book = request.args.get("book")
    chapter = request.args.get("chapter")

    language = _select_bible_language(language)
    version = _select_bible_version(language, version)

    if not all([language, version, requested_book, chapter]):
        return Response(
            json.dumps({"error": "Missing params"}),
            status=400,
            content_type="application/json",
        )

    book = _resolve_book_document_id(language, version, requested_book)
    if not book:
        return Response(
            json.dumps({"error": f"Unknown book '{requested_book}'"}),
            status=404,
            content_type="application/json",
        )

    verses_collection = (
        db.collection("bibles")
        .document(language)
        .collection(version)
        .document(book)
        .collection("chapters")
        .document(str(chapter))
        .collection("verses")
    )

    verses = []
    for doc in verses_collection.stream():
        verses.append(_build_verse_payload(doc.id, doc.to_dict()))

    verses.sort(key=lambda item: item["verse"] if isinstance(item["verse"], int) else 0)

    return Response(
        json.dumps(verses, ensure_ascii=False, indent=2),
        content_type="application/json; charset=utf-8",
    )


def _topics_collection(language: str, version: str):
    language = _select_bible_language(language)
    version = _select_bible_version(language, version)
    references = db.collection("references")

    def _normalize(value: str) -> str:
        return (value or "").strip().lower().replace(" ", "_")

    def _strip_trailing_digits(value: str) -> str:
        stripped = value.rstrip("0123456789")
        return stripped or value

    normalized_language = _normalize(language)
    normalized_version = _normalize(version)
    base_language = _strip_trailing_digits(normalized_language)
    base_version = _strip_trailing_digits(normalized_version)

    candidate_ids = []

    def _add_candidate(candidate: str):
        normalized = _normalize(candidate)
        if normalized and normalized not in candidate_ids:
            candidate_ids.append(normalized)

    if normalized_language and normalized_version:
        _add_candidate(f"{normalized_language}_{normalized_version}")
        if base_language != normalized_language:
            _add_candidate(f"{base_language}_{normalized_version}")
        if base_version != normalized_version:
            _add_candidate(f"{normalized_language}_{base_version}")
        if base_language != normalized_language or base_version != normalized_version:
            _add_candidate(f"{base_language}_{base_version}")

    _add_candidate(normalized_language)
    if base_language != normalized_language:
        _add_candidate(base_language)

    if normalized_version:
        _add_candidate(normalized_version)
    if base_version != normalized_version:
        _add_candidate(base_version)

    for candidate in candidate_ids:
        doc_ref = references.document(candidate)
        if doc_ref.get().exists:
            return doc_ref.collection("topics")

    search_language_tokens = [token for token in {normalized_language, base_language} if token]
    search_version_tokens = [token for token in {normalized_version, base_version} if token]

    fallback_doc = None
    for doc in references.list_documents():
        doc_id_normalized = _normalize(doc.id)
        if any(token in doc_id_normalized for token in search_language_tokens):
            if search_version_tokens and any(
                token in doc_id_normalized for token in search_version_tokens
            ):
                return doc.collection("topics")
            if fallback_doc is None:
                fallback_doc = doc

    if fallback_doc is not None:
        return fallback_doc.collection("topics")

    final_candidate = candidate_ids[0] if candidate_ids else normalized_language
    return references.document(final_candidate).collection("topics")


@app.route("/topics", methods=["GET"])
def get_topics():
    language = request.args.get("language", "english")
    version = request.args.get("version", "kjv")

    language = _select_bible_language(language)
    version = _select_bible_version(language, version)

    topics_ref = _topics_collection(language, version)
    topics = []
    for doc in topics_ref.stream():
        data = doc.to_dict() or {}
        # zero-pad numeric ids, but don't crash if not numeric
        try:
            padded_id = f"{int(doc.id):02}"
        except ValueError:
            padded_id = doc.id
        topics.append(
            {
                "id": padded_id,
                "name": data.get("name", ""),
                "references": data.get("entries", []),
            }
        )

    topics.sort(key=lambda x: int(x["id"]) if x["id"].isdigit() else x["id"])
    return Response(
        json.dumps(topics, ensure_ascii=False, indent=2),
        content_type="application/json; charset=utf-8",
    )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000, debug=True)
