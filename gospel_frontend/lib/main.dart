import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gospel_frontend/auth_screen.dart';
import 'package:gospel_frontend/main_scaffold.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:gospel_frontend/utils/format_verse_ref.dart';
import 'package:gospel_frontend/widgets/verse_ref_text.dart';
import 'reference_link_opener.dart';

// ---- CONFIGURATION ----
const apiBaseUrl = "http://164.68.108.181:8000"; // Change if your backend is hosted elsewhere
const defaultLanguage = "english";
// Default version key used when fetching topics and verses
const defaultVersion = "kjv";
const arabicVersionWithDiacritics = 'Van Dyke';
const arabicVersionWithoutDiacritics = 'Van Dyke-';
const _versionFieldCandidates = [
  'versions',
  'availableVersions',
  'available_versions',
  'versionList',
  'version_list',
  'supportedVersions',
  'supported_versions',
];

class LanguageSelectionController {
  LanguageSelectionController._();

  static final LanguageSelectionController instance =
      LanguageSelectionController._();

  String _languageCode = defaultLanguage;
  SharedPreferences? _prefs;
  bool _initialized = false;

  String get languageCode => _languageCode;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      _prefs = prefs;
      final stored = prefs.getString('selected_language_code');
      if (stored != null && stored.trim().isNotEmpty) {
        _languageCode = stored.trim();
      }
    } catch (_) {
      // If persistence fails we silently fall back to defaults.
    } finally {
      _initialized = true;
    }
  }

  void update(String code) {
    final normalized = code.trim();
    if (normalized.isEmpty) {
      return;
    }
    _languageCode = normalized;
    final prefs = _prefs;
    if (prefs != null) {
      prefs.setString('selected_language_code', normalized);
    }
  }
}

class BibleVersion {
  final String id;
  final String label;

  const BibleVersion({required this.id, required this.label});
}

class LanguageOption {
  final List<BibleVersion> versions;
  final String code;
  final String label;
  final String apiLanguage;
  final String apiVersion;
  final String versionLabel;
  final TextDirection direction;
  final String title;
  final String description;
  final String downloadLabel;
  final String resetLabel;
  final String pdfUnavailableMessage;
  final String subjectsHeader;
  final List<String> gospelHeaders;
  final String tooltipMessage;
  final String comparePrompt;

  const LanguageOption({
    required this.code,
    required this.label,
    required this.apiLanguage,
    required this.apiVersion,
    required this.versionLabel,
    required this.direction,
    required this.title,
    required this.description,
    required this.downloadLabel,
    required this.resetLabel,
    required this.pdfUnavailableMessage,
    required this.subjectsHeader,
    required this.gospelHeaders,
    required this.tooltipMessage,
    required this.comparePrompt,
    required this.versions,
  });

  LanguageOption copyWith({
    List<BibleVersion>? versions,
    String? code,
    String? label,
    String? apiLanguage,
    String? apiVersion,
    String? versionLabel,
    TextDirection? direction,
  }) {
    return LanguageOption(
      code: code ?? this.code,
      label: label ?? this.label,
      apiLanguage: apiLanguage ?? this.apiLanguage,
      apiVersion: apiVersion ?? this.apiVersion,
      versionLabel: versionLabel ?? this.versionLabel,
      direction: direction ?? this.direction,
      title: title,
      description: description,
      downloadLabel: downloadLabel,
      resetLabel: resetLabel,
      pdfUnavailableMessage: pdfUnavailableMessage,
      subjectsHeader: subjectsHeader,
      gospelHeaders: gospelHeaders,
      tooltipMessage: tooltipMessage,
      comparePrompt: comparePrompt,
      versions: versions ?? this.versions,
    );
  }
}

const List<LanguageOption> kBaseLanguageOptions = [
  LanguageOption(
    code: 'english',
    label: 'English',
    apiLanguage: 'english',
    apiVersion: 'kjv',
    versionLabel: 'KJV',
    versions: [
      BibleVersion(id: 'kjv', label: 'KJV'),
      BibleVersion(id: 'ASV', label: 'ASV'),
    ],
    direction: TextDirection.ltr,
    title: 'Harmony of the Gospels',
    description:
        'Explore a side-by-side overview of the key events recorded by Matthew, '
        'Mark, Luke, and John. Tap a subject to read the passages together.',
    downloadLabel: 'Download PDF',
    resetLabel: 'Reset Table',
    pdfUnavailableMessage: 'PDF download will be available soon.',
    subjectsHeader: 'Subjects',
    gospelHeaders: ['Matthew', 'Mark', 'Luke', 'John'],
    tooltipMessage: 'Click to view more',
    comparePrompt: 'Select authors to compare',
  ),
  LanguageOption(
    code: 'arabic',
    label: 'العربية',
    apiLanguage: 'arabic',
    apiVersion: arabicVersionWithDiacritics,
    versionLabel: 'Van Dyke',
    versions: [
      BibleVersion(id: 'Van Dyke', label: 'Van Dyke'),
      BibleVersion(id: 'Van Dyke-', label: 'Van Dyke'),
      BibleVersion(id: 'New Arabic Version', label: 'New Arabic Version'),
      BibleVersion(id: 'New Arabic Version-', label: 'New Arabic Version'),
    ],
    direction: TextDirection.rtl,
    title: 'تناغم الأناجيل',
    description:
        'استكشف نظرة عامة جنبًا إلى جنب على الأحداث الرئيسية التي سجلها '
        'متى ومرقس ولوقا ويوحنا. اضغط على موضوع لقراءة المقاطع معًا.',
    downloadLabel: 'تحميل PDF',
    resetLabel: 'إعادة تعيين الجدول',
    pdfUnavailableMessage: 'سيكون تنزيل ملف PDF متاحًا قريبًا.',
    subjectsHeader: 'المواضيع',
    gospelHeaders: ['متى', 'مرقس', 'لوقا', 'يوحنا'],
    tooltipMessage: 'اضغط لعرض المزيد',
    comparePrompt: 'اختر الأناجيل للمقارنة',
  ),
];

List<LanguageOption> _supportedLanguages =
    List<LanguageOption>.from(kBaseLanguageOptions);

final Map<String, LanguageOption> _baseLanguageLookup = {
  for (final option in kBaseLanguageOptions)
    option.code.toLowerCase(): option,
};

String _formatLanguageLabel(String raw) {
  if (raw.isEmpty) {
    return raw;
  }
  if (raw.length == 1) {
    return raw.toUpperCase();
  }
  return raw[0].toUpperCase() + raw.substring(1);
}

LanguageOption _fallbackLanguageOption(
    String languageId, List<BibleVersion> versions) {
  final template = _baseLanguageLookup['english'] ?? kBaseLanguageOptions.first;
  final sanitizedVersions = versions.isNotEmpty ? versions : template.versions;
  final apiVersion =
      sanitizedVersions.isNotEmpty ? sanitizedVersions.first.id : template.apiVersion;
  final normalizedCode = languageId.trim().isEmpty
      ? template.code
      : languageId.trim().toLowerCase();
  return template.copyWith(
    code: normalizedCode,
    label: _formatLanguageLabel(languageId),
    apiLanguage: languageId,
    apiVersion: apiVersion,
    versions: sanitizedVersions,
    direction: TextDirection.ltr,
  );
}

String _versionLabel(String languageId, String versionId) {
  final normalizedLanguage = languageId.trim().toLowerCase();
  final normalizedVersion = versionId.trim();
  if (normalizedLanguage == 'arabic') {
    final stripped = normalizedVersion.endsWith('-')
        ? normalizedVersion.substring(0, normalizedVersion.length - 1).trim()
        : normalizedVersion;
    final baseLabel = _formatLanguageLabel(
        stripped.isNotEmpty ? stripped : normalizedVersion);
    return baseLabel;
  }
  return _formatLanguageLabel(normalizedVersion);
}

void _collectVersionId(dynamic value, Set<String> versionIds) {
  final id = value?.toString().trim();
  if (id != null && id.isNotEmpty) {
    versionIds.add(id);
  }
}

void _collectVersionIdsFromField(dynamic field, Set<String> versionIds) {
  if (field is Iterable) {
    for (final entry in field) {
      _collectVersionId(entry, versionIds);
    }
  } else if (field is Map) {
    for (final entry in field.entries) {
      _collectVersionId(entry.key, versionIds);
    }
  }
}

void _collectVersionIdsFromData(
    Map<String, dynamic> data, Set<String> versionIds) {
  for (final candidate in _versionFieldCandidates) {
    if (data.containsKey(candidate)) {
      _collectVersionIdsFromField(data[candidate], versionIds);
    }
  }

  for (final entry in data.entries) {
    final key = entry.key.toString().trim();
    if (key.isEmpty || key == 'label' || key == 'direction') {
      continue;
    }
    versionIds.add(key);
  }
}

Future<void> _collectVersionManifestDocs(
    DocumentReference<Map<String, dynamic>> docRef,
    Set<String> versionIds) async {
  const manifestPaths = [
    ['versions', 'manifest'],
    ['versions', '_index'],
    ['metadata', 'versions'],
    ['meta', 'versions'],
    ['version_manifest', 'index'],
    ['version_manifest', 'all'],
  ];

  for (final path in manifestPaths) {
    try {
      final snapshot = await docRef.collection(path[0]).doc(path[1]).get();
      if (snapshot.exists) {
        final data = snapshot.data() ?? {};
        _collectVersionIdsFromData(data, versionIds);
      }
    } catch (_) {
      // Ignore manifest lookup failures and keep trying other sources.
    }
  }
}

Future<List<BibleVersion>> _loadVersionsForLanguage(String languageId) async {
  final docRef = FirebaseFirestore.instance.collection('bibles').doc(languageId);
  final Set<String> versionIds = {};

  try {
    final docSnapshot = await docRef.get();
    final data = docSnapshot.data() ?? {};
    _collectVersionIdsFromData(data, versionIds);
  } catch (_) {
    // If fetching the document fails, we fall back to other sources below.
  }

  await _collectVersionManifestDocs(docRef, versionIds);

  try {
    final versionsCollection = await docRef.collection('versions').get();
    for (final versionDoc in versionsCollection.docs) {
      final id = versionDoc.id.trim();
      if (id.isNotEmpty) {
        versionIds.add(id);
      }
      final versionData = versionDoc.data();
      _collectVersionIdsFromData(versionData, versionIds);
    }
  } catch (_) {
    // The collection may not exist or security rules may block listing.
  }

  final versions = versionIds
      .map((id) => BibleVersion(
          id: id,
          label: _versionLabel(languageId, id)))
      .toList();
  versions.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
  return versions;
}

Future<List<LanguageOption>> _loadLanguagesFromFirestore() async {
  final snapshot = await FirebaseFirestore.instance.collection('bibles').get();
  if (snapshot.docs.isEmpty) {
    return kBaseLanguageOptions;
  }

  final List<LanguageOption> options = [];
  for (final doc in snapshot.docs) {
    final languageId = doc.id.trim();
    if (languageId.isEmpty) {
      continue;
    }
    final normalizedCode = languageId.toLowerCase();
    final baseOption = _baseLanguageLookup[normalizedCode];
    final data = doc.data();
    final labelFromData = (data['label'] as String?)?.trim();
    final directionField = (data['direction'] as String?)?.trim().toLowerCase();
    final versions = await _loadVersionsForLanguage(languageId);

    final template = baseOption ?? _fallbackLanguageOption(languageId, versions);
    final sanitizedVersions = versions.isNotEmpty ? versions : template.versions;
    final apiVersion = sanitizedVersions.isNotEmpty
        ? sanitizedVersions.first.id
        : template.apiVersion;
    final direction = directionField == 'rtl'
        ? TextDirection.rtl
        : directionField == 'ltr'
            ? TextDirection.ltr
            : template.direction;

    options.add(template.copyWith(
      code: normalizedCode,
      label: labelFromData?.isNotEmpty == true
          ? labelFromData!
          : (baseOption?.label ?? _formatLanguageLabel(languageId)),
      apiLanguage: languageId,
      apiVersion: apiVersion,
      versions: sanitizedVersions,
      direction: direction,
    ));
  }

  return options.isNotEmpty ? options : kBaseLanguageOptions;
}

LanguageOption _languageOptionForCode(String code) {
  return _supportedLanguages.firstWhere(
    (option) => option.code == code,
    orElse: () => _supportedLanguages.first,
  );
}

BibleVersion? _versionOptionFor(LanguageOption option, String versionId) {
  final normalized = versionId.trim().toLowerCase();
  for (final version in option.versions) {
    if (version.id.toLowerCase() == normalized ||
        version.label.toLowerCase() == normalized) {
      return version;
    }
  }
  return null;
}

LanguageOption? _languageOptionForApiLanguage(String apiLanguage) {
  final normalized = apiLanguage.trim().toLowerCase();
  if (normalized.isEmpty) {
    return null;
  }
  const aliases = {
    'arabic2': 'arabic',
    'ar': 'arabic',
    'en': 'english',
  };
  final canonical = aliases[normalized] ?? normalized;
  try {
    return _supportedLanguages.firstWhere(
      (option) => option.apiLanguage.toLowerCase() == canonical,
    );
  } catch (_) {
    return null;
  }
}

LanguageOption _languageOptionForVersion(String version) {
  final normalized = version.trim().toLowerCase();
  for (final option in _supportedLanguages) {
    if (_versionOptionFor(option, normalized) != null ||
        option.apiVersion.toLowerCase() == normalized ||
        option.code == normalized ||
        option.label.toLowerCase() == normalized) {
      return option;
    }
  }
  if (normalized == 'arabic2') {
    return _languageOptionForCode('arabic');
  }
  if (normalized.contains('van') &&
      (normalized.contains('dyck') || normalized.contains('dyke'))) {
    return _languageOptionForCode('arabic');
  }
  return _languageOptionForCode(defaultLanguage);
}

String _normalizeArabicBaseVersion(String version) {
  final trimmed = version.trim();
  if (trimmed.isEmpty) {
    return '';
  }

  final withoutSuffix =
      trimmed.endsWith('-') ? trimmed.substring(0, trimmed.length - 1) : trimmed;
  final normalized = withoutSuffix.toLowerCase();

  if (normalized.contains('dyck')) {
    return normalized.replaceAll('dyck', 'dyke');
  }

  return normalized;
}

String? _resolveArabicVersion(LanguageOption option,
    {required bool withDiacritics, String? preferredVersion}) {
  final preferredBase =
      preferredVersion != null && preferredVersion.trim().isNotEmpty
          ? _normalizeArabicBaseVersion(preferredVersion)
          : null;

  BibleVersion? fallback;
  for (final version in option.versions) {
    final matchesDiacritics =
        _isArabicWithoutDiacritics(version.id) == !withDiacritics;
    if (!matchesDiacritics) {
      continue;
    }
    fallback ??= version;
    if (preferredBase != null &&
        _normalizeArabicBaseVersion(version.id) == preferredBase) {
      return version.id;
    }
  }

  if (preferredVersion != null && preferredVersion.trim().isNotEmpty) {
    if (fallback != null) {
      return fallback.id;
    }
    final normalizedPreferred = preferredVersion.trim();
    if (withDiacritics && _isArabicWithoutDiacritics(normalizedPreferred)) {
      return normalizedPreferred.endsWith('-')
          ? normalizedPreferred.substring(0, normalizedPreferred.length - 1)
          : normalizedPreferred;
    }
    if (!withDiacritics && !_isArabicWithoutDiacritics(normalizedPreferred)) {
      return '${normalizedPreferred}-';
    }
    return normalizedPreferred;
  }

  return fallback?.id ??
      (withDiacritics ? arabicVersionWithDiacritics : arabicVersionWithoutDiacritics);
}

String _sanitizeVersionForLanguage(LanguageOption option, String rawVersion) {
  final normalized = rawVersion.trim();

  if (option.code == 'arabic') {
    final effectiveVersion =
        normalized.isNotEmpty ? normalized : option.apiVersion.trim();
    final resolved = _resolveArabicVersion(option,
        withDiacritics: !_isArabicWithoutDiacritics(effectiveVersion),
        preferredVersion: effectiveVersion);
    return resolved ?? option.apiVersion;
  }

  if (normalized.isEmpty) {
    return option.apiVersion;
  }

  final match = _versionOptionFor(option, normalized);
  if (match != null) {
    return match.id;
  }

  return option.apiVersion;
}

bool _isArabicWithoutDiacritics(String version) {
  final normalized = version.trim().toLowerCase();
  return normalized == arabicVersionWithoutDiacritics.toLowerCase() ||
      normalized.endsWith('-');
}

String _arabicBaseVersion(String version) {
  final trimmed = version.trim();
  if (trimmed.isEmpty) {
    return trimmed;
  }
  if (trimmed.endsWith('-')) {
    return trimmed.substring(0, trimmed.length - 1).trim();
  }
  return trimmed;
}

String _versionIdentityKey(LanguageOption option, String version) {
  final normalized = version.trim();
  if (option.code == 'arabic') {
    return _arabicBaseVersion(normalized).toLowerCase();
  }
  return normalized.toLowerCase();
}

bool _isSameTranslation(LanguageOption a, String versionA, LanguageOption b,
    String versionB) {
  if (a.code != b.code) {
    return false;
  }
  return _versionIdentityKey(a, versionA) == _versionIdentityKey(b, versionB);
}

List<BibleVersion> _selectableVersions(LanguageOption option) {
  if (option.code != 'arabic') {
    return option.versions;
  }
  final filtered = option.versions
      .where((version) => !_isArabicWithoutDiacritics(version.id))
      .toList();
  return filtered.isNotEmpty ? filtered : option.versions;
}

String _selectionVersionValue(LanguageOption option, String versionId) {
  if (option.code != 'arabic') {
    return versionId;
  }
  return _arabicBaseVersion(versionId);
}

LanguageOption _resolveLanguageOption({
  String? languageParam,
  String? versionParam,
}) {
  final normalizedLanguage = languageParam?.trim() ?? '';
  final normalizedVersion = versionParam?.trim() ?? '';

  LanguageOption? option;
  if (normalizedLanguage.isNotEmpty) {
    option = _languageOptionForApiLanguage(normalizedLanguage) ??
        _languageOptionForCode(normalizedLanguage.toLowerCase()) ??
        _languageOptionForVersion(normalizedLanguage);
  }

  if (option == null && normalizedVersion.isNotEmpty) {
    option = _languageOptionForVersion(normalizedVersion);
  }

  return option ?? _languageOptionForCode(defaultLanguage);
}

// Order in which gospel references should appear.
// Accept both common spellings for Matthew to maintain sort order.
const Map<String, int> canonicalGospelsIndex = {
  'Matthew': 0,
  'Mathew': 0,
  'Mark': 1,
  'Luke': 2,
  'John': 3,
};

const List<String> orderedGospels = ['Matthew', 'Mark', 'Luke', 'John'];

const Map<String, int> gospelChapterCounts = {
  'Matthew': 28,
  'Mark': 16,
  'Luke': 24,
  'John': 21,
};

const Map<String, String> gospelNameSynonyms = {
  'mathew': 'Matthew',
  'matthew': 'Matthew',
  'mark': 'Mark',
  'luke': 'Luke',
  'john': 'John',
  'متى': 'Matthew',
  'متّى': 'Matthew',
  'مرقس': 'Mark',
  'لوقا': 'Luke',
  'يوحنا': 'John',
  'يوحنّا': 'John',
};

const Map<String, String> _arabicGospelDisplayNames = {
  'Matthew': 'متى',
  'Mark': 'مرقس',
  'Luke': 'لوقا',
  'John': 'يوحنا',
};

String _normalizeGospelName(String name) {
  final trimmed = name.trim();
  final lower = trimmed.toLowerCase();
  if (gospelNameSynonyms.containsKey(lower)) {
    return gospelNameSynonyms[lower]!;
  }
  if (gospelNameSynonyms.containsKey(trimmed)) {
    return gospelNameSynonyms[trimmed]!;
  }
  return trimmed;
}

int _gospelIndex(String book) {
  final normalized = _normalizeGospelName(book);
  return canonicalGospelsIndex[normalized] ??
      canonicalGospelsIndex[book] ??
      canonicalGospelsIndex[book.toLowerCase()] ??
      canonicalGospelsIndex.length;
}

String _displayGospelName(String book, LanguageOption option) {
  final canonical = _normalizeGospelName(book);
  if (option.code == 'arabic') {
    return _arabicGospelDisplayNames[canonical] ?? canonical;
  }
  return canonical;
}

final RegExp _referenceDigitsPattern = RegExp(r'\d');

String _formatReferenceForDirection(String reference, TextDirection direction) {
  if (direction != TextDirection.rtl) {
    return reference;
  }
  if (!_referenceDigitsPattern.hasMatch(reference)) {
    return reference;
  }
  return '\u2066$reference\u2069';
}

String _formatArabicReference(String reference) {
  return formatVerseRef(reference, 'arabic').text;
}

String _formatReferenceForLanguage(String reference, TextDirection direction,
    {required bool isArabic}) {
  if (isArabic) {
    return _formatArabicReference(reference);
  }
  return _formatReferenceForDirection(reference, direction);
}

