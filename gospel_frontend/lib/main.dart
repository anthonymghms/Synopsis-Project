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
import 'package:url_launcher/link.dart';

// ---- CONFIGURATION ----
const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8010',
);
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

const double _zoomMin = 0.8;
const double _zoomMax = 1.6;
const double _zoomDefault = 1.0;

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

class MenuLanguageController {
  MenuLanguageController._();

  static final MenuLanguageController instance = MenuLanguageController._();

  final ValueNotifier<String> _languageCode = ValueNotifier<String>(
    defaultLanguage,
  );
  SharedPreferences? _prefs;
  bool _initialized = false;

  ValueListenable<String> get listenable => _languageCode;
  ValueNotifier<String> get notifier => _languageCode;
  String get languageCode => _languageCode.value;

  Future<void> initialize({String? fallbackLanguageCode}) async {
    if (_initialized) {
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      _prefs = prefs;
      final stored = prefs.getString('selected_menu_language_code');
      final fallback = fallbackLanguageCode?.trim();
      _languageCode.value = stored?.trim().isNotEmpty == true
          ? stored!.trim()
          : (fallback?.isNotEmpty == true ? fallback! : defaultLanguage);
    } catch (_) {
      final fallback = fallbackLanguageCode?.trim();
      _languageCode.value = fallback?.isNotEmpty == true
          ? fallback!
          : defaultLanguage;
    } finally {
      _initialized = true;
    }
  }

  void update(String code) {
    final normalized = code.trim();
    if (normalized.isEmpty || normalized == _languageCode.value) {
      return;
    }
    _languageCode.value = normalized;
    final prefs = _prefs;
    if (prefs != null) {
      prefs.setString('selected_menu_language_code', normalized);
    }
  }
}

class ZoomController {
  ZoomController._();

  static final ZoomController instance = ZoomController._();

  final ValueNotifier<double> _textScale = ValueNotifier<double>(_zoomDefault);
  SharedPreferences? _prefs;
  bool _initialized = false;

  ValueListenable<double> get listenable => _textScale;
  double get textScale => _textScale.value;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      _prefs = prefs;
      final stored = prefs.getDouble('reader_zoom_scale');
      if (stored != null) {
        _textScale.value = stored.clamp(_zoomMin, _zoomMax).toDouble();
      }
    } catch (_) {
      _textScale.value = _zoomDefault;
    } finally {
      _initialized = true;
    }
  }

  void update(double value) {
    final next = value.clamp(_zoomMin, _zoomMax).toDouble();
    if ((next - _textScale.value).abs() < 0.001) {
      return;
    }
    _textScale.value = next;
    final prefs = _prefs;
    if (prefs != null) {
      prefs.setDouble('reader_zoom_scale', next);
    }
  }
}

class BibleVersion {
  final String id;
  final String label;

  const BibleVersion({required this.id, required this.label});
}

class LocalizedUiLabels {
  final String title;
  final String description;
  final String downloadPdf;
  final String resetTable;
  final String pdfUnavailableMessage;
  final String subjectsHeader;
  final List<String> gospelHeaders;
  final String tooltipMessage;
  final String comparePrompt;
  final String language;
  final String version;
  final String addTranslation;
  final String addComparison;
  final String interlinearView;
  final String zoom;
  final String backToMainTable;
  final String nextChapter;
  final String previousChapter;
  final String nextTopic;
  final String previousTopic;
  final String nextBook;
  final String previousBook;
  final String chapter;
  final String addDiacritics;
  final String removeDiacritics;
  final String selectVersion;
  final String selectVersions;
  final String selectTranslationToAdd;
  final String selectLanguage;
  final String versions;
  final String noAlternativeVersions;
  final String comparisonScopeChapter;
  final String comparisons;
  final String change;
  final String changeTranslation;
  final String changeMainTranslation;
  final String removeComparison;
  final String editComparisonRange;
  final String cancel;
  final String done;
  final String save;
  final String saveRange;
  final String customRange;
  final String entireChapter;
  final String highlightedReference;
  final String startVerse;
  final String endVerse;
  final String selected;
  final String duplicateComparison;
  final String noPassageText;
  final String unableToOpenReference;
  final String topicNotFound;
  final String reference;
  final String clickToReadInChapter;
  final String clickToReadAllReferences;
  final String showTopicNames;
  final String hideTopicNames;
  final String menuLanguage;
  final String settings;
  final String logout;
  final String account;
  final String continueAction;
  final String compare;
  final String chooseAuthors;

  const LocalizedUiLabels({
    required this.title,
    required this.description,
    required this.downloadPdf,
    required this.resetTable,
    required this.pdfUnavailableMessage,
    required this.subjectsHeader,
    required this.gospelHeaders,
    required this.tooltipMessage,
    required this.comparePrompt,
    required this.language,
    required this.version,
    required this.addTranslation,
    required this.addComparison,
    required this.interlinearView,
    required this.zoom,
    required this.backToMainTable,
    required this.nextChapter,
    required this.previousChapter,
    required this.nextTopic,
    required this.previousTopic,
    required this.nextBook,
    required this.previousBook,
    required this.chapter,
    required this.addDiacritics,
    required this.removeDiacritics,
    required this.selectVersion,
    required this.selectVersions,
    required this.selectTranslationToAdd,
    required this.selectLanguage,
    required this.versions,
    required this.noAlternativeVersions,
    required this.comparisonScopeChapter,
    required this.comparisons,
    required this.change,
    required this.changeTranslation,
    required this.changeMainTranslation,
    required this.removeComparison,
    required this.editComparisonRange,
    required this.cancel,
    required this.done,
    required this.save,
    required this.saveRange,
    required this.customRange,
    required this.entireChapter,
    required this.highlightedReference,
    required this.startVerse,
    required this.endVerse,
    required this.selected,
    required this.duplicateComparison,
    required this.noPassageText,
    required this.unableToOpenReference,
    required this.topicNotFound,
    required this.reference,
    required this.clickToReadInChapter,
    required this.clickToReadAllReferences,
    required this.showTopicNames,
    required this.hideTopicNames,
    required this.menuLanguage,
    required this.settings,
    required this.logout,
    required this.account,
    required this.continueAction,
    required this.compare,
    required this.chooseAuthors,
  });
}

class LanguageOption {
  final List<BibleVersion> versions;
  final String code;
  final String label;
  final String apiLanguage;
  final String apiVersion;
  final String versionLabel;
  final TextDirection direction;
  final LocalizedUiLabels ui;

  const LanguageOption({
    required this.code,
    required this.label,
    required this.apiLanguage,
    required this.apiVersion,
    required this.versionLabel,
    required this.direction,
    required this.ui,
    required this.versions,
  });

  String get title => ui.title;
  String get description => ui.description;
  String get downloadLabel => ui.downloadPdf;
  String get resetLabel => ui.resetTable;
  String get pdfUnavailableMessage => ui.pdfUnavailableMessage;
  String get subjectsHeader => ui.subjectsHeader;
  List<String> get gospelHeaders => ui.gospelHeaders;
  String get tooltipMessage => ui.tooltipMessage;
  String get comparePrompt => ui.comparePrompt;

  LanguageOption copyWith({
    List<BibleVersion>? versions,
    String? code,
    String? label,
    String? apiLanguage,
    String? apiVersion,
    String? versionLabel,
    TextDirection? direction,
    LocalizedUiLabels? ui,
  }) {
    return LanguageOption(
      code: code ?? this.code,
      label: label ?? this.label,
      apiLanguage: apiLanguage ?? this.apiLanguage,
      apiVersion: apiVersion ?? this.apiVersion,
      versionLabel: versionLabel ?? this.versionLabel,
      direction: direction ?? this.direction,
      ui: ui ?? this.ui,
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
    ui: LocalizedUiLabels(
      title: 'Harmony of the Gospels',
      description:
          'Explore a side-by-side overview of the key events recorded by Matthew, '
          'Mark, Luke, and John. Tap a subject to read the passages together.',
      downloadPdf: 'Download PDF',
      resetTable: 'Reset Table',
      pdfUnavailableMessage: 'PDF download will be available soon.',
      subjectsHeader: 'Subjects',
      gospelHeaders: ['Matthew', 'Mark', 'Luke', 'John'],
      tooltipMessage: 'Click to view more',
      comparePrompt: 'Select authors to compare',
      language: 'Language',
      version: 'Version',
      addTranslation: 'Add translation',
      addComparison: 'Add comparison',
      interlinearView: 'Interlinear View',
      zoom: 'Zoom',
      backToMainTable: 'Back to main table',
      nextChapter: 'Next chapter',
      previousChapter: 'Previous chapter',
      nextTopic: 'Next topic',
      previousTopic: 'Previous topic',
      nextBook: 'Next book',
      previousBook: 'Previous book',
      chapter: 'Chapter',
      addDiacritics: 'Add diacritics',
      removeDiacritics: 'Remove diacritics',
      selectVersion: 'Select version',
      selectVersions: 'Select versions',
      selectTranslationToAdd: 'Select translations to add',
      selectLanguage: 'Select language',
      versions: 'Versions',
      noAlternativeVersions: 'No alternative versions available',
      comparisonScopeChapter: 'Comparison scope: Entire chapter',
      comparisons: 'Comparisons',
      change: 'Change',
      changeTranslation: 'Change translation',
      changeMainTranslation: 'Change main translation',
      removeComparison: 'Remove comparison',
      editComparisonRange: 'Edit comparison range',
      cancel: 'Cancel',
      done: 'Done',
      save: 'Save',
      saveRange: 'Save range',
      customRange: 'Custom range',
      entireChapter: 'Entire chapter',
      highlightedReference: 'Highlighted reference',
      startVerse: 'Start verse',
      endVerse: 'End verse',
      selected: 'Selected',
      duplicateComparison:
          'A comparison with this translation and range already exists.',
      noPassageText: 'No passage text is available for this translation yet.',
      unableToOpenReference: 'Unable to open reference.',
      topicNotFound: 'Topic not found',
      reference: 'Reference',
      clickToReadInChapter: 'Click to read in chapter',
      clickToReadAllReferences: 'Click to read all references',
      showTopicNames: 'Show topic names',
      hideTopicNames: 'Hide topic names',
      menuLanguage: 'Menu language',
      settings: 'Settings',
      logout: 'Logout',
      account: 'Account',
      continueAction: 'Continue',
      compare: 'Compare',
      chooseAuthors: 'Choose authors',
    ),
  ),
  LanguageOption(
    code: 'arabic',
    label: 'العربية',
    apiLanguage: 'arabic',
    apiVersion: arabicVersionWithoutDiacritics,
    versionLabel: 'البستاني فاندايك',
    versions: [
      BibleVersion(id: 'Van Dyke', label: 'البستاني فاندايك'),
      BibleVersion(id: 'Van Dyke-', label: 'البستاني فاندايك'),
      BibleVersion(id: 'New Arabic Version', label: 'كتاب الحياة'),
      BibleVersion(id: 'New Arabic Version-', label: 'كتاب الحياة'),
    ],
    direction: TextDirection.rtl,
    ui: LocalizedUiLabels(
      title: 'تناغم الأناجيل',
      description:
          'استكشف نظرة عامة جنبًا إلى جنب على الأحداث الرئيسية التي سجلها '
          'متى ومرقس ولوقا ويوحنا. اضغط على موضوع لقراءة المقاطع معًا.',
      downloadPdf: 'تحميل PDF',
      resetTable: 'إعادة تعيين الجدول',
      pdfUnavailableMessage: 'سيكون تنزيل ملف PDF متاحًا قريبًا.',
      subjectsHeader: 'المواضيع',
      gospelHeaders: ['متى', 'مرقس', 'لوقا', 'يوحنا'],
      tooltipMessage: 'اضغط لعرض المزيد',
      comparePrompt: 'اختر الأناجيل للمقارنة',
      language: 'اللغة',
      version: 'الترجمة',
      addTranslation: 'إضافة ترجمة',
      addComparison: 'إضافة مقارنة',
      interlinearView: 'العرض المتوازي',
      zoom: 'التكبير',
      backToMainTable: 'العودة إلى الجدول الرئيسي',
      nextChapter: 'الفصل التالي',
      previousChapter: 'الفصل السابق',
      nextTopic: 'الموضوع التالي',
      previousTopic: 'الموضوع السابق',
      nextBook: 'السفر التالي',
      previousBook: 'السفر السابق',
      chapter: 'فصل',
      addDiacritics: 'إضافة الحركات',
      removeDiacritics: 'إزالة الحركات',
      selectVersion: 'اختر الترجمة',
      selectVersions: 'اختر الترجمات',
      selectTranslationToAdd: 'اختر ترجمات لإضافتها',
      selectLanguage: 'اختر اللغة',
      versions: 'الترجمات',
      noAlternativeVersions: 'لا توجد ترجمات بديلة متاحة',
      comparisonScopeChapter: 'نطاق المقارنة: الفصل كاملًا',
      comparisons: 'المقارنات',
      change: 'تغيير',
      changeTranslation: 'تغيير الترجمة',
      changeMainTranslation: 'تغيير الترجمة الرئيسية',
      removeComparison: 'إزالة المقارنة',
      editComparisonRange: 'تعديل نطاق المقارنة',
      cancel: 'إلغاء',
      done: 'تم',
      save: 'حفظ',
      saveRange: 'حفظ النطاق',
      customRange: 'نطاق مخصص',
      entireChapter: 'الفصل كاملًا',
      highlightedReference: 'المرجع المحدد',
      startVerse: 'آية البداية',
      endVerse: 'آية النهاية',
      selected: 'المحدد',
      duplicateComparison: 'توجد مقارنة بهذه الترجمة وهذا النطاق بالفعل.',
      noPassageText: 'لا يتوفر نص لهذا المقطع في هذه الترجمة بعد.',
      unableToOpenReference: 'تعذر فتح المرجع.',
      topicNotFound: 'لم يتم العثور على الموضوع',
      reference: 'مرجع',
      clickToReadInChapter: 'قراءة ضمن الفصل',
      clickToReadAllReferences: 'قراءة كل المراجع',
      showTopicNames: 'إظهار أسماء المواضيع',
      hideTopicNames: 'إخفاء أسماء المواضيع',
      menuLanguage: 'لغة القوائم',
      settings: 'الإعدادات',
      logout: 'تسجيل الخروج',
      account: 'الحساب',
      continueAction: 'متابعة',
      compare: 'قارن',
      chooseAuthors: 'اختر الأناجيل',
    ),
  ),
];

List<LanguageOption> _supportedLanguages = List<LanguageOption>.from(
  kBaseLanguageOptions,
);

final Map<String, LanguageOption> _baseLanguageLookup = {
  for (final option in kBaseLanguageOptions) option.code.toLowerCase(): option,
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
  String languageId,
  List<BibleVersion> versions,
) {
  final template = _baseLanguageLookup['english'] ?? kBaseLanguageOptions.first;
  final sanitizedVersions = versions.isNotEmpty ? versions : template.versions;
  final apiVersion = sanitizedVersions.isNotEmpty
      ? sanitizedVersions.first.id
      : template.apiVersion;
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
    final normalizedArabicVersion = stripped.toLowerCase();
    if (normalizedArabicVersion == 'van dyke') {
      return 'البستاني فاندايك';
    }
    if (normalizedArabicVersion == 'new arabic version' ||
        normalizedArabicVersion == 'nav') {
      return 'كتاب الحياة';
    }
    final baseLabel = _formatLanguageLabel(
      stripped.isNotEmpty ? stripped : normalizedVersion,
    );
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
  Map<String, dynamic> data,
  Set<String> versionIds,
) {
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
  Set<String> versionIds,
) async {
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
      .map((id) => BibleVersion(id: id, label: _versionLabel(languageId, id)))
      .toList();
  versions.sort(
    (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
  );
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

    final template =
        baseOption ?? _fallbackLanguageOption(languageId, versions);
    final sanitizedVersions = versions.isNotEmpty
        ? versions
        : template.versions;
    final apiVersion = sanitizedVersions.isNotEmpty
        ? sanitizedVersions.first.id
        : template.apiVersion;
    final direction = directionField == 'rtl'
        ? TextDirection.rtl
        : directionField == 'ltr'
        ? TextDirection.ltr
        : template.direction;

    options.add(
      template.copyWith(
        code: normalizedCode,
        label: labelFromData?.isNotEmpty == true
            ? labelFromData!
            : (baseOption?.label ?? _formatLanguageLabel(languageId)),
        apiLanguage: languageId,
        apiVersion: apiVersion,
        versions: sanitizedVersions,
        direction: direction,
      ),
    );
  }

  return options.isNotEmpty ? options : kBaseLanguageOptions;
}

LanguageOption _languageOptionForCode(String code) {
  return _supportedLanguages.firstWhere(
    (option) => option.code == code,
    orElse: () => _supportedLanguages.first,
  );
}

class MenuLanguageScope extends InheritedNotifier<ValueNotifier<String>> {
  const MenuLanguageScope({
    super.key,
    required ValueNotifier<String> notifier,
    required super.child,
  }) : super(notifier: notifier);

  static LanguageOption of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<MenuLanguageScope>();
    final code =
        scope?.notifier?.value ?? MenuLanguageController.instance.languageCode;
    return _languageOptionForCode(code);
  }
}

Uri _mainTableUri({required LanguageOption language, required String version}) {
  return Uri(
    path: '/',
    queryParameters: {
      'language': language.apiLanguage,
      'version': _sanitizeVersionForLanguage(language, version),
    },
  );
}

Uri _topicUri({
  required Topic topic,
  required LanguageOption language,
  required String version,
  String topicNumber = '',
  String comparisonState = '',
}) {
  final queryParameters = {
    'language': language.apiLanguage,
    'version': _sanitizeVersionForLanguage(language, version),
    'topicId': topic.id.isNotEmpty ? topic.id : topic.name,
    'topicNumber': topicNumber.trim().isNotEmpty
        ? topicNumber.trim()
        : _topicNumberForDisplay(topic),
  };
  if (comparisonState.trim().isNotEmpty) {
    queryParameters['comparisons'] = comparisonState.trim();
  }
  return Uri(path: '/topic', queryParameters: queryParameters);
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
  const aliases = {'arabic2': 'arabic', 'ar': 'arabic', 'en': 'english'};
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

  final withoutSuffix = trimmed.endsWith('-')
      ? trimmed.substring(0, trimmed.length - 1)
      : trimmed;
  final normalized = withoutSuffix.toLowerCase();

  if (normalized.contains('dyck')) {
    return normalized.replaceAll('dyck', 'dyke');
  }

  return normalized;
}

