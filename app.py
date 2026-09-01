from flask import Flask, request, Response
import json
import os
import re
from flask_cors import CORS
from werkzeug.exceptions import RequestEntityTooLarge

from admin_api import admin_api
from services.firebase_service import firestore_client


db = firestore_client()

app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = int(
    os.environ.get("MAX_ADMIN_UPLOAD_BYTES", str(32 * 1024 * 1024))
)
app.register_blueprint(admin_api)


def _cors_origins():
    configured = os.environ.get("CORS_ORIGINS", "").strip()
    if configured:
        return [origin.strip() for origin in configured.split(",") if origin.strip()]

    # TODO: Replace the raw VPS IP with the production HTTPS domain once deployed.
    return [
        "http://localhost:8760",
        "http://127.0.0.1:8760",
        "http://164.68.108.181",
        "http://164.68.108.181:8760",
    ]


CORS(
    app,
    resources={
        r"/*": {
            "origins": _cors_origins(),
            "methods": ["GET", "POST", "OPTIONS"],
            "allow_headers": ["Authorization", "Content-Type"],
        }
    },
)


def _json_response(payload, status=200, cache_seconds=300):
    response = Response(
        json.dumps(payload, ensure_ascii=False),
        status=status,
        content_type="application/json; charset=utf-8",
    )
    if status == 200 and cache_seconds > 0:
        response.headers["Cache-Control"] = f"public, max-age={cache_seconds}"
    else:
        response.headers["Cache-Control"] = "no-store"
    return response


@app.errorhandler(RequestEntityTooLarge)
def _upload_too_large(_error):
    maximum_mb = app.config["MAX_CONTENT_LENGTH"] // (1024 * 1024)
    return _json_response(
        {
            "error": {
                "code": "upload_too_large",
                "message": f"The upload exceeds the {maximum_mb} MB server limit.",
            }
        },
        status=413,
        cache_seconds=0,
    )


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
    selected_language = _select_bible_language(language)
    selected_version = _select_bible_version(selected_language, version)
    topic_language = _requested_topic_language(selected_language)
    localization_names, localization_source = _topic_localization_context(
        topic_language
    )
    canonical_topics = _canonical_topics_collection()
    if canonical_topics is None and localization_names:
        canonical_topics = _reference_source_collection(localization_source)
    topics = (
        canonical_topics
        if canonical_topics is not None
        else _topics_collection(selected_language, selected_version)
    )
    normalized_topic_id = _normalize_topic_id(topic_id)
    doc_ref = topics.document(normalized_topic_id)
    doc = doc_ref.get()
    if not doc.exists:
        return _json_response({"error": "Topic not found"}, status=404)

    data = doc.to_dict() or {}
    if canonical_topics is not None:
        localized_name = localization_names.get(normalized_topic_id)
        if localized_name:
            data["name"] = localized_name
    data["id"] = doc.id
    return _json_response(data, cache_seconds=0)


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
    if normalized.lower() in {"arabic", "arabic2", "arabic3", "ar"}:
        return "arabic"
    return normalized


def _select_bible_version(language: str, version: str) -> str:
    normalized_language = (language or "").strip().lower()
    requested_version = (version or "").strip()

    if normalized_language == "arabic":
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


def _bible_books_collection(language: str, version: str):
    language_ref = db.collection("bibles").document(language)
    version_meta = language_ref.collection("versions").document(version).get()
    if version_meta.exists:
        active_path = (version_meta.to_dict() or {}).get("activeBooksPath")
        if isinstance(active_path, str) and active_path:
            return db.collection(active_path)
    return language_ref.collection(version)


def _resolve_book_document_id(language: str, version: str, book: str):
    collection = _bible_books_collection(language, version)
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
    if not isinstance(data, dict):
        return ""

    text = (data.get("text") or "").strip()
    if text:
        return text

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
            return " ".join(text_parts).strip()

    return ""


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
        _bible_books_collection(language, version)
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
        return _json_response({"error": "Missing params"}, status=400)

    book = _resolve_book_document_id(language, version, requested_book)
    if not book:
        return _json_response(
            {"error": f"Unknown book '{requested_book}'"},
            status=404,
        )

    results = []
    if "-" in verse:
        try:
            start, end = map(int, verse.split("-"))
        except ValueError:
            return _json_response({"error": "Invalid verse range"}, status=400)
        for i in range(start, end + 1):
            results.append(_load_single_verse(language, version, book, chapter, i))
    else:
        results.append(_load_single_verse(language, version, book, chapter, verse))

    return _json_response(results, cache_seconds=0)