bool _isArabicLanguage(String language) {
  final trimmed = language.trim();
  if (trimmed.isEmpty) {
    return false;
  }
  final option = _languageOptionForApiLanguage(trimmed);
  if (option != null) {
    return option.code == 'arabic';
  }
  final normalized = trimmed.toLowerCase();
  return normalized == 'arabic' || normalized == 'arabic2' || normalized == 'ar';
}

String _combineBookAndReference(
    String book, String reference, TextDirection direction,
    {bool isArabic = false}) {
  final trimmedBook = book.trim();
  final trimmedReference = reference.trim();
  if (trimmedBook.isEmpty) {
    return _formatReferenceForLanguage(reference, direction, isArabic: isArabic);
  }
  if (trimmedReference.isEmpty) {
    return trimmedBook;
  }
  final formattedReference =
      _formatReferenceForLanguage(reference, direction, isArabic: isArabic);
  if (direction == TextDirection.rtl) {
    if (isArabic) {
      return '$trimmedBook $formattedReference';
    }
    return '$formattedReference $trimmedBook';
  }
  return '$trimmedBook $formattedReference';
}

int _compareBooks(String a, String b) {
  final indexA = _gospelIndex(a);
  final indexB = _gospelIndex(b);
  if (indexA != indexB) {
    return indexA.compareTo(indexB);
  }
  return a.toLowerCase().compareTo(b.toLowerCase());
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await LanguageSelectionController.instance.initialize();
  runApp(GospelApp());
}

class GospelApp extends StatelessWidget {
  const GospelApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gospel Topics',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      onGenerateRoute: _onGenerateRoute,
    );
  }

  Route<dynamic> _onGenerateRoute(RouteSettings settings) {
    final rawName = settings.name ?? '/';
    String normalized = rawName;
    if (normalized.startsWith('/#/')) {
      normalized = normalized.substring(2);
    }
    if (normalized.startsWith('#/')) {
      normalized = normalized.substring(1);
    }
    if (normalized.startsWith('#')) {
      normalized = normalized.substring(1);
    }
    if (normalized.isEmpty) {
      normalized = '/';
    }
    if (!normalized.startsWith('/')) {
      normalized = '/$normalized';
    }

    if (normalized == '/' || normalized.isEmpty) {
      return MaterialPageRoute(
        settings: settings,
        builder: (_) => AuthGate(
          builder: (context) => const TopicListScreen(),
        ),
      );
    }

    final uri = Uri.parse(normalized);
    final path = uri.path.isEmpty ? '/' : uri.path;
    if (path == '/reference') {
      final rawLanguage = uri.queryParameters['language'] ?? defaultLanguage;
      final rawVersion = uri.queryParameters['version'] ?? defaultVersion;
      final languageOption = _resolveLanguageOption(
        languageParam: rawLanguage,
        versionParam: rawVersion,
      );
      final language = languageOption.apiLanguage;
      final version = _sanitizeVersionForLanguage(languageOption, rawVersion);
      final bookDisplay =
          uri.queryParameters['bookDisplay'] ?? uri.queryParameters['book'] ?? '';
      final bookId = uri.queryParameters['bookId'] ?? '';
      final chapter = int.tryParse(uri.queryParameters['chapter'] ?? '') ?? 0;
      final verses = uri.queryParameters['verses'] ?? '';
      final topicName = uri.queryParameters['topic'] ?? '';
      final label = uri.queryParameters['label'] ?? '';
      final source = uri.queryParameters['source'] ?? '';
      final topicId = uri.queryParameters['topicId'] ?? '';
      final gospel = uri.queryParameters['gospel'] ?? '';
      final comparisons = uri.queryParameters['comparisons'] ?? '';

      return MaterialPageRoute(
        settings: settings,
        builder: (_) => AuthGate(
          builder: (context) => ReferenceViewerPage(
            displayBook: bookDisplay,
            bookId: bookId,
            chapter: chapter,
            verses: verses,
            language: language,
            version: version,
            topicName: topicName,
            referenceLabelOverride: label,
            source: source,
            topicId: topicId,
            gospel: gospel,
            comparisonState: comparisons,
          ),
        ),
      );
    }

    if (path == '/topic') {
      final initialLanguage = uri.queryParameters['language'] ?? defaultLanguage;
      final initialVersion = uri.queryParameters['version'] ?? defaultVersion;
      final initialTopicId = uri.queryParameters['topicId'] ?? '';

      final languageOption = _resolveLanguageOption(
        languageParam: initialLanguage,
        versionParam: initialVersion,
      );
      final sanitizedVersion = _sanitizeVersionForLanguage(
        languageOption,
        initialVersion,
      );

      return MaterialPageRoute(
        settings: settings,
        builder: (_) => AuthGate(
          builder: (context) => TopicDetailScreen(
            languageOption: languageOption,
            apiVersion: sanitizedVersion,
            topicId: initialTopicId,
          ),
        ),
      );
    }

    return MaterialPageRoute(
      settings: settings,
      builder: (_) => AuthGate(
        builder: (context) => const TopicListScreen(),
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.builder});

  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasData) {
          return builder(context);
        }
        return const AuthScreen();
      },
    );
  }
}

class TopicDetailScreen extends StatefulWidget {
  const TopicDetailScreen({
    super.key,
    required this.languageOption,
    required this.apiVersion,
    required this.topicId,
  });

  final LanguageOption languageOption;
  final String apiVersion;
  final String topicId;

  @override
  State<TopicDetailScreen> createState() => _TopicDetailScreenState();
}