String? _resolveArabicVersion(
  LanguageOption option, {
  required bool withDiacritics,
  String? preferredVersion,
}) {
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
      return '$normalizedPreferred-';
    }
    return normalizedPreferred;
  }

  return fallback?.id ??
      (withDiacritics
          ? arabicVersionWithDiacritics
          : arabicVersionWithoutDiacritics);
}

String _sanitizeVersionForLanguage(LanguageOption option, String rawVersion) {
  final normalized = rawVersion.trim();

  if (option.code == 'arabic') {
    final effectiveVersion = normalized.isNotEmpty
        ? normalized
        : option.apiVersion.trim();
    final resolved = _resolveArabicVersion(
      option,
      withDiacritics: !_isArabicWithoutDiacritics(effectiveVersion),
      preferredVersion: effectiveVersion,
    );
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

final RegExp _arabicDiacriticsPattern = RegExp(
  r'[\u0610-\u061A\u064B-\u065F\u0670\u06D6-\u06ED]',
);

String _stripArabicDiacritics(String text) {
  if (text.isEmpty) {
    return text;
  }
  return text.replaceAll(_arabicDiacriticsPattern, '');
}

List<_VerseLine> _normalizeVerseLinesForDisplay(
  List<_VerseLine> verses, {
  required LanguageOption language,
  required bool withDiacritics,
}) {
  if (language.code != 'arabic' || withDiacritics) {
    return verses;
  }
  return verses
      .map(
        (verse) => _VerseLine(
          number: verse.number,
          text: _stripArabicDiacritics(verse.text),
        ),
      )
      .toList();
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

bool _isSameTranslation(
  LanguageOption a,
  String versionA,
  LanguageOption b,
  String versionB,
) {
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
    final code = normalizedLanguage.toLowerCase();
    option = _languageOptionForApiLanguage(normalizedLanguage);
    if (option == null &&
        _supportedLanguages.any((language) => language.code == code)) {
      option = _languageOptionForCode(code);
    }
    option ??= _languageOptionForVersion(normalizedLanguage);
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

String _formatReferenceForLanguage(
  String reference,
  TextDirection direction, {
  required bool isArabic,
}) {
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
  return normalized == 'arabic' ||
      normalized == 'arabic2' ||
      normalized == 'ar';
}

String _topicNumberForDisplay(
  Topic topic, {
  int? zeroBasedIndex,
  String? rawNumber,
}) {
  final override = rawNumber?.trim() ?? '';
  if (override.isNotEmpty) {
    return override;
  }

  final id = topic.id.trim();
  final parsedId = int.tryParse(id);
  if (parsedId != null) {
    return parsedId.toString();
  }
  if (id.isNotEmpty) {
    return id;
  }
  if (zeroBasedIndex != null) {
    return (zeroBasedIndex + 1).toString();
  }
  return '';
}

String _localizedTopicNumber(String rawNumber, LanguageOption option) {
  final trimmed = rawNumber.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  return option.code == 'arabic' ? toArabicIndicDigits(trimmed) : trimmed;
}

String _numberedTopicTitle(
  Topic topic,
  LanguageOption option, {
  int? zeroBasedIndex,
  String? topicNumber,
}) {
  final rawNumber = _topicNumberForDisplay(
    topic,
    zeroBasedIndex: zeroBasedIndex,
    rawNumber: topicNumber,
  );
  final localizedNumber = _localizedTopicNumber(rawNumber, option);
  final title = topic.name.trim();
  if (localizedNumber.isEmpty) {
    return title;
  }
  if (title.isEmpty) {
    return localizedNumber;
  }
  return '$localizedNumber $title';
}

String _zoomLabel(double value) => '${(value * 100).round()}%';

ButtonStyle _toolbarOutlinedStyle(BuildContext context) {
  return OutlinedButton.styleFrom(
    minimumSize: const Size(0, 36),
    padding: const EdgeInsetsDirectional.symmetric(horizontal: 12, vertical: 8),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: VisualDensity.compact,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    side: BorderSide(color: Theme.of(context).colorScheme.outline),
  );
}

ButtonStyle _toolbarFilledStyle(BuildContext context) {
  return FilledButton.styleFrom(
    minimumSize: const Size(0, 36),
    padding: const EdgeInsetsDirectional.symmetric(horizontal: 14, vertical: 8),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: VisualDensity.compact,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
  );
}

Widget _compactDiacriticsButton({
  required BuildContext context,
  required bool withDiacritics,
  required LocalizedUiLabels labels,
  required VoidCallback onPressed,
}) {
  final label = withDiacritics ? labels.removeDiacritics : labels.addDiacritics;
  final icon = withDiacritics
      ? Icons.remove_circle_outline
      : Icons.add_circle_outline;
  return Tooltip(
    message: label,
    child: TextButton.icon(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 32),
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: 8,
          vertical: 6,
        ),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
      icon: Icon(icon, size: 18),
      label: Text(label, overflow: TextOverflow.ellipsis),
    ),
  );
}

Widget _toolbarDropdownButton<T>({
  required BuildContext context,
  required IconData icon,
  required String label,
  required List<PopupMenuEntry<T>> items,
  required PopupMenuItemSelected<T> onSelected,
  bool enabled = true,
  Key? popupKey,
  VoidCallback? onCanceled,
}) {
  final button = OutlinedButton.icon(
    onPressed: enabled ? () {} : null,
    style: _toolbarOutlinedStyle(context),
    icon: Icon(icon, size: 18),
    label: Text(label, overflow: TextOverflow.ellipsis),
  );

  if (!enabled) {
    return button;
  }

  return Directionality(
    textDirection: MenuLanguageScope.of(context).direction,
    child: PopupMenuButton<T>(
      key: popupKey,
      tooltip: label,
      position: PopupMenuPosition.under,
      onCanceled: onCanceled,
      onSelected: onSelected,
      itemBuilder: (_) => items,
      child: IgnorePointer(child: button),
    ),
  );
}

PopupMenuItem<T> _checkedMenuItem<T>({
  required T value,
  required String label,
  required bool selected,
  required TextDirection textDirection,
}) {
  return PopupMenuItem<T>(
    value: value,
    child: Directionality(
      textDirection: textDirection,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        textDirection: textDirection,
        children: [
          SizedBox(
            width: 24,
            child: selected ? const Icon(Icons.check, size: 18) : null,
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240),
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              textAlign: textDirection == TextDirection.rtl
                  ? TextAlign.right
                  : TextAlign.left,
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _buildToolbarLanguageButton({
  required BuildContext context,
  required LanguageOption language,
  required LanguageOption menuLanguage,
  required List<LanguageOption> languages,
  required ValueChanged<LanguageOption> onSelected,
  bool loading = false,
}) {
  final labels = menuLanguage.ui;
  if (loading) {
    return OutlinedButton.icon(
      onPressed: null,
      style: _toolbarOutlinedStyle(context),
      icon: const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      label: Text(labels.language),
    );
  }

  return _toolbarDropdownButton<String>(
    context: context,
    icon: Icons.language,
    label: '${labels.language}: ${language.label}',
    enabled: languages.length > 1,
    items: languages
        .map(
          (option) => _checkedMenuItem<String>(
            value: option.code,
            label: option.label,
            selected: option.code == language.code,
            textDirection: menuLanguage.direction,
          ),
        )
        .toList(),
    onSelected: (code) {
      final match = languages.firstWhere(
        (option) => option.code == code,
        orElse: () => language,
      );
      if (match.code != language.code) {
        onSelected(match);
      }
    },
  );
}

Widget _buildToolbarVersionButton({
  required BuildContext context,
  required LanguageOption language,
  required LanguageOption menuLanguage,
  required String selectedVersion,
  required ValueChanged<String> onSelected,
  Key? popupKey,
  VoidCallback? onCanceled,
}) {
  final versions = _selectableVersions(language);
  if (versions.isEmpty) {
    return const SizedBox.shrink();
  }

  final current = _selectionVersionValue(language, selectedVersion);
  final currentLabel = _versionLabel(language.code, selectedVersion);
  return _toolbarDropdownButton<String>(
    context: context,
    icon: Icons.menu_book_outlined,
    label: '${menuLanguage.ui.version}: $currentLabel',
    enabled: versions.length > 1,
    popupKey: popupKey,
    onCanceled: onCanceled,
    items: versions
        .map(
          (version) => _checkedMenuItem<String>(
            value: version.id,
            label: version.label,
            selected:
                _selectionVersionValue(language, version.id).toLowerCase() ==
                current.toLowerCase(),
            textDirection: menuLanguage.direction,
          ),
        )
        .toList(),
    onSelected: onSelected,
  );
}

Widget _buildToolbarZoomButton({
  required BuildContext context,
  required LanguageOption menuLanguage,
  required double value,
  required ValueChanged<double> onSelected,
}) {
  final current = value.clamp(_zoomMin, _zoomMax).toDouble();
  final label = '${menuLanguage.ui.zoom}: ${_zoomLabel(current)}';
  return Directionality(
    textDirection: menuLanguage.direction,
    child: Tooltip(
      message: label,
      child: Container(
        height: 36,
        width: 222,
        padding: const EdgeInsetsDirectional.only(start: 10, end: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
        child: Row(
          children: [
            const Icon(Icons.zoom_in, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 7,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 14,
                  ),
                ),
                child: Slider(
                  min: _zoomMin,
                  max: _zoomMax,
                  value: current,
                  onChanged: onSelected,
                  semanticFormatterCallback: _zoomLabel,
                ),
              ),
            ),
            SizedBox(
              width: 42,
              child: Text(
                _zoomLabel(current),
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

typedef ToolbarTranslationChanged =
    FutureOr<void> Function(LanguageOption language, String version);

class AppToolbar extends StatefulWidget {
  const AppToolbar({
    super.key,
    required this.language,
    required this.version,
    required this.languages,
    required this.onLanguageChanged,
    required this.onVersionChanged,
    this.title,
    this.titleWidget,
    this.languagesLoading = false,
    this.primaryActions = const <Widget>[],
    this.trailingActions = const <Widget>[],
    this.showVersionSelector = true,
    this.showLanguageSelector = true,
    this.onTranslationChanged,
  });

  final String? title;
  final Widget? titleWidget;
  final LanguageOption language;
  final String version;
  final List<LanguageOption> languages;
  final ValueChanged<LanguageOption> onLanguageChanged;
  final ValueChanged<String> onVersionChanged;
  final bool languagesLoading;
  final List<Widget> primaryActions;
  final List<Widget> trailingActions;
  final bool showVersionSelector;
  final bool showLanguageSelector;
  final ToolbarTranslationChanged? onTranslationChanged;

  @override
  State<AppToolbar> createState() => _AppToolbarState();
}

class _AppToolbarState extends State<AppToolbar> {
  final GlobalKey<PopupMenuButtonState<String>> _versionMenuKey =
      GlobalKey<PopupMenuButtonState<String>>();
  LanguageOption? _versionGuidanceLanguage;

  LanguageOption get _versionLanguage =>
      _versionGuidanceLanguage ?? widget.language;

  String get _versionValue {
    final guidanceLanguage = _versionGuidanceLanguage;
    if (guidanceLanguage == null) {
      return widget.version;
    }
    return _defaultToolbarVersion(guidanceLanguage);
  }

  String _defaultToolbarVersion(LanguageOption language) {
    if (language.code == widget.language.code) {
      return widget.version;
    }
    final versions = _selectableVersions(language);
    if (versions.isNotEmpty) {
      return _sanitizeVersionForLanguage(language, versions.first.id);
    }
    return _sanitizeVersionForLanguage(language, language.apiVersion);
  }

  void _clearVersionGuidance() {
    if (_versionGuidanceLanguage == null || !mounted) {
      return;
    }
    setState(() {
      _versionGuidanceLanguage = null;
    });
  }

  void _handleLanguageSelected(LanguageOption language) {
    if (language.code == widget.language.code) {
      return;
    }
    final combinedHandler = widget.onTranslationChanged;
    final versions = _selectableVersions(language);
    if (combinedHandler == null || versions.length <= 1) {
      final version = versions.isNotEmpty
          ? versions.first.id
          : language.apiVersion;
      if (combinedHandler != null) {
        combinedHandler(
          language,
          _sanitizeVersionForLanguage(language, version),
        );
      } else {
        widget.onLanguageChanged(language);
      }
      return;
    }

    setState(() {
      _versionGuidanceLanguage = language;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _versionMenuKey.currentState?.showButtonMenu();
    });
  }

  void _handleVersionSelected(String version) {
    final guidanceLanguage = _versionGuidanceLanguage;
    if (guidanceLanguage != null) {
      setState(() {
        _versionGuidanceLanguage = null;
      });
      widget.onTranslationChanged?.call(
        guidanceLanguage,
        _sanitizeVersionForLanguage(guidanceLanguage, version),
      );
      return;
    }
    widget.onVersionChanged(version);
  }

  @override
  Widget build(BuildContext context) {
    final titleText = widget.title?.trim() ?? '';
    final menuLanguage = MenuLanguageScope.of(context);
    final resolvedTitle =
        widget.titleWidget ??
        (titleText.isEmpty
            ? null
            : Text(
                titleText,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ));
    final controls = <Widget>[
      if (widget.showLanguageSelector)
        _buildToolbarLanguageButton(
          context: context,
          language: widget.language,
          menuLanguage: menuLanguage,
          languages: widget.languages,
          loading: widget.languagesLoading,
          onSelected: _handleLanguageSelected,
        ),
      if (widget.showVersionSelector)
        _buildToolbarVersionButton(
          context: context,
          language: _versionLanguage,
          menuLanguage: menuLanguage,
          selectedVersion: _versionValue,
          onSelected: _handleVersionSelected,
          popupKey: _versionMenuKey,
          onCanceled: _clearVersionGuidance,
        ),
      ...widget.primaryActions,
      ...widget.trailingActions,
    ].where((widget) => widget is! SizedBox).toList();

    return Directionality(
      textDirection: menuLanguage.direction,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (resolvedTitle != null) ...[
              SizedBox(width: double.infinity, child: resolvedTitle),
              const SizedBox(height: 6),
            ],
            if (controls.isNotEmpty)
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                textDirection: menuLanguage.direction,
                spacing: 6,
                runSpacing: 6,
                children: controls,
              ),
          ],
        ),
      ),
    );
  }
}

Widget _buildMenuLanguageButton({
  required BuildContext context,
  required LanguageOption menuLanguage,
}) {
  final languages = _supportedLanguages.isNotEmpty
      ? _supportedLanguages
      : kBaseLanguageOptions;
  return Directionality(
    textDirection: menuLanguage.direction,
    child: PopupMenuButton<String>(
      tooltip: menuLanguage.ui.menuLanguage,
      position: PopupMenuPosition.under,
      icon: const Icon(Icons.public, size: 22),
      onSelected: MenuLanguageController.instance.update,
      itemBuilder: (_) => languages
          .map(
            (option) => _checkedMenuItem<String>(
              value: option.code,
              label: option.label,
              selected: option.code == menuLanguage.code,
              textDirection: menuLanguage.direction,
            ),
          )
          .toList(),
    ),
  );
}

Widget _buildGlobalTopNavigation({
  required BuildContext context,
  required LanguageOption contentLanguage,
  required String contentVersion,
  bool showBackToMainTable = false,
}) {
  final menuLanguage = MenuLanguageScope.of(context);
  final labels = menuLanguage.ui;
  return Directionality(
    textDirection: menuLanguage.direction,
    child: Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 4,
      children: [
        if (showBackToMainTable)
          TextButton.icon(
            onPressed: () {
              Navigator.of(context).pushNamed(
                _mainTableUri(
                  language: contentLanguage,
                  version: contentVersion,
                ).toString(),
              );
            },
            icon: const Icon(Icons.table_chart_outlined, size: 18),
            label: Text(labels.backToMainTable),
          ),
        _buildMenuLanguageButton(context: context, menuLanguage: menuLanguage),
      ],
    ),
  );
}

Future<String> _storedVersionForLanguage(LanguageOption option) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('selected_version_${option.code}');
    if (stored != null && stored.trim().isNotEmpty) {
      if (option.code == 'arabic') {
        return _resolveArabicVersion(
              option,
              withDiacritics: false,
              preferredVersion: stored,
            ) ??
            _sanitizeVersionForLanguage(option, stored);
      }
      return _sanitizeVersionForLanguage(option, stored);
    }
  } catch (_) {
    // Persistence is a convenience, not a blocker for navigation.
  }
  if (option.code == 'arabic') {
    return _resolveArabicVersion(
          option,
          withDiacritics: false,
          preferredVersion: option.apiVersion,
        ) ??
        _sanitizeVersionForLanguage(option, option.apiVersion);
  }
  return _sanitizeVersionForLanguage(option, option.apiVersion);
}

Future<void> _persistLanguageVersion(
  LanguageOption option,
  String version, {
  bool? withDiacritics,
}) async {
  LanguageSelectionController.instance.update(option.code);
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'selected_version_${option.code}',
      _sanitizeVersionForLanguage(option, version),
    );
    if (option.code == 'arabic' && withDiacritics != null) {
      await prefs.setBool('arabic_with_diacritics', withDiacritics);
    }
  } catch (_) {
    // Keep the UI responsive if local persistence is unavailable.
  }
}

bool _hasAdminFlag(Map<String, dynamic> data) {
  final role = data['role']?.toString().trim().toLowerCase();
  final roles = data['roles'];
  return data['isAdmin'] == true ||
      data['admin'] == true ||
      role == 'admin' ||
      (roles is Iterable &&
          roles.any((entry) => entry.toString().toLowerCase() == 'admin'));
}

Future<bool> _isCurrentUserAdmin() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    return false;
  }

  try {
    final token = await user.getIdTokenResult();
    final claims = token.claims ?? const <String, dynamic>{};
    if (_hasAdminFlag(Map<String, dynamic>.from(claims))) {
      return true;
    }
  } catch (_) {
    // Fall through to the Firestore profile check.
  }

  // Temporary client-side visibility helper only. Backend endpoints and
  // Firestore rules must enforce real admin authorization before trusting it.
  try {
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final data = snapshot.data();
    return data != null && _hasAdminFlag(data);
  } catch (_) {
    return false;
  }
}

String _combineBookAndReference(
  String book,
  String reference,
  TextDirection direction, {
  bool isArabic = false,
}) {
  final trimmedBook = book.trim();
  final trimmedReference = reference.trim();
  if (trimmedBook.isEmpty) {
    return _formatReferenceForLanguage(
      reference,
      direction,
      isArabic: isArabic,
    );
  }
  if (trimmedReference.isEmpty) {
    return trimmedBook;
  }
  final formattedReference = _formatReferenceForLanguage(
    reference,
    direction,
    isArabic: isArabic,
  );
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
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await LanguageSelectionController.instance.initialize();
  await MenuLanguageController.instance.initialize(
    fallbackLanguageCode: LanguageSelectionController.instance.languageCode,
  );
  await ZoomController.instance.initialize();
  runApp(GospelApp());
}

class GospelApp extends StatelessWidget {
  const GospelApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MenuLanguageScope(
      notifier: MenuLanguageController.instance.notifier,
      child: MaterialApp(
        title: 'Gospel Topics',
        theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
        onGenerateRoute: _onGenerateRoute,
        builder: (context, child) {
          final menuLanguage = MenuLanguageScope.of(context);
          return Directionality(
            textDirection: menuLanguage.direction,
            child: child ?? const SizedBox.shrink(),
          );
        },
      ),
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

    final uri = Uri.parse(normalized);
    final path = uri.path.isEmpty ? '/' : uri.path;

    if (path == '/') {
      final rawLanguage = uri.queryParameters['language'];
      final rawVersion = uri.queryParameters['version'];
      return MaterialPageRoute(
        settings: settings,
        builder: (_) => AuthGate(
          builder: (context) => TopicListScreen(
            initialLanguage: rawLanguage,
            initialVersion: rawVersion,
          ),
        ),
      );
    }

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
          uri.queryParameters['bookDisplay'] ??
          uri.queryParameters['book'] ??
          '';
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
      final initialLanguage =
          uri.queryParameters['language'] ?? defaultLanguage;
      final initialVersion = uri.queryParameters['version'] ?? defaultVersion;
      final initialTopicId = uri.queryParameters['topicId'] ?? '';
      final initialTopicNumber = uri.queryParameters['topicNumber'] ?? '';
      final comparisons = uri.queryParameters['comparisons'] ?? '';

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
            topicNumber: initialTopicNumber,
            comparisonState: comparisons,
          ),
        ),
      );
    }

    return MaterialPageRoute(
      settings: settings,
      builder: (_) => AuthGate(builder: (context) => const TopicListScreen()),
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
    this.topicNumber = '',
    this.comparisonState = '',
  });

  final LanguageOption languageOption;
  final String apiVersion;
  final String topicId;
  final String topicNumber;
  final String comparisonState;

  @override
  State<TopicDetailScreen> createState() => _TopicDetailScreenState();
}