@app.route("/get_chapter", methods=["GET"])
def get_chapter():
    language = request.args.get("language")
    version = request.args.get("version")
    requested_book = request.args.get("book")
    chapter = request.args.get("chapter")

    language = _select_bible_language(language)
    version = _select_bible_version(language, version)

    if not all([language, version, requested_book, chapter]):
        return _json_response({"error": "Missing params"}, status=400)

    book = _resolve_book_document_id(language, version, requested_book)
    if not book:
        return _json_response(
            {"error": f"Unknown book '{requested_book}'"},
            status=404,
        )

    verses_collection = (
        _bible_books_collection(language, version)
        .document(book)
        .collection("chapters")
        .document(str(chapter))
        .collection("verses")
    )

    verses = []
    for doc in verses_collection.stream():
        verses.append(_build_verse_payload(doc.id, doc.to_dict()))

    verses.sort(key=lambda item: item["verse"] if isinstance(item["verse"], int) else 0)

    return _json_response(verses, cache_seconds=0)


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
        snapshot = doc_ref.get()
        if snapshot.exists:
            active_path = (snapshot.to_dict() or {}).get("activeTopicsPath")
            if isinstance(active_path, str) and active_path:
                return db.collection(active_path)
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
        snapshot = fallback_doc.get()
        if snapshot.exists:
            active_path = (snapshot.to_dict() or {}).get("activeTopicsPath")
            if isinstance(active_path, str) and active_path:
                return db.collection(active_path)
        return fallback_doc.collection("topics")

    final_candidate = candidate_ids[0] if candidate_ids else normalized_language
    return references.document(final_candidate).collection("topics")


def _active_child_collection(document_ref, legacy_child: str):
    snapshot = document_ref.get()
    data = snapshot.to_dict() if snapshot.exists else {}
    active_path = (data or {}).get("activeTopicsPath")
    if isinstance(active_path, str) and active_path:
        return db.collection(active_path)
    return document_ref.collection(legacy_child)


def _canonical_topics_collection():
    canonical_ref = db.collection("harmony").document("canonical")
    snapshot = canonical_ref.get()
    data = snapshot.to_dict() if snapshot.exists else {}
    active_path = (data or {}).get("activeTopicsPath")
    if isinstance(active_path, str) and active_path:
        return db.collection(active_path)
    legacy_topics = canonical_ref.collection("topics")
    if next(legacy_topics.limit(1).stream(), None) is not None:
        return legacy_topics
    return None


def _reference_source_collection(source: str):
    match = re.fullmatch(r"references/([A-Za-z0-9_-]{1,80})", source or "")
    if match is None:
        return None
    reference = db.collection("references").document(match.group(1))
    snapshot = reference.get()
    data = snapshot.to_dict() if snapshot.exists else {}
    active_path = (data or {}).get("activeTopicsPath")
    if isinstance(active_path, str) and active_path:
        return db.collection(active_path)
    legacy_topics = reference.collection("topics")
    if next(legacy_topics.limit(1).stream(), None) is not None:
        return legacy_topics
    return None


def _topic_localization_context(language: str) -> tuple[dict[str, str], str]:
    language = _normalize_topic_language(language)
    localization_ref = db.collection("harmony_localizations").document(language)
    snapshot = localization_ref.get()
    if not snapshot.exists:
        return {}, ""
    metadata = snapshot.to_dict() or {}
    collection = _active_child_collection(localization_ref, "topics")
    names = {
        _normalize_topic_id(document.id): str(
            (document.to_dict() or {}).get("name") or ""
        ).strip()
        for document in collection.stream()
    }
    source = str(metadata.get("canonicalSource") or "").strip()
    if not source:
        fallback = os.environ.get(
            "HARMONY_CANONICAL_FALLBACK", "english_kjv"
        ).strip()
        source = f"references/{fallback}" if fallback else ""
    return names, source