class _TopicDetailScreenState extends State<TopicDetailScreen> {
  Topic? _topic;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    LanguageSelectionController.instance.update(widget.languageOption.code);
    _loadTopic();
  }

  Future<void> _loadTopic() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final uri = Uri.parse('$apiBaseUrl/topics').replace(queryParameters: {
      'language': widget.languageOption.apiLanguage,
      'version': widget.apiVersion,
    });

    try {
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        setState(() {
          _error = 'Error: ${response.statusCode}';
          _loading = false;
        });
        return;
      }

      final List data = json.decode(response.body);
      final topics = data.map((e) => Topic.fromJson(e)).toList();
      final match = _findTopic(topics);

      if (!mounted) {
        return;
      }

      setState(() {
        _topic = match;
        _loading = false;
        if (match == null) {
          _error = 'Topic not found';
        }
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Failed to fetch topic: $e';
        _loading = false;
      });
    }
  }

  Topic? _findTopic(List<Topic> topics) {
    final normalizedId = widget.topicId.trim().toLowerCase();
    for (final topic in topics) {
      final id = topic.id.trim();
      if (id.isNotEmpty && id.toLowerCase() == normalizedId) {
        return topic;
      }
      final name = topic.name.trim();
      if (name.isNotEmpty && name.toLowerCase() == normalizedId) {
        return topic;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final textDirection = widget.languageOption.direction;

    if (_loading) {
      return Directionality(
        textDirection: textDirection,
        child: const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_error != null) {
      return Directionality(
        textDirection: textDirection,
        child: Scaffold(
          appBar: AppBar(),
          body: Center(child: Text(_error!)),
        ),
      );
    }

    final topic = _topic;
    if (topic == null) {
      return Directionality(
        textDirection: textDirection,
        child: const Scaffold(
          body: Center(child: Text('Topic not found')),
        ),
      );
    }

    final authors = topic.references.map((e) => e.book).toSet().toList()
      ..sort(_compareBooks);

    return AuthorComparisonScreen(
      languageOption: widget.languageOption,
      apiVersion: widget.apiVersion,
      topic: topic,
      initialAuthors: authors,
    );
  }
}

class TopicListScreen extends StatefulWidget {
  const TopicListScreen({
    super.key,
    this.initialTopicId,
    this.initialLanguage,
    this.initialVersion,
  });

  final String? initialTopicId;
  final String? initialLanguage;
  final String? initialVersion;
  @override
  State<TopicListScreen> createState() => _TopicListScreenState();
}

class _TopicListScreenState extends State<TopicListScreen> {
  final GlobalKey<_HarmonyTableState> _tableKey =
      GlobalKey<_HarmonyTableState>();
  List<Topic> _topics = [];
  bool _loading = true;
  String? _error;
  bool _languagesLoading = true;
  String? _languageLoadError;
  String _selectedLanguageCode =
      LanguageSelectionController.instance.languageCode;
  bool _arabicWithDiacritics = false;
  final Map<String, String> _selectedVersions = {};
  SharedPreferences? _prefs;
  String? _pendingTopicId;

  LanguageOption get _languageOption =>
      _languageOptionForCode(_selectedLanguageCode);

  @override
  void initState() {
    super.initState();
    final initialLanguage = widget.initialLanguage?.trim();
    final initialVersion = widget.initialVersion?.trim();
    if (initialLanguage != null && initialLanguage.isNotEmpty) {
      final resolved = _resolveLanguageOption(
        languageParam: initialLanguage,
        versionParam: initialVersion,
      );
      _selectedLanguageCode = resolved.code;
      if (initialVersion != null && initialVersion.isNotEmpty) {
        _selectedVersions[_selectedLanguageCode] =
            _sanitizeVersionForLanguage(resolved, initialVersion);
        if (_selectedLanguageCode == 'arabic') {
          _arabicWithDiacritics = !_isArabicWithoutDiacritics(initialVersion);
        }
      }
    }
    _pendingTopicId = widget.initialTopicId?.trim().isNotEmpty == true
        ? widget.initialTopicId!.trim()
        : null;
    LanguageSelectionController.instance.update(_selectedLanguageCode);
    _initializePreferences();
    _refreshLanguagesFromFirestore();
  }

  Future<void> _reconcileSelectedVersions() async {
    if (_supportedLanguages.isEmpty || _selectedVersions.isEmpty) {
      return;
    }

    final prefs = _prefs ?? await SharedPreferences.getInstance();
    _prefs = prefs;
    final Map<String, String> updates = {};

    for (final option in _supportedLanguages) {
      final stored = _selectedVersions[option.code];
      if (stored == null) {
        continue;
      }
      final sanitized = _sanitizeVersionForLanguage(option, stored);
      if (sanitized != stored) {
        updates[option.code] = sanitized;
      }
    }

    if (updates.isEmpty) {
      return;
    }

    if (mounted) {
      setState(() {
        _selectedVersions.addAll(updates);
        final normalizedArabic = _selectedVersions['arabic'];
        if (normalizedArabic != null && normalizedArabic.trim().isNotEmpty) {
          _arabicWithDiacritics = !_isArabicWithoutDiacritics(normalizedArabic);
        }
      });
    }

    for (final entry in updates.entries) {
      try {
        await prefs.setString('selected_version_${entry.key}', entry.value);
      } catch (_) {
        // Ignore persistence errors so UI stays responsive.
      }
    }
  }

  Future<void> _initializePreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedArabicPref = prefs.getBool('arabic_with_diacritics');
      final versionSelections = <String, String>{};
      for (final option in _supportedLanguages) {
        final storedVersion =
            prefs.getString('selected_version_${option.code}') ?? '';
        if (storedVersion.trim().isNotEmpty) {
          versionSelections[option.code] = storedVersion.trim();
        }
      }
      setState(() {
        _prefs = prefs;
        if (storedArabicPref != null) {
          _arabicWithDiacritics = storedArabicPref;
        }
        _selectedVersions.addAll(versionSelections);
      });
    } catch (_) {
      // If persistence fails we silently fall back to defaults.
    } finally {
      if (mounted && !_languagesLoading) {
        fetchTopics();
      }
    }
  }

  Future<void> _refreshLanguagesFromFirestore() async {
    setState(() {
      _languagesLoading = true;
      _languageLoadError = null;
    });
    try {
      final options = await _loadLanguagesFromFirestore();
      if (!mounted) {
        return;
      }
      setState(() {
        _supportedLanguages = options;
        _languagesLoading = false;
      });

      await _reconcileSelectedVersions();

      final hasSelection =
          _supportedLanguages.any((option) => option.code == _selectedLanguageCode);
      if (!hasSelection && _supportedLanguages.isNotEmpty) {
        final fallbackCode = _supportedLanguages.first.code;
        setState(() {
          _selectedLanguageCode = fallbackCode;
        });
        LanguageSelectionController.instance.update(fallbackCode);
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _languageLoadError = 'Unable to load available languages (using defaults).';
        _languagesLoading = false;
        _supportedLanguages = kBaseLanguageOptions;
      });
    } finally {
      if (mounted) {
        fetchTopics();
      }
    }
  }

  Future<void> _updateVersionForLanguage(
      LanguageOption option, String versionId) async {
    final normalized = versionId.trim();
    if (normalized.isEmpty) {
      return;
    }
    final arabicWithDiacritics = false;
    setState(() {
      _selectedVersions[option.code] = normalized;
      if (option.code == 'arabic') {
        _arabicWithDiacritics = arabicWithDiacritics;
      }
    });
    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      _prefs = prefs;
      await prefs.setString('selected_version_${option.code}', normalized);
      if (option.code == 'arabic') {
        await prefs.setBool('arabic_with_diacritics', arabicWithDiacritics);
      }
    } catch (_) {
      // Ignore persistence errors to keep UX smooth.
    }
    if (mounted && option.code == _selectedLanguageCode) {
      fetchTopics(option);
    }
  }

  String _apiVersionFor(LanguageOption option) {
    final selectedVersion = _selectedVersions[option.code]?.trim();
    if (option.code == 'arabic') {
      final baseVersion = (selectedVersion != null && selectedVersion.isNotEmpty)
          ? selectedVersion
          : (option.versions.isNotEmpty
              ? option.versions.first.id
              : option.apiVersion);
      final resolved = _resolveArabicVersion(option,
              withDiacritics: _arabicWithDiacritics,
              preferredVersion: baseVersion) ??
          _sanitizeVersionForLanguage(option, baseVersion);
      return resolved;
    }

    if (selectedVersion != null && selectedVersion.isNotEmpty) {
      return _sanitizeVersionForLanguage(option, selectedVersion);
    }

    if (option.versions.isNotEmpty) {
      return _sanitizeVersionForLanguage(option, option.versions.first.id);
    }

    return option.apiVersion;
  }

  Future<void> fetchTopics([LanguageOption? option]) async {
    final languageOption = option ?? _languageOption;
    final apiVersion = _apiVersionFor(languageOption);
    final expectedLanguage = _languageOption.apiLanguage;
    final expectedVersion = _apiVersionFor(_languageOption);
    setState(() {
      _loading = true;
      _error = null;
    });
    final uri = Uri.parse('$apiBaseUrl/topics').replace(queryParameters: {
      'language': languageOption.apiLanguage,
      'version': apiVersion,
    });
    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        List data = json.decode(response.body);
        if (!mounted) {
          return;
        }
        if (_languageOption.apiLanguage != expectedLanguage ||
            _apiVersionFor(_languageOption) != expectedVersion) {
          return;
        }
        setState(() {
          _topics = data.map((e) => Topic.fromJson(e)).toList();
          _loading = false;
        });
        _openPendingTopicIfNeeded();
      } else {
        if (!mounted) {
          return;
        }
        if (_languageOption.apiLanguage != expectedLanguage ||
            _apiVersionFor(_languageOption) != expectedVersion) {
          return;
        }
        setState(() {
          _error = "Error: ${response.statusCode}";
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      if (_languageOption.apiLanguage != expectedLanguage ||
          _apiVersionFor(_languageOption) != expectedVersion) {
        return;
      }
      setState(() {
        _error = "Failed to fetch topics: $e";
        _loading = false;
      });
    }
  }

  void _openPendingTopicIfNeeded() {
    if (_pendingTopicId == null || _pendingTopicId!.isEmpty) {
      return;
    }
    Topic? match;
    for (final topic in _topics) {
      if (topic.id == _pendingTopicId) {
        match = topic;
        break;
      }
    }
    if (match == null) {
      return;
    }
    _pendingTopicId = null;
    WidgetsBinding.instance.addPostFrameCallback((_) => _openTopic(match!));
  }

  Widget _buildLanguageDropdown(BuildContext context) {
    final theme = Theme.of(context);

    if (_languagesLoading) {
      return const SizedBox(
        height: 48,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final dropdown = DropdownButtonHideUnderline(
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: DropdownButton<String>(
            value: _selectedLanguageCode,
            onChanged: (value) {
              if (value == null || value == _selectedLanguageCode) {
                return;
              }
              setState(() {
                _selectedLanguageCode = value;
              });
              LanguageSelectionController.instance.update(value);
              fetchTopics(_languageOptionForCode(value));
            },
            items: _supportedLanguages
                .map(
                  (option) => DropdownMenuItem(
                    value: option.code,
                    child: Text(option.label),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );


    return dropdown;
  }

  String _versionLabelFor(LanguageOption option) {
    final selectedVersion = _selectedVersions[option.code] ??
        (option.versions.isNotEmpty
            ? option.versions.first.id
            : option.apiVersion);
    final versionOption = _versionOptionFor(option, selectedVersion);
    final baseLabel = versionOption?.label ?? option.versionLabel;
    if (option.code == 'arabic') {
      if (versionOption != null) {
        return versionOption.label;
      }
      return baseLabel;
    }
    return baseLabel;
  }

  Future<void> _showVersionSelector(
      BuildContext context, LanguageOption option) async {
    final availableVersions = _selectableVersions(option);
    final currentSelection = _selectionVersionValue(
      option,
      _selectedVersions[option.code] ??
          (option.versions.isNotEmpty
              ? option.versions.first.id
              : option.apiVersion),
    );
    await showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Select version (${option.label})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              ...availableVersions.map(
                (version) => RadioListTile<String>(
                  title: Text(version.label),
                  value: version.id,
                  groupValue: currentSelection,
                  onChanged: (value) {
                    if (value != null) {
                      Navigator.of(context).pop();
                      _updateVersionForLanguage(option, value);
                    }
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _buildVersionButton(
      BuildContext context, LanguageOption languageOption) {
    final availableVersions = _selectableVersions(languageOption);
    if (availableVersions.isEmpty) {
      return const SizedBox.shrink();
    }
    final hasMultipleVersions = availableVersions.length > 1;
    return OutlinedButton.icon(
      onPressed:
          hasMultipleVersions ? () => _showVersionSelector(context, languageOption) : null,
      icon: const Icon(Icons.menu_book_outlined),
      label: Text('Version: ${_versionLabelFor(languageOption)}'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final languageOption = _languageOption;
    return Directionality(
      textDirection: languageOption.direction,
      child: MainScaffold(
        title: '',
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: double.infinity,
                              child: Center(
                                child: Text(
                                  languageOption.title,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 12,
                              runSpacing: 8,
                              children: [
                                _buildLanguageDropdown(context),
                                _buildVersionButton(context, languageOption),
                                FilledButton.icon(
                                  onPressed: () {
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(
                                      SnackBar(
                                        content: Text(languageOption
                                            .pdfUnavailableMessage),
                                      ),
                                    );
                                  },
                                  icon: const Icon(
                                      Icons.picture_as_pdf_outlined),
                                  label:
                                      Text(languageOption.downloadLabel),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () {
                                    _tableKey.currentState?.resetScroll();
                                  },
                                  icon: const Icon(Icons.refresh),
                                  label: Text(languageOption.resetLabel),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 0),
                      Expanded(
                        child: HarmonyTable(
                          key: _tableKey,
                          topics: _topics,
                          onTopicSelected: _openTopic,
                          languageOption: languageOption,
                          apiVersion: _apiVersionFor(languageOption),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  void _openTopic(Topic topic) {
    final authors = topic.references.map((e) => e.book).toSet().toList()
      ..sort(_compareBooks);
    if (kIsWeb) {
      final language = _languageOption;
      final version = _apiVersionFor(language);
      final uri = Uri(path: '/topic', queryParameters: {
        'language': language.apiLanguage,
        'version': version,
        'topicId': topic.id.isNotEmpty ? topic.id : topic.name,
      });
      openReferenceLink(uri);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AuthorComparisonScreen(
        languageOption: _languageOption,
        apiVersion: _apiVersionFor(_languageOption),
        topic: topic,
        initialAuthors: authors,
      ),
    ));
  }
}

class HarmonyTable extends StatefulWidget {
  const HarmonyTable({
    super.key,
    required this.topics,
    this.onTopicSelected,
    required this.languageOption,
    required this.apiVersion,
  });

  final List<Topic> topics;
  final ValueChanged<Topic>? onTopicSelected;
  final LanguageOption languageOption;
  final String apiVersion;

  @override
  State<HarmonyTable> createState() => _HarmonyTableState();
}

class _HarmonyTableState extends State<HarmonyTable> {
  late final ScrollController _verticalController;
  late final ScrollController _headerHorizontalController;
  late final ScrollController _bodyHorizontalController;
  bool _isSyncingHorizontalScroll = false;

  @override
  void initState() {
    super.initState();
    _verticalController = ScrollController();
    _headerHorizontalController = ScrollController();
    _bodyHorizontalController = ScrollController();
    _headerHorizontalController.addListener(_syncFromHeader);
    _bodyHorizontalController.addListener(_syncFromBody);
  }

  @override
  void dispose() {
    _verticalController.dispose();
    _headerHorizontalController.removeListener(_syncFromHeader);
    _bodyHorizontalController.removeListener(_syncFromBody);
    _headerHorizontalController.dispose();
    _bodyHorizontalController.dispose();
    super.dispose();
  }

  void resetScroll() {
    if (_verticalController.hasClients) {
      _verticalController.animateTo(0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic);
    }
    if (_bodyHorizontalController.hasClients) {
      _bodyHorizontalController.animateTo(0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic);
    }
    if (_headerHorizontalController.hasClients) {
      _headerHorizontalController.animateTo(0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic);
    }
  }

  void _syncFromHeader() {
    if (_isSyncingHorizontalScroll) return;
    if (!_headerHorizontalController.hasClients ||
        !_bodyHorizontalController.hasClients) {
      return;
    }
    final targetOffset = _headerHorizontalController.offset;
    if ((_bodyHorizontalController.offset - targetOffset).abs() < 0.5) {
      return;
    }
    _isSyncingHorizontalScroll = true;
    final position = _bodyHorizontalController.position;
    final clamped = targetOffset
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    _bodyHorizontalController.jumpTo(clamped);
    _isSyncingHorizontalScroll = false;
  }

  void _syncFromBody() {
    if (_isSyncingHorizontalScroll) return;
    if (!_bodyHorizontalController.hasClients ||
        !_headerHorizontalController.hasClients) {
      return;
    }
    final targetOffset = _bodyHorizontalController.offset;
    if ((_headerHorizontalController.offset - targetOffset).abs() < 0.5) {
      return;
    }
    _isSyncingHorizontalScroll = true;
    final position = _headerHorizontalController.position;
    final clamped = targetOffset
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    _headerHorizontalController.jumpTo(clamped);
    _isSyncingHorizontalScroll = false;
  }

  Map<String, List<GospelReference>> _groupReferences(Topic topic) {
    final map = {
      for (final gospel in orderedGospels) gospel: <GospelReference>[]
    };
    for (final reference in topic.references) {
      final key = _normalizeGospelName(reference.book);
      map.putIfAbsent(key, () => <GospelReference>[]).add(reference);
    }
    for (final entry in map.entries) {
      entry.value.sort((a, b) {
        final chapterCompare = a.chapter.compareTo(b.chapter);
        if (chapterCompare != 0) return chapterCompare;
        return a.verses.compareTo(b.verses);
      });
    }
    return map;
  }

  Widget _buildNumberedTopic({
    required int index,
    required Topic topic,
    required TextAlign textAlign,
    required bool isRtl,
    TextStyle? textStyle,
  }) {
    final alignment = isRtl ? Alignment.centerRight : Alignment.centerLeft;
    final isArabic = widget.languageOption.code == 'arabic';
    final number = isArabic
        ? toArabicIndicDigits((index + 1).toString())
        : (index + 1).toString();

    return Align(
      alignment: alignment,
      child: Row(
        mainAxisSize: MainAxisSize.max,
        mainAxisAlignment:
            isRtl ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
        children: [
          Text(
            number,
            style: textStyle,
            textAlign: TextAlign.start,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              topic.name,
              style: textStyle,
              textAlign: textAlign,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(String label, TextStyle? style, TextAlign align) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      child: Text(label, style: style, textAlign: align),
    );
  }

  Widget _buildReferenceCell(
    Topic topic,
    String gospel,
    List<GospelReference> refs,
    TextStyle? style,
    TextAlign align,
  ) {
    final filteredRefs = refs
        .where((ref) => ref.formattedReference.trim().isNotEmpty)
        .toList();

    if (filteredRefs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          '—',
          style: style,
          textAlign: align,
        ),
      );
    }

    CrossAxisAlignment crossAxisAlignment;
    switch (align) {
      case TextAlign.center:
        crossAxisAlignment = CrossAxisAlignment.center;
        break;
      case TextAlign.right:
        crossAxisAlignment = CrossAxisAlignment.end;
        break;
      default:
        crossAxisAlignment = CrossAxisAlignment.start;
        break;
    }

    final children = <Widget>[];
    for (var i = 0; i < filteredRefs.length; i++) {
            children.add(
              ReferenceHoverText(
                reference: filteredRefs[i],
                textStyle: style,
                textAlign: align,
                textDirection: widget.languageOption.direction,
                topicName: topic.name,
                topicId: topic.id.isNotEmpty ? topic.id : topic.name,
                sourceContext: 'harmony',
                gospel: gospel,
                language: widget.languageOption.apiLanguage,
                version: widget.apiVersion,
                tooltipMessage: widget.languageOption.tooltipMessage,
              ),
            );
          if (i < filteredRefs.length - 1) {
            children.add(const SizedBox(height: 6));
          }
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: crossAxisAlignment,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final languageOption = widget.languageOption;
    final isRtl = languageOption.direction == TextDirection.rtl;
    final headerStyle = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
      color: theme.colorScheme.onSurface,
    );
    final subjectStyle = theme.textTheme.bodyLarge?.copyWith(
      fontWeight: FontWeight.w600,
    );
    final referenceStyle = theme.textTheme.bodyMedium?.copyWith(
      height: 1.4,
    );
    final borderColor = theme.dividerColor.withOpacity(0.4);
    final headerBackground = theme.colorScheme.surfaceVariant;
    final subjectAlign = isRtl ? TextAlign.right : TextAlign.left;
    final referenceAlign = isRtl ? TextAlign.right : TextAlign.center;
    assert(languageOption.gospelHeaders.length == orderedGospels.length,
        'languageOption.gospelHeaders must match number of gospels');

    final headerRow = TableRow(
      decoration: BoxDecoration(color: headerBackground),
      children: [
        _buildHeaderCell(
            languageOption.subjectsHeader, headerStyle, subjectAlign),
        for (var i = 0; i < orderedGospels.length; i++)
          _buildHeaderCell(languageOption.gospelHeaders[i], headerStyle,
              TextAlign.center),
      ],
    );
    final bodyRows = <TableRow>[];

    for (var i = 0; i < widget.topics.length; i++) {
      final topic = widget.topics[i];
      final grouped = _groupReferences(topic);
      final isEvenRow = i.isEven;
      final baseColor = theme.colorScheme.surface;
      final alternateColor =
          theme.colorScheme.surfaceVariant.withOpacity(0.35);
      bodyRows.add(
        TableRow(
          decoration: BoxDecoration(
            color: isEvenRow
                ? baseColor
                : alternateColor,
          ),
          children: [
            TableCell(
              verticalAlignment: TableCellVerticalAlignment.top,
              child: TableRowInkWell(
                onTap: widget.onTopicSelected == null
                    ? null
                    : () => widget.onTopicSelected!(topic),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: _buildNumberedTopic(
                    index: i,
                    topic: topic,
                    textAlign: subjectAlign,
                    isRtl: isRtl,
                    textStyle: subjectStyle,
                  ),
                ),
              ),
            ),
            for (final gospel in orderedGospels)
              TableCell(
                verticalAlignment: TableCellVerticalAlignment.top,
                child: _buildReferenceCell(
                  topic,
                  gospel,
                  grouped[gospel] ?? const <GospelReference>[],
                  referenceStyle,
                  referenceAlign,
                ),
              ),
          ],
        ),
      );
    }

    final availableWidth = MediaQuery.of(context).size.width;
    final minTableWidth = availableWidth < 720 ? 720.0 : availableWidth;

    return Column(
      children: [
        SingleChildScrollView(
          controller: _headerHorizontalController,
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: minTableWidth),
            child: Table(
              border: TableBorder(
                verticalInside: BorderSide(color: borderColor, width: 0.6),
                top: BorderSide(color: borderColor, width: 0.8),
                bottom: BorderSide(color: borderColor, width: 0.6),
                left: BorderSide(color: borderColor, width: 0.8),
                right: BorderSide(color: borderColor, width: 0.8),
              ),
              columnWidths: const {
                0: FlexColumnWidth(2.6),
                1: FlexColumnWidth(1.4),
                2: FlexColumnWidth(1.4),
                3: FlexColumnWidth(1.4),
                4: FlexColumnWidth(1.4),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [headerRow],
            ),
          ),
        ),
        Expanded(
          child: Scrollbar(
            controller: _verticalController,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _verticalController,
              child: Scrollbar(
                controller: _bodyHorizontalController,
                thumbVisibility: true,
                notificationPredicate: (notification) =>
                    notification.metrics.axis == Axis.horizontal,
                child: SingleChildScrollView(
                  controller: _bodyHorizontalController,
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: minTableWidth),
                    child: Table(
                      border: TableBorder(
                        horizontalInside:
                            BorderSide(color: borderColor, width: 0.6),
                        verticalInside:
                            BorderSide(color: borderColor, width: 0.6),
                        bottom: BorderSide(color: borderColor, width: 0.8),
                        left: BorderSide(color: borderColor, width: 0.8),
                        right: BorderSide(color: borderColor, width: 0.8),
                      ),
                      columnWidths: const {
                        0: FlexColumnWidth(2.6),
                        1: FlexColumnWidth(1.4),
                        2: FlexColumnWidth(1.4),
                        3: FlexColumnWidth(1.4),
                        4: FlexColumnWidth(1.4),
                      },
                      defaultVerticalAlignment:
                          TableCellVerticalAlignment.middle,
                      children: bodyRows,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class ReferenceHoverText extends StatefulWidget {
  const ReferenceHoverText({
    super.key,
    required this.reference,
    this.textStyle,
    this.textAlign = TextAlign.center,
    this.textDirection = TextDirection.ltr,
    this.topicName = '',
    this.language = defaultLanguage,
    this.version = defaultVersion,
    this.tooltipMessage = 'Click to view more',
    this.labelOverride = '',
    this.enableHoverPreview = true,
    this.topicId = '',
    this.sourceContext = '',
    this.gospel = '',
  });

  final GospelReference reference;
  final TextStyle? textStyle;
  final TextAlign textAlign;
  final TextDirection textDirection;
  final String topicName;
  final String language;
  final String version;
  final String tooltipMessage;
  final String labelOverride;
  final bool enableHoverPreview;
  final String topicId;
  final String sourceContext;
  final String gospel;

  @override
  State<ReferenceHoverText> createState() => _ReferenceHoverTextState();
}

class _ReferenceHoverTextState extends State<ReferenceHoverText>
    with WidgetsBindingObserver {
  static const double _previewGap = 8;
  static const double _previewViewportPadding = 8;

  bool _isHovered = false;
  bool _isLaunching = false;
  bool _loadingPreview = false;
  String? _previewError;
  List<_VerseLine> _previewVerses = const <_VerseLine>[];
  OverlayEntry? _previewEntry;
  bool _previewLoaded = false;
  bool _isTriggerHovered = false;
  bool _isPreviewHovered = false;
  Timer? _hidePreviewTimer;
  Timer? _repositionPreviewTimer;
  final GlobalKey _anchorKey = GlobalKey();
  final GlobalKey _previewKey = GlobalKey();
  Size _previewSize = const Size(280, 220);
  bool _pendingPreviewMeasurement = false;

  static final Map<String, _ReferencePreviewCache> _previewCache = {};

  AlignmentGeometry _alignmentForTextAlign(TextAlign align) {
    switch (align) {
      case TextAlign.center:
        return Alignment.center;
      case TextAlign.right:
        return Alignment.centerRight;
      case TextAlign.left:
        return Alignment.centerLeft;
      case TextAlign.start:
        return AlignmentDirectional.centerStart;
      case TextAlign.end:
        return AlignmentDirectional.centerEnd;
      case TextAlign.justify:
        return AlignmentDirectional.centerStart;
    }
  }

  Uri? _buildReferenceUri(GospelReference reference) {
    final displayBook = reference.book.trim();
    final bookParam = reference.bookId.trim().isNotEmpty
        ? reference.bookId.trim()
        : displayBook;
    if (bookParam.isEmpty || reference.chapter <= 0) {
      return null;
    }

    final queryParameters = <String, String>{
      'book': bookParam,
      'bookDisplay': displayBook,
      'chapter': reference.chapter.toString(),
      'language': widget.language,
      'version': widget.version,
      'label': reference.formattedReference,
    };

    final verses = reference.verses.trim();
    if (verses.isNotEmpty) {
      queryParameters['verses'] = verses;
    }

    if (widget.topicName.trim().isNotEmpty) {
      queryParameters['topic'] = widget.topicName.trim();
    }
    if (widget.topicId.trim().isNotEmpty) {
      queryParameters['topicId'] = widget.topicId.trim();
    }
    if (widget.sourceContext.trim().isNotEmpty) {
      queryParameters['source'] = widget.sourceContext.trim();
    }
    if (widget.gospel.trim().isNotEmpty) {
      queryParameters['gospel'] = widget.gospel.trim();
    }

    return Uri(path: '/reference', queryParameters: queryParameters);
  }

  Future<void> _handleTap() async {
    if (_isLaunching) {
      return;
    }
    final uri = _buildReferenceUri(widget.reference);
    if (uri == null) {
      return;
    }
    setState(() {
      _isLaunching = true;
    });
    try {
      final opened = await openReferenceLink(uri);
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to open reference.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to open reference.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLaunching = false;
        });
      }
    }
  }

  void _updateHover(bool isHovered) {
    if (_isHovered != isHovered) {
      setState(() {
        _isHovered = isHovered;
      });
    }
  }

  void _cancelHideTimer() {
    _hidePreviewTimer?.cancel();
    _hidePreviewTimer = null;
  }

  void _schedulePreviewHide() {
    _cancelHideTimer();
    _hidePreviewTimer = Timer(const Duration(milliseconds: 160), () {
      if (!_isTriggerHovered && !_isPreviewHovered) {
        _hidePreview();
      }
    });
  }

  String _previewCacheKey(GospelReference reference) {
    final bookParam = reference.bookId.trim().isNotEmpty
        ? reference.bookId.trim()
        : reference.book.trim();
    return '${widget.language}|${widget.version}|$bookParam|${reference.chapter}|${reference.verses.trim()}';
  }

  String _previewHeading() {
    final languageOption = _languageOptionForApiLanguage(widget.language);
    final book = _displayGospelName(
            widget.reference.book,
            languageOption ?? _languageOptionForCode(defaultLanguage))
        .trim();
    if (book.isEmpty || widget.reference.chapter <= 0) {
      return _formatReferenceForLanguage(
        widget.reference.formattedReference,
        widget.textDirection,
        isArabic: _isArabicLanguage(widget.language),
      );
    }
    final verses = widget.reference.verses.trim();
    final reference = verses.isEmpty
        ? '${widget.reference.chapter}'
        : '${widget.reference.chapter}:$verses';
    return _combineBookAndReference(
      book,
      reference,
      widget.textDirection,
      isArabic: _isArabicLanguage(widget.language),
    );
  }

  Offset _previewOffset(Rect target, Size viewportSize, Size previewSize) {
    final maxLeft =
        math.max(_previewViewportPadding, viewportSize.width - previewSize.width - _previewViewportPadding);
    final maxTop =
        math.max(_previewViewportPadding, viewportSize.height - previewSize.height - _previewViewportPadding);

    final topBottom = target.bottom + _previewGap;
    final fitsBottom =
        topBottom + previewSize.height + _previewViewportPadding <= viewportSize.height;
    final topTop = target.top - _previewGap - previewSize.height;
    final fitsTop = topTop >= _previewViewportPadding;

    final top = fitsBottom
        ? topBottom
        : fitsTop
            ? topTop
            : topBottom.clamp(_previewViewportPadding, maxTop).toDouble();

    final anchorCenterX = target.left + target.width / 2;
    final left = (anchorCenterX - previewSize.width / 2)
        .clamp(_previewViewportPadding, maxLeft)
        .toDouble();

    return Offset(left, top);
  }

  void _markPreviewNeedsBuild() {
    if (_previewEntry != null) {
      _previewEntry!.markNeedsBuild();
    }
  }

  void _schedulePreviewMeasurement() {
    if (_pendingPreviewMeasurement) {
      return;
    }
    _pendingPreviewMeasurement = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pendingPreviewMeasurement = false;
      final context = _previewKey.currentContext;
      final renderBox = context?.findRenderObject() as RenderBox?;
      if (renderBox == null || !renderBox.hasSize) {
        return;
      }
      final measured = renderBox.size;
      final widthDelta = (_previewSize.width - measured.width).abs();
      final heightDelta = (_previewSize.height - measured.height).abs();
      if (widthDelta <= 1 && heightDelta <= 1) {
        return;
      }
      _previewSize = measured;
      _markPreviewNeedsBuild();
    });
  }

  void _startRepositionListener() {
    _repositionPreviewTimer?.cancel();
    _repositionPreviewTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      _markPreviewNeedsBuild();
    });
  }

  void _stopRepositionListener() {
    _repositionPreviewTimer?.cancel();
    _repositionPreviewTimer = null;
  }

  Future<void> _loadPreview() async {
    if (!widget.enableHoverPreview || _loadingPreview || _previewLoaded) {
      return;
    }
    final reference = widget.reference;
    final bookParam = reference.bookId.trim().isNotEmpty
        ? reference.bookId.trim()
        : reference.book.trim();
    if (bookParam.isEmpty || reference.chapter <= 0) {
      return;
    }

    final cacheKey = _previewCacheKey(reference);
    final cached = _previewCache[cacheKey];
    if (cached != null) {
      setState(() {
        _previewLoaded = true;
        _previewVerses = cached.verses;
        _previewError = cached.error;
      });
      _previewEntry?.markNeedsBuild();
      return;
    }

    setState(() {
      _loadingPreview = true;
      _previewError = null;
    });
    _previewEntry?.markNeedsBuild();

    final verseParam = reference.verses.trim().isEmpty
        ? '1'
        : reference.verses.trim();

    try {
      final uri = Uri.parse('$apiBaseUrl/get_verse').replace(queryParameters: {
        'language': widget.language,
        'version': widget.version,
        'book': bookParam,
        'chapter': reference.chapter.toString(),
        'verse': verseParam,
      });
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        throw Exception('Error ${response.statusCode}');
      }
      final verses = _parseVerseLines(response.body);
      if (!mounted) {
        return;
      }
      setState(() {
        _previewLoaded = true;
        _loadingPreview = false;
        _previewVerses = verses;
      });
      _previewCache[cacheKey] =
          _ReferencePreviewCache(verses: verses, error: null);
      _previewEntry?.markNeedsBuild();
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _previewLoaded = true;
        _loadingPreview = false;
        _previewError = 'Failed to load preview.';
      });
      _previewCache[cacheKey] =
          _ReferencePreviewCache(verses: const <_VerseLine>[], error: _previewError);
      _previewEntry?.markNeedsBuild();
    }
  }

  void _showPreview() {
    if (!widget.enableHoverPreview || _previewEntry != null) {
      return;
    }
    final overlay = Overlay.of(context, rootOverlay: true);
    if (overlay == null) {
      return;
    }
    _previewEntry = OverlayEntry(builder: (overlayContext) {
      final renderBox = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox == null || !renderBox.hasSize) {
        return const SizedBox.shrink();
      }
      final target = renderBox.localToGlobal(Offset.zero) & renderBox.size;
      final viewportSize = MediaQuery.of(overlayContext).size;
      final maxWidth = math.min(360.0, viewportSize.width - (_previewViewportPadding * 2));
      final maxHeight = math.min(520.0, viewportSize.height - (_previewViewportPadding * 2));
      final estimatedWidth = _previewSize.width.clamp(220.0, maxWidth).toDouble();
      final estimatedHeight = _previewSize.height.clamp(200.0, maxHeight).toDouble();
      final offset = _previewOffset(target, viewportSize, Size(estimatedWidth, estimatedHeight));
      final theme = Theme.of(overlayContext);
      _schedulePreviewMeasurement();

      return Positioned(
        left: offset.dx,
        top: offset.dy,
        child: MouseRegion(
          onEnter: (_) {
            _cancelHideTimer();
            _isPreviewHovered = true;
          },
          onExit: (_) {
            _isPreviewHovered = false;
            _schedulePreviewHide();
          },
          child: Material(
            key: _previewKey,
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            color: theme.colorScheme.surface,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: 220,
                maxWidth: maxWidth,
                minHeight: 200,
                maxHeight: maxHeight,
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Directionality(
                  textDirection: widget.textDirection,
                  child: _buildPreviewContent(theme),
                ),
              ),
            ),
          ),
        ),
      );
    });
    overlay.insert(_previewEntry!);
    _startRepositionListener();
  }

  void _hidePreview() {
    _stopRepositionListener();
    _previewEntry?.remove();
    _previewEntry = null;
  }

  @override
  void didChangeMetrics() {
    _markPreviewNeedsBuild();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  Widget _buildPreviewContent(ThemeData theme) {
    final headingStyle = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w600,
    );
    final bodyStyle = theme.textTheme.bodySmall?.copyWith(height: 1.4);
    final numberStyle = bodyStyle?.copyWith(fontWeight: FontWeight.w600);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_previewHeading(), style: headingStyle),
        const SizedBox(height: 8),
        if (_loadingPreview)
          const Center(child: CircularProgressIndicator())
        else if (_previewError != null)
          Text(_previewError!, style: bodyStyle?.copyWith(color: theme.colorScheme.error))
        else if (_previewVerses.isEmpty)
          Text(
            'No passage text is available for this reference yet.',
            style: bodyStyle,
          )
        else
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _previewVerses
                    .map((verse) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: RichText(
                            text: TextSpan(
                              style: bodyStyle,
                              children: [
                                if (verse.number != null && verse.number! > 0)
                                  TextSpan(
                                      text: '${formatVerseMarker(verse.number!, language: widget.language, version: widget.version)}. ',
                                      style: numberStyle),
                                TextSpan(text: verse.text),
                              ],
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ),
          ),

      ],
    );
  }

  @override
  void dispose() {
    _cancelHideTimer();
    WidgetsBinding.instance.removeObserver(this);
    _stopRepositionListener();
    _hidePreview();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseStyle = widget.textStyle ?? theme.textTheme.bodyMedium;
    final hoverStyle = baseStyle?.copyWith(
      color: theme.colorScheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: theme.colorScheme.primary,
    );
    final override = widget.labelOverride.trim();
    final text = override.isNotEmpty
        ? override
        : widget.reference.formattedReference;
    final alignment = _alignmentForTextAlign(widget.textAlign);

    return MouseRegion(
      cursor:
          text.isEmpty ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) {
        if (text.isEmpty) {
          return;
        }
        _isTriggerHovered = true;
        _cancelHideTimer();
        _updateHover(true);
        if (widget.enableHoverPreview) {
          _showPreview();
          _loadPreview();
        }
      },
      onExit: (_) {
        _isTriggerHovered = false;
        _updateHover(false);
        if (widget.enableHoverPreview) {
          _schedulePreviewHide();
        }
      },
      child: KeyedSubtree(
        key: _anchorKey,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: text.isEmpty ? null : _handleTap,
          child: Align(
            alignment: alignment,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: VerseRefText(
                value: text,
                lang: widget.language,
                style: _isHovered ? hoverStyle : baseStyle,
                textAlign: widget.textAlign,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReferencePreviewCache {
  const _ReferencePreviewCache({required this.verses, this.error});

  final List<_VerseLine> verses;
  final String? error;
}

class ReferenceViewerPage extends StatefulWidget {
  const ReferenceViewerPage({
    super.key,
    required this.displayBook,
    required this.bookId,
    required this.chapter,
    required this.verses,
    required this.language,
    required this.version,
    this.topicName = '',
    this.referenceLabelOverride = '',
    this.source = '',
    this.topicId = '',
    this.gospel = '',
    this.comparisonState = '',
  });

  final String displayBook;
  final String bookId;
  final int chapter;
  final String verses;
  final String language;
  final String version;
  final String topicName;
  final String referenceLabelOverride;
  final String source;
  final String topicId;
  final String gospel;
  final String comparisonState;

  @override
  State<ReferenceViewerPage> createState() => _ReferenceViewerPageState();
}


class ChapterNav extends StatelessWidget {
  const ChapterNav({
    super.key,
    required this.chapter,
    required this.onPreviousBook,
    required this.onPreviousChapter,
    required this.onNextChapter,
    required this.onNextBook,
    required this.hasPreviousBook,
    required this.hasPreviousChapter,
    required this.hasNextChapter,
    required this.hasNextBook,
    required this.isArabic,
  });

  final int chapter;
  final VoidCallback? onPreviousBook;
  final VoidCallback? onPreviousChapter;
  final VoidCallback? onNextChapter;
  final VoidCallback? onNextBook;
  final bool hasPreviousBook;
  final bool hasPreviousChapter;
  final bool hasNextChapter;
  final bool hasNextBook;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            children: [
              IconButton(
                tooltip: 'Previous book',
                onPressed: hasPreviousBook ? onPreviousBook : null,
                icon: const Icon(Icons.keyboard_double_arrow_left),
              ),
              IconButton(
                tooltip: 'Previous chapter',
                onPressed: hasPreviousChapter ? onPreviousChapter : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  isArabic
                      ? 'فصل ${toArabicIndicDigits(chapter.toString())}'
                      : 'Chapter $chapter',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: 'Next chapter',
                onPressed: hasNextChapter ? onNextChapter : null,
                icon: const Icon(Icons.chevron_right),
              ),
              IconButton(
                tooltip: 'Next book',
                onPressed: hasNextBook ? onNextBook : null,
                icon: const Icon(Icons.keyboard_double_arrow_right),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class _HarmonySection {
  const _HarmonySection({
    required this.topicId,
    required this.topicTitle,
    required this.startVerse,
    required this.endVerse,
    required this.verses,
  });

  final String topicId;
  final String topicTitle;
  final int startVerse;
  final int endVerse;
  final List<_VerseLine> verses;
}

enum _ComparisonScopeMode { highlight, custom, chapter }

class _ReferenceViewerPageState extends State<ReferenceViewerPage> {
  static const double _minTextScale = 0.85;
  static const double _maxTextScale = 1.4;
  static const double _textScaleStep = 0.1;
  bool _loadingChapter = true;
  String? _error;
  List<_VerseLine> _chapterVerses = const <_VerseLine>[];
  Set<int> _highlightVerses = const <int>{};
  int? _highlightStart;
  bool _loadingHarmonyTopics = false;
  String? _harmonyTopicsError;
  List<Topic> _harmonyTopics = const <Topic>[];
  bool _withDiacritics = true;
  bool _interlinearView = false;
  double _textScale = 1.0;
  late String _selectedVersion;
  final List<_ComparisonPassage> _comparisons = [];

  int get _chapterMaxVerse {
    var maxVerse = 0;
    for (final verse in _chapterVerses) {
      final number = verse.number;
      if (number != null && number > maxVerse) {
        maxVerse = number;
      }
    }
    return maxVerse > 0 ? maxVerse : _chapterVerses.length;
  }

  Set<int> get _availableChapterVerses {
    final verses = <int>{};
    for (final verse in _chapterVerses) {
      final number = verse.number;
      if (number != null && number > 0) {
        verses.add(number);
      }
    }
    if (verses.isEmpty) {
      for (var i = 1; i <= _chapterVerses.length; i++) {
        verses.add(i);
      }
    }
    return verses;
  }

  int get _defaultScopeEndVerse {
    final maxVerse = _chapterMaxVerse;
    if (maxVerse <= 0) {
      return 1;
    }
    return math.min(10, maxVerse);
  }

  int get _highlightStartVerseForScope {
    if (_highlightVerses.isEmpty) {
      return 1;
    }
    final ordered = _highlightVerses.toList()..sort();
    return ordered.first;
  }

  int get _highlightEndVerseForScope {
    if (_highlightVerses.isEmpty) {
      return _defaultScopeEndVerse;
    }
    final ordered = _highlightVerses.toList()..sort();
    return ordered.last;
  }

  bool get _hasHighlightScope => _highlightVerses.isNotEmpty;

  LanguageOption get _languageOption {
    final fromLanguage = _languageOptionForApiLanguage(widget.language);
    if (fromLanguage != null) {
      return fromLanguage;
    }
    return _languageOptionForVersion(widget.version);
  }

  @override
  void initState() {
    super.initState();
    LanguageSelectionController.instance.update(_languageOption.code);
    _selectedVersion =
        _sanitizeVersionForLanguage(_languageOption, widget.version);
    _withDiacritics = !_isArabicWithoutDiacritics(_selectedVersion);
    _hydrateComparisonsFromRoute();
    _loadChapter();
    if (_isHarmonySource) {
      _loadHarmonyTopics();
    }
  }

  String get _baseVersion {
    final trimmed = _selectedVersion.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
    return _languageOption.apiVersion;
  }

  String get _activeVersion {
    if (_languageOption.code == 'arabic') {
      return _resolveArabicVersion(_languageOption,
              withDiacritics: _withDiacritics,
              preferredVersion: _selectedVersion) ??
          _languageOption.apiVersion;
    }
    return _baseVersion;
  }

  String _comparisonVersion(LanguageOption option, String version,
      {bool? withDiacritics}) {
    if (option.code == 'arabic') {
      final prefersDiacritics = withDiacritics ??
          !_isArabicWithoutDiacritics(version.isNotEmpty
              ? version
              : option.apiVersion.trim());
      return _resolveArabicVersion(option,
              withDiacritics: prefersDiacritics, preferredVersion: version) ??
          option.apiVersion;
    }
    final normalized = version.trim();
    if (normalized.isNotEmpty) {
      return normalized;
    }
    return option.apiVersion;
  }


  bool get _isHarmonySource => widget.source.trim().toLowerCase() == 'harmony';

  String get _currentCanonicalBook {
    final gospelParam = widget.gospel.trim();
    if (gospelParam.isNotEmpty) {
      return _normalizeGospelName(gospelParam);
    }
    return _normalizeGospelName(_bookParameter);
  }

  String get _bookParameter {
    final trimmedBookId = widget.bookId.trim();
    if (trimmedBookId.isNotEmpty) {
      return trimmedBookId;
    }
    return widget.displayBook.trim();
  }

  String get _referenceHeading {
    final book = _displayBookLabel;
    final override = widget.referenceLabelOverride.trim();
    final direction =
        _languageOptionForApiLanguage(widget.language)?.direction ??
            TextDirection.ltr;
    if (override.isNotEmpty) {
      if (book.isEmpty) {
        return _formatReferenceForLanguage(override, direction,
            isArabic: _isArabicLanguage(widget.language));
      }
      return _combineBookAndReference(book, override, direction,
          isArabic: _isArabicLanguage(widget.language));
    }
    if (book.isEmpty) {
      return 'Reference';
    }
    if (widget.chapter <= 0) {
      return book;
    }
    final verses = widget.verses.trim();
    final reference = verses.isEmpty
        ? '${widget.chapter}'
        : '${widget.chapter}:$verses';
    return _combineBookAndReference(book, reference, direction,
        isArabic: _isArabicLanguage(widget.language));
  }

  String get _displayBookLabel {
    final book = widget.displayBook.trim();
    if (book.isEmpty) {
      return book;
    }
    final option = _languageOptionForApiLanguage(widget.language);
    if (option == null) {
      return book;
    }
    return _displayGospelName(book, option);
  }

  String _slugBookForId(String book) {
    final canonical = _normalizeGospelName(book);
    return canonical.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-');
  }

  Set<int> _parseHighlightVerses() {
    String source = widget.verses.trim();
    if (source.isEmpty) {
      final label = widget.referenceLabelOverride.trim();
      final match = RegExp(r'(?:\d+)\s*:\s*(\d+)(?:\s*-\s*(\d+))?').firstMatch(label);
      if (match != null) {
        source = match.group(2) != null
            ? '${match.group(1)}-${match.group(2)}'
            : (match.group(1) ?? '');
      }
    }
    if (source.isEmpty) {
      return const <int>{};
    }

    final verses = <int>{};
    for (final rawPart in source.split(',')) {
      final part = rawPart.trim();
      if (part.isEmpty) {
        continue;
      }
      final range = RegExp(r'^(\d+)\s*-\s*(\d+)$').firstMatch(part);
      if (range != null) {
        final a = int.tryParse(range.group(1)!);
        final b = int.tryParse(range.group(2)!);
        if (a == null || b == null) {
          continue;
        }
        final start = a <= b ? a : b;
        final end = a <= b ? b : a;
        for (var v = start; v <= end; v++) {
          verses.add(v);
        }
        continue;
      }
      final single = int.tryParse(part);
      if (single != null) {
        verses.add(single);
      }
    }
    return verses;
  }

  Future<bool> _canLoadChapter(String book, int chapter) async {
    if (chapter <= 0) {
      return false;
    }
    final uri = Uri.parse('$apiBaseUrl/get_chapter').replace(queryParameters: {
      'language': widget.language,
      'version': _activeVersion,
      'book': book,
      'chapter': chapter.toString(),
    });
    try {
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        return false;
      }
      final verses = _parseVerseLines(response.body);
      return verses.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  void _scrollToHighlightedVerse() {
    if (_highlightStart == null) {
      return;
    }
    final targetId =
        'verse-${_slugBookForId(_bookParameter)}-${widget.chapter}-${_highlightStart!}';
    void tryScroll() {
      final context = _verseKeys[targetId]?.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          alignment: 0.5,
          duration: Duration.zero,
          curve: Curves.linear,
        );
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      tryScroll();
      WidgetsBinding.instance.addPostFrameCallback((_) => tryScroll());
    });
  }

  final Map<String, GlobalKey> _verseKeys = <String, GlobalKey>{};

  String _encodeComparisonState() {
    if (_comparisons.isEmpty) {
      return '';
    }
    final payload = _comparisons.map((entry) => {
          'language': entry.language.apiLanguage,
          'version': entry.version,
          'scopeMode': entry.scopeMode.name,
          'scopeStartVerse': entry.scopeStartVerse,
          'scopeEndVerse': entry.scopeEndVerse,
          'withDiacritics': entry.withDiacritics,
        }).toList();
    final jsonText = jsonEncode(payload);
    return base64Url.encode(utf8.encode(jsonText));
  }

  void _hydrateComparisonsFromRoute() {
    final encoded = widget.comparisonState.trim();
    if (encoded.isEmpty) {
      return;
    }
    try {
      final decoded = utf8.decode(base64Url.decode(encoded));
      final raw = jsonDecode(decoded);
      if (raw is! List) {
        return;
      }
      final parsed = <_ComparisonPassage>[];
      for (final item in raw) {
        if (item is! Map) {
          continue;
        }
        final mapItem = Map<String, dynamic>.from(item);
        final language = _languageOptionForApiLanguage((mapItem['language'] ?? '').toString());
        if (language == null) {
          continue;
        }
        final version = _sanitizeVersionForLanguage(language, (mapItem['version'] ?? '').toString());
        final scopeModeRaw = (mapItem['scopeMode'] ?? '').toString();
        final scopeMode = _ComparisonScopeMode.values.firstWhere(
          (mode) => mode.name == scopeModeRaw,
          orElse: () => _ComparisonScopeMode.chapter,
        );
        final scopeStartVerse = (mapItem['scopeStartVerse'] is int)
            ? mapItem['scopeStartVerse'] as int
            : int.tryParse((mapItem['scopeStartVerse'] ?? '').toString()) ?? 1;
        final scopeEndVerse = (mapItem['scopeEndVerse'] is int)
            ? mapItem['scopeEndVerse'] as int
            : int.tryParse((mapItem['scopeEndVerse'] ?? '').toString()) ?? 1;
        final withDiacritics = mapItem['withDiacritics'] is bool
            ? mapItem['withDiacritics'] as bool
            : true;
        parsed.add(
          _ComparisonPassage(
            language: language,
            version: version,
            scopeMode: scopeMode,
            scopeStartVerse: scopeStartVerse,
            scopeEndVerse: scopeEndVerse,
            withDiacritics: withDiacritics,
          ),
        );
      }
      if (parsed.isNotEmpty) {
        _comparisons
          ..clear()
          ..addAll(parsed);
      }
    } catch (_) {
      // Ignore invalid URL payloads.
    }
  }

  Uri _referenceUri({required String book, required int chapter}) {
    final queryParameters = <String, String>{
      'book': book,
      'bookDisplay': book,
      'chapter': chapter.toString(),
      'language': widget.language,
      'version': _activeVersion,
    };
    if (widget.topicName.trim().isNotEmpty) {
      queryParameters['topic'] = widget.topicName.trim();
    }
    final comparisonState = _encodeComparisonState();
    if (comparisonState.isNotEmpty) {
      queryParameters['comparisons'] = comparisonState;
    }
    if (_isHarmonySource) {
      queryParameters['source'] = 'harmony';
      if (widget.topicId.trim().isNotEmpty) {
        queryParameters['topicId'] = widget.topicId.trim();
      }
      queryParameters['gospel'] = _normalizeGospelName(book);
    }
    return Uri(path: '/reference', queryParameters: queryParameters);
  }


  Future<void> _loadHarmonyTopics() async {
    setState(() {
      _loadingHarmonyTopics = true;
      _harmonyTopicsError = null;
    });
    final uri = Uri.parse('$apiBaseUrl/topics').replace(queryParameters: {
      'language': widget.language,
      'version': _activeVersion,
    });
    try {
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        throw Exception('Error ${response.statusCode}');
      }
      final raw = json.decode(response.body);
      final list = raw is List
          ? raw.whereType<Map<String, dynamic>>().map(Topic.fromJson).toList()
          : <Topic>[];
      if (!mounted) {
        return;
      }
      setState(() {
        _harmonyTopics = list;
        _loadingHarmonyTopics = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _harmonyTopicsError = 'Failed to load harmony topics: $e';
        _loadingHarmonyTopics = false;
      });
    }
  }

  Set<int> _topicVerseNumbersForCurrentChapter(GospelReference reference) {
    final verses = <int>{};
    final maxVerse = _chapterVerses.length;
    if (reference.chapter <= 0 || maxVerse <= 0) {
      return verses;
    }

    final currentChapter = widget.chapter;
    final sourceChapter = reference.chapter;
    final rawVerses = reference.verses.trim();
    if (rawVerses.isEmpty) {
      if (sourceChapter == currentChapter) {
        for (var i = 1; i <= maxVerse; i++) {
          verses.add(i);
        }
      }
      return verses;
    }

    for (final rawPart in rawVerses.split(',')) {
      final part = rawPart.trim();
      if (part.isEmpty) {
        continue;
      }

      final single = RegExp(r'^(\d+)$').firstMatch(part);
      if (single != null) {
        if (sourceChapter == currentChapter) {
          final number = int.tryParse(single.group(1)!);
          if (number != null) {
            verses.add(number);
          }
        }
        continue;
      }

      final sameChapterRange = RegExp(r'^(\d+)\s*-\s*(\d+)$').firstMatch(part);
      if (sameChapterRange != null) {
        if (sourceChapter == currentChapter) {
          final a = int.tryParse(sameChapterRange.group(1)!);
          final b = int.tryParse(sameChapterRange.group(2)!);
          if (a != null && b != null) {
            final start = a <= b ? a : b;
            final end = a <= b ? b : a;
            for (var v = start; v <= end; v++) {
              verses.add(v);
            }
          }
        }
        continue;
      }

      final explicitRange = RegExp(r'^(\d+):(\d+)\s*-\s*(\d+):(\d+)$').firstMatch(part);
      if (explicitRange != null) {
        final startChapter = int.tryParse(explicitRange.group(1)!);
        final startVerse = int.tryParse(explicitRange.group(2)!);
        final endChapter = int.tryParse(explicitRange.group(3)!);
        final endVerse = int.tryParse(explicitRange.group(4)!);
        if (startChapter == null || startVerse == null || endChapter == null || endVerse == null) {
          continue;
        }
        if (currentChapter < startChapter || currentChapter > endChapter) {
          continue;
        }
        if (currentChapter == startChapter && currentChapter == endChapter) {
          for (var v = startVerse; v <= endVerse; v++) {
            verses.add(v);
          }
        } else if (currentChapter == startChapter) {
          for (var v = startVerse; v <= maxVerse; v++) {
            verses.add(v);
          }
        } else if (currentChapter == endChapter) {
          for (var v = 1; v <= endVerse; v++) {
            verses.add(v);
          }
        } else {
          for (var v = 1; v <= maxVerse; v++) {
            verses.add(v);
          }
        }
        continue;
      }

      final openCross = RegExp(r'^(\d+)\s*-\s*(\d+):(\d+)$').firstMatch(part);
      if (openCross != null) {
        final startVerse = int.tryParse(openCross.group(1)!);
        final endChapter = int.tryParse(openCross.group(2)!);
        final endVerse = int.tryParse(openCross.group(3)!);
        if (startVerse == null || endChapter == null || endVerse == null) {
          continue;
        }
        if (currentChapter == sourceChapter) {
          for (var v = startVerse; v <= maxVerse; v++) {
            verses.add(v);
          }
        } else if (currentChapter == endChapter) {
          for (var v = 1; v <= endVerse; v++) {
            verses.add(v);
          }
        }
      }
    }

    verses.removeWhere((value) => value <= 0 || value > maxVerse);
    return verses;
  }

  List<_HarmonySection> _buildHarmonySections() {
    if (!_isHarmonySource || _harmonyTopics.isEmpty || _chapterVerses.isEmpty) {
      return const <_HarmonySection>[];
    }

    final canonicalBook = _currentCanonicalBook;
    final sections = <_HarmonySection>[];

    for (final topic in _harmonyTopics) {
      final topicVerses = <int>{};
      for (final reference in topic.references) {
        if (_normalizeGospelName(reference.book) != canonicalBook) {
          continue;
        }
        topicVerses.addAll(_topicVerseNumbersForCurrentChapter(reference));
      }
      if (topicVerses.isEmpty) {
        continue;
      }
      final ordered = topicVerses.toList()..sort();
      final verses = _chapterVerses.where((verse) {
        final number = verse.number;
        return number != null && topicVerses.contains(number);
      }).toList();
      if (verses.isEmpty) {
        continue;
      }
      sections.add(
        _HarmonySection(
          topicId: topic.id,
          topicTitle: topic.name,
          startVerse: ordered.first,
          endVerse: ordered.last,
          verses: verses,
        ),
      );
    }

    return sections;
  }

  String get _metaSummary {
    final segments = <String>[];
    final version = _activeVersion.trim();
    if (version.isNotEmpty) {
      final languageOption = _languageOptionForVersion(version);
      final versionOption = _versionOptionFor(languageOption, version);
      String displayVersion =
          (versionOption?.label ?? languageOption.versionLabel).trim();
      if (displayVersion.isEmpty) {
        displayVersion = version;
      }
      segments.add(displayVersion.trim());
    }
    final apiLanguage = widget.language.trim();
    if (apiLanguage.isNotEmpty) {
      final displayLanguage =
          _languageOptionForApiLanguage(apiLanguage)?.label ?? apiLanguage;
      segments.add(displayLanguage);
    }
    return segments.join(' · ');
  }

  Future<void> _loadChapter() async {
    final bookParam = _bookParameter;
    if (widget.chapter <= 0 || bookParam.isEmpty) {
      setState(() {
        _error = 'This reference is missing details needed to load the text.';
        _loadingChapter = false;
      });
      return;
    }

    setState(() {
      _loadingChapter = true;
      _error = null;
    });

    try {
      final uri = Uri.parse('$apiBaseUrl/get_chapter').replace(queryParameters: {
        'language': widget.language,
        'version': _activeVersion,
        'book': bookParam,
        'chapter': widget.chapter.toString(),
      });
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        throw Exception('Error ${response.statusCode}');
      }
      final verses = _parseVerseLines(response.body);
      final highlights = _parseHighlightVerses();
      final start = highlights.isEmpty ? null : (highlights.toList()..sort()).first;
      if (!mounted) {
        return;
      }
      setState(() {
        _chapterVerses = verses;
        _highlightVerses = highlights;
        _highlightStart = start;
        _loadingChapter = false;
      });
      for (final comparison in _comparisons) {
        _loadComparisonPassage(comparison);
      }
      _scrollToHighlightedVerse();
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Failed to load chapter: $e';
        _loadingChapter = false;
      });
    }
  }

  void _toggleReferenceDiacritics() {

    if (_languageOption.code != 'arabic') {
      return;
    }
    final shouldReloadChapter = _chapterVerses.isNotEmpty || _error != null;
    setState(() {
      _withDiacritics = !_withDiacritics;
      if (shouldReloadChapter) {
        _chapterVerses = const <_VerseLine>[];
        _error = null;
        _loadingChapter = false;
      }
    });
    _loadChapter();
    if (_isHarmonySource) {
      _loadHarmonyTopics();
    }
  }

  Future<void> _updateSelectedVersion(String newVersion) async {
    final sanitized = _sanitizeVersionForLanguage(_languageOption, newVersion);
    if (sanitized == _selectedVersion &&
        (_languageOption.code != 'arabic' ||
            _withDiacritics == !_isArabicWithoutDiacritics(sanitized))) {
      return;
    }
    final shouldReloadChapter = _chapterVerses.isNotEmpty || _error != null;

    setState(() {
      _selectedVersion = sanitized;
      if (_languageOption.code == 'arabic') {
        _withDiacritics = false;
      }
      if (shouldReloadChapter) {
        _chapterVerses = const <_VerseLine>[];
        _error = null;
        _loadingChapter = false;
      }
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('selected_version_${_languageOption.code}', sanitized);
    } catch (_) {
      // Ignore persistence errors and continue.
    }

    _loadChapter();
    if (_isHarmonySource) {
      _loadHarmonyTopics();
    }
  }

  Widget _buildVerseParagraph(
    _VerseLine verse,
    ThemeData theme, {
    bool highlighted = false,
    String? verseId,
    String? markerLanguage,
    String? markerVersion,
  }) {
    final TextStyle baseStyle =
        theme.textTheme.bodyLarge?.copyWith(height: 1.6) ??
            const TextStyle(fontSize: 16, height: 1.6);
    final TextStyle numberStyle =
        baseStyle.copyWith(fontWeight: FontWeight.w600);
    final content = RichText(
      textScaler: TextScaler.linear(_textScale),
      textAlign: TextAlign.start,
      text: TextSpan(
        style: baseStyle,
        children: [
          if (verse.number != null && verse.number! > 0)
            TextSpan(
              text:
                  '${formatVerseMarker(verse.number!, language: markerLanguage ?? _languageOption.apiLanguage, version: markerVersion ?? _activeVersion)}. ',
              style: numberStyle,
            ),
          TextSpan(text: verse.text),
        ],
      ),
    );

    final widgetChild = highlighted
        ? Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.10),
              borderRadius: BorderRadius.circular(10),
              border: BorderDirectional(
                start: BorderSide(color: theme.colorScheme.primary, width: 3),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: content,
          )
        : content;

    return Padding(
      key: verseId != null
          ? (_verseKeys.putIfAbsent(verseId, () => GlobalKey()))
          : null,
      padding: const EdgeInsets.only(bottom: 12),
      child: widgetChild,
    );
  }


  Future<void> _openReferenceUri(Uri uri) async {
    final opened = await openReferenceLink(uri);
    if (!opened && mounted) {
      Navigator.of(context).pushReplacementNamed(uri.toString());
    }
  }

  int _clampChapterForBook(String book, int chapter) {
    final maxChapter = gospelChapterCounts[_normalizeGospelName(book)];
    if (maxChapter == null) {
      return chapter <= 0 ? 1 : chapter;
    }
    if (chapter <= 0) {
      return 1;
    }
    if (chapter > maxChapter) {
      return maxChapter;
    }
    return chapter;
  }

  Widget _buildChapterSection(ThemeData theme) {

    if (_loadingChapter) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Text(
        _error!,
        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
      );
    }

    if (_chapterVerses.isEmpty) {
      return Text(
        'No chapter text is available for this passage yet.',
        style: theme.textTheme.bodyMedium,
      );
    }

    final canonical = _normalizeGospelName(_bookParameter);
    final bookIndex = orderedGospels.indexOf(canonical);
    final hasPrevBook = bookIndex > 0;
    final hasNextBook =
        bookIndex >= 0 && bookIndex < orderedGospels.length - 1;
    final hasPrevChapter = widget.chapter > 1;
    final maxChapter = gospelChapterCounts[canonical];
    final hasNextChapter =
        maxChapter == null ? true : widget.chapter < maxChapter;

    final bookSlug = _slugBookForId(_bookParameter);
    final harmonySections = _buildHarmonySections();
    final useHarmonySections = _isHarmonySource && harmonySections.isNotEmpty;

    final registeredScrollVerseIds = <String>{};
    final verseWidgets = useHarmonySections
        ? harmonySections
            .expand<Widget>((section) {
              final sectionHighlighted = section.verses.any(
                (verse) => verse.number != null && _highlightVerses.contains(verse.number),
              );
              final sectionId = section.topicId.trim().isNotEmpty
                  ? section.topicId.trim()
                  : section.topicTitle.trim();
              return <Widget>[
                Container(
                  key: sectionId == widget.topicId.trim() ? const ValueKey<String>('selected-topic-header') : null,
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: sectionHighlighted
                        ? theme.colorScheme.primary.withOpacity(0.08)
                        : theme.colorScheme.surfaceVariant.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(10),
                    border: BorderDirectional(
                      start: BorderSide(
                        color: sectionHighlighted
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outlineVariant,
                        width: sectionHighlighted ? 3 : 2,
                      ),
                    ),
                  ),
                  child: Text(
                    section.topicTitle,
                    style: (theme.textTheme.titleMedium ??
                            const TextStyle(fontSize: 19))
                        .copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.15,
                    ),
                    textAlign: TextAlign.start,
                  ),
                ),
                ...section.verses.map((verse) {
                  final number = verse.number;
                  final highlighted =
                      number != null && _highlightVerses.contains(number);
                  final rawVerseId = number != null && number > 0
                      ? 'verse-$bookSlug-${widget.chapter}-$number'
                      : null;
                  final verseId = rawVerseId != null &&
                          registeredScrollVerseIds.add(rawVerseId)
                      ? rawVerseId
                      : null;
                  return _buildVerseParagraph(
                    verse,
                    theme,
                    highlighted: highlighted,
                    verseId: verseId,
                  );
                }),
              ];
            })
            .toList()
        : _chapterVerses.map((verse) {
            final number = verse.number;
            final highlighted = number != null && _highlightVerses.contains(number);
            final rawVerseId = number != null && number > 0
                ? 'verse-$bookSlug-${widget.chapter}-$number'
                : null;
            final verseId = rawVerseId != null &&
                    registeredScrollVerseIds.add(rawVerseId)
                ? rawVerseId
                : null;
            return _buildVerseParagraph(
              verse,
              theme,
              highlighted: highlighted,
              verseId: verseId,
            );
          }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_isHarmonySource && _loadingHarmonyTopics)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        if (_isHarmonySource && _harmonyTopicsError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _harmonyTopicsError!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ),
        ChapterNav(
          chapter: widget.chapter,
          isArabic: _isArabicLanguage(widget.language),
          hasPreviousBook: hasPrevBook,
          hasPreviousChapter: hasPrevChapter,
          hasNextChapter: hasNextChapter,
          hasNextBook: hasNextBook,
          onPreviousBook: hasPrevBook
              ? () => _openReferenceUri(
                  _referenceUri(
                      book: orderedGospels[bookIndex - 1],
                      chapter: _clampChapterForBook(
                        orderedGospels[bookIndex - 1],
                        widget.chapter,
                      ),
                    ),
                )
              : null,
          onPreviousChapter: hasPrevChapter
              ? () => _openReferenceUri(
                  _referenceUri(book: canonical, chapter: widget.chapter - 1),
                )
              : null,
          onNextChapter: hasNextChapter
              ? () async {
                  if (maxChapter == null) {
                    final next = widget.chapter + 1;
                    final ok = await _canLoadChapter(canonical, next);
                    if (!ok) {
                      return;
                    }
                    await _openReferenceUri(
                      _referenceUri(book: canonical, chapter: next),
                    );
                    return;
                  }
                  await _openReferenceUri(
                    _referenceUri(book: canonical, chapter: widget.chapter + 1),
                  );
                }
              : null,
          onNextBook: hasNextBook
              ? () => _openReferenceUri(
                  _referenceUri(
                      book: orderedGospels[bookIndex + 1],
                      chapter: _clampChapterForBook(
                        orderedGospels[bookIndex + 1],
                        widget.chapter,
                      ),
                    ),
                )
              : null,
        ),
        const SizedBox(height: 8),
        ...verseWidgets,
        const SizedBox(height: 12),
        ChapterNav(
          chapter: widget.chapter,
          isArabic: _isArabicLanguage(widget.language),
          hasPreviousBook: hasPrevBook,
          hasPreviousChapter: hasPrevChapter,
          hasNextChapter: hasNextChapter,
          hasNextBook: hasNextBook,
          onPreviousBook: hasPrevBook
              ? () => _openReferenceUri(
                  _referenceUri(
                      book: orderedGospels[bookIndex - 1],
                      chapter: _clampChapterForBook(
                        orderedGospels[bookIndex - 1],
                        widget.chapter,
                      ),
                    ),
                )
              : null,
          onPreviousChapter: hasPrevChapter
              ? () => _openReferenceUri(
                  _referenceUri(book: canonical, chapter: widget.chapter - 1),
                )
              : null,
          onNextChapter: hasNextChapter
              ? () async {
                  if (maxChapter == null) {
                    final next = widget.chapter + 1;
                    final ok = await _canLoadChapter(canonical, next);
                    if (!ok) {
                      return;
                    }
                    await _openReferenceUri(
                      _referenceUri(book: canonical, chapter: next),
                    );
                    return;
                  }
                  await _openReferenceUri(
                    _referenceUri(book: canonical, chapter: widget.chapter + 1),
                  );
                }
              : null,
          onNextBook: hasNextBook
              ? () => _openReferenceUri(
                  _referenceUri(
                      book: orderedGospels[bookIndex + 1],
                      chapter: _clampChapterForBook(
                        orderedGospels[bookIndex + 1],
                        widget.chapter,
                      ),
                    ),
                )
              : null,
        ),
      ],
    );
  }

  Widget _buildArabicReferenceToggleButton() {

    if (_languageOption.code != 'arabic') {
      return const SizedBox.shrink();
    }
    final label = _withDiacritics ? 'إزالة الحركات' : 'إضافة الحركات';
    final icon =
        _withDiacritics ? Icons.remove_circle_outline : Icons.add_circle_outline;
    return OutlinedButton.icon(
      onPressed: _toggleReferenceDiacritics,
      icon: Icon(icon),
      label: Text(label),
    );
  }

  String _currentVersionLabel() {
    final version = _activeVersion;
    final option = _languageOptionForVersion(version);
    final match = _versionOptionFor(option, version);
    return match?.label ?? option.versionLabel;
  }

  void _showVersionPicker() {
    final versions = _selectableVersions(_languageOption);
    final current = _selectionVersionValue(_languageOption, _activeVersion);
    showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Select version (${_languageOption.label})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              ...versions.map(
                (version) => RadioListTile<String>(
                  title: Text(version.label),
                  value: version.id,
                  groupValue: current,
                  onChanged: (value) {
                    if (value != null) {
                      Navigator.of(context).pop();
                      _updateSelectedVersion(value);
                    }
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _buildVersionSwitchButton() {
    final versions = _selectableVersions(_languageOption);
    if (versions.length < 2) {
      return const SizedBox.shrink();
    }
    return OutlinedButton.icon(
      onPressed: _showVersionPicker,
      icon: const Icon(Icons.menu_book_outlined),
      label: Text('Version: ${_currentVersionLabel()}'),
    );
  }

  Widget _buildAddComparisonButton() {
    return OutlinedButton.icon(
      onPressed: _showComparisonPicker,
      icon: const Icon(Icons.library_add),
      label: const Text('Add comparison'),
    );
  }

  void _toggleInterlinearView() {
    setState(() {
      _interlinearView = !_interlinearView;
    });
  }

  void _adjustTextScale(double delta) {
    setState(() {
      _textScale =
          (_textScale + delta).clamp(_minTextScale, _maxTextScale).toDouble();
    });
  }

  bool get _canZoomIn => _textScale < _maxTextScale;
  bool get _canZoomOut => _textScale > _minTextScale;

  Widget _buildZoomInButton() {
    return OutlinedButton.icon(
      onPressed: _canZoomIn ? () => _adjustTextScale(_textScaleStep) : null,
      icon: const Icon(Icons.zoom_in),
      label: const Text('Zoom in'),
    );
  }

  Widget _buildZoomOutButton() {
    return OutlinedButton.icon(
      onPressed: _canZoomOut ? () => _adjustTextScale(-_textScaleStep) : null,
      icon: const Icon(Icons.zoom_out),
      label: const Text('Zoom out'),
    );
  }

  Widget _wrapWithTextScale(BuildContext context, Widget child) {
    final mediaQuery = MediaQuery.of(context);
    return MediaQuery(
      data: mediaQuery.copyWith(
        textScaler: TextScaler.linear(_textScale),
      ),
      child: child,
    );
  }

  Widget _buildInterlinearToggleButton() {
    return OutlinedButton.icon(
      onPressed: _toggleInterlinearView,
      icon: Icon(_interlinearView ? Icons.view_agenda : Icons.view_agenda_outlined),
      label: const Text('Interlinear View'),
    );
  }

  String _comparisonKey(
    LanguageOption option,
    String version,
    _ComparisonScopeMode scopeMode,
    int scopeStartVerse,
    int scopeEndVerse,
  ) {
    return '${option.code}|${version.toLowerCase()}|${scopeMode.name}|$scopeStartVerse|$scopeEndVerse';
  }

  String _scopePreviewLabel(int startVerse, int endVerse) {
    final reference = startVerse == endVerse
        ? '${widget.chapter}:$startVerse'
        : '${widget.chapter}:$startVerse–$endVerse';
    final direction =
        _languageOptionForApiLanguage(widget.language)?.direction ??
            TextDirection.ltr;
    final book = _displayBookLabel.isNotEmpty
        ? _displayBookLabel
        : _currentCanonicalBook;
    return _combineBookAndReference(
      book,
      reference,
      direction,
      isArabic: _isArabicLanguage(widget.language),
    );
  }

  bool _isValidScopeRange(int startVerse, int endVerse, int maxVerse) {
    if (!(startVerse >= 1 && endVerse >= 1 && startVerse <= endVerse && endVerse <= maxVerse)) {
      return false;
    }
    final available = _availableChapterVerses;
    return available.contains(startVerse) && available.contains(endVerse);
  }

  void _showComparisonPicker() {
    final maxVerse = _chapterMaxVerse;
    if (_supportedLanguages.isEmpty || maxVerse <= 0) {
      return;
    }

    final mainLanguage = _languageOption;
    final mainVersion =
        _sanitizeVersionForLanguage(mainLanguage, _activeVersion);
    final initialMode =
        _hasHighlightScope ? _ComparisonScopeMode.highlight : _ComparisonScopeMode.custom;
    var scopeMode = initialMode;
    var customStartVerse = 1;
    var customEndVerse = _defaultScopeEndVerse;
    var selectedStartVerse =
        initialMode == _ComparisonScopeMode.highlight ? _highlightStartVerseForScope : customStartVerse;
    var selectedEndVerse =
        initialMode == _ComparisonScopeMode.highlight ? _highlightEndVerseForScope : customEndVerse;

    LanguageOption selectedLanguage = mainLanguage;
    var selectedVersion = _sanitizeVersionForLanguage(
      selectedLanguage,
      selectedLanguage.apiVersion,
    );

    int modalStep = 0;

    showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: math.min(720, MediaQuery.of(context).size.width * 0.92),
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            child: StatefulBuilder(
            builder: (context, setModalState) {
              final selectedPreview = _scopePreviewLabel(
                selectedStartVerse,
                selectedEndVerse,
              );
              final scopeError = _isValidScopeRange(
                selectedStartVerse,
                selectedEndVerse,
                maxVerse,
              )
                  ? null
                  : 'Please select a verse range within 1–$maxVerse.';
              final choices = _selectableVersions(selectedLanguage)
                  .map((choice) {
                    final sanitized =
                        _sanitizeVersionForLanguage(selectedLanguage, choice.id);
                    return _VersionChoice(
                      version: sanitized,
                      label: choice.label,
                    );
                  })
                  .where((choice) => !_isSameTranslation(
                        selectedLanguage,
                        choice.version,
                        mainLanguage,
                        mainVersion,
                      ))
                  .toList();

              if (!choices.any((choice) => choice.version == selectedVersion) &&
                  choices.isNotEmpty) {
                selectedVersion = choices.first.version;
              }

              Future<void> openVersionSelector() async {
                await showDialog<void>(
                  context: context,
                  builder: (dialogContext) {
                    return AlertDialog(
                      title: Text('Select version (${selectedLanguage.label})'),
                      content: SizedBox(
                        width: double.maxFinite,
                        child: ListView(
                          shrinkWrap: true,
                          children: choices.map((choice) {
                            return RadioListTile<String>(
                              value: choice.version,
                              groupValue: selectedVersion,
                              onChanged: (value) {
                                if (value == null) {
                                  return;
                                }
                                setModalState(() {
                                  selectedVersion = value;
                                });
                                Navigator.of(dialogContext).pop();
                              },
                              title: Text(choice.label),
                            );
                          }).toList(),
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          child: const Text('Cancel'),
                        ),
                      ],
                    );
                  },
                );
              }

              return Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (modalStep == 0) ...[
                      Text(
                        'Select verses to compare',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      if (_hasHighlightScope)
                        RadioListTile<_ComparisonScopeMode>(
                          value: _ComparisonScopeMode.highlight,
                          groupValue: scopeMode,
                          onChanged: (value) {
                            if (value == null) {
                              return;
                            }
                            setModalState(() {
                              scopeMode = value;
                              selectedStartVerse = _highlightStartVerseForScope;
                              selectedEndVerse = _highlightEndVerseForScope;
                            });
                          },
                          title: const Text('Highlighted reference (recommended)'),
                        ),
                      RadioListTile<_ComparisonScopeMode>(
                        value: _ComparisonScopeMode.custom,
                        groupValue: scopeMode,
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          setModalState(() {
                            scopeMode = value;
                            selectedStartVerse = customStartVerse;
                            selectedEndVerse = customEndVerse;
                          });
                        },
                        title: const Text('Custom range'),
                      ),
                      if (scopeMode == _ComparisonScopeMode.custom)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(start: 16, end: 16, bottom: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  initialValue: customStartVerse.toString(),
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    labelText: 'Start verse (1-$maxVerse)',
                                  ),
                                  onChanged: (value) {
                                    final parsed = int.tryParse(value);
                                    if (parsed == null) {
                                      return;
                                    }
                                    setModalState(() {
                                      customStartVerse = parsed;
                                      selectedStartVerse = parsed;
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextFormField(
                                  initialValue: customEndVerse.toString(),
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    labelText: 'End verse (1-$maxVerse)',
                                  ),
                                  onChanged: (value) {
                                    final parsed = int.tryParse(value);
                                    if (parsed == null) {
                                      return;
                                    }
                                    setModalState(() {
                                      customEndVerse = parsed;
                                      selectedEndVerse = parsed;
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      RadioListTile<_ComparisonScopeMode>(
                        value: _ComparisonScopeMode.chapter,
                        groupValue: scopeMode,
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          setModalState(() {
                            scopeMode = value;
                            selectedStartVerse = 1;
                            selectedEndVerse = maxVerse;
                          });
                        },
                        title: const Text('Entire chapter'),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Selected: $selectedPreview',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      if (scopeError != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          scopeError,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Theme.of(context).colorScheme.error),
                        ),
                      ],
                      const Spacer(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: scopeError == null
                                ? () {
                                    setModalState(() {
                                      modalStep = 1;
                                    });
                                  }
                                : null,
                            child: const Text('Next'),
                          ),
                        ],
                      ),
                    ] else ...[
                      Text(
                        'Select translation to add',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<LanguageOption>(
                        value: selectedLanguage,
                        decoration: const InputDecoration(labelText: 'Language'),
                        items: _supportedLanguages
                            .map(
                              (option) => DropdownMenuItem(
                                value: option,
                                child: Text(option.label),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setModalState(() {
                            selectedLanguage = value;
                            selectedVersion = _sanitizeVersionForLanguage(
                              value,
                              value.apiVersion,
                            );
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      InkWell(
                        onTap: choices.isEmpty ? null : openVersionSelector,
                        child: InputDecorator(
                          decoration: const InputDecoration(labelText: 'Version'),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  choices.isEmpty
                                      ? 'No alternative versions available'
                                      : _versionLabel(
                                          selectedLanguage.code,
                                          selectedVersion,
                                        ),
                                ),
                              ),
                              const Icon(Icons.arrow_drop_down),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Selected: $selectedPreview',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const Spacer(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () {
                              setModalState(() {
                                modalStep = 0;
                              });
                            },
                            child: const Text('Back'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: choices.isEmpty
                                ? null
                                : () {
                                    Navigator.of(context).pop();
                                    _addComparison(
                                      selectedLanguage,
                                      selectedVersion,
                                      scopeMode,
                                      selectedStartVerse,
                                      selectedEndVerse,
                                    );
                                  },
                            child: const Text('Add comparison'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
          ),
        );
      },
    );
  }

  void _addComparison(
    LanguageOption option,
    String version,
    _ComparisonScopeMode scopeMode,
    int scopeStartVerse,
    int scopeEndVerse,
  ) {
    final sanitized = _sanitizeVersionForLanguage(option, version);
    final maxVerse = _chapterMaxVerse;
    if (!_isValidScopeRange(scopeStartVerse, scopeEndVerse, maxVerse)) {
      return;
    }
    final existing = _comparisons.indexWhere((entry) =>
        _comparisonKey(
          entry.language,
          entry.version,
          entry.scopeMode,
          entry.scopeStartVerse,
          entry.scopeEndVerse,
        ) ==
        _comparisonKey(option, sanitized, scopeMode, scopeStartVerse, scopeEndVerse));
    if (existing != -1) {
      _loadComparisonPassage(_comparisons[existing]);
      return;
    }

    final entry = _ComparisonPassage(
      language: option,
      version: sanitized,
      withDiacritics: option.code == 'arabic'
          ? _withDiacritics
          : !_isArabicWithoutDiacritics(sanitized),
      scopeMode: scopeMode,
      scopeStartVerse: scopeStartVerse,
      scopeEndVerse: scopeEndVerse,
    );
    setState(() {
      _comparisons.add(entry);
    });
    _loadComparisonPassage(entry);
  }

  Future<void> _loadComparisonPassage(_ComparisonPassage entry) async {
    final bookParam = _bookParameter;
    if (widget.chapter <= 0 || bookParam.isEmpty) {
      setState(() {
        entry.error = 'This reference is missing details needed to load the text.';
      });
      return;
    }
    setState(() {
      entry.loading = true;
      entry.error = null;
      entry.verses = const [];
    });

    try {
      final uri = Uri.parse('$apiBaseUrl/get_chapter').replace(queryParameters: {
        'language': entry.language.apiLanguage,
        'version': _comparisonVersion(entry.language, entry.version,
            withDiacritics: entry.withDiacritics),
        'book': bookParam,
        'chapter': widget.chapter.toString(),
      });
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        throw Exception('Error ${response.statusCode}');
      }
      final verses = _parseVerseLines(response.body);
      if (!mounted) {
        return;
      }
      setState(() {
        entry.verses = verses;
        entry.loading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        entry.error = 'Failed to load comparison: $e';
        entry.loading = false;
      });
    }
  }

  Future<void> _showComparisonColumnSelector(_ComparisonPassage entry) async {
    LanguageOption selectedLanguage = entry.language;
    String selectedVersion = _sanitizeVersionForLanguage(selectedLanguage, entry.version);

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final versions = _selectableVersions(selectedLanguage);
            if (!versions.any((v) => v.id == selectedVersion) && versions.isNotEmpty) {
              selectedVersion = versions.first.id;
            }
            return AlertDialog(
              title: const Text('Change translation'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: selectedLanguage.code,
                    items: _supportedLanguages
                        .map((option) => DropdownMenuItem<String>(
                              value: option.code,
                              child: Text(option.label),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      final match = _supportedLanguages.firstWhere((item) => item.code == value);
                      setModalState(() {
                        selectedLanguage = match;
                        selectedVersion = _sanitizeVersionForLanguage(match, match.apiVersion);
                      });
                    },
                    decoration: const InputDecoration(labelText: 'Language'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedVersion,
                    items: versions
                        .map((version) => DropdownMenuItem<String>(
                              value: version.id,
                              child: Text(version.label),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setModalState(() {
                        selectedVersion = value;
                      });
                    },
                    decoration: const InputDecoration(labelText: 'Version'),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    setState(() {
                      entry.language = selectedLanguage;
                      entry.version = _sanitizeVersionForLanguage(selectedLanguage, selectedVersion);
                      if (selectedLanguage.code != 'arabic') {
                        entry.withDiacritics = !_isArabicWithoutDiacritics(entry.version);
                      }
                    });
                    _loadComparisonPassage(entry);
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _removeComparison(_ComparisonPassage entry) {
    setState(() {
      _comparisons.remove(entry);
    });
  }

  void _showEditComparisonScopeDialog(_ComparisonPassage entry) {
    final maxVerse = _chapterMaxVerse;
    if (maxVerse <= 0) {
      return;
    }

    var scopeMode = entry.scopeMode;
    if (scopeMode == _ComparisonScopeMode.highlight && !_hasHighlightScope) {
      scopeMode = _ComparisonScopeMode.custom;
    }

    var customStartVerse = entry.scopeStartVerse;
    var customEndVerse = entry.scopeEndVerse;
    var selectedStartVerse = entry.scopeStartVerse;
    var selectedEndVerse = entry.scopeEndVerse;

    if (scopeMode == _ComparisonScopeMode.highlight) {
      selectedStartVerse = _highlightStartVerseForScope;
      selectedEndVerse = _highlightEndVerseForScope;
    } else if (scopeMode == _ComparisonScopeMode.chapter) {
      selectedStartVerse = 1;
      selectedEndVerse = maxVerse;
    }

    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit comparison verse range'),
          content: StatefulBuilder(
            builder: (context, setModalState) {
              final selectedPreview = _scopePreviewLabel(
                selectedStartVerse,
                selectedEndVerse,
              );
              final scopeError = _isValidScopeRange(
                selectedStartVerse,
                selectedEndVerse,
                maxVerse,
              )
                  ? null
                  : 'Please select a verse range within 1–$maxVerse.';

              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_hasHighlightScope)
                      RadioListTile<_ComparisonScopeMode>(
                        value: _ComparisonScopeMode.highlight,
                        groupValue: scopeMode,
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          setModalState(() {
                            scopeMode = value;
                            selectedStartVerse = _highlightStartVerseForScope;
                            selectedEndVerse = _highlightEndVerseForScope;
                          });
                        },
                        title:
                            const Text('Highlighted reference (recommended)'),
                      ),
                    RadioListTile<_ComparisonScopeMode>(
                      value: _ComparisonScopeMode.custom,
                      groupValue: scopeMode,
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setModalState(() {
                          scopeMode = value;
                          selectedStartVerse = customStartVerse;
                          selectedEndVerse = customEndVerse;
                        });
                      },
                      title: const Text('Custom range'),
                    ),
                    if (scopeMode == _ComparisonScopeMode.custom)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                            start: 16, end: 16, bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                initialValue: customStartVerse.toString(),
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  labelText: 'Start verse (1-$maxVerse)',
                                ),
                                onChanged: (value) {
                                  final parsed = int.tryParse(value);
                                  if (parsed == null) {
                                    return;
                                  }
                                  setModalState(() {
                                    customStartVerse = parsed;
                                    selectedStartVerse = parsed;
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                initialValue: customEndVerse.toString(),
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  labelText: 'End verse (1-$maxVerse)',
                                ),
                                onChanged: (value) {
                                  final parsed = int.tryParse(value);
                                  if (parsed == null) {
                                    return;
                                  }
                                  setModalState(() {
                                    customEndVerse = parsed;
                                    selectedEndVerse = parsed;
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    RadioListTile<_ComparisonScopeMode>(
                      value: _ComparisonScopeMode.chapter,
                      groupValue: scopeMode,
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setModalState(() {
                          scopeMode = value;
                          selectedStartVerse = 1;
                          selectedEndVerse = maxVerse;
                        });
                      },
                      title: const Text('Entire chapter'),
                    ),
                    const SizedBox(height: 8),
                    Text('Selected: $selectedPreview'),
                    if (scopeError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        scopeError,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Theme.of(context).colorScheme.error),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: !_isValidScopeRange(
                selectedStartVerse,
                selectedEndVerse,
                maxVerse,
              )
                  ? null
                  : () {
                      final targetKey = _comparisonKey(
                        entry.language,
                        entry.version,
                        scopeMode,
                        selectedStartVerse,
                        selectedEndVerse,
                      );
                      final duplicateExists = _comparisons.any((item) {
                        if (identical(item, entry)) {
                          return false;
                        }
                        return _comparisonKey(
                              item.language,
                              item.version,
                              item.scopeMode,
                              item.scopeStartVerse,
                              item.scopeEndVerse,
                            ) ==
                            targetKey;
                      });
                      if (duplicateExists) {
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'A comparison with this translation and range already exists.',
                            ),
                          ),
                        );
                        return;
                      }
                      Navigator.of(context).pop();
                      setState(() {
                        entry.scopeMode = scopeMode;
                        entry.scopeStartVerse = selectedStartVerse;
                        entry.scopeEndVerse = selectedEndVerse;
                      });
                      _loadComparisonPassage(entry);
                    },
              child: const Text('Save range'),
            ),
          ],
        );
      },
    );
  }


  Widget _buildParallelComparisonSection(ThemeData theme) {
    if (_loadingChapter) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Text(
        _error!,
        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
      );
    }
    final columns = <_ParallelColumn>[
      _ParallelColumn.main(
        language: _languageOption,
        version: _activeVersion,
        verses: _mapVersesByNumber(_chapterVerses),
      ),
      ..._comparisons.map(
        (entry) => _ParallelColumn.comparison(
          entry: entry,
          language: entry.language,
          version: _comparisonVersion(entry.language, entry.version, withDiacritics: entry.withDiacritics),
          verses: _mapVersesByNumber(entry.verses),
        ),
      ),
    ];
    final pairs = <List<_ParallelColumn>>[];
    for (var i = 0; i < columns.length; i += 2) {
      final end = math.min(i + 2, columns.length);
      pairs.add(columns.sublist(i, end));
    }
    final harmonySections = _buildHarmonySections();
    final sectionRanges = harmonySections.isNotEmpty
        ? harmonySections
            .map((section) => _ParallelSectionRange(
                  title: section.topicTitle,
                  start: section.startVerse,
                  end: section.endVerse,
                ))
            .toList()
        : <_ParallelSectionRange>[
            _ParallelSectionRange(
              title: _isHarmonySource ? 'Passage' : _referenceHeading,
              start: 1,
              end: _chapterMaxVerse,
            ),
          ];

    final canonical = _normalizeGospelName(_bookParameter);
    final bookIndex = orderedGospels.indexOf(canonical);
    final hasPrevBook = bookIndex > 0;
    final hasNextBook = bookIndex >= 0 && bookIndex < orderedGospels.length - 1;
    final hasPrevChapter = widget.chapter > 1;
    final maxChapter = gospelChapterCounts[canonical];
    final hasNextChapter = maxChapter == null ? true : widget.chapter < maxChapter;

    Widget buildColumnHeader(_ParallelColumn column) {
      final versionLabel = _versionLabel(column.language.code, column.version);
      final title = '${column.language.label} · $versionLabel';
      return Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            onPressed: () {
              if (column.isMain) {
                _showVersionPicker();
              } else if (column.entry != null) {
                _showComparisonColumnSelector(column.entry!);
              }
            },
            child: const Text('Change'),
          ),
          if (!column.isMain && column.entry != null)
            IconButton(
              onPressed: () => _removeComparison(column.entry!),
              icon: const Icon(Icons.close),
              tooltip: 'Remove comparison',
            ),
        ],
      );
    }

    Widget buildVerseCell(_ParallelColumn column, int verseNumber) {
      final text = column.verses[verseNumber] ?? '—';
      final highlighted = _highlightVerses.contains(verseNumber);
      return Container(
        decoration: BoxDecoration(
          color: highlighted ? theme.colorScheme.primary.withOpacity(0.08) : null,
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Directionality(
          textDirection: column.language.direction,
          child: RichText(
            text: TextSpan(
              style: theme.textTheme.bodyMedium,
              children: [
                TextSpan(
                  text: '${formatVerseMarker(verseNumber, language: column.language.apiLanguage, version: column.version)}. ',
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                TextSpan(text: text),
              ],
            ),
          ),
        ),
      );
    }

    final pairWidgets = <Widget>[];
    final bookSlug = _slugBookForId(_bookParameter);
    final registeredScrollVerseIds = <String>{};
    for (var pairIndex = 0; pairIndex < pairs.length; pairIndex++) {
      final pair = pairs[pairIndex];
      final left = pair.first;
      final right = pair.length > 1 ? pair[1] : null;
      pairWidgets.add(
        Card(
          margin: const EdgeInsets.only(bottom: 16),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: buildColumnHeader(left)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: right != null ? buildColumnHeader(right) : const SizedBox.shrink(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...sectionRanges.expand((section) {
                  final sectionHighlighted = _highlightVerses.any((v) => v >= section.start && v <= section.end);
                  return [
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(top: 8, bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: sectionHighlighted
                            ? theme.colorScheme.primary.withOpacity(0.08)
                            : theme.colorScheme.surfaceVariant.withOpacity(0.35),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        section.title,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    ...List.generate(section.end - section.start + 1, (index) {
                      final verseNumber = section.start + index;
                      final rawVerseId = 'verse-$bookSlug-${widget.chapter}-$verseNumber';
                      final verseId = pairIndex == 0 && registeredScrollVerseIds.add(rawVerseId)
                          ? rawVerseId
                          : null;
                      return Padding(
                        key: verseId != null
                            ? (_verseKeys.putIfAbsent(verseId, () => GlobalKey()))
                            : null,
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: buildVerseCell(left, verseNumber)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: right != null
                                  ? buildVerseCell(right, verseNumber)
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ),
                      );
                    }),
                  ];
                }),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ChapterNav(
          chapter: widget.chapter,
          isArabic: _isArabicLanguage(widget.language),
          hasPreviousBook: hasPrevBook,
          hasPreviousChapter: hasPrevChapter,
          hasNextChapter: hasNextChapter,
          hasNextBook: hasNextBook,
          onPreviousBook: hasPrevBook
              ? () => _openReferenceUri(_referenceUri(
                    book: orderedGospels[bookIndex - 1],
                    chapter: _clampChapterForBook(orderedGospels[bookIndex - 1], widget.chapter),
                  ))
              : null,
          onPreviousChapter: hasPrevChapter
              ? () => _openReferenceUri(_referenceUri(book: canonical, chapter: widget.chapter - 1))
              : null,
          onNextChapter: hasNextChapter
              ? () async {
                  if (maxChapter == null) {
                    final next = widget.chapter + 1;
                    final ok = await _canLoadChapter(canonical, next);
                    if (!ok) return;
                    await _openReferenceUri(_referenceUri(book: canonical, chapter: next));
                    return;
                  }
                  await _openReferenceUri(_referenceUri(book: canonical, chapter: widget.chapter + 1));
                }
              : null,
          onNextBook: hasNextBook
              ? () => _openReferenceUri(_referenceUri(
                    book: orderedGospels[bookIndex + 1],
                    chapter: _clampChapterForBook(orderedGospels[bookIndex + 1], widget.chapter),
                  ))
              : null,
        ),
        const SizedBox(height: 8),
        ...pairWidgets,
        ChapterNav(
          chapter: widget.chapter,
          isArabic: _isArabicLanguage(widget.language),
          hasPreviousBook: hasPrevBook,
          hasPreviousChapter: hasPrevChapter,
          hasNextChapter: hasNextChapter,
          hasNextBook: hasNextBook,
          onPreviousBook: hasPrevBook
              ? () => _openReferenceUri(_referenceUri(
                    book: orderedGospels[bookIndex - 1],
                    chapter: _clampChapterForBook(orderedGospels[bookIndex - 1], widget.chapter),
                  ))
              : null,
          onPreviousChapter: hasPrevChapter
              ? () => _openReferenceUri(_referenceUri(book: canonical, chapter: widget.chapter - 1))
              : null,
          onNextChapter: hasNextChapter
              ? () async {
                  if (maxChapter == null) {
                    final next = widget.chapter + 1;
                    final ok = await _canLoadChapter(canonical, next);
                    if (!ok) return;
                    await _openReferenceUri(_referenceUri(book: canonical, chapter: next));
                    return;
                  }
                  await _openReferenceUri(_referenceUri(book: canonical, chapter: widget.chapter + 1));
                }
              : null,
          onNextBook: hasNextBook
              ? () => _openReferenceUri(_referenceUri(
                    book: orderedGospels[bookIndex + 1],
                    chapter: _clampChapterForBook(orderedGospels[bookIndex + 1], widget.chapter),
                  ))
              : null,
        ),
      ],
    );
  }

  Widget _buildComparisonSection(ThemeData theme) {
    if (_comparisons.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Comparisons',
          style:
              theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        ..._comparisons
            .map((entry) => _buildComparisonCard(entry, theme))
            .toList(),
      ],
    );
  }

  Widget _buildInterlinearReferenceSection(ThemeData theme) {
    if (_chapterVerses.isEmpty) {
      return Text(
        'No passage text is available for this reference yet.',
        style: theme.textTheme.bodyMedium,
        textAlign: TextAlign.start,
      );
    }

    final statusWidgets = <Widget>[];
    final translations = <_InterlinearTranslation>[
      _InterlinearTranslation(
        label: _metaSummary.isNotEmpty ? _metaSummary : _currentVersionLabel(),
        direction: _languageOption.direction,
        verses: _mapVersesByNumber(_chapterVerses),
      ),
    ];
    for (final entry in _comparisons) {
      final resolvedVersion = entry.language.code == 'arabic'
          ? _comparisonVersion(entry.language, entry.version,
              withDiacritics: entry.withDiacritics)
          : entry.version;
      final versionLabel = _versionLabel(entry.language.code, resolvedVersion);
      final label = '${entry.language.label} · $versionLabel';
      if (entry.loading) {
        statusWidgets.addAll([
          Text(label, style: theme.textTheme.labelSmall),
          const SizedBox(height: 4),
          const LinearProgressIndicator(),
          const SizedBox(height: 8),
        ]);
        continue;
      }
      if (entry.error != null) {
        statusWidgets.addAll([
          Text(
            '$label: ${entry.error}',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.error),
          ),
          const SizedBox(height: 8),
        ]);
        continue;
      }
      if (entry.verses.isEmpty) {
        statusWidgets.addAll([
          Text(
            '$label: No passage text is available for this translation yet.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
        ]);
        continue;
      }
      final scopedVerses = entry.verses.where((verse) {
        final number = verse.number;
        if (number == null) {
          return false;
        }
        return number >= entry.scopeStartVerse && number <= entry.scopeEndVerse;
      }).toList();
      translations.add(
        _InterlinearTranslation(
          label: label,
          direction: entry.language.direction,
          verses: _mapVersesByNumber(scopedVerses),
        ),
      );
    }

    final verseKeys = _sortedVerseKeys(translations.map((t) => t.verses));
    if (verseKeys.isEmpty) {
      return Text(
        'No passage text is available for this reference yet.',
        style: theme.textTheme.bodyMedium,
        textAlign: TextAlign.start,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...verseKeys.map(
          (number) => _buildInterlinearVerseGroup(
            verseNumber: number,
            translations: translations,
            theme: theme,
            language: widget.language,
            version: _activeVersion,
          ),
        ),
        if (statusWidgets.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...statusWidgets,
        ],
      ],
    );
  }

  void _toggleComparisonDiacritics(_ComparisonPassage entry) {
    if (entry.language.code != 'arabic') {
      return;
    }
    setState(() {
      entry.withDiacritics = !entry.withDiacritics;
    });
    _loadComparisonPassage(entry);
  }

  Widget _buildComparisonDiacriticsToggle(_ComparisonPassage entry) {
    if (entry.language.code != 'arabic') {
      return const SizedBox.shrink();
    }
    final label = entry.withDiacritics ? 'إزالة الحركات' : 'إضافة الحركات';
    final icon = entry.withDiacritics
        ? Icons.remove_circle_outline
        : Icons.add_circle_outline;
    return OutlinedButton.icon(
      onPressed: () => _toggleComparisonDiacritics(entry),
      icon: Icon(icon),
      label: Text(label),
    );
  }

  Widget _buildComparisonCard(_ComparisonPassage entry, ThemeData theme) {
    final resolvedVersion = entry.language.code == 'arabic'
        ? _comparisonVersion(entry.language, entry.version,
            withDiacritics: entry.withDiacritics)
        : entry.version;
    final versionLabel = _versionLabel(entry.language.code, resolvedVersion);
    final header = '${entry.language.label} · $versionLabel';
    final textDirection = entry.language.direction;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Directionality(
          textDirection: textDirection,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      header,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    onPressed: () => _showEditComparisonScopeDialog(entry),
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'Edit comparison range',
                  ),
                  IconButton(
                    onPressed: () => _removeComparison(entry),
                    icon: const Icon(Icons.close),
                    tooltip: 'Remove comparison',
                  ),
                ],
              ),
              if (entry.language.code == 'arabic') ...[
                const SizedBox(height: 8),
                _buildComparisonDiacriticsToggle(entry),
              ],
              if (entry.loading) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ] else if (entry.error != null) ...[
                const SizedBox(height: 12),
                Text(
                  entry.error!,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ] else if (entry.verses.isEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'No passage text is available for this translation yet.',
                  style: theme.textTheme.bodyMedium,
                ),
              ] else ...[
                const SizedBox(height: 12),
                ...entry.verses
                    .where((verse) {
                      final number = verse.number;
                      if (number == null) {
                        return false;
                      }
                      return number >= entry.scopeStartVerse &&
                          number <= entry.scopeEndVerse;
                    })
                    .map(
                      (verse) => _buildVerseParagraph(
                        verse,
                        theme,
                        markerLanguage: entry.language.apiLanguage,
                        markerVersion: resolvedVersion,
                      ),
                    )
                    .toList(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String get _chapterTitle {
    final book = _displayBookLabel.isNotEmpty ? _displayBookLabel : _currentCanonicalBook;
    if (widget.chapter > 0) {
      return '$book ${widget.chapter}';
    }
    return book.isNotEmpty ? book : 'Reference';
  }

  String get _harmonyAppBarTitle {
    final book = _displayBookLabel.isNotEmpty ? _displayBookLabel : _currentCanonicalBook;
    if (book.isEmpty) {
      return 'Reference';
    }
    if (_languageOption.code == 'arabic') {
      return 'إنجيل $book';
    }
    return 'Book of $book';
  }

  @override
  Widget build(BuildContext context) {
    final title = _isHarmonySource
        ? _harmonyAppBarTitle
        : (widget.topicName.trim().isNotEmpty
            ? widget.topicName
            : (_displayBookLabel.isNotEmpty ? _displayBookLabel : 'Reference'));
    return MainScaffold(
      title: title,
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final theme = Theme.of(context);
    final direction = _languageOption.direction;
    final actionButtons = <Widget>[
      _buildZoomOutButton(),
      _buildZoomInButton(),
      _buildVersionSwitchButton(),
      _buildArabicReferenceToggleButton(),
      _buildAddComparisonButton(),
      _buildInterlinearToggleButton(),
    ].where((button) => button is! SizedBox).toList();

    return Directionality(
      textDirection: direction,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!_isHarmonySource)
                      Text(
                        _referenceHeading,
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                        textAlign: TextAlign.start,
                      ),
                    if (actionButtons.isNotEmpty) ...[
                      SizedBox(height: _isHarmonySource ? 0 : 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: actionButtons,
                      ),
                    ],
                    const SizedBox(height: 24),
                    _wrapWithTextScale(
                      context,
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_interlinearView && _comparisons.isNotEmpty) ...[
                            _buildInterlinearReferenceSection(theme),
                            const SizedBox(height: 24),
                            _buildChapterSection(theme),
                          ] else if (_comparisons.isNotEmpty) ...[
                            _buildParallelComparisonSection(theme),
                          ] else ...[
                            _buildChapterSection(theme),
                            const SizedBox(height: 24),
                            _buildComparisonSection(theme),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _VerseLine {
  const _VerseLine({required this.number, required this.text});

  final int? number;
  final String text;
}

List<_VerseLine> _parseVerseLines(String body) {
  final decoded = json.decode(body);
  if (decoded is! List) {
    return const <_VerseLine>[];
  }
  return _parseVerseLinesFromJson(decoded);
}

List<_VerseLine> _parseVerseLinesFromJson(List<dynamic> decoded) {
  final verses = decoded
      .whereType<Map<String, dynamic>>()
      .map((item) {
        final rawNumber = item['verse'];
        int? number;
        if (rawNumber is int) {
          number = rawNumber;
        } else if (rawNumber is String) {
          number = int.tryParse(rawNumber);
        }
        final text = (item['text'] ?? '').toString().trim();
        return _VerseLine(number: number, text: text);
      })
      .toList();
  verses.sort((a, b) => (a.number ?? 0).compareTo(b.number ?? 0));
  return verses;
}

Map<int, String> _mapVersesByNumber(List<_VerseLine> verses) {
  final map = <int, String>{};
  for (var i = 0; i < verses.length; i++) {
    final verse = verses[i];
    final number = verse.number != null && verse.number! > 0
        ? verse.number!
        : i + 1;
    map[number] = verse.text;
  }
  return map;
}

List<int> _sortedVerseKeys(Iterable<Map<int, String>> maps) {
  final keys = <int>{};
  for (final map in maps) {
    keys.addAll(map.keys);
  }
  final sorted = keys.toList()..sort();
  return sorted;
}

class _InterlinearTranslation {
  const _InterlinearTranslation({
    required this.label,
    required this.direction,
    required this.verses,
  });

  final String label;
  final TextDirection direction;
  final Map<int, String> verses;
}

Widget _buildInterlinearVerseGroup({
  required int verseNumber,
  required List<_InterlinearTranslation> translations,
  required ThemeData theme,
  required String language,
  String? version,
  TextStyle? textStyle,
  TextStyle? labelStyle,
}) {
  final resolvedTextStyle =
      textStyle ?? theme.textTheme.bodyLarge?.copyWith(height: 1.6);
  final resolvedLabelStyle = labelStyle ??
      theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      );
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          formatVerseMarker(verseNumber, language: language, version: version),
          style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        ...translations.map((translation) {
          final text = translation.verses[verseNumber] ?? '';
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Directionality(
              textDirection: translation.direction,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(translation.label, style: resolvedLabelStyle),
                  const SizedBox(height: 4),
                  Text(
                    text.isNotEmpty ? text : '—',
                    style: resolvedTextStyle,
                    textAlign: TextAlign.start,
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    ),
  );
}



class _ParallelSectionRange {
  const _ParallelSectionRange({
    required this.title,
    required this.start,
    required this.end,
  });

  final String title;
  final int start;
  final int end;
}

class _ParallelColumn {
  const _ParallelColumn.main({
    required this.language,
    required this.version,
    required this.verses,
  })  : isMain = true,
        entry = null;

  const _ParallelColumn.comparison({
    required this.entry,
    required this.language,
    required this.version,
    required this.verses,
  }) : isMain = false;

  final bool isMain;
  final _ComparisonPassage? entry;
  final LanguageOption language;
  final String version;
  final Map<int, String> verses;
}

class _ComparisonPassage {
  _ComparisonPassage({
    required this.language,
    required this.version,
    this.scopeMode = _ComparisonScopeMode.custom,
    this.scopeStartVerse = 1,
    this.scopeEndVerse = 1,
    this.verses = const <_VerseLine>[],
    this.error,
    this.loading = false,
    this.withDiacritics = true,
  });

  LanguageOption language;
  String version;
  _ComparisonScopeMode scopeMode;
  int scopeStartVerse;
  int scopeEndVerse;
  List<_VerseLine> verses;
  String? error;
  bool loading;
  bool withDiacritics;
}

class _VersionChoice {
  const _VersionChoice({
    required this.version,
    required this.label,
  });

  final String version;
  final String label;
}

class Topic {
  final String id;
  final String name;
  final List<GospelReference> references;
  const Topic({
    required this.id,
    required this.name,
    required this.references,
  });

  factory Topic.fromJson(Map<String, dynamic> json) {
    final dynamic referencesRaw = json['references'] ?? json['entries'] ?? [];
    final referencesJson =
        referencesRaw is List ? referencesRaw : const <dynamic>[];
    return Topic(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? json['topic'] ?? '').toString().trim(),
      references: (referencesJson ?? [])
          .whereType<Map<String, dynamic>>()
          .map(GospelReference.fromJson)
          .toList(),
    );
  }
}

class GospelReference {
  final String book;
  final int chapter;
  final String verses;
  final String bookId;

  const GospelReference({
    required this.book,
    required this.chapter,
    required this.verses,
    this.bookId = '',
  });

  factory GospelReference.fromJson(Map<String, dynamic> json) {
    final rawChapter = json['chapter'];
    final parsedChapter = rawChapter is int
        ? rawChapter
        : int.tryParse(rawChapter?.toString() ?? '') ?? 0;
    final rawBookId =
        json['book_id'] ?? json['bookId'] ?? json['documentId'] ?? '';
    return GospelReference(
      book: (json['book'] ?? '').toString().trim(),
      chapter: parsedChapter,
      verses:
          (json['verses'] ?? json['verse'] ?? '').toString().trim(),
      bookId: rawBookId.toString().trim(),
    );
  }

  String get formattedReference {
    if (chapter <= 0 && verses.isEmpty) {
      return '';
    }
    if (chapter <= 0) {
      return verses;
    }
    final trimmedVerses = verses.trim();
    if (trimmedVerses.isEmpty) {
      return '$chapter';
    }
    return '$chapter:$trimmedVerses';
  }
}


// ----- Second Screen: Choose Version -----
class ChooseVersionScreen extends StatefulWidget {
  final Topic topic;
  ChooseVersionScreen({super.key, required this.topic});

  @override
  State<ChooseVersionScreen> createState() => _ChooseVersionScreenState();
}

class _ChooseVersionScreenState extends State<ChooseVersionScreen> {
  final List<LanguageOption> availableOptions = _supportedLanguages;

  String? _selected;

  @override
  Widget build(BuildContext context) {
    return MainScaffold(
      title: "Choose Version",
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: availableOptions.length,
              itemBuilder: (context, idx) {
                final option = availableOptions[idx];
                final version = option.apiVersion;
                return RadioListTile<String>(
                  title: Text(option.versionLabel),
                  value: version,
                  groupValue: _selected,
                  onChanged: (val) {
                    setState(() {
                      _selected = val;
                    });
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton(
              onPressed: _selected == null
                  ? null
                  : () {
                      Navigator.push(context, MaterialPageRoute(
                        builder: (_) => ChooseAuthorScreen(
                          topic: widget.topic,
                          version: _selected!,
                        ),
                      ));
                    },
              child: const Text("Continue"),
            ),
          )
        ],
      ),
    );
  }
}


// ----- Third Screen: Choose Authors -----
class ChooseAuthorScreen extends StatefulWidget {
  final Topic topic;
  final String version;
  const ChooseAuthorScreen({super.key, required this.topic, required this.version});

  @override
  State<ChooseAuthorScreen> createState() => _ChooseAuthorScreenState();
}

class _ChooseAuthorScreenState extends State<ChooseAuthorScreen> {
  late final List<String> authors;
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    authors = widget.topic.references
        .map((e) => _normalizeGospelName(e.book))
        .toSet()
        .toList()
      ..sort(_compareBooks);
  }

  @override
  Widget build(BuildContext context) {
    final option = _languageOptionForVersion(widget.version);
    return MainScaffold(
      title: "Choose Authors",
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: authors.length,
              itemBuilder: (context, idx) {
                final author = authors[idx];
                return CheckboxListTile(
                  title: Text(_displayGospelName(author, option)),
                  value: _selected.contains(author),
                  onChanged: (val) {
                    setState(() {
                      if (val == true) {
                        _selected.add(author);
                      } else {
                        _selected.remove(author);
                      }
                    });
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton(
              onPressed: _selected.isEmpty
                  ? null
                  : () {
                      Navigator.push(context, MaterialPageRoute(
                        builder: (_) => AuthorComparisonScreen(
                          languageOption:
                              _languageOptionForVersion(widget.version),
                          apiVersion: widget.version,
                          topic: widget.topic,
                          initialAuthors:
                              _selected.toList()..sort(_compareBooks),
                        ),
                      ));
                    },
              child: const Text("Compare"),
            ),
          )
        ],
      ),
    );
  }
}

class AuthorComparisonScreen extends StatefulWidget {
  final LanguageOption languageOption;
  final Topic topic;
  final List<String> initialAuthors;
  final String apiVersion;
  const AuthorComparisonScreen({
    super.key,
    required this.languageOption,
    required this.topic,
    required this.initialAuthors,
    required this.apiVersion,
  });

  @override
  State<AuthorComparisonScreen> createState() => _AuthorComparisonScreenState();
}

class _AuthorTextEntry {
  const _AuthorTextEntry({
    required this.reference,
    required this.title,
    required this.text,
    required this.verses,
    required this.displayAuthor,
  });

  final GospelReference reference;
  final String title;
  final String text;
  final List<_VerseLine> verses;
  final String displayAuthor;
}

class _AuthorComparisonScreenState extends State<AuthorComparisonScreen> {
  static const double _minTextScale = 0.85;
  static const double _maxTextScale = 1.4;
  static const double _textScaleStep = 0.1;
  late List<String> _allAuthors;
  late Set<String> _selected;
  Map<String, List<_AuthorTextEntry>> _texts = {};
  final Map<String, List<_ComparisonPassage>> _entryComparisons = {};
  String? _error;
  bool _loading = true;
  bool _withDiacritics = true;
  bool _interlinearView = false;
  double _textScale = 1.0;
  late LanguageOption _languageOption;
  late String _apiVersion;
  late Topic _topic;

  String get _activeVersion {
    if (_languageOption.code == 'arabic') {
      return _resolveArabicVersion(_languageOption,
              withDiacritics: _withDiacritics, preferredVersion: _apiVersion) ??
          _apiVersion;
    }
    return _apiVersion;
  }

  String _displayAuthorName(String author) {
    return _displayGospelName(author, _languageOption);
  }

  String _entryKey(GospelReference reference) {
    final normalizedBook = _normalizeGospelName(reference.book);
    final bookParam = reference.bookId.trim().isNotEmpty
        ? reference.bookId.trim()
        : reference.book.trim();
    return '${normalizedBook.toLowerCase()}|$bookParam|${reference.chapter}|${reference.verses.trim()}';
  }

  List<GospelReference> get _visibleReferences {
    final references = <String, GospelReference>{};
    for (final author in _selected) {
      for (final entry in _texts[author] ?? const <_AuthorTextEntry>[]) {
        final key = _entryKey(entry.reference);
        references.putIfAbsent(key, () => entry.reference);
      }
    }
    return references.values.toList();
  }

  String _comparisonVersionFor(LanguageOption option, String version,
      {bool? withDiacritics}) {
    if (option.code == 'arabic') {
      final prefersDiacritics = withDiacritics ??
          !_isArabicWithoutDiacritics(version.isNotEmpty
              ? version
              : option.apiVersion.trim());
      return _resolveArabicVersion(option,
              withDiacritics: prefersDiacritics, preferredVersion: version) ??
          option.apiVersion;
    }
    final normalized = version.trim();
    if (normalized.isNotEmpty) {
      return normalized;
    }
    return option.apiVersion;
  }

  String get _languageVersionSummary {
    final option = _languageOption;
    final versionLabel = _versionLabel(option.code, _activeVersion);
    return '${option.label} · $versionLabel';
  }

  @override
  void initState() {
    super.initState();
    _languageOption = widget.languageOption;
    _apiVersion = _sanitizeVersionForLanguage(_languageOption, widget.apiVersion);
    _withDiacritics = !_isArabicWithoutDiacritics(_apiVersion);
    LanguageSelectionController.instance.update(_languageOption.code);
    _topic = widget.topic;
    _allAuthors = _topic.references
        .map((e) => _normalizeGospelName(e.book))
        .toSet()
        .toList()
      ..sort(_compareBooks);
    _selected = widget.initialAuthors.map(_normalizeGospelName).toSet();
    fetchTexts();
  }

  Future<void> _loadTopicForLanguage(
      LanguageOption language, String version) async {
    final topicKey =
        _topic.id.trim().isNotEmpty ? _topic.id.trim() : _topic.name.trim();
    if (topicKey.isEmpty) {
      return;
    }
    final uri = Uri.parse('$apiBaseUrl/topics').replace(queryParameters: {
      'language': language.apiLanguage,
      'version': version,
    });
    try {
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        return;
      }
      final List data = json.decode(response.body);
      final topics = data.map((e) => Topic.fromJson(e)).toList();
      final normalizedKey = topicKey.toLowerCase();
      Topic? match;
      for (final topic in topics) {
        final id = topic.id.trim();
        if (id.isNotEmpty && id.toLowerCase() == normalizedKey) {
          match = topic;
          break;
        }
        final name = topic.name.trim();
        if (name.isNotEmpty && name.toLowerCase() == normalizedKey) {
          match = topic;
          break;
        }
      }
      if (!mounted || match == null) {
        return;
      }
      final authors = match.references
          .map((e) => _normalizeGospelName(e.book))
          .toSet()
          .toList()
        ..sort(_compareBooks);
      final authorSet = authors.toSet();
      final updatedSelected = _selected
          .where((author) => authorSet.contains(author))
          .toSet();
      setState(() {
        _topic = match!;
        _allAuthors = authors;
        _selected = updatedSelected.isNotEmpty ? updatedSelected : authorSet;
      });
    } catch (_) {
      // Ignore topic refresh issues and keep the previous topic.
    }
  }

  Future<void> _toggleArabicDiacritics() async {
    if (_languageOption.code != 'arabic') {
      return;
    }
    final newValue = !_withDiacritics;
    setState(() {
      _withDiacritics = newValue;
      _entryComparisons.forEach((key, entries) {
        for (final entry in entries) {
          if (entry.language.code == 'arabic') {
            entry.withDiacritics = newValue;
          }
        }
      });
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('arabic_with_diacritics', newValue);
    } catch (_) {
      // Ignore persistence issues.
    }
    await fetchTexts(preserveComparisons: true);
    _reloadEntryComparisons(onlyArabic: true);
  }

  Future<void> fetchTexts({bool preserveComparisons = false}) async {
    if (_selected.isEmpty) {
      setState(() {
        _texts = {};
        _loading = false;
        if (!preserveComparisons) {
          _entryComparisons.clear();
        }
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      if (!preserveComparisons) {
        _entryComparisons.clear();
      }
    });
    try {
      final option = _languageOption;
      final version = _activeVersion;
      final futures = _selected.map((author) async {
        final refs = _topic.references
            .where((r) => _normalizeGospelName(r.book) == author);
        final displayAuthor = _displayAuthorName(author);
        final parts = <_AuthorTextEntry>[];
        for (final ref in refs) {
          final bookId = ref.bookId.isNotEmpty ? ref.bookId : ref.book;
          final url = "$apiBaseUrl/get_verse"
              "?language=${Uri.encodeComponent(option.apiLanguage)}"
              "&version=${Uri.encodeComponent(version)}"
              "&book=${Uri.encodeComponent(bookId)}"
              "&chapter=${ref.chapter}"
              "&verse=${Uri.encodeComponent(ref.verses)}";
          final response = await http.get(Uri.parse(url));
          if (response.statusCode != 200) {
            throw Exception("Error ${response.statusCode} for $author");
          }
          final List<dynamic> verses = json.decode(response.body);
          final verseLines = _parseVerseLinesFromJson(verses);
          final text = verseLines
              .map((v) {
                if (v.number == null) {
                  return v.text;
                }
                final marker = formatVerseMarker(
                  v.number!,
                  language: option.apiLanguage,
                  version: _activeVersion,
                );
                return '$marker. ${v.text}';
              })
              .join("\n");
          final refLabel = ref.formattedReference;
          final direction = option.direction;
          final title = refLabel.isEmpty
              ? displayAuthor
              : _combineBookAndReference(displayAuthor, refLabel, direction,
                  isArabic: option.code == 'arabic');
          parts.add(_AuthorTextEntry(
            reference: ref,
            title: title,
            text: text,
            verses: verseLines,
            displayAuthor: displayAuthor,
          ));
        }
        return MapEntry(author, parts);
      });

      final results = await Future.wait(futures);
      setState(() {
        _texts = Map.fromEntries(results);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = "Failed to fetch: $e";
        _loading = false;
      });
    }
  }

  void _reloadEntryComparisons({bool onlyArabic = false}) {
    if (_entryComparisons.isEmpty) {
      return;
    }
    final references = _visibleReferences;
    if (references.isEmpty) {
      return;
    }
    final referenceLookup = <String, GospelReference>{
      for (final reference in references) _entryKey(reference): reference,
    };
    _entryComparisons.forEach((key, entries) {
      final reference = referenceLookup[key];
      if (reference == null) {
        return;
      }
      for (final entry in entries) {
        if (onlyArabic && entry.language.code != 'arabic') {
          continue;
        }
        _loadEntryComparison(reference, entry);
      }
    });
  }

  void _showComparisonPicker(
      void Function(LanguageOption option, String version) onConfirm,
      {String title = 'Add comparison translation',
      String confirmLabel = 'Add translation'}) {
    if (_supportedLanguages.isEmpty) {
      return;
    }
    LanguageOption selectedLanguage = _languageOption;
    String selectedVersion = _activeVersion;

    showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: math.min(720, MediaQuery.of(context).size.width * 0.92),
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            child: StatefulBuilder(
            builder: (context, setModalState) {
              final versions = _selectableVersions(selectedLanguage);
              if (selectedVersion.isEmpty && versions.isNotEmpty) {
                selectedVersion = versions.first.id;
              }
              selectedVersion =
                  _selectionVersionValue(selectedLanguage, selectedVersion);
              if (selectedVersion.isEmpty && versions.isNotEmpty) {
                selectedVersion = versions.first.id;
              }
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<LanguageOption>(
                      value: selectedLanguage,
                      decoration: const InputDecoration(labelText: 'Language'),
                      items: _supportedLanguages
                          .map(
                            (option) => DropdownMenuItem(
                              value: option,
                              child: Text(option.label),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setModalState(() {
                          selectedLanguage = value;
                          selectedVersion =
                              _selectionVersionValue(value, value.apiVersion);
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedVersion,
                      decoration: const InputDecoration(labelText: 'Version'),
                      items: (versions.isEmpty
                              ? [BibleVersion(id: selectedVersion, label: selectedVersion)]
                              : versions)
                          .map(
                            (version) => DropdownMenuItem(
                              value: version.id,
                              child: Text(version.label),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setModalState(() {
                          selectedVersion = value;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        onConfirm(selectedLanguage, selectedVersion);
                      },
                      child: Text(confirmLabel),
                    ),
                  ],
                ),
              );
            },
          ),
          ),
        );
      },
    );
  }

  void _showTopicComparisonPicker() {
    final references = _visibleReferences;
    if (references.isEmpty) {
      return;
    }
    _showTopicMultiComparisonPicker(references);
  }

  void _showTranslationChangePicker() {
    _showComparisonPicker(
      (language, version) async {
        setState(() {
          _languageOption = language;
          _apiVersion = _sanitizeVersionForLanguage(language, version);
          _withDiacritics = !_isArabicWithoutDiacritics(_apiVersion);
        });
        LanguageSelectionController.instance.update(language.code);
        await _loadTopicForLanguage(language, _activeVersion);
        await fetchTexts(preserveComparisons: true);
        _reloadEntryComparisons();
      },
      title: 'Change main translation',
      confirmLabel: 'Change main translation',
    );
  }

  String _entryComparisonKey(LanguageOption option, String version) {
    return '${option.code}|${version.toLowerCase()}';
  }

  void _showTopicMultiComparisonPicker(List<GospelReference> references) {
    if (_supportedLanguages.isEmpty) {
      return;
    }
    final mainLanguage = _languageOption;
    final mainVersion =
        _sanitizeVersionForLanguage(mainLanguage, _activeVersion);
    LanguageOption selectedLanguage = mainLanguage;
    final selectedByLanguage = <String, Set<String>>{};

    void addSelection(LanguageOption language, String version) {
      final sanitized = _sanitizeVersionForLanguage(language, version);
      selectedByLanguage
          .putIfAbsent(language.code, () => <String>{})
          .add(sanitized);
    }

    for (final entries in _entryComparisons.values) {
      for (final entry in entries) {
        addSelection(entry.language, entry.version);
      }
    }

    List<_VersionChoice> buildChoices(LanguageOption language) {
      final choices = <String, _VersionChoice>{};
      for (final version in _selectableVersions(language)) {
        final sanitized = _sanitizeVersionForLanguage(language, version.id);
        if (_isSameTranslation(
            language, sanitized, mainLanguage, mainVersion)) {
          continue;
        }
        choices[_versionIdentityKey(language, sanitized)] = _VersionChoice(
          version: sanitized,
          label: version.label,
        );
      }
      for (final selected in selectedByLanguage[language.code] ?? {}) {
        choices.putIfAbsent(
          _versionIdentityKey(language, selected),
          () => _VersionChoice(
            version: selected,
            label: _versionLabel(language.code, selected),
          ),
        );
      }
      final ordered = choices.values.toList()
        ..sort((a, b) => a.label.compareTo(b.label));
      return ordered;
    }

    showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: math.min(720, MediaQuery.of(context).size.width * 0.92),
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            child: StatefulBuilder(
            builder: (context, setModalState) {
              final currentSelections = selectedByLanguage.putIfAbsent(
                selectedLanguage.code,
                () => <String>{},
              );
              final choices = buildChoices(selectedLanguage);

              Future<void> openVersionSelector() async {
                await showDialog<void>(
                  context: context,
                  builder: (context) {
                    return StatefulBuilder(
                      builder: (context, setDialogState) {
                        return AlertDialog(
                          title: Text(
                            'Select versions (${selectedLanguage.label})',
                          ),
                          content: SizedBox(
                            width: double.maxFinite,
                            child: ListView(
                              shrinkWrap: true,
                              children: choices.map((choice) {
                                final isSelected =
                                    currentSelections.contains(choice.version);
                                return CheckboxListTile(
                                  value: isSelected,
                                  onChanged: (value) {
                                          setDialogState(() {
                                            if (value == true) {
                                              currentSelections
                                                  .add(choice.version);
                                            } else {
                                              currentSelections
                                                  .remove(choice.version);
                                            }
                                          });
                                          setModalState(() {});
                                        },
                                  title: Text(choice.label),
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
                                );
                              }).toList(),
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('Done'),
                            ),
                          ],
                        );
                      },
                    );
                  },
                );
              }

              return Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Add comparison translation',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<LanguageOption>(
                      value: selectedLanguage,
                      decoration: const InputDecoration(labelText: 'Language'),
                      items: _supportedLanguages
                          .map(
                            (option) => DropdownMenuItem(
                              value: option,
                              child: Text(option.label),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setModalState(() {
                          selectedLanguage = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: SingleChildScrollView(
                        child: InkWell(
                          onTap: openVersionSelector,
                          child: InputDecorator(
                            decoration:
                                const InputDecoration(labelText: 'Versions'),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    children: currentSelections.isEmpty
                                        ? [
                                            Text(
                                              'Select versions',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodyMedium
                                                  ?.copyWith(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                            ),
                                          ]
                                        : currentSelections.map((version) {
                                            final label = _versionLabel(
                                                selectedLanguage.code, version);
                                            return InputChip(
                                              label: Text(label),
                                              onDeleted: () {
                                                setModalState(() {
                                                  currentSelections
                                                      .remove(version);
                                                });
                                              },
                                            );
                                          }).toList(),
                                  ),
                                ),
                                const Icon(Icons.arrow_drop_down),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        FilledButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            final desired = <String>{};
                            selectedByLanguage.forEach((code, versions) {
                              final language = _supportedLanguages.firstWhere(
                                (option) => option.code == code,
                                orElse: () => mainLanguage,
                              );
                              for (final version in versions) {
                                final key = _entryComparisonKey(language, version);
                                if (_isSameTranslation(language, version,
                                    mainLanguage, mainVersion)) {
                                  continue;
                                }
                                desired.add(key);
                              }
                            });

                            setState(() {
                              for (final reference in references) {
                                final entryKey = _entryKey(reference);
                                final existing =
                                    _entryComparisons[entryKey] ?? const [];
                                final remaining = existing.where((entry) {
                                  final key = _entryComparisonKey(
                                      entry.language, entry.version);
                                  return desired.contains(key);
                                }).toList();
                                if (remaining.isEmpty) {
                                  _entryComparisons.remove(entryKey);
                                } else {
                                  _entryComparisons[entryKey] = remaining;
                                }
                              }
                            });

                            for (final reference in references) {
                              final entryKey = _entryKey(reference);
                              final existing =
                                  _entryComparisons[entryKey] ?? const [];
                              for (final key in desired) {
                                if (existing.any((entry) =>
                                    _entryComparisonKey(
                                        entry.language, entry.version) ==
                                    key)) {
                                  continue;
                                }
                                final parts = key.split('|');
                                if (parts.length != 2) {
                                  continue;
                                }
                                final language = _supportedLanguages.firstWhere(
                                  (option) => option.code == parts[0],
                                  orElse: () => mainLanguage,
                                );
                                _addEntryComparison(reference, language, parts[1]);
                              }
                            }
                          },
                          child: const Text('Done'),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
          ),
        );
      },
    );
  }

  void _addEntryComparison(
      GospelReference reference, LanguageOption option, String version) {
    final sanitized = _sanitizeVersionForLanguage(option, version);
    final key = _entryKey(reference);
    final comparisons = _entryComparisons[key] ?? <_ComparisonPassage>[];
    final existingIndex = comparisons.indexWhere((entry) =>
        entry.language.code == option.code &&
        entry.version.toLowerCase() == sanitized.toLowerCase());
    if (existingIndex != -1) {
      _loadEntryComparison(reference, comparisons[existingIndex]);
      return;
    }

    final entry = _ComparisonPassage(
      language: option,
      version: sanitized,
      withDiacritics: option.code == 'arabic'
          ? _withDiacritics
          : !_isArabicWithoutDiacritics(sanitized),
    );
    setState(() {
      _entryComparisons[key] = List<_ComparisonPassage>.from(comparisons)
        ..add(entry);
    });
    _loadEntryComparison(reference, entry);
  }

  Future<void> _loadEntryComparison(
      GospelReference reference, _ComparisonPassage entry) async {
    final bookParam = reference.bookId.trim().isNotEmpty
        ? reference.bookId.trim()
        : reference.book.trim();
    if (reference.chapter <= 0 || bookParam.isEmpty) {
      setState(() {
        entry.error = 'This reference is missing details needed to load the text.';
      });
      return;
    }
    final verseParam =
        reference.verses.trim().isEmpty ? '1' : reference.verses.trim();

    setState(() {
      entry.loading = true;
      entry.error = null;
      entry.verses = const [];
    });

    try {
      final uri = Uri.parse('$apiBaseUrl/get_verse').replace(queryParameters: {
        'language': entry.language.apiLanguage,
        'version': _comparisonVersionFor(entry.language, entry.version,
            withDiacritics: entry.withDiacritics),
        'book': bookParam,
        'chapter': reference.chapter.toString(),
        'verse': verseParam,
      });
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        throw Exception('Error ${response.statusCode}');
      }
      final verses = _parseVerseLines(response.body);
      if (!mounted) {
        return;
      }
      setState(() {
        entry.verses = verses;
        entry.loading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        entry.error = 'Failed to load comparison: $e';
        entry.loading = false;
      });
    }
  }

  void _removeEntryComparison(GospelReference reference, _ComparisonPassage entry) {
    final key = _entryKey(reference);
    final existing = _entryComparisons[key];
    if (existing == null) {
      return;
    }
    setState(() {
      final updated = List<_ComparisonPassage>.from(existing)..remove(entry);
      if (updated.isEmpty) {
        _entryComparisons.remove(key);
      } else {
        _entryComparisons[key] = updated;
      }
    });
  }

  Widget _buildEntryComparisonCard(
      GospelReference reference, _ComparisonPassage entry, ThemeData theme) {
    final resolvedVersion = entry.language.code == 'arabic'
        ? _comparisonVersionFor(entry.language, entry.version,
            withDiacritics: entry.withDiacritics)
        : entry.version;
    final versionLabel = _versionLabel(entry.language.code, resolvedVersion);
    final header = '${entry.language.label} · $versionLabel';
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Directionality(
          textDirection: entry.language.direction,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      header,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    onPressed: () => _removeEntryComparison(reference, entry),
                    icon: const Icon(Icons.close),
                    tooltip: 'Remove comparison',
                  ),
                ],
              ),
              if (entry.loading) ...[
                const SizedBox(height: 8),
                const LinearProgressIndicator(),
              ] else if (entry.error != null) ...[
                const SizedBox(height: 8),
                Text(
                  entry.error!,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ] else if (entry.verses.isEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'No passage text is available for this translation yet.',
                  style: theme.textTheme.bodyMedium,
                ),
              ] else ...[
                const SizedBox(height: 8),
                ...entry.verses
                    .map((verse) => _buildComparisonVerse(verse, theme))
                    .toList(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildComparisonVerse(_VerseLine verse, ThemeData theme) {
    final baseStyle =
        theme.textTheme.bodyMedium?.copyWith(height: 1.5) ??
            const TextStyle(fontSize: 15, height: 1.5);
    final numberStyle = baseStyle.copyWith(fontWeight: FontWeight.w600);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RichText(
        textScaler: TextScaler.linear(_textScale),
        text: TextSpan(
          style: baseStyle,
          children: [
            if (verse.number != null && verse.number! > 0)
              TextSpan(text: '${formatVerseMarker(verse.number!, language: _languageOption.apiLanguage, version: _activeVersion)}. ', style: numberStyle),
            TextSpan(text: verse.text),
          ],
        ),
      ),
    );
  }

  Widget _buildDiacriticsToggle(LanguageOption option) {
    if (option.code != 'arabic') {
      return const SizedBox.shrink();
    }
    final label = _withDiacritics ? 'إزالة الحركات' : 'إضافة الحركات';
    final icon =
        _withDiacritics ? Icons.remove_circle_outline : Icons.add_circle_outline;
    return OutlinedButton.icon(
      onPressed: _toggleArabicDiacritics,
      icon: Icon(icon),
      label: Text(label),
    );
  }

  void _toggleInterlinearView() {
    setState(() {
      _interlinearView = !_interlinearView;
    });
  }

  void _adjustTextScale(double delta) {
    setState(() {
      _textScale =
          (_textScale + delta).clamp(_minTextScale, _maxTextScale).toDouble();
    });
  }

  bool get _canZoomIn => _textScale < _maxTextScale;
  bool get _canZoomOut => _textScale > _minTextScale;

  Widget _buildZoomOutButton() {
    return OutlinedButton.icon(
      onPressed: _canZoomOut ? () => _adjustTextScale(-_textScaleStep) : null,
      icon: const Icon(Icons.zoom_out),
      label: const Text('Zoom out'),
    );
  }

  Widget _buildZoomInButton() {
    return OutlinedButton.icon(
      onPressed: _canZoomIn ? () => _adjustTextScale(_textScaleStep) : null,
      icon: const Icon(Icons.zoom_in),
      label: const Text('Zoom in'),
    );
  }

  Widget _wrapWithTextScale(BuildContext context, Widget child) {
    final mediaQuery = MediaQuery.of(context);
    return MediaQuery(
      data: mediaQuery.copyWith(
        textScaler: TextScaler.linear(_textScale),
      ),
      child: child,
    );
  }

  Widget _buildInterlinearToggleButton() {
    return OutlinedButton.icon(
      onPressed: _toggleInterlinearView,
      icon: Icon(_interlinearView ? Icons.view_agenda : Icons.view_agenda_outlined),
      label: const Text('Interlinear View'),
    );
  }

  Widget _buildEntryInterlinearSection(
    _AuthorTextEntry entry,
    List<_ComparisonPassage> comparisons,
    ThemeData theme,
  ) {
    final statusWidgets = <Widget>[];
    final translations = <_InterlinearTranslation>[
      _InterlinearTranslation(
        label: _languageVersionSummary,
        direction: _languageOption.direction,
        verses: _mapVersesByNumber(entry.verses),
      ),
    ];
    for (final comparison in comparisons) {
      final resolvedVersion = comparison.language.code == 'arabic'
          ? _comparisonVersionFor(comparison.language, comparison.version,
              withDiacritics: comparison.withDiacritics)
          : comparison.version;
      final versionLabel =
          _versionLabel(comparison.language.code, resolvedVersion);
      final label = '${comparison.language.label} · $versionLabel';
      if (comparison.loading) {
        statusWidgets.addAll([
          Text(label, style: theme.textTheme.labelSmall),
          const SizedBox(height: 4),
          const LinearProgressIndicator(),
          const SizedBox(height: 8),
        ]);
        continue;
      }
      if (comparison.error != null) {
        statusWidgets.addAll([
          Text(
            '$label: ${comparison.error}',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.error),
          ),
          const SizedBox(height: 8),
        ]);
        continue;
      }
      if (comparison.verses.isEmpty) {
        statusWidgets.addAll([
          Text(
            '$label: No passage text is available for this translation yet.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
        ]);
        continue;
      }
      translations.add(
        _InterlinearTranslation(
          label: label,
          direction: comparison.language.direction,
          verses: _mapVersesByNumber(comparison.verses),
        ),
      );
    }
    final verseKeys = _sortedVerseKeys(translations.map((t) => t.verses));
    if (verseKeys.isEmpty) {
      return Text(
        'No passage text is available for this translation yet.',
        style: theme.textTheme.bodyMedium,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...verseKeys.map(
          (number) => _buildInterlinearVerseGroup(
            verseNumber: number,
            translations: translations,
            theme: theme,
            language: _languageOption.apiLanguage,
            version: _activeVersion,
            textStyle: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
        ),
        if (statusWidgets.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...statusWidgets,
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final option = _languageOption;
    return Directionality(
      textDirection: option.direction,
      child: MainScaffold(
        title: _topic.name,
        body: Column(
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ..._allAuthors
                    .map(
                      (author) => FilterChip(
                        label: Text(_displayAuthorName(author)),
                        selected: _selected.contains(author),
                        onSelected: (val) {
                          setState(() {
                            if (val) {
                              _selected.add(author);
                            } else {
                              _selected.remove(author);
                            }
                          });
                          fetchTexts();
                        },
                      ),
                    )
                    .toList(),
                _buildDiacriticsToggle(option),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: (_visibleReferences.isEmpty || _loading)
                          ? null
                          : _showTopicComparisonPicker,
                      icon: const Icon(Icons.library_add),
                      label: const Text('Add translation'),
                    ),
                    OutlinedButton.icon(
                      onPressed:
                          _loading ? null : _showTranslationChangePicker,
                      icon: const Icon(Icons.translate),
                      label: Text(_versionLabel(_languageOption.code, _activeVersion)),
                    ),
                    _buildZoomOutButton(),
                    _buildZoomInButton(),
                    _buildInterlinearToggleButton(),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _selected.isEmpty
                  ? Center(child: Text(option.comparePrompt))
                  : _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? Center(child: Text(_error!))
                          : _wrapWithTextScale(
                              context,
                              SingleChildScrollView(
                                child: Builder(
                                  builder: (context) {
                                    final selectedSorted =
                                        _selected.toList()..sort(_compareBooks);
                                    final width =
                                        MediaQuery.of(context).size.width /
                                            selectedSorted.length;
                                    final columnWidths = <int, TableColumnWidth>{
                                      for (int i = 0;
                                          i < selectedSorted.length;
                                          i++)
                                        i: FixedColumnWidth(width),
                                    };
                                    final maxLen = selectedSorted
                                        .map((a) => _texts[a]?.length ?? 0)
                                        .fold<int>(
                                            0, (prev, e) => e > prev ? e : prev);
                                    if (maxLen == 0) {
                                      return const SizedBox.shrink();
                                    }

                                    final rows = <TableRow>[];
                                    for (int i = 0; i < maxLen; i++) {
                                      rows.add(
                                        TableRow(
                                          children: [
                                            for (final a in selectedSorted)
                                              Padding(
                                                padding:
                                                    const EdgeInsets.all(8.0),
                                                child: () {
                                                  final entries = _texts[a] ?? [];
                                                  if (i >= entries.length) {
                                                    return const SizedBox.shrink();
                                                  }
                                                  final entry = entries[i];
                                                  final theme = Theme.of(context);
                                                  final headingStyle = theme
                                                      .textTheme
                                                      .titleSmall
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      );
                                                  final referenceLabel = entry
                                                      .reference
                                                      .formattedReference
                                                      .trim();
                                                  final heading =
                                                      referenceLabel.isEmpty
                                                          ? Text(
                                                              entry.title,
                                                              style: headingStyle,
                                                            )
                                                          : ReferenceHoverText(
                                                              reference:
                                                                  entry.reference,
                                                              textStyle:
                                                                  headingStyle,
                                                              textAlign:
                                                                  TextAlign.start,
                                                              textDirection:
                                                                  option.direction,
                                                              topicName:
                                                                  _topic.name,
                                                              language:
                                                                  option.apiLanguage,
                                                              version:
                                                                  _activeVersion,
                                                              tooltipMessage:
                                                                  option
                                                                      .tooltipMessage,
                                                              labelOverride:
                                                                  entry.title,
                                                              enableHoverPreview:
                                                                  false,
                                                            );
                                                  final comparisons =
                                                      _entryComparisons[_entryKey(
                                                              entry.reference)] ??
                                                          const <_ComparisonPassage>[];
                                                  return Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment.start,
                                                    children: [
                                                      heading,
                                                      const SizedBox(height: 4),
                                                      if (_interlinearView)
                                                        _buildEntryInterlinearSection(
                                                          entry,
                                                          comparisons,
                                                          theme,
                                                        )
                                                      else ...[
                                                        Text(entry.text),
                                                        if (comparisons
                                                            .isNotEmpty) ...[
                                                          const SizedBox(height: 8),
                                                          ...comparisons
                                                              .map(
                                                                (comparison) =>
                                                                    _buildEntryComparisonCard(
                                                                  entry.reference,
                                                                  comparison,
                                                                  theme,
                                                                ),
                                                              )
                                                              .toList(),
                                                        ],
                                                      ],
                                                      const SizedBox(height: 8),
                                                    ],
                                                  );
                                                }(),
                                              ),
                                          ],
                                        ),
                                      );
                                    }

                                    return Table(
                                      columnWidths: columnWidths,
                                      border: TableBorder.symmetric(
                                        inside: BorderSide(
                                          color: Colors.grey.shade300,
                                        ),
                                      ),
                                      children: rows,
                                    );
                                  },
                                ),
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }
}