class _TopicDetailScreenState extends State<TopicDetailScreen> {
  Topic? _topic;
  List<Topic> _topics = const <Topic>[];
  int _topicIndex = -1;
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

    final uri = Uri.parse('$apiBaseUrl/topics').replace(
      queryParameters: {
        'language': widget.languageOption.apiLanguage,
        'version': widget.apiVersion,
      },
    );

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
      final matchIndex = _findTopicIndex(topics);
      final match = matchIndex == -1 ? null : topics[matchIndex];

      if (!mounted) {
        return;
      }

      setState(() {
        _topics = topics;
        _topicIndex = matchIndex;
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

  int _findTopicIndex(List<Topic> topics) {
    final normalizedId = widget.topicId.trim().toLowerCase();
    for (var i = 0; i < topics.length; i++) {
      final topic = topics[i];
      final id = topic.id.trim();
      if (id.isNotEmpty && id.toLowerCase() == normalizedId) {
        return i;
      }
      final name = topic.name.trim();
      if (name.isNotEmpty && name.toLowerCase() == normalizedId) {
        return i;
      }
    }
    return -1;
  }

  @override
  Widget build(BuildContext context) {
    final menuLanguage = MenuLanguageScope.of(context);
    final textDirection = menuLanguage.direction;

    Widget pageScaffold(Widget body) {
      return Directionality(
        textDirection: textDirection,
        child: MainScaffold(
          title: '',
          topNavigation: _buildGlobalTopNavigation(
            context: context,
            contentLanguage: widget.languageOption,
            contentVersion: widget.apiVersion,
            showBackToMainTable: true,
          ),
          settingsLabel: menuLanguage.ui.settings,
          logoutLabel: menuLanguage.ui.logout,
          accountTooltip: menuLanguage.ui.account,
          body: body,
        ),
      );
    }

    if (_loading) {
      return pageScaffold(const Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      final message = _error == 'Topic not found'
          ? menuLanguage.ui.topicNotFound
          : _error!;
      return pageScaffold(Center(child: Text(message)));
    }

    final topic = _topic;
    if (topic == null) {
      return pageScaffold(Center(child: Text(menuLanguage.ui.topicNotFound)));
    }

    final authors = topic.references.map((e) => e.book).toSet().toList()
      ..sort(_compareBooks);

    return AuthorComparisonScreen(
      languageOption: widget.languageOption,
      apiVersion: widget.apiVersion,
      topic: topic,
      initialAuthors: authors,
      topics: _topics,
      topicIndex: _topicIndex,
      topicNumber: widget.topicNumber.trim().isNotEmpty
          ? widget.topicNumber
          : _topicNumberForDisplay(topic, zeroBasedIndex: _topicIndex),
      comparisonState: widget.comparisonState,
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
  String _selectedLanguageCode =
      LanguageSelectionController.instance.languageCode;
  bool _arabicWithDiacritics = false;
  final Map<String, String> _selectedVersions = {};
  SharedPreferences? _prefs;
  String? _pendingTopicId;
  bool _isAdmin = false;
  bool _routeProvidedInitialVersion = false;

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
        _routeProvidedInitialVersion = true;
        _selectedVersions[_selectedLanguageCode] = _sanitizeVersionForLanguage(
          resolved,
          initialVersion,
        );
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
    _loadAdminState();
  }

  Future<void> _loadAdminState() async {
    final isAdmin = await _isCurrentUserAdmin();
    if (!mounted) {
      return;
    }
    setState(() {
      _isAdmin = isAdmin;
    });
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
      final sanitized = option.code == 'arabic'
          ? (_resolveArabicVersion(
                  option,
                  withDiacritics: false,
                  preferredVersion: stored,
                ) ??
                _sanitizeVersionForLanguage(option, stored))
          : _sanitizeVersionForLanguage(option, stored);
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
        _arabicWithDiacritics = false;
        for (final entry in versionSelections.entries) {
          final routeOwnsCurrentSelection =
              _routeProvidedInitialVersion &&
              entry.key == _selectedLanguageCode;
          if (!routeOwnsCurrentSelection) {
            _selectedVersions[entry.key] = entry.value;
          }
        }
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

      final hasSelection = _supportedLanguages.any(
        (option) => option.code == _selectedLanguageCode,
      );
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
    LanguageOption option,
    String versionId,
  ) async {
    final normalized = option.code == 'arabic'
        ? (_resolveArabicVersion(
                option,
                withDiacritics: false,
                preferredVersion: versionId,
              ) ??
              _sanitizeVersionForLanguage(option, versionId))
        : _sanitizeVersionForLanguage(option, versionId);
    if (normalized.isEmpty) {
      return;
    }
    final arabicWithDiacritics = false;
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
      Navigator.of(context).pushReplacementNamed(
        _mainTableUri(language: option, version: normalized).toString(),
      );
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedVersions[option.code] = normalized;
      if (option.code == 'arabic') {
        _arabicWithDiacritics = arabicWithDiacritics;
      }
    });
  }

  Future<void> _updateContentTranslation(
    LanguageOption option,
    String versionId,
  ) async {
    final normalized = option.code == 'arabic'
        ? (_resolveArabicVersion(
                option,
                withDiacritics: false,
                preferredVersion: versionId,
              ) ??
              _sanitizeVersionForLanguage(option, versionId))
        : _sanitizeVersionForLanguage(option, versionId);
    if (normalized.isEmpty) {
      return;
    }
    await _persistLanguageVersion(
      option,
      normalized,
      withDiacritics: option.code == 'arabic' ? false : null,
    );
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushReplacementNamed(
      _mainTableUri(language: option, version: normalized).toString(),
    );
  }

  Future<void> _updateLanguage(LanguageOption option) async {
    if (option.code == _selectedLanguageCode) {
      return;
    }
    final storedVersion = await _storedVersionForLanguage(option);
    await _updateContentTranslation(option, storedVersion);
  }

  String _apiVersionFor(LanguageOption option) {
    final selectedVersion = _selectedVersions[option.code]?.trim();
    if (option.code == 'arabic') {
      final baseVersion =
          (selectedVersion != null && selectedVersion.isNotEmpty)
          ? selectedVersion
          : (option.versions.isNotEmpty
                ? option.versions.first.id
                : option.apiVersion);
      final resolved =
          _resolveArabicVersion(
            option,
            withDiacritics: _arabicWithDiacritics,
            preferredVersion: baseVersion,
          ) ??
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
    final uri = Uri.parse('$apiBaseUrl/topics').replace(
      queryParameters: {
        'language': languageOption.apiLanguage,
        'version': apiVersion,
      },
    );
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

  @override
  Widget build(BuildContext context) {
    final languageOption = _languageOption;
    final menuLanguage = MenuLanguageScope.of(context);
    return Directionality(
      textDirection: menuLanguage.direction,
      child: MainScaffold(
        title: '',
        topNavigation: _buildGlobalTopNavigation(
          context: context,
          contentLanguage: languageOption,
          contentVersion: _apiVersionFor(languageOption),
        ),
        settingsLabel: menuLanguage.ui.settings,
        logoutLabel: menuLanguage.ui.logout,
        accountTooltip: menuLanguage.ui.account,
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(child: Text(_error!))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppToolbar(
                    language: languageOption,
                    version: _apiVersionFor(languageOption),
                    languages: _supportedLanguages,
                    languagesLoading: _languagesLoading,
                    onLanguageChanged: _updateLanguage,
                    onVersionChanged: (version) =>
                        _updateVersionForLanguage(languageOption, version),
                    onTranslationChanged: _updateContentTranslation,
                    trailingActions: [
                      if (_isAdmin)
                        FilledButton.icon(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  menuLanguage.pdfUnavailableMessage,
                                ),
                              ),
                            );
                          },
                          style: _toolbarFilledStyle(context),
                          icon: const Icon(
                            Icons.picture_as_pdf_outlined,
                            size: 18,
                          ),
                          label: Text(menuLanguage.downloadLabel),
                        ),
                      if (_isAdmin)
                        OutlinedButton.icon(
                          onPressed: () {
                            _tableKey.currentState?.resetScroll();
                          },
                          style: _toolbarOutlinedStyle(context),
                          icon: const Icon(Icons.refresh, size: 18),
                          label: Text(menuLanguage.resetLabel),
                        ),
                    ],
                  ),
                  const Divider(height: 0),
                  Expanded(
                    child: HarmonyTable(
                      key: _tableKey,
                      topics: _topics,
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
      final uri = _topicUri(topic: topic, language: language, version: version);
      Navigator.of(context).pushNamed(uri.toString());
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AuthorComparisonScreen(
          languageOption: _languageOption,
          apiVersion: _apiVersionFor(_languageOption),
          topic: topic,
          initialAuthors: authors,
          topicNumber: _topicNumberForDisplay(topic),
        ),
      ),
    );
  }
}

class HarmonyTable extends StatefulWidget {
  const HarmonyTable({
    super.key,
    required this.topics,
    required this.languageOption,
    required this.apiVersion,
  });

  final List<Topic> topics;
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
      _verticalController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
    if (_bodyHorizontalController.hasClients) {
      _bodyHorizontalController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
    if (_headerHorizontalController.hasClients) {
      _headerHorizontalController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
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
      for (final gospel in orderedGospels) gospel: <GospelReference>[],
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
    final number = _localizedTopicNumber(
      _topicNumberForDisplay(topic, zeroBasedIndex: index),
      widget.languageOption,
    );

    return Align(
      alignment: alignment,
      child: Row(
        mainAxisSize: MainAxisSize.max,
        mainAxisAlignment: isRtl
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
        children: [
          Text(
            number,
            style: textStyle,
            textAlign: TextAlign.start,
            maxLines: 1,
            overflow: TextOverflow.clip,
            softWrap: false,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              topic.name,
              style: textStyle,
              textAlign: textAlign,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(String label, TextStyle? style, TextAlign align) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: Text(label, style: style, textAlign: align),
    );
  }

  Uri _topicRouteUri(Topic topic, int index) {
    return _topicUri(
      topic: topic,
      language: widget.languageOption,
      version: widget.apiVersion,
      topicNumber: _topicNumberForDisplay(topic, zeroBasedIndex: index),
    );
  }

  WrapAlignment _wrapAlignmentForTextAlign(
    TextAlign align,
    TextDirection direction,
  ) {
    switch (align) {
      case TextAlign.center:
        return WrapAlignment.center;
      case TextAlign.right:
        return direction == TextDirection.rtl
            ? WrapAlignment.start
            : WrapAlignment.end;
      case TextAlign.left:
        return direction == TextDirection.rtl
            ? WrapAlignment.end
            : WrapAlignment.start;
      case TextAlign.start:
        return WrapAlignment.start;
      case TextAlign.end:
        return WrapAlignment.end;
      case TextAlign.justify:
        return WrapAlignment.start;
    }
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Text('—', style: style, textAlign: align),
      );
    }

    AlignmentGeometry cellAlignment;
    switch (align) {
      case TextAlign.center:
        cellAlignment = Alignment.center;
        break;
      case TextAlign.right:
        cellAlignment = Alignment.centerRight;
        break;
      default:
        cellAlignment = Alignment.centerLeft;
        break;
    }

    final wrapAlignment = _wrapAlignmentForTextAlign(
      align,
      widget.languageOption.direction,
    );
    final tooltipMessage = MenuLanguageScope.of(
      context,
    ).ui.clickToReadInChapter;
    final useCombinedHoverPreview = filteredRefs.length > 1;
    final children = filteredRefs
        .map(
          (ref) => ReferenceHoverText(
            key: ValueKey(
              [
                widget.languageOption.apiLanguage,
                widget.apiVersion,
                topic.id,
                ref.bookId,
                ref.book,
                ref.chapter,
                ref.verses,
              ].join('|'),
            ),
            reference: ref,
            textStyle: style,
            textAlign: align,
            textDirection: widget.languageOption.direction,
            topicName: topic.name,
            topicId: topic.id.isNotEmpty ? topic.id : topic.name,
            sourceContext: 'harmony',
            gospel: gospel,
            language: widget.languageOption.apiLanguage,
            version: widget.apiVersion,
            tooltipMessage: tooltipMessage,
            enableHoverPreview: !useCombinedHoverPreview,
          ),
        )
        .toList();

    final cellContent = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
      child: Align(
        alignment: cellAlignment,
        child: Wrap(
          alignment: wrapAlignment,
          runAlignment: wrapAlignment,
          crossAxisAlignment: WrapCrossAlignment.center,
          textDirection: widget.languageOption.direction,
          spacing: 8,
          runSpacing: 4,
          children: children,
        ),
      ),
    );

    if (!useCombinedHoverPreview) {
      return cellContent;
    }

    return ReferenceCellHoverPreview(
      key: ValueKey(
        [
          'cell-preview',
          widget.languageOption.apiLanguage,
          widget.apiVersion,
          topic.id,
          gospel,
          ...filteredRefs.map(
            (ref) => [ref.bookId, ref.book, ref.chapter, ref.verses].join(':'),
          ),
        ].join('|'),
      ),
      references: filteredRefs,
      textDirection: widget.languageOption.direction,
      topicName: topic.name,
      topicId: topic.id.isNotEmpty ? topic.id : topic.name,
      sourceContext: 'harmony',
      gospel: gospel,
      language: widget.languageOption.apiLanguage,
      version: widget.apiVersion,
      tooltipMessage: tooltipMessage,
      child: SizedBox(width: double.infinity, child: cellContent),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final languageOption = widget.languageOption;
    final menuLanguage = MenuLanguageScope.of(context);
    final labels = menuLanguage.ui;
    final isRtl = languageOption.direction == TextDirection.rtl;
    final headerStyle = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
      color: theme.colorScheme.onSurface,
    );
    final subjectStyle = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w600,
      height: 1.18,
    );
    final referenceStyle = theme.textTheme.bodyMedium?.copyWith(height: 1.18);
    final borderColor = theme.dividerColor.withValues(alpha: 0.4);
    final headerBackground = theme.colorScheme.surfaceContainerHighest;
    final subjectAlign = isRtl ? TextAlign.right : TextAlign.left;
    final referenceAlign = isRtl ? TextAlign.right : TextAlign.center;
    assert(
      labels.gospelHeaders.length == orderedGospels.length,
      'labels.gospelHeaders must match number of gospels',
    );

    final headerRow = TableRow(
      decoration: BoxDecoration(color: headerBackground),
      children: [
        _buildHeaderCell(labels.subjectsHeader, headerStyle, subjectAlign),
        for (var i = 0; i < orderedGospels.length; i++)
          _buildHeaderCell(
            labels.gospelHeaders[i],
            headerStyle,
            TextAlign.center,
          ),
      ],
    );
    final bodyRows = <TableRow>[];

    for (var i = 0; i < widget.topics.length; i++) {
      final topic = widget.topics[i];
      final grouped = _groupReferences(topic);
      final isEvenRow = i.isEven;
      final baseColor = theme.colorScheme.surface;
      final alternateColor = theme.colorScheme.surfaceContainerHighest
          .withValues(alpha: 0.35);
      bodyRows.add(
        TableRow(
          decoration: BoxDecoration(
            color: isEvenRow ? baseColor : alternateColor,
          ),
          children: [
            TableCell(
              verticalAlignment: TableCellVerticalAlignment.top,
              child: Tooltip(
                message:
                    '${labels.clickToReadAllReferences}\n${_numberedTopicTitle(topic, languageOption, zeroBasedIndex: i)}',
                waitDuration: const Duration(milliseconds: 400),
                child: Link(
                  uri: _topicRouteUri(topic, i),
                  target: LinkTarget.self,
                  builder: (context, followLink) => TableRowInkWell(
                    onTap: followLink,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
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

    final availableWidth = MediaQuery.sizeOf(context).width;
    const minScrollableTableWidth = 760.0;
    final tableWidth = math.max(availableWidth, minScrollableTableWidth);
    final horizontalFrameWidth = tableWidth;

    return Column(
      children: [
        SingleChildScrollView(
          controller: _headerHorizontalController,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: horizontalFrameWidth,
            child: Center(
              child: SizedBox(
                width: tableWidth,
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
                  child: SizedBox(
                    width: horizontalFrameWidth,
                    child: Center(
                      child: SizedBox(
                        width: tableWidth,
                        child: Table(
                          border: TableBorder(
                            horizontalInside: BorderSide(
                              color: borderColor,
                              width: 0.6,
                            ),
                            verticalInside: BorderSide(
                              color: borderColor,
                              width: 0.6,
                            ),
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
    this.tooltipMessage = 'Click to read in chapter',
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
    return '${widget.language}|${_previewVersionForRequest()}|$bookParam|${reference.chapter}|${reference.verses.trim()}';
  }

  LanguageOption _previewLanguageOption() {
    return _languageOptionForApiLanguage(widget.language) ??
        _languageOptionForCode(defaultLanguage);
  }

  String _previewVersionForRequest() {
    final option = _previewLanguageOption();
    if (option.code == 'arabic') {
      return _resolveArabicVersion(
            option,
            withDiacritics: false,
            preferredVersion: widget.version,
          ) ??
          widget.version;
    }
    return widget.version;
  }

  String _previewHeading() {
    final languageOption = _languageOptionForApiLanguage(widget.language);
    final book = _displayGospelName(
      widget.reference.book,
      languageOption ?? _languageOptionForCode(defaultLanguage),
    ).trim();
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
    final maxLeft = math.max(
      _previewViewportPadding,
      viewportSize.width - previewSize.width - _previewViewportPadding,
    );
    final maxTop = math.max(
      _previewViewportPadding,
      viewportSize.height - previewSize.height - _previewViewportPadding,
    );

    final topBottom = target.bottom + _previewGap;
    final fitsBottom =
        topBottom + previewSize.height + _previewViewportPadding <=
        viewportSize.height;
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
    _repositionPreviewTimer = Timer.periodic(const Duration(milliseconds: 16), (
      _,
    ) {
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
      final uri = Uri.parse('$apiBaseUrl/get_verse').replace(
        queryParameters: {
          'language': widget.language,
          'version': _previewVersionForRequest(),
          'book': bookParam,
          'chapter': reference.chapter.toString(),
          'verse': verseParam,
        },
      );
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        throw Exception('Error ${response.statusCode}');
      }
      final verses = _normalizeVerseLinesForDisplay(
        _parseVerseLines(response.body),
        language: _previewLanguageOption(),
        withDiacritics: false,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _previewLoaded = true;
        _loadingPreview = false;
        _previewVerses = verses;
      });
      _previewCache[cacheKey] = _ReferencePreviewCache(
        verses: verses,
        error: null,
      );
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
      _previewCache[cacheKey] = _ReferencePreviewCache(
        verses: const <_VerseLine>[],
        error: _previewError,
      );
      _previewEntry?.markNeedsBuild();
    }
  }

  void _showPreview() {
    if (!widget.enableHoverPreview || _previewEntry != null) {
      return;
    }
    final overlay = Overlay.of(context, rootOverlay: true);
    _previewEntry = OverlayEntry(
      builder: (overlayContext) {
        final renderBox =
            _anchorKey.currentContext?.findRenderObject() as RenderBox?;
        if (renderBox == null || !renderBox.hasSize) {
          return const SizedBox.shrink();
        }
        final target = renderBox.localToGlobal(Offset.zero) & renderBox.size;
        final viewportSize = MediaQuery.of(overlayContext).size;
        final maxWidth = math.min(
          360.0,
          viewportSize.width - (_previewViewportPadding * 2),
        );
        final maxHeight = math.min(
          520.0,
          viewportSize.height - (_previewViewportPadding * 2),
        );
        final estimatedWidth = _previewSize.width
            .clamp(220.0, maxWidth)
            .toDouble();
        final estimatedHeight = _previewSize.height
            .clamp(200.0, maxHeight)
            .toDouble();
        final offset = _previewOffset(
          target,
          viewportSize,
          Size(estimatedWidth, estimatedHeight),
        );
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
      },
    );
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

  bool _previewIdentityChanged(ReferenceHoverText oldWidget) {
    final oldReference = oldWidget.reference;
    final reference = widget.reference;
    return oldWidget.language != widget.language ||
        oldWidget.version != widget.version ||
        oldReference.book != reference.book ||
        oldReference.bookId != reference.bookId ||
        oldReference.chapter != reference.chapter ||
        oldReference.verses != reference.verses;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant ReferenceHoverText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_previewIdentityChanged(oldWidget)) {
      return;
    }
    _hidePreview();
    _cancelHideTimer();
    _isHovered = false;
    _isTriggerHovered = false;
    _isPreviewHovered = false;
    _loadingPreview = false;
    _previewLoaded = false;
    _previewError = null;
    _previewVerses = const <_VerseLine>[];
  }

  Widget _buildPreviewHeader(ThemeData theme) {
    final headingStyle = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w600,
    );
    final helperText = widget.tooltipMessage.trim();
    final helperStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.primary,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
      decorationColor: theme.colorScheme.primary,
    );
    final uri = _buildReferenceUri(widget.reference);
    return Row(
      textDirection: widget.textDirection,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            _previewHeading(),
            style: headingStyle,
            textAlign: TextAlign.start,
          ),
        ),
        if (helperText.isNotEmpty && uri != null) ...[
          const SizedBox(width: 8),
          Link(
            uri: uri,
            target: LinkTarget.self,
            builder: (context, followLink) => InkWell(
              onTap: followLink,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  helperText,
                  style: helperStyle,
                  textAlign: TextAlign.start,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPreviewContent(ThemeData theme) {
    final bodyStyle = theme.textTheme.bodySmall?.copyWith(height: 1.4);
    final numberStyle = bodyStyle?.copyWith(fontWeight: FontWeight.w600);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPreviewHeader(theme),
        const SizedBox(height: 8),
        if (_loadingPreview)
          const Center(child: CircularProgressIndicator())
        else if (_previewError != null)
          Text(
            _previewError!,
            style: bodyStyle?.copyWith(color: theme.colorScheme.error),
          )
        else if (_previewVerses.isEmpty)
          Text(
            (_languageOptionForApiLanguage(widget.language) ??
                    _languageOptionForCode(defaultLanguage))
                .ui
                .noPassageText,
            style: bodyStyle,
          )
        else
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _previewVerses
                    .map(
                      (verse) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: RichText(
                          textScaler: TextScaler.linear(
                            ZoomController.instance.textScale,
                          ),
                          text: TextSpan(
                            style: bodyStyle,
                            children: [
                              if (verse.number != null && verse.number! > 0)
                                TextSpan(
                                  text:
                                      '${formatVerseMarker(verse.number!, language: widget.language, version: widget.version)}. ',
                                  style: numberStyle,
                                ),
                              TextSpan(text: verse.text),
                            ],
                          ),
                        ),
                      ),
                    )
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
    final uri = _buildReferenceUri(widget.reference);

    final link = MouseRegion(
      cursor: text.isEmpty
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
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
        child: Link(
          uri: text.isEmpty ? null : uri,
          target: LinkTarget.self,
          builder: (context, followLink) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: followLink,
            child: Align(
              alignment: alignment,
              widthFactor: 1,
              heightFactor: 1,
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
      ),
    );

    final helperText = widget.tooltipMessage.trim();
    if (text.isEmpty || helperText.isEmpty) {
      return link;
    }

    return Tooltip(
      message: helperText,
      waitDuration: const Duration(milliseconds: 400),
      child: link,
    );
  }
}

class ReferenceCellHoverPreview extends StatefulWidget {
  const ReferenceCellHoverPreview({
    super.key,
    required this.references,
    required this.child,
    this.textDirection = TextDirection.ltr,
    this.topicName = '',
    this.language = defaultLanguage,
    this.version = defaultVersion,
    this.tooltipMessage = 'Click to read in chapter',
    this.topicId = '',
    this.sourceContext = '',
    this.gospel = '',
  });

  final List<GospelReference> references;
  final Widget child;
  final TextDirection textDirection;
  final String topicName;
  final String language;
  final String version;
  final String tooltipMessage;
  final String topicId;
  final String sourceContext;
  final String gospel;

  @override
  State<ReferenceCellHoverPreview> createState() =>
      _ReferenceCellHoverPreviewState();
}

class _ReferenceCellHoverPreviewState extends State<ReferenceCellHoverPreview>
    with WidgetsBindingObserver {
  static const double _previewGap = 8;
  static const double _previewViewportPadding = 8;

  bool _loadingPreview = false;
  bool _previewLoaded = false;
  bool _isTriggerHovered = false;
  bool _isPreviewHovered = false;
  OverlayEntry? _previewEntry;
  Timer? _hidePreviewTimer;
  Timer? _repositionPreviewTimer;
  final GlobalKey _anchorKey = GlobalKey();
  final GlobalKey _previewKey = GlobalKey();
  Size _previewSize = const Size(320, 260);
  bool _pendingPreviewMeasurement = false;
  Map<String, _ReferencePreviewCache> _previewResults =
      const <String, _ReferencePreviewCache>{};

  String _bookParam(GospelReference reference) {
    return reference.bookId.trim().isNotEmpty
        ? reference.bookId.trim()
        : reference.book.trim();
  }

  Uri? _buildReferenceUri(GospelReference reference) {
    final displayBook = reference.book.trim();
    final bookParam = _bookParam(reference);
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

  LanguageOption _previewLanguageOption() {
    return _languageOptionForApiLanguage(widget.language) ??
        _languageOptionForCode(defaultLanguage);
  }

  String _previewVersionForRequest() {
    final option = _previewLanguageOption();
    if (option.code == 'arabic') {
      return _resolveArabicVersion(
            option,
            withDiacritics: false,
            preferredVersion: widget.version,
          ) ??
          widget.version;
    }
    return widget.version;
  }

  String _previewCacheKey(GospelReference reference) {
    return '${widget.language}|${_previewVersionForRequest()}|${_bookParam(reference)}|${reference.chapter}|${reference.verses.trim()}';
  }

  String _previewHeading(GospelReference reference) {
    final languageOption = _languageOptionForApiLanguage(widget.language);
    final book = _displayGospelName(
      reference.book,
      languageOption ?? _languageOptionForCode(defaultLanguage),
    ).trim();
    if (book.isEmpty || reference.chapter <= 0) {
      return _formatReferenceForLanguage(
        reference.formattedReference,
        widget.textDirection,
        isArabic: _isArabicLanguage(widget.language),
      );
    }
    final verses = reference.verses.trim();
    final formattedReference = verses.isEmpty
        ? '${reference.chapter}'
        : '${reference.chapter}:$verses';
    return _combineBookAndReference(
      book,
      formattedReference,
      widget.textDirection,
      isArabic: _isArabicLanguage(widget.language),
    );
  }

  List<GospelReference> _previewReferences() {
    final seen = <String>{};
    final references = <GospelReference>[];
    for (final reference in widget.references) {
      if (reference.formattedReference.trim().isEmpty ||
          reference.chapter <= 0 ||
          _bookParam(reference).isEmpty) {
        continue;
      }
      final key = _previewCacheKey(reference);
      if (seen.add(key)) {
        references.add(reference);
      }
    }
    return references;
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

  Offset _previewOffset(Rect target, Size viewportSize, Size previewSize) {
    final maxLeft = math.max(
      _previewViewportPadding,
      viewportSize.width - previewSize.width - _previewViewportPadding,
    );
    final maxTop = math.max(
      _previewViewportPadding,
      viewportSize.height - previewSize.height - _previewViewportPadding,
    );

    final topBottom = target.bottom + _previewGap;
    final fitsBottom =
        topBottom + previewSize.height + _previewViewportPadding <=
        viewportSize.height;
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
    _previewEntry?.markNeedsBuild();
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
    _repositionPreviewTimer = Timer.periodic(const Duration(milliseconds: 16), (
      _,
    ) {
      _markPreviewNeedsBuild();
    });
  }

  void _stopRepositionListener() {
    _repositionPreviewTimer?.cancel();
    _repositionPreviewTimer = null;
  }

  Future<MapEntry<String, _ReferencePreviewCache>> _fetchPreview(
    GospelReference reference,
  ) async {
    final cacheKey = _previewCacheKey(reference);
    final verseParam = reference.verses.trim().isEmpty
        ? '1'
        : reference.verses.trim();

    try {
      final uri = Uri.parse('$apiBaseUrl/get_verse').replace(
        queryParameters: {
          'language': widget.language,
          'version': _previewVersionForRequest(),
          'book': _bookParam(reference),
          'chapter': reference.chapter.toString(),
          'verse': verseParam,
        },
      );
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        throw Exception('Error ${response.statusCode}');
      }
      final cache = _ReferencePreviewCache(
        verses: _normalizeVerseLinesForDisplay(
          _parseVerseLines(response.body),
          language: _previewLanguageOption(),
          withDiacritics: false,
        ),
        error: null,
      );
      _ReferenceHoverTextState._previewCache[cacheKey] = cache;
      return MapEntry(cacheKey, cache);
    } catch (_) {
      const cache = _ReferencePreviewCache(
        verses: <_VerseLine>[],
        error: 'Failed to load preview.',
      );
      _ReferenceHoverTextState._previewCache[cacheKey] = cache;
      return MapEntry(cacheKey, cache);
    }
  }

  Future<void> _loadPreview() async {
    if (_loadingPreview || _previewLoaded) {
      return;
    }

    final references = _previewReferences();
    if (references.isEmpty) {
      return;
    }

    final cachedResults = <String, _ReferencePreviewCache>{};
    final missingReferences = <GospelReference>[];
    for (final reference in references) {
      final cacheKey = _previewCacheKey(reference);
      final cached = _ReferenceHoverTextState._previewCache[cacheKey];
      if (cached == null) {
        missingReferences.add(reference);
      } else {
        cachedResults[cacheKey] = cached;
      }
    }

    if (missingReferences.isEmpty) {
      setState(() {
        _previewLoaded = true;
        _previewResults = cachedResults;
      });
      _markPreviewNeedsBuild();
      return;
    }

    setState(() {
      _loadingPreview = true;
      _previewResults = cachedResults;
    });
    _markPreviewNeedsBuild();

    final loadedResults = await Future.wait(
      missingReferences.map(_fetchPreview),
    );
    if (!mounted) {
      return;
    }

    final results = <String, _ReferencePreviewCache>{...cachedResults};
    for (final entry in loadedResults) {
      results[entry.key] = entry.value;
    }

    setState(() {
      _previewLoaded = true;
      _loadingPreview = false;
      _previewResults = results;
    });
    _markPreviewNeedsBuild();
  }

  void _showPreview() {
    if (_previewEntry != null) {
      return;
    }
    final overlay = Overlay.of(context, rootOverlay: true);
    _previewEntry = OverlayEntry(
      builder: (overlayContext) {
        final renderBox =
            _anchorKey.currentContext?.findRenderObject() as RenderBox?;
        if (renderBox == null || !renderBox.hasSize) {
          return const SizedBox.shrink();
        }
        final target = renderBox.localToGlobal(Offset.zero) & renderBox.size;
        final viewportSize = MediaQuery.of(overlayContext).size;
        final maxWidth = math.min(
          380.0,
          viewportSize.width - (_previewViewportPadding * 2),
        );
        final maxHeight = math.min(
          520.0,
          viewportSize.height - (_previewViewportPadding * 2),
        );
        final estimatedWidth = _previewSize.width
            .clamp(240.0, maxWidth)
            .toDouble();
        final estimatedHeight = _previewSize.height
            .clamp(180.0, maxHeight)
            .toDouble();
        final offset = _previewOffset(
          target,
          viewportSize,
          Size(estimatedWidth, estimatedHeight),
        );
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
                  minWidth: 240,
                  maxWidth: maxWidth,
                  minHeight: 180,
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
      },
    );
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

  bool _previewIdentityChanged(ReferenceCellHoverPreview oldWidget) {
    if (oldWidget.language != widget.language ||
        oldWidget.version != widget.version ||
        oldWidget.references.length != widget.references.length) {
      return true;
    }
    for (var i = 0; i < widget.references.length; i++) {
      final oldReference = oldWidget.references[i];
      final reference = widget.references[i];
      if (oldReference.book != reference.book ||
          oldReference.bookId != reference.bookId ||
          oldReference.chapter != reference.chapter ||
          oldReference.verses != reference.verses) {
        return true;
      }
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant ReferenceCellHoverPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_previewIdentityChanged(oldWidget)) {
      return;
    }
    _hidePreview();
    _cancelHideTimer();
    _isTriggerHovered = false;
    _isPreviewHovered = false;
    _loadingPreview = false;
    _previewLoaded = false;
    _previewResults = const <String, _ReferencePreviewCache>{};
  }

  Widget _buildPreviewHeader(ThemeData theme, GospelReference reference) {
    final headingStyle = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w600,
    );
    final helperText = widget.tooltipMessage.trim();
    final helperStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.primary,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
      decorationColor: theme.colorScheme.primary,
    );
    final uri = _buildReferenceUri(reference);
    return Row(
      textDirection: widget.textDirection,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            _previewHeading(reference),
            style: headingStyle,
            textAlign: TextAlign.start,
          ),
        ),
        if (helperText.isNotEmpty && uri != null) ...[
          const SizedBox(width: 8),
          Link(
            uri: uri,
            target: LinkTarget.self,
            builder: (context, followLink) => InkWell(
              onTap: followLink,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  helperText,
                  style: helperStyle,
                  textAlign: TextAlign.start,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPreviewVerse(
    _VerseLine verse,
    ThemeData theme,
    TextStyle? bodyStyle,
    TextStyle? numberStyle,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        textScaler: TextScaler.linear(ZoomController.instance.textScale),
        text: TextSpan(
          style: bodyStyle,
          children: [
            if (verse.number != null && verse.number! > 0)
              TextSpan(
                text:
                    '${formatVerseMarker(verse.number!, language: widget.language, version: widget.version)}. ',
                style: numberStyle,
              ),
            TextSpan(text: verse.text),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewSection(
    ThemeData theme,
    GospelReference reference,
    int index,
  ) {
    final bodyStyle = theme.textTheme.bodySmall?.copyWith(height: 1.4);
    final numberStyle = bodyStyle?.copyWith(fontWeight: FontWeight.w600);
    final cache = _previewResults[_previewCacheKey(reference)];
    final error = cache?.error;
    final verses = cache?.verses ?? const <_VerseLine>[];
    final noPassageText = _previewLanguageOption().ui.noPassageText;

    return Padding(
      padding: EdgeInsets.only(top: index == 0 ? 0 : 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (index > 0) ...[
            Divider(
              height: 14,
              thickness: 0.8,
              color: theme.dividerColor.withValues(alpha: 0.65),
            ),
          ],
          _buildPreviewHeader(theme, reference),
          const SizedBox(height: 8),
          if (error != null)
            Text(
              error,
              style: bodyStyle?.copyWith(color: theme.colorScheme.error),
            )
          else if (verses.isEmpty)
            Text(noPassageText, style: bodyStyle)
          else
            ...verses.map(
              (verse) =>
                  _buildPreviewVerse(verse, theme, bodyStyle, numberStyle),
            ),
        ],
      ),
    );
  }

  Widget _buildPreviewContent(ThemeData theme) {
    final references = _previewReferences();
    final bodyStyle = theme.textTheme.bodySmall?.copyWith(height: 1.4);
    if (references.isEmpty) {
      return Text(_previewLanguageOption().ui.noPassageText, style: bodyStyle);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_loadingPreview)
          const Center(child: CircularProgressIndicator())
        else
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < references.length; i++)
                    _buildPreviewSection(theme, references[i], i),
                ],
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
    return MouseRegion(
      cursor: MouseCursor.defer,
      hitTestBehavior: HitTestBehavior.opaque,
      onEnter: (_) {
        _isTriggerHovered = true;
        _cancelHideTimer();
        _showPreview();
        _loadPreview();
      },
      onExit: (_) {
        _isTriggerHovered = false;
        _schedulePreviewHide();
      },
      child: KeyedSubtree(key: _anchorKey, child: widget.child),
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
    required this.previousBookUri,
    required this.previousChapterUri,
    required this.nextChapterUri,
    required this.nextBookUri,
  });

  final int chapter;
  final Uri? previousBookUri;
  final Uri? previousChapterUri;
  final Uri? nextChapterUri;
  final Uri? nextBookUri;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final uiLanguage = MenuLanguageScope.of(context);
    final isRtl = uiLanguage.direction == TextDirection.rtl;
    final labels = uiLanguage.ui;
    final chapterNumber = uiLanguage.code == 'arabic'
        ? toArabicIndicDigits(chapter.toString())
        : chapter.toString();

    Widget fixedDirectionIcon(IconData icon) {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: Icon(icon),
      );
    }

    Widget navButton({
      required String tooltip,
      required Uri? uri,
      required IconData icon,
    }) {
      return Link(
        uri: uri,
        target: LinkTarget.self,
        builder: (context, followLink) => IconButton(
          tooltip: tooltip,
          onPressed: uri == null ? null : followLink,
          icon: fixedDirectionIcon(icon),
        ),
      );
    }

    final leadingControls = isRtl
        ? <Widget>[
            navButton(
              tooltip: labels.nextBook,
              uri: nextBookUri,
              icon: Icons.keyboard_double_arrow_left,
            ),
            navButton(
              tooltip: labels.nextChapter,
              uri: nextChapterUri,
              icon: Icons.chevron_left,
            ),
          ]
        : <Widget>[
            navButton(
              tooltip: labels.previousBook,
              uri: previousBookUri,
              icon: Icons.keyboard_double_arrow_left,
            ),
            navButton(
              tooltip: labels.previousChapter,
              uri: previousChapterUri,
              icon: Icons.chevron_left,
            ),
          ];
    final trailingControls = isRtl
        ? <Widget>[
            navButton(
              tooltip: labels.previousChapter,
              uri: previousChapterUri,
              icon: Icons.chevron_right,
            ),
            navButton(
              tooltip: labels.previousBook,
              uri: previousBookUri,
              icon: Icons.keyboard_double_arrow_right,
            ),
          ]
        : <Widget>[
            navButton(
              tooltip: labels.nextChapter,
              uri: nextChapterUri,
              icon: Icons.chevron_right,
            ),
            navButton(
              tooltip: labels.nextBook,
              uri: nextBookUri,
              icon: Icons.keyboard_double_arrow_right,
            ),
          ];

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          textDirection: TextDirection.ltr,
          children: [
            ...leadingControls,
            Expanded(
              child: Directionality(
                textDirection: uiLanguage.direction,
                child: Text(
                  '${labels.chapter} $chapterNumber',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            ...trailingControls,
          ],
        ),
      ),
    );
  }
}

class _ChapterVerseGroup {
  const _ChapterVerseGroup({required this.title, required this.verses});

  final String? title;
  final List<_VerseLine> verses;
}

enum _ComparisonScopeMode { highlight, custom, chapter }

class _ReferenceViewerPageState extends State<ReferenceViewerPage> {
  static const double _minTextScale = _zoomMin;
  static const double _maxTextScale = _zoomMax;
  bool _loadingChapter = true;
  String? _error;
  List<_VerseLine> _chapterVerses = const <_VerseLine>[];
  Set<int> _highlightVerses = const <int>{};
  int? _highlightStart;
  bool _loadingHarmonyTopics = false;
  String? _harmonyTopicsError;
  List<Topic> _harmonyTopics = const <Topic>[];
  bool _withDiacritics = false;
  bool _showTopicNames = false;
  bool _interlinearView = false;
  double _textScale = 1.0;
  late String _selectedVersion;
  final List<_ComparisonPassage> _comparisons = [];
  bool _languagesLoading = false;

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

  LanguageOption get _languageOption {
    final fromLanguage = _languageOptionForApiLanguage(widget.language);
    if (fromLanguage != null) {
      return fromLanguage;
    }
    return _languageOptionForVersion(widget.version);
  }

  LocalizedUiLabels get _labels => MenuLanguageScope.of(context).ui;

  String get _activeApiLanguage => _languageOption.apiLanguage;

  @override
  void initState() {
    super.initState();
    _textScale = ZoomController.instance.textScale;
    LanguageSelectionController.instance.update(_languageOption.code);
    _selectedVersion = _sanitizeVersionForLanguage(
      _languageOption,
      widget.version,
    );
    if (_languageOption.code == 'arabic') {
      _selectedVersion =
          _resolveArabicVersion(
            _languageOption,
            withDiacritics: false,
            preferredVersion: _selectedVersion,
          ) ??
          _selectedVersion;
      _withDiacritics = false;
    } else {
      _withDiacritics = !_isArabicWithoutDiacritics(_selectedVersion);
    }
    _hydrateComparisonsFromRoute();
    _loadChapter();
    if (_isHarmonySource) {
      _loadHarmonyTopics();
    }
    _refreshLanguagesForToolbar();
  }

  Future<void> _refreshLanguagesForToolbar() async {
    setState(() {
      _languagesLoading = true;
    });
    try {
      final options = await _loadLanguagesFromFirestore();
      if (!mounted) {
        return;
      }
      setState(() {
        _supportedLanguages = options;
      });
    } catch (_) {
      // Keep the bundled language config if Firestore is unavailable.
    } finally {
      if (mounted) {
        setState(() {
          _languagesLoading = false;
        });
      }
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
      return _resolveArabicVersion(
            _languageOption,
            withDiacritics: _withDiacritics,
            preferredVersion: _selectedVersion,
          ) ??
          _languageOption.apiVersion;
    }
    return _baseVersion;
  }

  String _comparisonVersion(
    LanguageOption option,
    String version, {
    bool? withDiacritics,
  }) {
    if (option.code == 'arabic') {
      final prefersDiacritics =
          withDiacritics ??
          !_isArabicWithoutDiacritics(
            version.isNotEmpty ? version : option.apiVersion.trim(),
          );
      return _resolveArabicVersion(
            option,
            withDiacritics: prefersDiacritics,
            preferredVersion: version,
          ) ??
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
        return _formatReferenceForLanguage(
          override,
          direction,
          isArabic: _isArabicLanguage(widget.language),
        );
      }
      return _combineBookAndReference(
        book,
        override,
        direction,
        isArabic: _isArabicLanguage(widget.language),
      );
    }
    if (book.isEmpty) {
      return _labels.reference;
    }
    if (widget.chapter <= 0) {
      return book;
    }
    final verses = widget.verses.trim();
    final reference = verses.isEmpty
        ? '${widget.chapter}'
        : '${widget.chapter}:$verses';
    return _combineBookAndReference(
      book,
      reference,
      direction,
      isArabic: _isArabicLanguage(widget.language),
    );
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
      final match = RegExp(
        r'(?:\d+)\s*:\s*(\d+)(?:\s*-\s*(\d+))?',
      ).firstMatch(label);
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

  void _scrollToHighlightedVerse({int attempts = 10}) {
    if (_highlightStart == null) {
      return;
    }

    final targetId =
        'verse-${_slugBookForId(_bookParameter)}-${widget.chapter}-${_highlightStart!}';
    final targetContext = _verseKeys[targetId]?.currentContext;

    if (targetContext == null) {
      if (attempts <= 0) {
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _scrollToHighlightedVerse(attempts: attempts - 1);
      });
      return;
    }

    Scrollable.ensureVisible(
      targetContext,
      alignment: 0.15,
      duration: Duration.zero,
      curve: Curves.linear,
    );
  }

  final Map<String, GlobalKey> _verseKeys = <String, GlobalKey>{};

  String _encodeComparisonState() {
    if (_comparisons.isEmpty) {
      return '';
    }
    final payload = _comparisons
        .map(
          (entry) => {
            'language': entry.language.apiLanguage,
            'version': entry.version,
            'scopeMode': entry.scopeMode.name,
            'scopeStartVerse': entry.scopeStartVerse,
            'scopeEndVerse': entry.scopeEndVerse,
            'withDiacritics': entry.withDiacritics,
          },
        )
        .toList();
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
        final language = _languageOptionForApiLanguage(
          (mapItem['language'] ?? '').toString(),
        );
        if (language == null) {
          continue;
        }
        final version = _sanitizeVersionForLanguage(
          language,
          (mapItem['version'] ?? '').toString(),
        );
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
            : language.code != 'arabic';
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
      'language': _activeApiLanguage,
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
    final uri = Uri.parse('$apiBaseUrl/topics').replace(
      queryParameters: {
        'language': _activeApiLanguage,
        'version': _activeVersion,
      },
    );
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

      final explicitRange = RegExp(
        r'^(\d+):(\d+)\s*-\s*(\d+):(\d+)$',
      ).firstMatch(part);
      if (explicitRange != null) {
        final startChapter = int.tryParse(explicitRange.group(1)!);
        final startVerse = int.tryParse(explicitRange.group(2)!);
        final endChapter = int.tryParse(explicitRange.group(3)!);
        final endVerse = int.tryParse(explicitRange.group(4)!);
        if (startChapter == null ||
            startVerse == null ||
            endChapter == null ||
            endVerse == null) {
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
    final apiLanguage = _activeApiLanguage.trim();
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
      final uri = Uri.parse('$apiBaseUrl/get_chapter').replace(
        queryParameters: {
          'language': _activeApiLanguage,
          'version': _activeVersion,
          'book': bookParam,
          'chapter': widget.chapter.toString(),
        },
      );
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        throw Exception('Error ${response.statusCode}');
      }
      final verses = _normalizeVerseLinesForDisplay(
        _parseVerseLines(response.body),
        language: _languageOption,
        withDiacritics: _withDiacritics,
      );
      final highlights = _parseHighlightVerses();
      final start = highlights.isEmpty
          ? null
          : (highlights.toList()..sort()).first;
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

  Future<void> _toggleReferenceDiacritics() async {
    if (_languageOption.code != 'arabic') {
      return;
    }
    setState(() {
      _withDiacritics = !_withDiacritics;
    });
    await _loadChapter();
  }

  Future<void> _updateSelectedVersion(String newVersion) async {
    await _updateReferenceTranslation(_languageOption, newVersion);
  }

  Future<void> _updateReferenceTranslation(
    LanguageOption language,
    String versionId,
  ) async {
    final sanitized = language.code == 'arabic'
        ? (_resolveArabicVersion(
                language,
                withDiacritics: false,
                preferredVersion: versionId,
              ) ??
              _sanitizeVersionForLanguage(language, versionId))
        : _sanitizeVersionForLanguage(language, versionId);
    if (language.code == _languageOption.code &&
        sanitized == _selectedVersion &&
        (language.code != 'arabic' || !_withDiacritics)) {
      return;
    }

    try {
      await _persistLanguageVersion(
        language,
        sanitized,
        withDiacritics: language.code == 'arabic' ? false : null,
      );
    } catch (_) {}

    if (!mounted) {
      return;
    }
    Navigator.of(context).pushReplacementNamed(
      _referenceUriForTranslation(language, sanitized).toString(),
    );
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
    final TextStyle verseStyle = highlighted
        ? baseStyle.copyWith(fontWeight: FontWeight.w700)
        : baseStyle;
    final TextStyle numberStyle = baseStyle.copyWith(
      fontWeight: highlighted ? FontWeight.w700 : FontWeight.w600,
    );
    return Padding(
      key: verseId != null
          ? (_verseKeys.putIfAbsent(verseId, () => GlobalKey()))
          : null,
      padding: const EdgeInsets.only(bottom: 12),
      child: RichText(
        textScaler: TextScaler.linear(_textScale),
        textAlign: TextAlign.start,
        text: TextSpan(
          style: verseStyle,
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
      ),
    );
  }

  Uri _referenceUriForTranslation(LanguageOption language, String version) {
    final queryParameters = <String, String>{
      'book': _bookParameter,
      'bookDisplay': widget.displayBook.trim().isNotEmpty
          ? widget.displayBook.trim()
          : _bookParameter,
      'chapter': widget.chapter.toString(),
      'language': language.apiLanguage,
      'version': _sanitizeVersionForLanguage(language, version),
    };

    if (widget.verses.trim().isNotEmpty) {
      queryParameters['verses'] = widget.verses.trim();
    }
    if (widget.topicName.trim().isNotEmpty) {
      queryParameters['topic'] = widget.topicName.trim();
    }
    if (widget.referenceLabelOverride.trim().isNotEmpty) {
      queryParameters['label'] = widget.referenceLabelOverride.trim();
    }
    if (widget.source.trim().isNotEmpty) {
      queryParameters['source'] = widget.source.trim();
    }
    if (widget.topicId.trim().isNotEmpty) {
      queryParameters['topicId'] = widget.topicId.trim();
    }
    if (widget.gospel.trim().isNotEmpty) {
      queryParameters['gospel'] = widget.gospel.trim();
    }
    final comparisonState = _encodeComparisonState();
    if (comparisonState.isNotEmpty) {
      queryParameters['comparisons'] = comparisonState;
    }
    return Uri(path: '/reference', queryParameters: queryParameters);
  }

  Future<void> _updateReferenceLanguage(LanguageOption language) async {
    final storedVersion = await _storedVersionForLanguage(language);
    await _updateReferenceTranslation(language, storedVersion);
  }

  ChapterNav _buildChapterNavigation() {
    final canonical = _normalizeGospelName(_bookParameter);
    final bookIndex = orderedGospels.indexOf(canonical);
    final maxChapter = gospelChapterCounts[canonical];
    final hasPreviousBook = bookIndex > 0;
    final hasNextBook = bookIndex >= 0 && bookIndex < orderedGospels.length - 1;
    final hasPreviousChapter = widget.chapter > 1;
    final hasNextChapter =
        bookIndex >= 0 &&
        (maxChapter == null ? true : widget.chapter < maxChapter);

    return ChapterNav(
      chapter: widget.chapter,
      previousBookUri: hasPreviousBook
          ? _referenceUri(book: orderedGospels[bookIndex - 1], chapter: 1)
          : null,
      previousChapterUri: hasPreviousChapter
          ? _referenceUri(book: canonical, chapter: widget.chapter - 1)
          : null,
      nextChapterUri: hasNextChapter
          ? _referenceUri(book: canonical, chapter: widget.chapter + 1)
          : null,
      nextBookUri: hasNextBook
          ? _referenceUri(book: orderedGospels[bookIndex + 1], chapter: 1)
          : null,
    );
  }

  List<_ChapterVerseGroup> _buildChapterVerseGroups(List<_VerseLine> verses) {
    if (!_showTopicNames || verses.isEmpty || _harmonyTopics.isEmpty) {
      return [_ChapterVerseGroup(title: null, verses: verses)];
    }

    final canonicalBook = _currentCanonicalBook;
    final topicByVerse = <int, String>{};
    for (final topic in _harmonyTopics) {
      final topicTitle = topic.name.trim();
      if (topicTitle.isEmpty) {
        continue;
      }
      for (final reference in topic.references) {
        if (_normalizeGospelName(reference.book) != canonicalBook) {
          continue;
        }
        final verseNumbers = _topicVerseNumbersForCurrentChapter(
          reference,
        ).toList()..sort();
        for (final number in verseNumbers) {
          topicByVerse.putIfAbsent(number, () => topicTitle);
        }
      }
    }

    if (topicByVerse.isEmpty) {
      return [_ChapterVerseGroup(title: null, verses: verses)];
    }

    final groups = <_ChapterVerseGroup>[];
    String? currentTitle;
    var currentVerses = <_VerseLine>[];

    void flush() {
      if (currentVerses.isEmpty) {
        return;
      }
      groups.add(
        _ChapterVerseGroup(
          title: currentTitle,
          verses: List<_VerseLine>.from(currentVerses),
        ),
      );
      currentVerses = <_VerseLine>[];
    }

    for (final verse in verses) {
      final number = verse.number;
      final title = number == null ? null : topicByVerse[number];
      if (currentVerses.isNotEmpty && title != currentTitle) {
        flush();
      }
      currentTitle = title;
      currentVerses.add(verse);
    }
    flush();

    return groups.isEmpty
        ? [_ChapterVerseGroup(title: null, verses: verses)]
        : groups;
  }

  List<Widget> _buildVerseGroupWidgets({
    required List<_VerseLine> verses,
    required ThemeData theme,
    required LanguageOption language,
    required String version,
    bool registerScrollTargets = false,
  }) {
    final groups = _buildChapterVerseGroups(verses);
    final bookSlug = _slugBookForId(_bookParameter);
    final registeredScrollVerseIds = <String>{};
    final widgets = <Widget>[];

    for (final group in groups) {
      final title = group.title?.trim();
      if (title != null && title.isNotEmpty) {
        widgets.add(
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 8, bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.35,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }

      for (final verse in group.verses) {
        final number = verse.number;
        final rawVerseId = registerScrollTargets && number != null && number > 0
            ? 'verse-$bookSlug-${widget.chapter}-$number'
            : null;
        final verseId =
            rawVerseId != null && registeredScrollVerseIds.add(rawVerseId)
            ? rawVerseId
            : null;
        widgets.add(
          _buildVerseParagraph(
            verse,
            theme,
            highlighted: number != null && _highlightVerses.contains(number),
            verseId: verseId,
            markerLanguage: language.apiLanguage,
            markerVersion: version,
          ),
        );
      }
    }

    return widgets;
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
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.error,
        ),
      );
    }

    if (_chapterVerses.isEmpty) {
      return Text(_labels.noPassageText, style: theme.textTheme.bodyMedium);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildChapterNavigation(),
        const SizedBox(height: 8),
        ..._buildVerseGroupWidgets(
          verses: _chapterVerses,
          theme: theme,
          language: _languageOption,
          version: _activeVersion,
          registerScrollTargets: true,
        ),
        const SizedBox(height: 12),
        _buildChapterNavigation(),
      ],
    );
  }

  Widget _buildArabicReferenceToggleButton() {
    if (_languageOption.code != 'arabic') {
      return const SizedBox.shrink();
    }
    return _compactDiacriticsButton(
      context: context,
      withDiacritics: _withDiacritics,
      labels: _labels,
      onPressed: _toggleReferenceDiacritics,
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
    var selectedVersion =
        versions.any((version) {
          return _selectionVersionValue(
                _languageOption,
                version.id,
              ).toLowerCase() ==
              _selectionVersionValue(
                _languageOption,
                _activeVersion,
              ).toLowerCase();
        })
        ? versions.firstWhere((version) {
            return _selectionVersionValue(
                  _languageOption,
                  version.id,
                ).toLowerCase() ==
                _selectionVersionValue(
                  _languageOption,
                  _activeVersion,
                ).toLowerCase();
          }).id
        : (versions.isNotEmpty ? versions.first.id : '');
    final labels = _labels;
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('${labels.selectVersion} (${_languageOption.label})'),
          content: StatefulBuilder(
            builder: (context, setModalState) {
              return DropdownButtonFormField<String>(
                key: ValueKey('reference-main-version-$selectedVersion'),
                initialValue: selectedVersion.isEmpty ? null : selectedVersion,
                decoration: InputDecoration(labelText: labels.version),
                items: versions
                    .map(
                      (version) => DropdownMenuItem<String>(
                        value: version.id,
                        child: Text(version.label),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setModalState(() {
                    selectedVersion = value;
                  });
                },
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(labels.cancel),
            ),
            FilledButton(
              onPressed: selectedVersion.isEmpty
                  ? null
                  : () {
                      Navigator.of(context).pop();
                      _updateSelectedVersion(selectedVersion);
                    },
              child: Text(labels.save),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAddComparisonButton() {
    return FilledButton.icon(
      onPressed: _showComparisonPicker,
      style: _toolbarFilledStyle(context),
      icon: const Icon(Icons.library_add, size: 18),
      label: Text(_labels.addTranslation),
    );
  }

  void _toggleTopicNames() {
    final next = !_showTopicNames;
    setState(() {
      _showTopicNames = next;
    });
    if (next && _harmonyTopics.isEmpty && !_loadingHarmonyTopics) {
      _loadHarmonyTopics();
    }
  }

  Widget _buildTopicNamesToggleButton() {
    final label = _showTopicNames
        ? _labels.hideTopicNames
        : _labels.showTopicNames;
    return OutlinedButton.icon(
      onPressed: _toggleTopicNames,
      style: _toolbarOutlinedStyle(context),
      icon: Icon(
        _showTopicNames ? Icons.label_off_outlined : Icons.label_outline,
        size: 18,
      ),
      label: Text(label),
    );
  }

  void _toggleInterlinearView() {
    if (_comparisons.isEmpty) {
      if (_interlinearView) {
        setState(() {
          _interlinearView = false;
        });
      }
      return;
    }
    setState(() {
      _interlinearView = !_interlinearView;
    });
  }

  void _setTextScale(double value) {
    final next = value.clamp(_minTextScale, _maxTextScale).toDouble();
    ZoomController.instance.update(next);
    setState(() {
      _textScale = next;
    });
  }

  Widget _buildZoomControl() => _buildToolbarZoomButton(
    context: context,
    menuLanguage: MenuLanguageScope.of(context),
    value: _textScale,
    onSelected: _setTextScale,
  );

  Widget _wrapWithTextScale(BuildContext context, Widget child) {
    final mediaQuery = MediaQuery.of(context);
    return MediaQuery(
      data: mediaQuery.copyWith(textScaler: TextScaler.linear(_textScale)),
      child: child,
    );
  }

  Widget _buildInterlinearToggleButton() {
    final hasComparisons = _comparisons.isNotEmpty;
    return OutlinedButton.icon(
      onPressed: hasComparisons ? _toggleInterlinearView : null,
      style: _toolbarOutlinedStyle(context),
      icon: Icon(
        _interlinearView ? Icons.view_agenda : Icons.view_agenda_outlined,
      ),
      label: Text(_labels.interlinearView),
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

  bool _isValidScopeRange(int startVerse, int endVerse, int maxVerse) {
    if (!(startVerse >= 1 &&
        endVerse >= 1 &&
        startVerse <= endVerse &&
        endVerse <= maxVerse)) {
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
    final labels = _labels;

    final mainLanguage = _languageOption;
    final mainVersion = _sanitizeVersionForLanguage(
      mainLanguage,
      _activeVersion,
    );

    LanguageOption selectedLanguage = _supportedLanguages.firstWhere(
      (option) => option.code == mainLanguage.code,
      orElse: () => _supportedLanguages.first,
    );
    var selectedVersion = _sanitizeVersionForLanguage(
      selectedLanguage,
      selectedLanguage.apiVersion,
    );
    final versionFocusNode = FocusNode();

    showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: math.min(720, MediaQuery.of(context).size.width * 0.92),
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            child: StatefulBuilder(
              builder: (context, setModalState) {
                final choices = _selectableVersions(selectedLanguage)
                    .map((choice) {
                      final sanitized = _sanitizeVersionForLanguage(
                        selectedLanguage,
                        choice.id,
                      );
                      return _VersionChoice(
                        version: sanitized,
                        label: choice.label,
                      );
                    })
                    .where(
                      (choice) => !_isSameTranslation(
                        selectedLanguage,
                        choice.version,
                        mainLanguage,
                        mainVersion,
                      ),
                    )
                    .toList();

                if (!choices.any(
                      (choice) => choice.version == selectedVersion,
                    ) &&
                    choices.isNotEmpty) {
                  selectedVersion = choices.first.version;
                }

                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.max,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        labels.selectTranslationToAdd,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<LanguageOption>(
                        key: ValueKey(
                          'reference-add-language-${selectedLanguage.code}',
                        ),
                        initialValue: selectedLanguage,
                        decoration: InputDecoration(labelText: labels.language),
                        items: _supportedLanguages
                            .map(
                              (option) => DropdownMenuItem(
                                value: option,
                                child: Text(option.label),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          setModalState(() {
                            selectedLanguage = value;
                            selectedVersion = _sanitizeVersionForLanguage(
                              value,
                              value.apiVersion,
                            );
                          });
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            versionFocusNode.requestFocus();
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        key: ValueKey(
                          'reference-add-version-${selectedLanguage.code}-${choices.length}-$selectedVersion',
                        ),
                        focusNode: versionFocusNode,
                        initialValue:
                            choices.any(
                              (choice) => choice.version == selectedVersion,
                            )
                            ? selectedVersion
                            : null,
                        decoration: InputDecoration(labelText: labels.version),
                        hint: Text(labels.noAlternativeVersions),
                        items: choices
                            .map(
                              (choice) => DropdownMenuItem<String>(
                                value: choice.version,
                                child: Text(choice.label),
                              ),
                            )
                            .toList(),
                        onChanged: choices.isEmpty
                            ? null
                            : (value) {
                                if (value == null) {
                                  return;
                                }
                                setModalState(() {
                                  selectedVersion = value;
                                });
                              },
                      ),
                      const SizedBox(height: 12),
                      Text(
                        labels.comparisonScopeChapter,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const Spacer(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text(labels.cancel),
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
                                      _ComparisonScopeMode.chapter,
                                      1,
                                      maxVerse,
                                    );
                                  },
                            child: Text(labels.addComparison),
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
    ).whenComplete(versionFocusNode.dispose);
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
    final existing = _comparisons.indexWhere(
      (entry) =>
          _comparisonKey(
            entry.language,
            entry.version,
            entry.scopeMode,
            entry.scopeStartVerse,
            entry.scopeEndVerse,
          ) ==
          _comparisonKey(
            option,
            sanitized,
            scopeMode,
            scopeStartVerse,
            scopeEndVerse,
          ),
    );
    if (existing != -1) {
      _loadComparisonPassage(_comparisons[existing]);
      return;
    }

    final entry = _ComparisonPassage(
      language: option,
      version: sanitized,
      withDiacritics:
          option.code != 'arabic' && !_isArabicWithoutDiacritics(sanitized),
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
        entry.error =
            'This reference is missing details needed to load the text.';
      });
      return;
    }
    setState(() {
      entry.loading = true;
      entry.error = null;
      entry.verses = const [];
    });

    try {
      final uri = Uri.parse('$apiBaseUrl/get_chapter').replace(
        queryParameters: {
          'language': entry.language.apiLanguage,
          'version': _comparisonVersion(
            entry.language,
            entry.version,
            withDiacritics: entry.withDiacritics,
          ),
          'book': bookParam,
          'chapter': widget.chapter.toString(),
        },
      );
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
    final labels = _labels;
    LanguageOption selectedLanguage = entry.language;
    String selectedVersion = _sanitizeVersionForLanguage(
      selectedLanguage,
      entry.version,
    );

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final versions = _selectableVersions(selectedLanguage);
            if (!versions.any((v) => v.id == selectedVersion) &&
                versions.isNotEmpty) {
              selectedVersion = versions.first.id;
            }
            return AlertDialog(
              title: Text(labels.changeTranslation),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    key: ValueKey(
                      'reference-edit-language-${selectedLanguage.code}',
                    ),
                    initialValue: selectedLanguage.code,
                    items: _supportedLanguages
                        .map(
                          (option) => DropdownMenuItem<String>(
                            value: option.code,
                            child: Text(option.label),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      final match = _supportedLanguages.firstWhere(
                        (item) => item.code == value,
                      );
                      setModalState(() {
                        selectedLanguage = match;
                        selectedVersion = _sanitizeVersionForLanguage(
                          match,
                          match.apiVersion,
                        );
                      });
                    },
                    decoration: InputDecoration(labelText: labels.language),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey(
                      'reference-edit-version-${selectedLanguage.code}-$selectedVersion-${versions.length}',
                    ),
                    initialValue: selectedVersion,
                    items: versions
                        .map(
                          (version) => DropdownMenuItem<String>(
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
                    decoration: InputDecoration(labelText: labels.version),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(labels.cancel),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    setState(() {
                      entry.language = selectedLanguage;
                      entry.version = _sanitizeVersionForLanguage(
                        selectedLanguage,
                        selectedVersion,
                      );
                      entry.withDiacritics = selectedLanguage.code != 'arabic';
                    });
                    _loadComparisonPassage(entry);
                  },
                  child: Text(labels.save),
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
      if (_comparisons.isEmpty) {
        _interlinearView = false;
      }
    });
  }

  List<_VerseLine> _scopedComparisonVerses(_ComparisonPassage entry) {
    return entry.verses.where((verse) {
      final number = verse.number;
      if (number == null) {
        return false;
      }
      return number >= entry.scopeStartVerse && number <= entry.scopeEndVerse;
    }).toList();
  }

  Widget _buildTranslationPanel({
    required ThemeData theme,
    required LanguageOption language,
    required String version,
    required List<_VerseLine> verses,
    _ComparisonPassage? entry,
    bool isMain = false,
  }) {
    final versionLabel = _versionLabel(language.code, version);
    final title = '${language.label} · $versionLabel';
    final labels = _labels;

    Widget body;
    if (entry?.loading == true) {
      body = const LinearProgressIndicator();
    } else if (entry?.error != null) {
      body = Text(
        entry!.error!,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.error,
        ),
      );
    } else if (verses.isEmpty) {
      body = Text(_labels.noPassageText, style: theme.textTheme.bodyMedium);
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _buildVerseGroupWidgets(
          verses: verses,
          theme: theme,
          language: language,
          version: version,
          registerScrollTargets: isMain,
        ),
      );
    }

    final headerControls = <Widget>[
      if (language.code == 'arabic')
        isMain
            ? _buildArabicReferenceToggleButton()
            : _buildComparisonDiacriticsToggle(entry!),
      TextButton(
        onPressed: isMain
            ? _showVersionPicker
            : entry == null
            ? null
            : () => _showComparisonColumnSelector(entry),
        child: Text(labels.change),
      ),
      if (!isMain && entry != null)
        IconButton(
          onPressed: () => _removeComparison(entry),
          icon: const Icon(Icons.close),
          tooltip: labels.removeComparison,
        ),
    ];
    final titleWidget = Text(
      title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Directionality(
          textDirection: language.direction,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final compactHeader = constraints.maxWidth < 430;
                  if (compactHeader) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        titleWidget,
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          textDirection: language.direction,
                          children: headerControls,
                        ),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: titleWidget),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        textDirection: language.direction,
                        children: headerControls,
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 10),
              body,
            ],
          ),
        ),
      ),
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
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.error,
        ),
      );
    }
    final panels = <Widget Function(double width)>[
      (width) => SizedBox(
        width: width,
        child: _buildTranslationPanel(
          theme: theme,
          language: _languageOption,
          version: _activeVersion,
          verses: _chapterVerses,
          isMain: true,
        ),
      ),
      for (final entry in _comparisons)
        (width) {
          final resolvedVersion = _comparisonVersion(
            entry.language,
            entry.version,
            withDiacritics: entry.withDiacritics,
          );
          return SizedBox(
            width: width,
            child: _buildTranslationPanel(
              theme: theme,
              language: entry.language,
              version: resolvedVersion,
              verses: _scopedComparisonVerses(entry),
              entry: entry,
            ),
          );
        },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildChapterNavigation(),
        const SizedBox(height: 8),
        if (_loadingHarmonyTopics) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: 8),
        ],
        if (_harmonyTopicsError != null) ...[
          Text(
            _harmonyTopicsError!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          const SizedBox(height: 8),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : MediaQuery.of(context).size.width;
            final count = panels.length;
            final spacing = availableWidth >= 760 ? 14.0 : 10.0;
            final columnCount = availableWidth < 760 || count == 1
                ? 1
                : (availableWidth < 1180
                      ? math.min(2, count)
                      : math.min(3, count));
            final maxSinglePanelWidth = count == 1 ? 760.0 : availableWidth;
            final contentWidth = count == 1
                ? math.min(availableWidth, maxSinglePanelWidth)
                : availableWidth;
            final itemWidth = columnCount == 1
                ? math.min(contentWidth, maxSinglePanelWidth)
                : (contentWidth - (spacing * (columnCount - 1))) / columnCount;
            return Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: contentWidth,
                child: Wrap(
                  alignment: WrapAlignment.center,
                  runAlignment: WrapAlignment.center,
                  spacing: spacing,
                  runSpacing: spacing,
                  textDirection: _languageOption.direction,
                  children: [for (final panel in panels) panel(itemWidth)],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        _buildChapterNavigation(),
      ],
    );
  }

  Widget _buildInterlinearReferenceSection(ThemeData theme) {
    if (_chapterVerses.isEmpty) {
      return Text(
        _labels.noPassageText,
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
          ? _comparisonVersion(
              entry.language,
              entry.version,
              withDiacritics: entry.withDiacritics,
            )
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
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          const SizedBox(height: 8),
        ]);
        continue;
      }
      if (entry.verses.isEmpty) {
        statusWidgets.addAll([
          Text(
            '$label: ${_labels.noPassageText}',
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
        _labels.noPassageText,
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
            language: _activeApiLanguage,
            version: _activeVersion,
            emphasized: _highlightVerses.contains(number),
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
    return _compactDiacriticsButton(
      context: context,
      withDiacritics: entry.withDiacritics,
      labels: _labels,
      onPressed: () => _toggleComparisonDiacritics(entry),
    );
  }

  String get _harmonyAppBarTitle {
    final book = _displayBookLabel.isNotEmpty
        ? _displayBookLabel
        : _currentCanonicalBook;
    if (book.isEmpty) {
      return _labels.reference;
    }
    if (_languageOption.code == 'arabic') {
      return 'إنجيل $book';
    }
    return 'Book of $book';
  }

  @override
  Widget build(BuildContext context) {
    final menuLanguage = MenuLanguageScope.of(context);
    return MainScaffold(
      title: '',
      topNavigation: _buildGlobalTopNavigation(
        context: context,
        contentLanguage: _languageOption,
        contentVersion: _activeVersion,
        showBackToMainTable: true,
      ),
      settingsLabel: menuLanguage.ui.settings,
      logoutLabel: menuLanguage.ui.logout,
      accountTooltip: menuLanguage.ui.account,
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final theme = Theme.of(context);
    final direction = MenuLanguageScope.of(context).direction;
    final toolbarTitle = _isHarmonySource
        ? _harmonyAppBarTitle
        : _referenceHeading;
    final primaryActions = <Widget>[
      _buildAddComparisonButton(),
      _buildInterlinearToggleButton(),
      _buildTopicNamesToggleButton(),
      _buildZoomControl(),
    ].where((button) => button is! SizedBox).toList();

    return Directionality(
      textDirection: direction,
      child: Column(
        children: [
          Material(
            color: theme.colorScheme.surface,
            elevation: 1,
            surfaceTintColor: theme.colorScheme.surfaceTint,
            child: AppToolbar(
              title: toolbarTitle,
              language: _languageOption,
              version: _activeVersion,
              languages: _supportedLanguages,
              languagesLoading: _languagesLoading,
              onLanguageChanged: _updateReferenceLanguage,
              onVersionChanged: _updateSelectedVersion,
              onTranslationChanged: _updateReferenceTranslation,
              primaryActions: primaryActions,
            ),
          ),
          const Divider(height: 0),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: MediaQuery.sizeOf(context).width < 640 ? 14 : 20,
                vertical: 14,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1280),
                  child: Directionality(
                    textDirection: _languageOption.direction,
                    child: _wrapWithTextScale(
                      context,
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_interlinearView && _comparisons.isNotEmpty) ...[
                            _buildInterlinearReferenceSection(theme),
                            const SizedBox(height: 24),
                            _buildChapterSection(theme),
                          ] else ...[
                            _buildParallelComparisonSection(theme),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
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
  final verses = decoded.whereType<Map<String, dynamic>>().map((item) {
    final rawNumber = item['verse'];
    int? number;
    if (rawNumber is int) {
      number = rawNumber;
    } else if (rawNumber is String) {
      number = int.tryParse(rawNumber);
    }
    final text = (item['text'] ?? '').toString().trim();
    return _VerseLine(number: number, text: text);
  }).toList();
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
  bool emphasized = false,
}) {
  final resolvedTextStyle =
      textStyle ?? theme.textTheme.bodyLarge?.copyWith(height: 1.6);
  final verseTextStyle = emphasized
      ? resolvedTextStyle?.copyWith(fontWeight: FontWeight.w700)
      : resolvedTextStyle;
  final resolvedLabelStyle =
      labelStyle ??
      theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      );
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          formatVerseMarker(verseNumber, language: language, version: version),
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        ...translations.map((translation) {
          final text = translation.verses[verseNumber] ?? '';
          final verseText = text.isNotEmpty ? text : '—';
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Directionality(
              textDirection: translation.direction,
              child: RichText(
                textAlign: TextAlign.start,
                text: TextSpan(
                  style: resolvedTextStyle,
                  children: [
                    TextSpan(text: verseText, style: verseTextStyle),
                    const TextSpan(text: ' '),
                    TextSpan(
                      text: '(${translation.label})',
                      style: resolvedLabelStyle,
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    ),
  );
}

class _ComparisonPassage {
  _ComparisonPassage({
    required this.language,
    required this.version,
    this.scopeMode = _ComparisonScopeMode.custom,
    this.scopeStartVerse = 1,
    this.scopeEndVerse = 1,
    this.withDiacritics = true,
  });

  LanguageOption language;
  String version;
  _ComparisonScopeMode scopeMode;
  int scopeStartVerse;
  int scopeEndVerse;
  List<_VerseLine> verses = const <_VerseLine>[];
  String? error;
  bool loading = false;
  bool withDiacritics;
}

class _VersionChoice {
  const _VersionChoice({required this.version, required this.label});

  final String version;
  final String label;
}

class Topic {
  final String id;
  final String name;
  final List<GospelReference> references;
  const Topic({required this.id, required this.name, required this.references});

  factory Topic.fromJson(Map<String, dynamic> json) {
    final dynamic referencesRaw = json['references'] ?? json['entries'] ?? [];
    final referencesJson = referencesRaw is List
        ? referencesRaw
        : const <dynamic>[];
    return Topic(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? json['topic'] ?? '').toString().trim(),
      references: referencesJson
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
      verses: (json['verses'] ?? json['verse'] ?? '').toString().trim(),
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
  const ChooseVersionScreen({super.key, required this.topic});

  @override
  State<ChooseVersionScreen> createState() => _ChooseVersionScreenState();
}

class _ChooseVersionScreenState extends State<ChooseVersionScreen> {
  final List<LanguageOption> availableOptions = _supportedLanguages;

  String? _selected;

  @override
  Widget build(BuildContext context) {
    final menuLanguage = MenuLanguageScope.of(context);
    return MainScaffold(
      title: menuLanguage.ui.selectVersion,
      topNavigation: _buildGlobalTopNavigation(
        context: context,
        contentLanguage: menuLanguage,
        contentVersion: menuLanguage.apiVersion,
        showBackToMainTable: true,
      ),
      settingsLabel: menuLanguage.ui.settings,
      logoutLabel: menuLanguage.ui.logout,
      accountTooltip: menuLanguage.ui.account,
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              initialValue: _selected,
              decoration: InputDecoration(labelText: menuLanguage.ui.version),
              items: availableOptions
                  .map(
                    (option) => DropdownMenuItem<String>(
                      value: option.apiVersion,
                      child: Text('${option.label} · ${option.versionLabel}'),
                    ),
                  )
                  .toList(),
              onChanged: (val) {
                setState(() {
                  _selected = val;
                });
              },
            ),
            const Spacer(),
            FilledButton(
              onPressed: _selected == null
                  ? null
                  : () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChooseAuthorScreen(
                            topic: widget.topic,
                            version: _selected!,
                          ),
                        ),
                      );
                    },
              child: Text(menuLanguage.ui.continueAction),
            ),
          ],
        ),
      ),
    );
  }
}

// ----- Third Screen: Choose Authors -----
class ChooseAuthorScreen extends StatefulWidget {
  final Topic topic;
  final String version;
  const ChooseAuthorScreen({
    super.key,
    required this.topic,
    required this.version,
  });

  @override
  State<ChooseAuthorScreen> createState() => _ChooseAuthorScreenState();
}

class _ChooseAuthorScreenState extends State<ChooseAuthorScreen> {
  late final List<String> authors;
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    authors =
        widget.topic.references
            .map((e) => _normalizeGospelName(e.book))
            .toSet()
            .toList()
          ..sort(_compareBooks);
  }

  @override
  Widget build(BuildContext context) {
    final option = _languageOptionForVersion(widget.version);
    final menuLanguage = MenuLanguageScope.of(context);
    return MainScaffold(
      title: menuLanguage.ui.chooseAuthors,
      topNavigation: _buildGlobalTopNavigation(
        context: context,
        contentLanguage: option,
        contentVersion: widget.version,
        showBackToMainTable: true,
      ),
      settingsLabel: menuLanguage.ui.settings,
      logoutLabel: menuLanguage.ui.logout,
      accountTooltip: menuLanguage.ui.account,
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
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AuthorComparisonScreen(
                            languageOption: _languageOptionForVersion(
                              widget.version,
                            ),
                            apiVersion: widget.version,
                            topic: widget.topic,
                            initialAuthors: _selected.toList()
                              ..sort(_compareBooks),
                          ),
                        ),
                      );
                    },
              child: Text(menuLanguage.ui.compare),
            ),
          ),
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
  final String topicNumber;
  final List<Topic> topics;
  final int topicIndex;
  final String comparisonState;
  const AuthorComparisonScreen({
    super.key,
    required this.languageOption,
    required this.topic,
    required this.initialAuthors,
    required this.apiVersion,
    this.topicNumber = '',
    this.topics = const <Topic>[],
    this.topicIndex = -1,
    this.comparisonState = '',
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
  static const double _minTextScale = _zoomMin;
  static const double _maxTextScale = _zoomMax;
  late List<String> _allAuthors;
  late Set<String> _selected;
  Map<String, List<_AuthorTextEntry>> _texts = {};
  final Map<String, List<_ComparisonPassage>> _entryComparisons = {};
  final List<_ComparisonPassage> _comparisonTemplates = [];
  String? _error;
  bool _loading = true;
  bool _withDiacritics = true;
  bool _interlinearView = false;
  double _textScale = 1.0;
  late LanguageOption _languageOption;
  late String _apiVersion;
  late Topic _topic;
  bool _languagesLoading = false;

  LocalizedUiLabels get _labels => MenuLanguageScope.of(context).ui;

  String get _activeVersion {
    if (_languageOption.code == 'arabic') {
      return _resolveArabicVersion(
            _languageOption,
            withDiacritics: _withDiacritics,
            preferredVersion: _apiVersion,
          ) ??
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

  String _comparisonVersionFor(
    LanguageOption option,
    String version, {
    bool? withDiacritics,
  }) {
    if (option.code == 'arabic') {
      final prefersDiacritics =
          withDiacritics ??
          !_isArabicWithoutDiacritics(
            version.isNotEmpty ? version : option.apiVersion.trim(),
          );
      return _resolveArabicVersion(
            option,
            withDiacritics: prefersDiacritics,
            preferredVersion: version,
          ) ??
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

  String get _topicToolbarTitle => _numberedTopicTitle(
    _topic,
    _languageOption,
    topicNumber: widget.topicNumber,
  );

  @override
  void initState() {
    super.initState();
    _textScale = ZoomController.instance.textScale;
    _languageOption = widget.languageOption;
    _apiVersion = _sanitizeVersionForLanguage(
      _languageOption,
      widget.apiVersion,
    );
    if (_languageOption.code == 'arabic') {
      _apiVersion =
          _resolveArabicVersion(
            _languageOption,
            withDiacritics: false,
            preferredVersion: _apiVersion,
          ) ??
          _apiVersion;
      _withDiacritics = false;
    } else {
      _withDiacritics = !_isArabicWithoutDiacritics(_apiVersion);
    }
    LanguageSelectionController.instance.update(_languageOption.code);
    _topic = widget.topic;
    _allAuthors =
        _topic.references
            .map((e) => _normalizeGospelName(e.book))
            .toSet()
            .toList()
          ..sort(_compareBooks);
    _selected = widget.initialAuthors.map(_normalizeGospelName).toSet();
    _hydrateTopicComparisonsFromRoute();
    fetchTexts(preserveComparisons: true);
    _refreshLanguagesForToolbar();
  }

  bool get _hasEntryComparisons =>
      _comparisonTemplates.isNotEmpty ||
      _entryComparisons.values.any((entries) => entries.isNotEmpty);

  Future<void> _refreshLanguagesForToolbar() async {
    setState(() {
      _languagesLoading = true;
    });
    try {
      final options = await _loadLanguagesFromFirestore();
      if (!mounted) {
        return;
      }
      setState(() {
        _supportedLanguages = options;
        _languageOption = options.firstWhere(
          (option) => option.code == _languageOption.code,
          orElse: () => _languageOption,
        );
        _apiVersion = _sanitizeVersionForLanguage(_languageOption, _apiVersion);
      });
    } catch (_) {
      // Keep the bundled language config if Firestore is unavailable.
    } finally {
      if (mounted) {
        setState(() {
          _languagesLoading = false;
        });
      }
    }
  }

  Future<void> fetchTexts({bool preserveComparisons = false}) async {
    if (_selected.isEmpty) {
      setState(() {
        _texts = {};
        _loading = false;
        if (!preserveComparisons) {
          _entryComparisons.clear();
          _comparisonTemplates.clear();
        }
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      if (!preserveComparisons) {
        _entryComparisons.clear();
        _comparisonTemplates.clear();
      }
    });
    try {
      final option = _languageOption;
      final version = _activeVersion;
      final futures = _selected.map((author) async {
        final refs = _topic.references.where(
          (r) => _normalizeGospelName(r.book) == author,
        );
        final displayAuthor = _displayAuthorName(author);
        final parts = <_AuthorTextEntry>[];
        for (final ref in refs) {
          final bookId = ref.bookId.isNotEmpty ? ref.bookId : ref.book;
          final url =
              "$apiBaseUrl/get_verse"
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
          final verseLines = _normalizeVerseLinesForDisplay(
            _parseVerseLinesFromJson(verses),
            language: option,
            withDiacritics: _withDiacritics,
          );
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
              : _combineBookAndReference(
                  displayAuthor,
                  refLabel,
                  direction,
                  isArabic: option.code == 'arabic',
                );
          parts.add(
            _AuthorTextEntry(
              reference: ref,
              title: title,
              text: text,
              verses: verseLines,
              displayAuthor: displayAuthor,
            ),
          );
        }
        return MapEntry(author, parts);
      });

      final results = await Future.wait(futures);
      setState(() {
        _texts = Map.fromEntries(results);
        _loading = false;
      });
      if (_comparisonTemplates.isNotEmpty) {
        _syncComparisonTemplatesToVisibleReferences(reloadMissing: true);
      }
    } catch (e) {
      setState(() {
        _error = "Failed to fetch: $e";
        _loading = false;
      });
    }
  }

  void _showTopicComparisonPicker() {
    final references = _visibleReferences;
    if (references.isEmpty) {
      return;
    }
    _showTopicMultiComparisonPicker(references);
  }

  Future<void> _changeMainTranslation(
    LanguageOption language,
    String version,
  ) async {
    final sanitizedVersion = _sanitizeVersionForLanguage(language, version);
    final forceArabicWithoutDiacritics = language.code == 'arabic';
    final nextVersion = forceArabicWithoutDiacritics
        ? (_resolveArabicVersion(
                language,
                withDiacritics: false,
                preferredVersion: sanitizedVersion,
              ) ??
              sanitizedVersion)
        : sanitizedVersion;
    await _persistLanguageVersion(
      language,
      nextVersion,
      withDiacritics: language.code == 'arabic'
          ? !_isArabicWithoutDiacritics(nextVersion)
          : null,
    );
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushReplacementNamed(
      _topicUri(
        topic: _topic,
        language: language,
        version: nextVersion,
        topicNumber: widget.topicNumber,
        comparisonState: _encodeTopicComparisonState(),
      ).toString(),
    );
  }

  Future<void> _handleToolbarLanguageChanged(LanguageOption language) async {
    final version = await _storedVersionForLanguage(language);
    if (!mounted) {
      return;
    }
    await _changeMainTranslation(language, version);
  }

  Future<void> _handleToolbarVersionChanged(String version) async {
    await _changeMainTranslation(_languageOption, version);
  }

  bool get _hasPreviousTopic =>
      widget.topicIndex > 0 && widget.topicIndex < widget.topics.length;

  bool get _hasNextTopic =>
      widget.topicIndex >= 0 && widget.topicIndex < widget.topics.length - 1;

  void _navigateAdjacentTopic(int delta) {
    final nextIndex = widget.topicIndex + delta;
    if (nextIndex < 0 || nextIndex >= widget.topics.length) {
      return;
    }
    final topic = widget.topics[nextIndex];
    Navigator.of(context).pushNamed(
      _topicUri(
        topic: topic,
        language: _languageOption,
        version: _activeVersion,
        topicNumber: _topicNumberForDisplay(topic, zeroBasedIndex: nextIndex),
        comparisonState: _encodeTopicComparisonState(),
      ).toString(),
    );
  }

  Widget _buildTopicNavigationButton({
    required bool isPrevious,
    required bool enabled,
    bool compact = false,
  }) {
    final labels = _labels;
    final menuDirection = MenuLanguageScope.of(context).direction;
    final isRtl = menuDirection == TextDirection.rtl;
    final label = isPrevious ? labels.previousTopic : labels.nextTopic;
    final icon = isPrevious
        ? (isRtl ? Icons.chevron_right : Icons.chevron_left)
        : (isRtl ? Icons.chevron_left : Icons.chevron_right);
    Widget arrowIcon(double size) => Directionality(
      textDirection: TextDirection.ltr,
      child: Icon(icon, size: size),
    );
    if (compact) {
      return IconButton(
        onPressed: enabled
            ? () => _navigateAdjacentTopic(isPrevious ? -1 : 1)
            : null,
        tooltip: label,
        icon: arrowIcon(20),
      );
    }
    return OutlinedButton(
      onPressed: enabled
          ? () => _navigateAdjacentTopic(isPrevious ? -1 : 1)
          : null,
      style: _toolbarOutlinedStyle(context),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        textDirection: menuDirection,
        children: [arrowIcon(18), const SizedBox(width: 6), Text(label)],
      ),
    );
  }

  Widget _buildTopicTitleNavigation() {
    final menuDirection = MenuLanguageScope.of(context).direction;
    final isRtl = menuDirection == TextDirection.rtl;
    final title = _topicToolbarTitle;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 860;
        final titleReserve = compact ? 104.0 : 300.0;
        final availableTitleWidth = constraints.maxWidth.isFinite
            ? math.max(120.0, constraints.maxWidth - titleReserve)
            : 520.0;
        final titleMaxWidth = math.min(
          compact ? availableTitleWidth : 520.0,
          availableTitleWidth,
        );
        final previous = _buildTopicNavigationButton(
          isPrevious: true,
          enabled: _hasPreviousTopic,
          compact: compact,
        );
        final next = _buildTopicNavigationButton(
          isPrevious: false,
          enabled: _hasNextTopic,
          compact: compact,
        );
        final leftButton = isRtl ? next : previous;
        final rightButton = isRtl ? previous : next;
        return Center(
          child: Wrap(
            textDirection: TextDirection.ltr,
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: compact ? 6 : 10,
            runSpacing: 4,
            children: [
              leftButton,
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: titleMaxWidth),
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: compact ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              rightButton,
            ],
          ),
        );
      },
    );
  }

  String _entryComparisonKey(LanguageOption option, String version) {
    return '${option.code}|${version.toLowerCase()}';
  }

  _ComparisonPassage _comparisonTemplateFrom(
    _ComparisonPassage source, {
    bool includeRuntimeState = false,
  }) {
    final entry = _ComparisonPassage(
      language: source.language,
      version: _sanitizeVersionForLanguage(source.language, source.version),
      scopeMode: source.scopeMode,
      scopeStartVerse: source.scopeStartVerse,
      scopeEndVerse: source.scopeEndVerse,
      withDiacritics: source.withDiacritics,
    );
    if (includeRuntimeState) {
      entry
        ..verses = source.verses
        ..error = source.error
        ..loading = source.loading;
    }
    return entry;
  }

  String _encodeTopicComparisonState() {
    if (_comparisonTemplates.isEmpty) {
      return '';
    }
    final payload = _comparisonTemplates
        .map(
          (entry) => {
            'language': entry.language.apiLanguage,
            'version': entry.version,
            'withDiacritics': entry.withDiacritics,
          },
        )
        .toList();
    return base64Url.encode(utf8.encode(jsonEncode(payload)));
  }

  void _hydrateTopicComparisonsFromRoute() {
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
      final seen = <String>{};
      for (final item in raw) {
        if (item is! Map) {
          continue;
        }
        final mapItem = Map<String, dynamic>.from(item);
        final language = _languageOptionForApiLanguage(
          (mapItem['language'] ?? '').toString(),
        );
        if (language == null) {
          continue;
        }
        final version = _sanitizeVersionForLanguage(
          language,
          (mapItem['version'] ?? '').toString(),
        );
        final key = _entryComparisonKey(language, version);
        if (seen.contains(key)) {
          continue;
        }
        seen.add(key);
        parsed.add(
          _ComparisonPassage(
            language: language,
            version: version,
            withDiacritics: mapItem['withDiacritics'] is bool
                ? mapItem['withDiacritics'] as bool
                : language.code != 'arabic',
          ),
        );
      }
      _comparisonTemplates
        ..clear()
        ..addAll(parsed);
    } catch (_) {
      // Ignore invalid URL payloads.
    }
  }

  void _syncComparisonTemplatesToVisibleReferences({
    bool reloadMissing = false,
    bool reloadAll = false,
  }) {
    final references = _visibleReferences;
    final visibleKeys = references.map(_entryKey).toSet();
    final loads = <MapEntry<GospelReference, _ComparisonPassage>>[];

    setState(() {
      _entryComparisons.removeWhere((key, _) => !visibleKeys.contains(key));

      if (_comparisonTemplates.isEmpty) {
        _entryComparisons.clear();
        _interlinearView = false;
        return;
      }

      for (final reference in references) {
        final entryKey = _entryKey(reference);
        final existing = _entryComparisons[entryKey] ?? const [];
        final nextEntries = <_ComparisonPassage>[];

        for (final template in _comparisonTemplates) {
          final templateKey = _entryComparisonKey(
            template.language,
            template.version,
          );
          final existingIndex = existing.indexWhere(
            (entry) =>
                _entryComparisonKey(entry.language, entry.version) ==
                templateKey,
          );
          if (existingIndex == -1) {
            final created = _comparisonTemplateFrom(template);
            nextEntries.add(created);
            if (reloadMissing || reloadAll) {
              loads.add(MapEntry(reference, created));
            }
            continue;
          }

          final entry = existing[existingIndex];
          final shouldReload =
              entry.withDiacritics != template.withDiacritics ||
              entry.language.code != template.language.code ||
              entry.version != template.version;
          entry
            ..language = template.language
            ..version = template.version
            ..withDiacritics = template.withDiacritics;
          nextEntries.add(entry);
          if (reloadAll || shouldReload) {
            loads.add(MapEntry(reference, entry));
          }
        }

        if (nextEntries.isEmpty) {
          _entryComparisons.remove(entryKey);
        } else {
          _entryComparisons[entryKey] = nextEntries;
        }
      }
    });

    for (final load in loads) {
      _loadEntryComparison(load.key, load.value);
    }
  }

  void _removeComparisonTemplate(_ComparisonPassage entry) {
    final key = _entryComparisonKey(entry.language, entry.version);
    setState(() {
      _comparisonTemplates.removeWhere(
        (template) =>
            _entryComparisonKey(template.language, template.version) == key,
      );
      _entryComparisons.updateAll(
        (_, entries) => entries
            .where(
              (candidate) =>
                  _entryComparisonKey(candidate.language, candidate.version) !=
                  key,
            )
            .toList(),
      );
      _entryComparisons.removeWhere((_, entries) => entries.isEmpty);
      if (!_hasEntryComparisons) {
        _interlinearView = false;
      }
    });
  }

  void _updateComparisonTemplateDiacritics(
    _ComparisonPassage entry,
    bool withDiacritics,
  ) {
    final key = _entryComparisonKey(entry.language, entry.version);
    final loads = <MapEntry<GospelReference, _ComparisonPassage>>[];
    setState(() {
      for (final template in _comparisonTemplates) {
        if (_entryComparisonKey(template.language, template.version) == key) {
          template.withDiacritics = withDiacritics;
        }
      }
      for (final textEntry in _texts.values.expand((entries) => entries)) {
        final entryKey = _entryKey(textEntry.reference);
        for (final comparison in _entryComparisons[entryKey] ?? const []) {
          if (_entryComparisonKey(comparison.language, comparison.version) ==
              key) {
            comparison.withDiacritics = withDiacritics;
            loads.add(MapEntry(textEntry.reference, comparison));
          }
        }
      }
    });
    for (final load in loads) {
      _loadEntryComparison(load.key, load.value);
    }
  }

  void _showTopicMultiComparisonPicker(List<GospelReference> references) {
    if (_supportedLanguages.isEmpty || references.isEmpty) {
      return;
    }
    final labels = _labels;
    final mainLanguage = _languageOption;
    final mainVersion = _sanitizeVersionForLanguage(
      mainLanguage,
      _activeVersion,
    );
    LanguageOption selectedLanguage = _supportedLanguages.firstWhere(
      (option) => option.code == mainLanguage.code,
      orElse: () => _supportedLanguages.first,
    );
    String? selectedVersion;
    final selectedTemplates = _comparisonTemplates
        .map(_comparisonTemplateFrom)
        .toList();
    final versionFocusNode = FocusNode();

    List<_VersionChoice> buildChoices(LanguageOption language) {
      final choices = <String, _VersionChoice>{};
      for (final version in _selectableVersions(language)) {
        final sanitized = _sanitizeVersionForLanguage(language, version.id);
        if (_isSameTranslation(
          language,
          sanitized,
          mainLanguage,
          mainVersion,
        )) {
          continue;
        }
        choices[_versionIdentityKey(language, sanitized)] = _VersionChoice(
          version: sanitized,
          label: version.label,
        );
      }
      final ordered = choices.values.toList()
        ..sort((a, b) => a.label.compareTo(b.label));
      return ordered;
    }

    bool isSelected(LanguageOption language, String version) {
      final key = _entryComparisonKey(
        language,
        _sanitizeVersionForLanguage(language, version),
      );
      return selectedTemplates.any(
        (entry) => _entryComparisonKey(entry.language, entry.version) == key,
      );
    }

    void addSelectedTemplate(LanguageOption language, String version) {
      final sanitized = _sanitizeVersionForLanguage(language, version);
      if (sanitized.isEmpty ||
          _isSameTranslation(language, sanitized, mainLanguage, mainVersion) ||
          isSelected(language, sanitized)) {
        return;
      }
      selectedTemplates.add(
        _ComparisonPassage(
          language: language,
          version: sanitized,
          withDiacritics: language.code != 'arabic',
        ),
      );
    }

    void moveSelectedTemplate(int index, int delta) {
      final target = index + delta;
      if (target < 0 || target >= selectedTemplates.length) {
        return;
      }
      final item = selectedTemplates.removeAt(index);
      selectedTemplates.insert(target, item);
    }

    Widget buildSelectedTemplateChip(
      BuildContext context,
      StateSetter setModalState,
      int index,
    ) {
      final entry = selectedTemplates[index];
      final versionLabel = _versionLabel(entry.language.code, entry.version);
      final label = '${entry.language.label} · $versionLabel';
      return Container(
        padding: const EdgeInsetsDirectional.only(start: 10, end: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label),
            IconButton(
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              onPressed: index == 0
                  ? null
                  : () => setModalState(() {
                      moveSelectedTemplate(index, -1);
                    }),
              icon: const Icon(Icons.arrow_upward),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              onPressed: index == selectedTemplates.length - 1
                  ? null
                  : () => setModalState(() {
                      moveSelectedTemplate(index, 1);
                    }),
              icon: const Icon(Icons.arrow_downward),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              tooltip: labels.removeComparison,
              onPressed: () => setModalState(() {
                selectedTemplates.removeAt(index);
              }),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      );
    }

    showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: math.min(760, MediaQuery.of(context).size.width * 0.92),
              maxHeight: MediaQuery.of(context).size.height * 0.72,
            ),
            child: StatefulBuilder(
              builder: (context, setModalState) {
                final choices = buildChoices(selectedLanguage);
                final currentDropdownValue =
                    selectedVersion != null &&
                        choices.any(
                          (choice) => choice.version == selectedVersion,
                        )
                    ? selectedVersion
                    : null;

                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.max,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        labels.selectTranslationToAdd,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<LanguageOption>(
                        key: ValueKey(
                          'topic-add-language-${selectedLanguage.code}',
                        ),
                        initialValue: selectedLanguage,
                        decoration: InputDecoration(labelText: labels.language),
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
                          final nextChoices = buildChoices(value);
                          setModalState(() {
                            selectedLanguage = value;
                            selectedVersion = null;
                            if (nextChoices.length == 1) {
                              addSelectedTemplate(
                                value,
                                nextChoices.first.version,
                              );
                            }
                          });
                          if (nextChoices.length > 1) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              versionFocusNode.requestFocus();
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        key: ValueKey(
                          'topic-add-version-${selectedLanguage.code}-$currentDropdownValue-${choices.length}',
                        ),
                        focusNode: versionFocusNode,
                        initialValue: currentDropdownValue,
                        decoration: InputDecoration(
                          labelText:
                              '${labels.selectVersions} (${selectedLanguage.label})',
                        ),
                        hint: Text(labels.selectVersion),
                        items: choices
                            .map(
                              (choice) => DropdownMenuItem(
                                value: choice.version,
                                child: Text(choice.label),
                              ),
                            )
                            .toList(),
                        onChanged: choices.isEmpty
                            ? null
                            : (value) {
                                if (value == null) return;
                                setModalState(() {
                                  selectedVersion = value;
                                  addSelectedTemplate(selectedLanguage, value);
                                });
                              },
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: SingleChildScrollView(
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: labels.selected,
                            ),
                            child: selectedTemplates.isEmpty
                                ? Text(
                                    labels.selectVersions,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                  )
                                : Wrap(
                                    textDirection: MenuLanguageScope.of(
                                      context,
                                    ).direction,
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      for (
                                        var index = 0;
                                        index < selectedTemplates.length;
                                        index++
                                      )
                                        buildSelectedTemplateChip(
                                          context,
                                          setModalState,
                                          index,
                                        ),
                                    ],
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
                              _comparisonTemplates
                                ..clear()
                                ..addAll(
                                  selectedTemplates.map(
                                    _comparisonTemplateFrom,
                                  ),
                                );
                              _syncComparisonTemplatesToVisibleReferences(
                                reloadMissing: true,
                              );
                            },
                            child: Text(labels.done),
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
    ).whenComplete(versionFocusNode.dispose);
  }

  Future<void> _loadEntryComparison(
    GospelReference reference,
    _ComparisonPassage entry,
  ) async {
    final bookParam = reference.bookId.trim().isNotEmpty
        ? reference.bookId.trim()
        : reference.book.trim();
    if (reference.chapter <= 0 || bookParam.isEmpty) {
      setState(() {
        entry.error =
            'This reference is missing details needed to load the text.';
      });
      return;
    }
    final verseParam = reference.verses.trim().isEmpty
        ? '1'
        : reference.verses.trim();

    setState(() {
      entry.loading = true;
      entry.error = null;
      entry.verses = const [];
    });

    try {
      final uri = Uri.parse('$apiBaseUrl/get_verse').replace(
        queryParameters: {
          'language': entry.language.apiLanguage,
          'version': _comparisonVersionFor(
            entry.language,
            entry.version,
            withDiacritics: entry.withDiacritics,
          ),
          'book': bookParam,
          'chapter': reference.chapter.toString(),
          'verse': verseParam,
        },
      );
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        throw Exception('Error ${response.statusCode}');
      }
      final verses = _normalizeVerseLinesForDisplay(
        _parseVerseLines(response.body),
        language: entry.language,
        withDiacritics: entry.withDiacritics,
      );
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

  void _removeEntryComparison(
    GospelReference reference,
    _ComparisonPassage entry,
  ) {
    _removeComparisonTemplate(entry);
  }

  void _toggleEntryComparisonDiacritics(
    GospelReference reference,
    _ComparisonPassage entry,
  ) {
    if (entry.language.code != 'arabic') {
      return;
    }
    _updateComparisonTemplateDiacritics(entry, !entry.withDiacritics);
  }

  Widget _buildEntryComparisonDiacriticsToggle(
    GospelReference reference,
    _ComparisonPassage entry,
  ) {
    if (entry.language.code != 'arabic') {
      return const SizedBox.shrink();
    }
    return _compactDiacriticsButton(
      context: context,
      withDiacritics: entry.withDiacritics,
      labels: _labels,
      onPressed: () => _toggleEntryComparisonDiacritics(reference, entry),
    );
  }

  Widget _buildEntryComparisonCard(
    GospelReference reference,
    _ComparisonPassage entry,
    ThemeData theme,
  ) {
    final resolvedVersion = entry.language.code == 'arabic'
        ? _comparisonVersionFor(
            entry.language,
            entry.version,
            withDiacritics: entry.withDiacritics,
          )
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
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (entry.language.code == 'arabic')
                    _buildEntryComparisonDiacriticsToggle(reference, entry),
                  IconButton(
                    onPressed: () => _removeEntryComparison(reference, entry),
                    icon: const Icon(Icons.close),
                    tooltip: _labels.removeComparison,
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
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ] else if (entry.verses.isEmpty) ...[
                const SizedBox(height: 8),
                Text(_labels.noPassageText, style: theme.textTheme.bodyMedium),
              ] else ...[
                const SizedBox(height: 8),
                ...entry.verses.map(
                  (verse) => _buildComparisonVerse(verse, theme),
                ),
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
              TextSpan(
                text:
                    '${formatVerseMarker(verse.number!, language: _languageOption.apiLanguage, version: _activeVersion)}. ',
                style: numberStyle,
              ),
            TextSpan(text: verse.text),
          ],
        ),
      ),
    );
  }

  void _toggleInterlinearView() {
    setState(() {
      _interlinearView = !_interlinearView;
    });
  }

  void _setTextScale(double value) {
    final next = value.clamp(_minTextScale, _maxTextScale).toDouble();
    ZoomController.instance.update(next);
    setState(() {
      _textScale = next;
    });
  }

  Widget _buildZoomControl() => _buildToolbarZoomButton(
    context: context,
    menuLanguage: MenuLanguageScope.of(context),
    value: _textScale,
    onSelected: _setTextScale,
  );

  Widget _wrapWithTextScale(BuildContext context, Widget child) {
    final mediaQuery = MediaQuery.of(context);
    return MediaQuery(
      data: mediaQuery.copyWith(textScaler: TextScaler.linear(_textScale)),
      child: child,
    );
  }

  Widget _buildInterlinearToggleButton() {
    return OutlinedButton.icon(
      onPressed: _hasEntryComparisons ? _toggleInterlinearView : null,
      style: _toolbarOutlinedStyle(context),
      icon: Icon(
        _interlinearView ? Icons.view_agenda : Icons.view_agenda_outlined,
      ),
      label: Text(_labels.interlinearView),
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
          ? _comparisonVersionFor(
              comparison.language,
              comparison.version,
              withDiacritics: comparison.withDiacritics,
            )
          : comparison.version;
      final versionLabel = _versionLabel(
        comparison.language.code,
        resolvedVersion,
      );
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
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          const SizedBox(height: 8),
        ]);
        continue;
      }
      if (comparison.verses.isEmpty) {
        statusWidgets.addAll([
          Text(
            '$label: ${_labels.noPassageText}',
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
      return Text(_labels.noPassageText, style: theme.textTheme.bodyMedium);
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

  Widget _buildAuthorEntryBlock(
    _AuthorTextEntry entry,
    ThemeData theme,
    LanguageOption option,
  ) {
    final headingStyle = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w600,
    );
    final referenceLabel = entry.reference.formattedReference.trim();
    final heading = referenceLabel.isEmpty
        ? Text(entry.title, style: headingStyle)
        : ReferenceHoverText(
            key: ValueKey(
              [
                option.apiLanguage,
                _activeVersion,
                _topic.id,
                entry.reference.bookId,
                entry.reference.book,
                entry.reference.chapter,
                entry.reference.verses,
              ].join('|'),
            ),
            reference: entry.reference,
            textStyle: headingStyle,
            textAlign: TextAlign.start,
            textDirection: option.direction,
            topicName: _topic.name,
            topicId: _topic.id.isNotEmpty ? _topic.id : _topic.name,
            sourceContext: 'harmony',
            gospel: _normalizeGospelName(entry.reference.book),
            language: option.apiLanguage,
            version: _activeVersion,
            tooltipMessage: _labels.clickToReadInChapter,
            labelOverride: entry.title,
            enableHoverPreview: false,
          );
    final comparisons =
        _entryComparisons[_entryKey(entry.reference)] ??
        const <_ComparisonPassage>[];

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          heading,
          const SizedBox(height: 6),
          if (_interlinearView)
            _buildEntryInterlinearSection(entry, comparisons, theme)
          else ...[
            Text(entry.text),
            if (comparisons.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...comparisons.map(
                (comparison) => _buildEntryComparisonCard(
                  entry.reference,
                  comparison,
                  theme,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildAuthorGroupPanel(
    String author,
    ThemeData theme,
    LanguageOption option,
  ) {
    final entries = _texts[author] ?? const <_AuthorTextEntry>[];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final entry in entries)
              _buildAuthorEntryBlock(entry, theme, option),
          ],
        ),
      ),
    );
  }

  Widget _buildTopicContent(BuildContext context, LanguageOption option) {
    final theme = Theme.of(context);
    final selectedSorted = _selected.toList()..sort(_compareBooks);
    final visibleAuthors = selectedSorted
        .where((author) => (_texts[author]?.isNotEmpty ?? false))
        .toList();

    if (visibleAuthors.isEmpty) {
      return Center(child: Text(_labels.noPassageText));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.of(context).size.width;
        final horizontalPadding = availableWidth >= 1000 ? 24.0 : 12.0;
        final innerWidth = math.max(
          0.0,
          availableWidth - (horizontalPadding * 2),
        );
        final count = visibleAuthors.length;
        final spacing = innerWidth >= 760 ? 14.0 : 10.0;
        final columns = innerWidth < 720 || count == 1
            ? 1
            : (count == 4 && innerWidth < 1120 ? 2 : count);
        final maxPanelWidth = switch (count) {
          1 => 720.0,
          2 => 560.0,
          3 => 440.0,
          _ => innerWidth,
        };
        final idealWidth =
            (math.min(maxPanelWidth, innerWidth) * columns) +
            (spacing * (columns - 1));
        final contentWidth = count >= 4
            ? innerWidth
            : math.min(innerWidth, idealWidth);
        final itemWidth = columns == 1
            ? math.min(contentWidth, maxPanelWidth)
            : (contentWidth - (spacing * (columns - 1))) / columns;

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            10,
            horizontalPadding,
            28,
          ),
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: contentWidth,
              child: Wrap(
                alignment: WrapAlignment.center,
                runAlignment: WrapAlignment.center,
                spacing: spacing,
                runSpacing: spacing,
                textDirection: option.direction,
                children: [
                  for (final author in visibleAuthors)
                    SizedBox(
                      width: itemWidth,
                      child: _buildAuthorGroupPanel(author, theme, option),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final option = _languageOption;
    final menuLanguage = MenuLanguageScope.of(context);
    return Directionality(
      textDirection: menuLanguage.direction,
      child: MainScaffold(
        title: '',
        topNavigation: _buildGlobalTopNavigation(
          context: context,
          contentLanguage: option,
          contentVersion: _activeVersion,
          showBackToMainTable: true,
        ),
        settingsLabel: menuLanguage.ui.settings,
        logoutLabel: menuLanguage.ui.logout,
        accountTooltip: menuLanguage.ui.account,
        body: Column(
          children: [
            AppToolbar(
              titleWidget: _buildTopicTitleNavigation(),
              language: option,
              version: _activeVersion,
              languages: _supportedLanguages,
              languagesLoading: _languagesLoading,
              onLanguageChanged: _handleToolbarLanguageChanged,
              onVersionChanged: _handleToolbarVersionChanged,
              onTranslationChanged: _changeMainTranslation,
              primaryActions: [
                FilledButton.icon(
                  onPressed: (_visibleReferences.isEmpty || _loading)
                      ? null
                      : _showTopicComparisonPicker,
                  style: _toolbarFilledStyle(context),
                  icon: const Icon(Icons.library_add, size: 18),
                  label: Text(_labels.addTranslation),
                ),
                _buildInterlinearToggleButton(),
                _buildZoomControl(),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  ..._allAuthors.map(
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
                        fetchTexts(preserveComparisons: true);
                      },
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 0),
            Expanded(
              child: Directionality(
                textDirection: option.direction,
                child: _selected.isEmpty
                    ? Center(child: Text(_labels.comparePrompt))
                    : _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                    ? Center(child: Text(_error!))
                    : _wrapWithTextScale(
                        context,
                        _buildTopicContent(context, option),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