def _topic_localization_names(language: str) -> dict[str, str]:
    names, _ = _topic_localization_context(language)
    return names


def _normalize_topic_language(language: str) -> str:
    normalized = (language or "").strip().lower()
    aliases = {"ar": "arabic", "arabic2": "arabic", "arabic3": "arabic", "en": "english"}
    return aliases.get(normalized, normalized or "english")


def _requested_topic_language(legacy_language: str = "english") -> str:
    """Resolve the table-language dimension without breaking legacy links.

    New callers send ``topicLanguage`` (or ``tableLanguage``).  Historic URLs
    only have ``language`` and used that value for both table and Bible text, so
    the legacy Bible language remains the fallback when no explicit table
    language is present.
    """

    explicit = request.args.get("topicLanguage") or request.args.get("tableLanguage")
    return _normalize_topic_language(explicit or legacy_language)


def _normalize_topic_id(topic_id: str) -> str:
    value = str(topic_id or "").strip()
    if value.isdigit():
        return str(int(value))
    return value


def _topic_order(value, fallback: str) -> int:
    try:
        return int(value if value not in (None, "") else fallback)
    except (TypeError, ValueError):
        return 0


def _canonical_topic_payload(document) -> dict:
    data = document.to_dict() or {}
    topic_id = _normalize_topic_id(document.id)
    canonical_order = _topic_order(
        data.get("canonicalOrder", data.get("order")), topic_id
    )
    return {
        "id": topic_id,
        "canonicalOrder": canonical_order,
        "references": data.get("entries", []),
        "referenceCells": data.get("referenceCells", []),
        "referenceGrammarVersion": data.get("referenceGrammarVersion", 1),
    }


def _canonical_topic_payloads(collection_ref) -> list[dict]:
    payloads = [_canonical_topic_payload(document) for document in collection_ref.stream()]
    payloads.sort(key=lambda item: (item["canonicalOrder"], item["id"]))
    return payloads


def _topic_language_metadata(language: str) -> dict | None:
    language = _normalize_topic_language(language)
    document = db.collection("harmony_localizations").document(language)
    snapshot = document.get()
    if not snapshot.exists:
        return None
    data = snapshot.to_dict() or {}
    topic_count = int(data.get("topicCount") or 0)
    updated_at = data.get("updatedAt")
    if hasattr(updated_at, "isoformat"):
        updated_at = updated_at.isoformat()
    elif updated_at is not None:
        updated_at = str(updated_at)
    return {
        "id": language,
        "label": str(data.get("label") or language.title()),
        "direction": str(data.get("direction") or "ltr").lower(),
        "gospels": data.get("gospels") if isinstance(data.get("gospels"), dict) else {},
        "active": data.get("active", True) is not False,
        "topicCount": topic_count,
        "canonicalSource": str(data.get("canonicalSource") or "harmony/canonical"),
        "updatedAt": updated_at,
    }


def _legacy_localization_payload(language: str) -> tuple[dict | None, list[dict]]:
    """Read-only bridge for installations not yet migrated to localizations."""

    normalized = _normalize_topic_language(language)
    candidates = []
    for reference in db.collection("references").list_documents():
        snapshot = reference.get()
        data = snapshot.to_dict() if snapshot.exists else {}
        dataset_language = _normalize_topic_language(
            str((data or {}).get("language") or reference.id.split("_")[0])
        )
        if dataset_language == normalized:
            candidates.append((reference, data or {}))
    if not candidates:
        return None, []
    reference, data = candidates[0]
    collection = _active_child_collection(reference, "topics")
    topics = []
    for document in collection.stream():
        value = document.to_dict() or {}
        topics.append(
            {
                "id": _normalize_topic_id(document.id),
                "canonicalOrder": _topic_order(
                    value.get("canonicalOrder"), _normalize_topic_id(document.id)
                ),
                "name": str(value.get("name") or "").strip(),
            }
        )
    topics.sort(key=lambda item: (item["canonicalOrder"], item["id"]))
    metadata = {
        "id": normalized,
        "label": str(data.get("label") or normalized.title()),
        "direction": str(data.get("direction") or ("rtl" if normalized == "arabic" else "ltr")),
        "gospels": data.get("gospels") if isinstance(data.get("gospels"), dict) else {},
        "active": data.get("active", True) is not False,
        "topicCount": len(topics),
        "canonicalSource": f"references/{reference.id}",
        "legacyFallback": True,
    }
    return metadata, topics


@app.route("/harmony/topics", methods=["GET"])
def get_canonical_harmony_topics():
    topics_ref = _canonical_topics_collection()
    source = "harmony/canonical"
    if topics_ref is None:
        fallback = os.environ.get("HARMONY_CANONICAL_FALLBACK", "english_kjv").strip()
        topics_ref = _reference_source_collection(f"references/{fallback}")
        source = f"references/{fallback}"
    if topics_ref is None:
        return _json_response(
            {"error": "Canonical Harmony topics are not available."},
            status=404,
            cache_seconds=0,
        )
    return _json_response(
        {"source": source, "topics": _canonical_topic_payloads(topics_ref)},
        cache_seconds=60,
    )


@app.route("/topic-languages", methods=["GET"])
def get_topic_languages():
    languages = []
    for document in db.collection("harmony_localizations").list_documents():
        metadata = _topic_language_metadata(document.id)
        if metadata is not None and metadata["active"]:
            languages.append(metadata)
    languages.sort(key=lambda item: (item["label"].casefold(), item["id"]))
    return _json_response({"languages": languages}, cache_seconds=60)


@app.route("/topic-localizations/<language>", methods=["GET"])
def get_topic_localization(language):
    normalized = _normalize_topic_language(language)
    metadata = _topic_language_metadata(normalized)
    topics = []
    if metadata is not None:
        localization_ref = db.collection("harmony_localizations").document(normalized)
        collection = _active_child_collection(localization_ref, "topics")
        for document in collection.stream():
            data = document.to_dict() or {}
            topics.append(
                {
                    "id": _normalize_topic_id(document.id),
                    "canonicalOrder": _topic_order(
                        data.get("canonicalOrder"), _normalize_topic_id(document.id)
                    ),
                    "name": str(data.get("name") or "").strip(),
                }
            )
    else:
        metadata, topics = _legacy_localization_payload(normalized)
    if metadata is None:
        return _json_response(
            {"error": f'Topic language "{normalized}" is not available.'},
            status=404,
            cache_seconds=0,
        )
    topics.sort(key=lambda item: (item["canonicalOrder"], item["id"]))
    canonical_ref = _canonical_topics_collection()
    canonical_count = len(_canonical_topic_payloads(canonical_ref)) if canonical_ref else 0
    metadata = dict(metadata)
    metadata["canonicalTopicCount"] = canonical_count
    metadata["complete"] = canonical_count > 0 and len(topics) == canonical_count
    return _json_response(
        {"language": metadata, "topics": topics}, cache_seconds=60
    )


@app.route("/topics", methods=["GET"])
def get_topics():
    language = request.args.get("language", "english")
    version = request.args.get("version", "kjv")

    language = _select_bible_language(language)
    version = _select_bible_version(language, version)
    topic_language = _requested_topic_language(language)

    localization_names, localization_source = _topic_localization_context(topic_language)
    canonical_topics_ref = _canonical_topics_collection()
    if canonical_topics_ref is None and localization_names:
        canonical_topics_ref = _reference_source_collection(localization_source)
    topics_ref = (
        canonical_topics_ref
        if canonical_topics_ref is not None
        else _topics_collection(language, version)
    )
    topics = []
    for doc in topics_ref.stream():
        data = doc.to_dict() or {}
        topic_id = _normalize_topic_id(doc.id)
        canonical_order = _topic_order(
            data.get("canonicalOrder", data.get("order")), topic_id
        )
        topics.append(
            {
                "id": topic_id,
                "canonicalOrder": canonical_order,
                "name": localization_names.get(topic_id) or data.get("name", ""),
                "references": data.get("entries", []),
                "referenceCells": data.get("referenceCells", []),
                "referenceGrammarVersion": data.get("referenceGrammarVersion", 1),
            }
        )

    topics.sort(key=lambda x: (x["canonicalOrder"], x["id"]))
    return _json_response(topics, cache_seconds=0)


if __name__ == "__main__":
    app.run(
        host="0.0.0.0",
        port=8010,
        debug=os.environ.get("FLASK_DEBUG", "").strip() == "1",
    )
