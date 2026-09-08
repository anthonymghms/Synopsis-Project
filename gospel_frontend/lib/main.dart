import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gospel_frontend/auth_screen.dart';
import 'package:gospel_frontend/main_scaffold.dart';
import 'package:gospel_frontend/browser_find_text.dart';
import 'package:gospel_frontend/browser_route_link.dart';
import 'package:gospel_frontend/profile_setup_screen.dart';
import 'package:gospel_frontend/user_profile.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:gospel_frontend/utils/format_verse_ref.dart';
import 'package:gospel_frontend/widgets/verse_ref_text.dart';
import 'package:gospel_frontend/gospel_filter.dart';
import 'package:gospel_frontend/admin_portal.dart';
import 'package:gospel_frontend/catalog_events.dart';
import 'package:gospel_frontend/admin_access.dart';
import 'package:gospel_frontend/reference_model.dart';
import 'package:gospel_frontend/topic_language_catalog.dart';

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
const double _maxPageContentWidth = 1180.0;
const double _maxReadingContentWidth = 860.0;
const double _minHarmonyTableWidth = 760.0;
const double _maxHarmonyTableWidth = 1120.0;

double _responsiveHorizontalInset(double availableWidth) {
  if (availableWidth < 640) {
    return 14.0;
  }
  if (availableWidth < 1000) {
    return 18.0;
  }
  return 24.0;
}

double _responsiveContentWidth(
  double availableWidth, {
  required double maxWidth,
  double mediumScreenFraction = 0.96,
  double largeScreenFraction = 0.92,
}) {
  if (!availableWidth.isFinite || availableWidth <= 0) {
    return maxWidth;
  }
  if (availableWidth < 640) {
    return availableWidth;
  }
  if (availableWidth < 1000) {
    return math.min(availableWidth * mediumScreenFraction, maxWidth);
  }
  return math.min(availableWidth * largeScreenFraction, maxWidth);
}

class ResponsiveContentShell extends StatelessWidget {
  const ResponsiveContentShell({
    super.key,
    required this.child,
    this.maxWidth = _maxPageContentWidth,
    this.padding,
    this.alignment = Alignment.topCenter,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final resolvedPadding =
            padding ??
            EdgeInsets.symmetric(
              horizontal: _responsiveHorizontalInset(availableWidth),
            );
        final contentWidth = _responsiveContentWidth(
          availableWidth,
          maxWidth: maxWidth,
        );

        return Padding(
          padding: resolvedPadding,
          child: Align(
            alignment: alignment,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: contentWidth),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

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

class TopicLanguageSelectionController {
  TopicLanguageSelectionController._();

  static final TopicLanguageSelectionController instance =
      TopicLanguageSelectionController._();

  final ValueNotifier<String> _languageCode = ValueNotifier<String>(
    defaultLanguage,
  );
  SharedPreferences? _prefs;
  bool _initialized = false;

  ValueListenable<String> get listenable => _languageCode;
  String get languageCode => _languageCode.value;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _prefs = prefs;
      final stored = prefs.getString('selected_topic_language_code');
      if (stored != null && stored.trim().isNotEmpty) {
        _languageCode.value = stored.trim().toLowerCase();
      }
    } catch (_) {
      // A persisted preference is optional; profiles and defaults still work.
    } finally {
      _initialized = true;
    }
  }

  void update(String code) {
    final normalized = code.trim().toLowerCase();
    if (normalized.isEmpty) return;
    if (normalized != _languageCode.value) {
      _languageCode.value = normalized;
      _prefs?.setString('selected_topic_language_code', normalized);
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
      _languageCode.value = fallback?.isNotEmpty == true
          ? fallback!.toLowerCase()
          : (stored?.trim().isNotEmpty == true
                ? stored!.trim().toLowerCase()
                : defaultLanguage);
      if (fallback?.isNotEmpty == true) {
        await prefs.setString(
          'selected_menu_language_code',
          _languageCode.value,
        );
      }
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
    final normalized = code.trim().toLowerCase();
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

class PrimaryLanguageController {
  PrimaryLanguageController._();

  static final PrimaryLanguageController instance =
      PrimaryLanguageController._();

  String get languageCode =>
      LanguageSelectionController.instance.languageCode.toLowerCase();

  void select(String code) {
    final requested = code.trim().toLowerCase();
    if (requested.isEmpty) {
      return;
    }
    final normalized = _coercePrimaryLanguageOption(
      _languageOptionForCode(requested),
    ).code.toLowerCase();
    LanguageSelectionController.instance.update(normalized);
    TopicLanguageSelectionController.instance.update(normalized);
    MenuLanguageController.instance.update(normalized);
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
    final profileController = UserProfileController.instance;
    if (profileController.profile != null) {
      unawaited(
        _updateUserPreferencesBestEffort(
          profileController.preferences.copyWith(zoomLevel: next),
        ),
      );
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
  final String columns;
  final String showColumns;
  final String sort;
  final String sortBy;
  final String defaultSort;
  final String chronology;
  final String visibleColumns;
  final String resetColumns;
  final String filter;
  final String operation;
  final String union;
  final String intersection;
  final String includeGospels;
  final String exclude;
  final String currentFilter;
  final String finalResult;
  final String topics;
  final String references;
  final String atLeastOneColumnVisible;
  final String filterUpdatesLive;
  final String gospelCombinations;
  final String searchFilters;
  final String included;
  final String excluded;
  final String unrestricted;
  final String fourIncludedGospels;
  final String threeIncludedGospels;
  final String twoIncludedGospels;
  final String oneIncludedGospel;
  final String noExcludedGospels;
  final String oneExcludedGospel;
  final String twoExcludedGospels;
  final String threeExcludedGospels;
  final String applyFilter;
  final String noMatchingFilterCombinations;
  final String clearFilter;
  final String allTopics;
  final String results;
  final String language;
  final String version;
  final String bibleLanguage;
  final String translation;
  final String changeTopicLanguage;
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
    required this.columns,
    required this.showColumns,
    required this.sort,
    required this.sortBy,
    required this.defaultSort,
    required this.chronology,
    required this.visibleColumns,
    required this.resetColumns,
    required this.filter,
    required this.operation,
    required this.union,
    required this.intersection,
    required this.includeGospels,
    required this.exclude,
    required this.currentFilter,
    required this.finalResult,
    required this.topics,
    required this.references,
    required this.atLeastOneColumnVisible,
    required this.filterUpdatesLive,
    required this.gospelCombinations,
    required this.searchFilters,
    required this.included,
    required this.excluded,
    required this.unrestricted,
    required this.fourIncludedGospels,
    required this.threeIncludedGospels,
    required this.twoIncludedGospels,
    required this.oneIncludedGospel,
    required this.noExcludedGospels,
    required this.oneExcludedGospel,
    required this.twoExcludedGospels,
    required this.threeExcludedGospels,
    required this.applyFilter,
    required this.noMatchingFilterCombinations,
    required this.clearFilter,
    required this.allTopics,
    required this.results,
    required this.language,
    required this.version,
    required this.bibleLanguage,
    required this.translation,
    required this.changeTopicLanguage,
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
  final List<String> localizedGospelNames;

  const LanguageOption({
    required this.code,
    required this.label,
    required this.apiLanguage,
    required this.apiVersion,
    required this.versionLabel,
    required this.direction,
    required this.ui,
    required this.versions,
    this.localizedGospelNames = const <String>[],
  });

  String get title => ui.title;
  String get description => ui.description;
  String get downloadLabel => ui.downloadPdf;
  String get resetLabel => ui.resetTable;
  String get pdfUnavailableMessage => ui.pdfUnavailableMessage;
  String get subjectsHeader => ui.subjectsHeader;
  List<String> get gospelHeaders => localizedGospelNames.length == 4
      ? localizedGospelNames
      : ui.gospelHeaders;
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
    List<String>? localizedGospelNames,
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
      localizedGospelNames: localizedGospelNames ?? this.localizedGospelNames,
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
      columns: 'Columns',
      showColumns: 'Show columns',
      sort: 'Sort & Columns',
      sortBy: 'Sort by',
      defaultSort: 'Default',
      chronology: 'chronology',
      visibleColumns: 'Visible columns',
      resetColumns: 'Reset columns',
      filter: 'Filter',
      operation: 'Operation',
      union: 'Union',
      intersection: 'Intersection',
      includeGospels: 'Include Gospels',
      exclude: 'Exclude',
      currentFilter: 'Current filter',
      finalResult: 'Final',
      topics: 'topics',
      references: 'references',
      atLeastOneColumnVisible:
          'At least one Gospel column must remain visible.',
      filterUpdatesLive: 'The table and topic counts update as you choose.',
      gospelCombinations: 'Gospel combinations',
      searchFilters: 'Search filters',
      included: 'Included',
      excluded: 'Excluded',
      unrestricted: 'Any',
      fourIncludedGospels: 'Four included',
      threeIncludedGospels: 'Three included',
      twoIncludedGospels: 'Two included',
      oneIncludedGospel: 'One included',
      noExcludedGospels: 'No excluded Gospels',
      oneExcludedGospel: 'One excluded Gospel',
      twoExcludedGospels: 'Two excluded Gospels',
      threeExcludedGospels: 'Three excluded Gospels',
      applyFilter: 'Apply filter',
      noMatchingFilterCombinations: 'No matching filter combinations',
      clearFilter: 'Clear filter',
      allTopics: 'All topics',
      results: 'results',
      language: 'Language',
      version: 'Version',
      bibleLanguage: 'Language',
      translation: 'Translation',
      changeTopicLanguage: 'Change topic language',
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
      columns: 'الأعمدة',
      showColumns: 'إظهار الأعمدة',
      sort: 'الترتيب والأعمدة',
      sortBy: 'الترتيب بحسب',
      defaultSort: 'التنسيق العام',
      chronology: 'إنجيل',
      visibleColumns: 'الأعمدة الظاهرة',
      resetColumns: 'إعادة إظهار الأعمدة',
      filter: 'تصفية',
      operation: 'العملية',
      union: 'اتحاد',
      intersection: 'تقاطع',
      includeGospels: 'الأناجيل المشمولة',
      exclude: 'استبعاد',
      currentFilter: 'التصفية الحالية',
      finalResult: 'النتيجة النهائية',
      topics: 'موضوعًا',
      references: 'مرجعًا',
      atLeastOneColumnVisible: 'يجب إبقاء عمود إنجيل واحد ظاهرًا على الأقل.',
      filterUpdatesLive: 'يتحدث الجدول وعدد المواضيع مع كل اختيار.',
      gospelCombinations: 'تركيبات الأناجيل',
      searchFilters: 'البحث في التصفيات',
      included: 'مشمولة',
      excluded: 'مستبعدة',
      unrestricted: 'غير مقيّد',
      fourIncludedGospels: 'أربعة أناجيل مشمولة',
      threeIncludedGospels: 'ثلاثة أناجيل مشمولة',
      twoIncludedGospels: 'إنجيلان مشمولان',
      oneIncludedGospel: 'إنجيل واحد مشمول',
      noExcludedGospels: 'لا توجد أناجيل مستبعدة',
      oneExcludedGospel: 'إنجيل واحد مستبعد',
      twoExcludedGospels: 'إنجيلان مستبعدان',
      threeExcludedGospels: 'ثلاثة أناجيل مستبعدة',
      applyFilter: 'تطبيق التصفية',
      noMatchingFilterCombinations: 'لا توجد تصفيات مطابقة',
      clearFilter: 'إزالة التصفية',
      allTopics: 'كل المواضيع',
      results: 'نتيجة',
      language: 'اللغة',
      version: 'الترجمة',
      bibleLanguage: 'اللغة',
      translation: 'الترجمة',
      changeTopicLanguage: 'تغيير لغة المواضيع',
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
      chapter: 'الفصل',
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

List<TopicLanguageOption> _supportedTopicLanguages =
    List<TopicLanguageOption>.from(bundledTopicLanguages);
Future<List<TopicLanguageOption>>? _topicLanguageOptionsLoadFuture;

@visibleForTesting
List<LanguageOption> primaryLanguageOptionsFor({
  required Iterable<LanguageOption> bibleLanguages,
  required Iterable<TopicLanguageOption> topicLanguages,
}) {
  final uiLanguageCodes = kBaseLanguageOptions
      .map((option) => option.code.toLowerCase())
      .toSet();
  final bundledTopicCodes = bundledTopicLanguages
      .map((option) => option.code.toLowerCase())
      .toSet();
  final completeTopicCodes = topicLanguages
      .where(
        (option) =>
            option.complete ||
            bundledTopicCodes.contains(option.code.toLowerCase()),
      )
      .map((option) => option.code.toLowerCase())
      .toSet();

  return bibleLanguages
      .where(
        (option) =>
            uiLanguageCodes.contains(option.code.toLowerCase()) &&
            completeTopicCodes.contains(option.code.toLowerCase()) &&
            option.versions.isNotEmpty,
      )
      .toList(growable: false);
}

List<LanguageOption> _primaryLanguageOptions() {
  final options = primaryLanguageOptionsFor(
    bibleLanguages: _supportedLanguages,
    topicLanguages: _supportedTopicLanguages,
  );
  if (options.isNotEmpty) {
    return options;
  }
  return <LanguageOption>[
    kBaseLanguageOptions.firstWhere(
      (option) => option.code == defaultLanguage,
      orElse: () => kBaseLanguageOptions.first,
    ),
  ];
}

LanguageOption _coercePrimaryLanguageOption(LanguageOption option) {
  final primary = _primaryLanguageOptions();
  return primary.firstWhere(
    (candidate) => candidate.code == option.code,
    orElse: () => primary.firstWhere(
      (candidate) => candidate.code == defaultLanguage,
      orElse: () => primary.first,
    ),
  );
}

Future<List<TopicLanguageOption>> _loadTopicLanguages() {
  final cached = _topicLanguageOptionsLoadFuture;
  if (cached != null) return cached;
  final future = TopicLanguageCatalog(baseUrl: apiBaseUrl).load();
  _topicLanguageOptionsLoadFuture = future;
  return future
      .then((options) {
        final merged = List<TopicLanguageOption>.from(options);
        for (final bundled in bundledTopicLanguages) {
          if (!merged.any((option) => option.code == bundled.code)) {
            merged.add(bundled);
          }
        }
        _supportedTopicLanguages = merged;
        return merged;
      })
      .catchError((Object error) {
        if (identical(_topicLanguageOptionsLoadFuture, future)) {
          _topicLanguageOptionsLoadFuture = null;
        }
        throw error;
      });
}

TopicLanguageOption _topicLanguageOptionForCode(String code) =>
    TopicLanguageCatalog.resolve(_supportedTopicLanguages, code);

Future<List<LanguageOption>>? _languageOptionsLoadFuture;

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
  final sanitizedVersions = versions;
  final apiVersion = sanitizedVersions.isNotEmpty
      ? sanitizedVersions.first.id
      : '';
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
  final docRef = FirebaseFirestore.instance
      .collection('bibles')
      .doc(languageId);
  final Set<String> versionIds = {};
  final Map<String, String> versionLabels = <String, String>{};

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
      final explicitLabel =
          versionData['label']?.toString().trim() ??
          versionData['name']?.toString().trim() ??
          '';
      if (id.isNotEmpty && explicitLabel.isNotEmpty) {
        versionLabels[id] = explicitLabel;
      }
      _collectVersionIdsFromData(versionData, versionIds);
    }
  } catch (_) {
    // The collection may not exist or security rules may block listing.
  }

  final versions = versionIds
      .map(
        (id) => BibleVersion(
          id: id,
          label: versionLabels[id] ?? _versionLabel(languageId, id),
        ),
      )
      .toList();
  versions.sort(
    (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
  );
  return versions;
}

Future<List<LanguageOption>> _loadLanguagesFromFirestore() async {
  final cached = _languageOptionsLoadFuture;
  if (cached != null) {
    return cached;
  }

  final future = _loadLanguagesFromFirestoreUncached();
  _languageOptionsLoadFuture = future;
  try {
    return await future;
  } catch (_) {
    if (identical(_languageOptionsLoadFuture, future)) {
      _languageOptionsLoadFuture = null;
    }
    rethrow;
  }
}

Future<List<LanguageOption>> _loadLanguagesFromFirestoreUncached() async {
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
    final rawGospels = data['gospels'];
    final localizedGospelNames = rawGospels is Map
        ? <String>[
            for (final gospel in orderedGospels)
              rawGospels[gospel]?.toString().trim() ?? '',
          ]
        : const <String>[];
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
        localizedGospelNames:
            localizedGospelNames.length == 4 &&
                localizedGospelNames.every((name) => name.isNotEmpty)
            ? localizedGospelNames
            : template.localizedGospelNames,
      ),
    );
  }

  for (final bundled in kBaseLanguageOptions) {
    if (!options.any((option) => option.code == bundled.code)) {
      options.add(bundled);
    }
  }

  options.sort((a, b) {
    final aBase = kBaseLanguageOptions.indexWhere(
      (option) => option.code == a.code,
    );
    final bBase = kBaseLanguageOptions.indexWhere(
      (option) => option.code == b.code,
    );
    final aOrder = aBase < 0 ? kBaseLanguageOptions.length : aBase;
    final bOrder = bBase < 0 ? kBaseLanguageOptions.length : bBase;
    if (aOrder != bOrder) return aOrder.compareTo(bOrder);
    return a.label.toLowerCase().compareTo(b.label.toLowerCase());
  });

  return options.isNotEmpty ? options : kBaseLanguageOptions;
}

LanguageOption _languageOptionForCode(String code) {
  final normalized = code.trim().toLowerCase();
  LanguageOption fallback() {
    return _supportedLanguages.firstWhere(
      (option) => option.code.toLowerCase() == defaultLanguage,
      orElse: () => _supportedLanguages.first,
    );
  }

  return _supportedLanguages.firstWhere(
    (option) => option.code.toLowerCase() == normalized,
    orElse: fallback,
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
    final primary = _coercePrimaryLanguageOption(_languageOptionForCode(code));
    TopicLanguageOption? topicLanguage;
    for (final candidate in _supportedTopicLanguages) {
      if (candidate.code.toLowerCase() == primary.code.toLowerCase()) {
        topicLanguage = candidate;
        break;
      }
    }
    if (topicLanguage == null) {
      return primary;
    }
    return primary.copyWith(
      label: topicLanguage.label,
      direction: topicLanguage.direction,
      localizedGospelNames: topicLanguage.gospelNames,
    );
  }
}

const List<String> _menuLanguageQueryKeys = [
  'menuLanguage',
  'menu_language',
  'uiLanguage',
  'ui_language',
  'locale',
];

String? _menuLanguageQueryParameter(Uri uri) {
  for (final key in _menuLanguageQueryKeys) {
    final value = uri.queryParameters[key]?.trim();
    if (value != null && value.isNotEmpty) {
      return value;
    }
  }
  return null;
}

@visibleForTesting
String? primaryLanguageQueryParameter(Uri uri) {
  for (final key in <String>['bibleLanguage', 'language', 'topicLanguage']) {
    final value = uri.queryParameters[key]?.trim();
    if (value != null && value.isNotEmpty) {
      return value;
    }
  }
  return _menuLanguageQueryParameter(uri);
}

void _syncSelectedContentLanguage(LanguageOption option) {
  final nextCode = _coercePrimaryLanguageOption(
    option,
  ).code.trim().toLowerCase();
  if (nextCode.isEmpty) {
    return;
  }
  PrimaryLanguageController.instance.select(nextCode);
}

Uri _mainTableUri({
  required LanguageOption language,
  required String version,
  GospelFilterState filterState = const GospelFilterState(),
  GospelSortState sortState = const GospelSortState(),
  ColumnVisibilityState columnVisibility = const ColumnVisibilityState(),
}) {
  final queryParameters = <String, String>{
    'menuLanguage': language.code,
    'topicLanguage': language.code,
    'bibleLanguage': language.apiLanguage,
    'language': language.apiLanguage,
    'version': _sanitizeVersionForLanguage(language, version),
    ...harmonyViewQueryParameters(
      filter: filterState,
      sort: sortState,
      columns: columnVisibility,
    ),
  };
  return Uri(path: '/', queryParameters: queryParameters);
}

Uri _topicUri({
  required Topic topic,
  required LanguageOption language,
  required String version,
  String topicNumber = '',
  String comparisonState = '',
}) {
  final queryParameters = {
    'menuLanguage': language.code,
    'topicLanguage': language.code,
    'bibleLanguage': language.apiLanguage,
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

BibleVersion? _findArabicVersionForBase(
  LanguageOption option,
  String baseVersion, {
  required bool withDiacritics,
}) {
  final normalizedBase = _normalizeArabicBaseVersion(baseVersion);
  if (normalizedBase.isEmpty) {
    return null;
  }

  for (final version in option.versions) {
    if (_normalizeArabicBaseVersion(version.id) != normalizedBase) {
      continue;
    }
    if (_isArabicWithoutDiacritics(version.id) == !withDiacritics) {
      return version;
    }
  }
  return null;
}

bool _canDisplayArabicDiacritics(LanguageOption option, String version) {
  if (option.code != 'arabic') {
    return false;
  }

  final preferred = version.trim().isNotEmpty
      ? version.trim()
      : option.apiVersion;
  if (preferred.isNotEmpty && !_isArabicWithoutDiacritics(preferred)) {
    return true;
  }

  return _findArabicVersionForBase(option, preferred, withDiacritics: true) !=
      null;
}

String? _resolveArabicVersion(
  LanguageOption option, {
  required bool withDiacritics,
  String? preferredVersion,
}) {
  final preferred = preferredVersion?.trim() ?? '';
  if (option.versions.isEmpty) {
    if (preferred.isNotEmpty) {
      return preferred;
    }
    return option.apiVersion.trim().isNotEmpty
        ? option.apiVersion
        : (withDiacritics
              ? arabicVersionWithDiacritics
              : arabicVersionWithoutDiacritics);
  }
  final fallbackSource = preferred.isNotEmpty ? preferred : option.apiVersion;
  final matching = _findArabicVersionForBase(
    option,
    fallbackSource,
    withDiacritics: withDiacritics,
  );
  if (matching != null) {
    return matching.id;
  }

  final preferredMatch = _versionOptionFor(option, preferred);
  if (preferredMatch != null) {
    return preferredMatch.id;
  }

  for (final version in option.versions) {
    if (_isArabicWithoutDiacritics(version.id) == !withDiacritics) {
      return version.id;
    }
  }

  final apiMatch = _versionOptionFor(option, option.apiVersion);
  return apiMatch?.id ?? option.versions.first.id;
}

String _sanitizeVersionForLanguage(LanguageOption option, String rawVersion) {
  final normalized = rawVersion.trim();

  if (option.code == 'arabic') {
    final selected = _versionOptionFor(option, normalized);
    final effectiveVersion = selected?.id ?? option.apiVersion.trim();
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

Future<bool> _loadArabicDiacriticsPreference({
  bool defaultValue = false,
}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('arabic_with_diacritics') ?? defaultValue;
  } catch (_) {
    return defaultValue;
  }
}

Future<void> _persistArabicDiacriticsPreference(bool withDiacritics) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('arabic_with_diacritics', withDiacritics);
  } catch (_) {
    // Persistence is a convenience, not a blocker for reading.
  }
  final profileController = UserProfileController.instance;
  if (profileController.profile != null) {
    try {
      await profileController.updatePreferences(
        profileController.preferences.copyWith(showDiacritics: withDiacritics),
      );
    } catch (_) {
      // The reading view remains usable if remote persistence is unavailable.
    }
  }
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

LanguageOption _resolvePrimaryLanguageOption({
  String? languageParam,
  String? versionParam,
}) {
  return _coercePrimaryLanguageOption(
    _resolveLanguageOption(
      languageParam: languageParam,
      versionParam: versionParam,
    ),
  );
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
  final index = orderedGospels.indexOf(canonical);
  if (index >= 0 && index < option.gospelHeaders.length) {
    return option.gospelHeaders[index];
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
  return formatCompositeVerseRef(reference, 'arabic').text;
}

String _compactReferenceLabel(Iterable<GospelReference> references) {
  return formatHarmonyReferenceCellDisplay(
    references.map(
      (reference) => HarmonyReferenceSegment(
        chapter: reference.chapter,
        verses: reference.verses.trim(),
        separatorBefore: ReferenceSeparator.fromSymbol(
          reference.separatorBefore,
        ),
      ),
    ),
  );
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

const Set<String> _emptyReferenceMarkers = {'', '-', '–', '—', 'null'};

bool _isReferenceValuePresent(String value) {
  final trimmed = value.trim();
  if (_emptyReferenceMarkers.contains(trimmed.toLowerCase())) {
    return false;
  }
  return true;
}

bool _referenceHasData(GospelReference reference) {
  final verses = reference.verses.trim();
  if (reference.chapter > 0) {
    return verses.isEmpty || _isReferenceValuePresent(verses);
  }
  return _isReferenceValuePresent(verses) ||
      _isReferenceValuePresent(reference.formattedReference);
}

bool hasReference(Topic topic, String gospel) {
  final canonical = Gospel.fromCanonicalName(_normalizeGospelName(gospel));
  return canonical != null && hasGospelReference(topic, canonical);
}

Set<String> getReferencedGospels(Topic topic) {
  return <String>{
    for (final gospel in Gospel.values)
      if ((topic.gospelPresenceMask & gospel.bit) != 0) gospel.canonicalName,
  };
}

int _gospelPresenceMask(Iterable<GospelReference> references) {
  var mask = 0;
  for (final reference in references) {
    if (!_referenceHasData(reference)) {
      continue;
    }
    final gospel = _canonicalGospelForReference(reference);
    if (gospel != null) {
      mask |= gospel.bit;
    }
  }
  return mask;
}

Gospel? _canonicalGospelForReference(GospelReference reference) {
  return reference.canonicalGospel ??
      Gospel.fromCanonicalName(_normalizeGospelName(reference.book));
}

bool hasGospelReference(Topic topic, Gospel gospel) {
  return topic.gospelPresenceMask & gospel.bit != 0;
}

bool matchesFilter(Topic topic, GospelFilterCombination? filter) {
  return filter?.matchesPresenceMask(topic.gospelPresenceMask) ?? true;
}

bool matchesAdvancedFilter(Topic topic, GospelFilterState filter) {
  return filter.matchesPresenceMask(topic.gospelPresenceMask);
}

class GospelChronologyAnchor implements Comparable<GospelChronologyAnchor> {
  const GospelChronologyAnchor({required this.chapter, required this.verse});

  final int chapter;
  final int verse;

  @override
  int compareTo(GospelChronologyAnchor other) {
    final chapterComparison = chapter.compareTo(other.chapter);
    return chapterComparison != 0
        ? chapterComparison
        : verse.compareTo(other.verse);
  }

  @override
  bool operator ==(Object other) {
    return other is GospelChronologyAnchor &&
        other.chapter == chapter &&
        other.verse == verse;
  }

  @override
  int get hashCode => Object.hash(chapter, verse);
}

String _normalizeReferenceDigits(String value) {
  const replacements = <String, String>{
    '٠': '0',
    '١': '1',
    '٢': '2',
    '٣': '3',
    '٤': '4',
    '٥': '5',
    '٦': '6',
    '٧': '7',
    '٨': '8',
    '٩': '9',
    '۰': '0',
    '۱': '1',
    '۲': '2',
    '۳': '3',
    '۴': '4',
    '۵': '5',
    '۶': '6',
    '۷': '7',
    '۸': '8',
    '۹': '9',
  };
  return value.split('').map((digit) => replacements[digit] ?? digit).join();
}

int _parseReferenceNumber(Object? rawValue) {
  return int.tryParse(
        _normalizeReferenceDigits(rawValue?.toString().trim() ?? ''),
      ) ??
      0;
}

GospelChronologyAnchor? _chronologyAnchorForReference(
  GospelReference reference,
) {
  if (!_referenceHasData(reference)) {
    return null;
  }
  final numbers = RegExp(r'\d+')
      .allMatches(_normalizeReferenceDigits(reference.verses))
      .map((match) => int.parse(match.group(0)!))
      .toList();
  if (reference.chapter > 0) {
    return GospelChronologyAnchor(
      chapter: reference.chapter,
      verse: numbers.isEmpty ? 0 : numbers.first,
    );
  }
  if (numbers.isEmpty) {
    return null;
  }
  return GospelChronologyAnchor(
    chapter: numbers.first,
    verse: numbers.length > 1 ? numbers[1] : 0,
  );
}

Map<Gospel, GospelChronologyAnchor> _earliestGospelAnchors(
  Iterable<GospelReference> references,
) {
  final anchors = <Gospel, GospelChronologyAnchor>{};
  for (final reference in references) {
    final gospel = _canonicalGospelForReference(reference);
    final anchor = _chronologyAnchorForReference(reference);
    if (gospel == null || anchor == null) {
      continue;
    }
    final current = anchors[gospel];
    if (current == null || anchor.compareTo(current) < 0) {
      anchors[gospel] = anchor;
    }
  }
  return Map<Gospel, GospelChronologyAnchor>.unmodifiable(anchors);
}

List<Topic> applyAdvancedFilter(
  Iterable<Topic> topics,
  GospelFilterState filter,
) {
  return <Topic>[
    for (final topic in topics)
      if (matchesAdvancedFilter(topic, filter)) topic,
  ];
}

List<Topic> removeRowsWithoutVisibleReferences(
  Iterable<Topic> topics,
  ColumnVisibilityState columns,
) {
  return <Topic>[
    for (final topic in topics)
      if (topic.gospelPresenceMask & columns.visibleMask != 0) topic,
  ];
}

List<Topic> sortTopics(
  Iterable<Topic> topics,
  GospelSortState sort, {
  Map<Topic, int>? sourceIndexes,
}) {
  final sorted = List<Topic>.from(topics);
  final stableIndexes =
      sourceIndexes ??
      <Topic, int>{
        for (var index = 0; index < sorted.length; index++)
          sorted[index]: index,
      };
  if (sort.isDefault) {
    sorted.sort((first, second) {
      final firstOrder = first.canonicalOrder;
      final secondOrder = second.canonicalOrder;
      if (firstOrder > 0 && secondOrder > 0) {
        final comparison = firstOrder.compareTo(secondOrder);
        if (comparison != 0) {
          return comparison;
        }
      } else if (firstOrder > 0 || secondOrder > 0) {
        return firstOrder > 0 ? -1 : 1;
      }
      return stableIndexes[first]!.compareTo(stableIndexes[second]!);
    });
    return sorted;
  }

  final gospel = sort.gospel!;

  final leadingMissing = <Topic>[];
  final missingAfterAnchor = <Topic, List<Topic>>{};
  final anchored = <Topic>[];
  Topic? previousAnchoredTopic;

  for (final topic in sorted) {
    final anchor = topic.earliestGospelAnchors[gospel];
    if (anchor != null) {
      anchored.add(topic);
      previousAnchoredTopic = topic;
    } else if (previousAnchoredTopic == null) {
      leadingMissing.add(topic);
    } else {
      missingAfterAnchor
          .putIfAbsent(previousAnchoredTopic, () => <Topic>[])
          .add(topic);
    }
  }

  anchored.sort((firstTopic, secondTopic) {
    final first = firstTopic.earliestGospelAnchors[gospel]!;
    final second = secondTopic.earliestGospelAnchors[gospel]!;
    final anchorComparison = first.compareTo(second);
    return anchorComparison != 0
        ? anchorComparison
        : stableIndexes[firstTopic]!.compareTo(stableIndexes[secondTopic]!);
  });

  return <Topic>[
    ...leadingMissing,
    for (final topic in anchored) ...[topic, ...?missingAfterAnchor[topic]],
  ];
}

int countVisibleReferences(
  Iterable<Topic> topics,
  ColumnVisibilityState columns,
) {
  var count = 0;
  for (final topic in topics) {
    for (final reference in topic.references) {
      final gospel = _canonicalGospelForReference(reference);
      if (gospel != null &&
          columns.isVisible(gospel) &&
          _referenceHasData(reference) &&
          reference.separatorBefore != ReferenceSeparator.continuous.symbol) {
        count++;
      }
    }
  }
  return count;
}

class HarmonyTopicProcessingResult {
  const HarmonyTopicProcessingResult({
    required this.topics,
    required this.sourceIndexes,
    required this.visibleReferenceCount,
  });

  final List<Topic> topics;
  final List<int> sourceIndexes;
  final int visibleReferenceCount;

  int get visibleTopicCount => topics.length;
}

/// Canonical main-table pipeline: advanced filter, visible-column row pruning,
/// canonical/default or Gospel chronology sorting, and displayed counts.
HarmonyTopicProcessingResult processHarmonyTopics(
  List<Topic> topics,
  GospelFilterState filter,
  GospelSortState sort,
  ColumnVisibilityState columns,
) {
  final sourceIndexes = <Topic, int>{
    for (var index = 0; index < topics.length; index++) topics[index]: index,
  };
  final filtered = applyAdvancedFilter(topics, filter);
  final visible = removeRowsWithoutVisibleReferences(filtered, columns);
  final sorted = sortTopics(visible, sort, sourceIndexes: sourceIndexes);
  return HarmonyTopicProcessingResult(
    topics: List<Topic>.unmodifiable(sorted),
    sourceIndexes: List<int>.unmodifiable(
      sorted.map((topic) => sourceIndexes[topic]!),
    ),
    visibleReferenceCount: countVisibleReferences(sorted, columns),
  );
}

List<int> processHarmonyTopicIndexes(
  List<Topic> topics,
  GospelFilterState filter,
  GospelSortState sort, [
  ColumnVisibilityState columns = const ColumnVisibilityState(),
]) {
  return processHarmonyTopics(topics, filter, sort, columns).sourceIndexes;
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

String _localizedTopicNumber(
  String rawNumber,
  TopicLanguageOption topicLanguage,
) {
  final trimmed = rawNumber.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  return topicLanguage.code == 'arabic'
      ? toArabicIndicDigits(trimmed)
      : trimmed;
}

String _numberedTopicTitle(
  Topic topic,
  TopicLanguageOption topicLanguage, {
  int? zeroBasedIndex,
  String? topicNumber,
}) {
  final rawNumber = _topicNumberForDisplay(
    topic,
    zeroBasedIndex: zeroBasedIndex,
    rawNumber: topicNumber,
  );
  final localizedNumber = _localizedTopicNumber(rawNumber, topicLanguage);
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

Widget _buildToolbarDiacriticsButton({
  required BuildContext context,
  required LanguageOption menuLanguage,
  required bool withDiacritics,
  required VoidCallback? onPressed,
  bool enabled = true,
}) {
  final label = withDiacritics
      ? menuLanguage.ui.removeDiacritics
      : menuLanguage.ui.addDiacritics;
  final icon = withDiacritics
      ? Icons.remove_circle_outline
      : Icons.add_circle_outline;
  return Tooltip(
    message: label,
    child: OutlinedButton.icon(
      onPressed: enabled ? onPressed : null,
      style: _toolbarOutlinedStyle(context),
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
  var overlayOpen = false;
  void beginOverlay() {
    if (overlayOpen) return;
    overlayOpen = true;
    BrowserRouteLinkNavigation.pushBlock();
  }

  void endOverlay() {
    if (!overlayOpen) return;
    overlayOpen = false;
    BrowserRouteLinkNavigation.popBlockAfterEvent();
  }

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
      onOpened: beginOverlay,
      onCanceled: () {
        endOverlay();
        onCanceled?.call();
      },
      onSelected: (value) {
        endOverlay();
        onSelected(value);
      },
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
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
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
      label: Text(labels.bibleLanguage),
    );
  }

  return _toolbarDropdownButton<String>(
    context: context,
    icon: Icons.language,
    label:
        '${labels.bibleLanguage}: ${localizedLanguageNameForMenu(menuLanguage, language.code, language.label)}',
    enabled: languages.length > 1,
    items: languages
        .map(
          (option) => _checkedMenuItem<String>(
            value: option.code,
            label: localizedLanguageNameForMenu(
              menuLanguage,
              option.code,
              option.label,
            ),
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

String localizedLanguageNameForMenu(
  LanguageOption menuLanguage,
  String languageCode,
  String fallbackLabel,
) {
  if (menuLanguage.code.toLowerCase() == 'arabic') {
    return switch (languageCode.toLowerCase()) {
      'english' => 'الإنجليزية',
      'arabic' => 'العربية',
      _ => fallbackLabel,
    };
  }
  return switch (languageCode.toLowerCase()) {
    'english' => 'English',
    'arabic' => 'Arabic',
    _ => fallbackLabel,
  };
}

Widget _buildToolbarVersionButton({
  required BuildContext context,
  required LanguageOption language,
  required LanguageOption menuLanguage,
  required String? selectedVersion,
  required ValueChanged<String> onSelected,
  Key? popupKey,
  VoidCallback? onCanceled,
}) {
  final versions = _selectableVersions(language);
  if (versions.isEmpty) {
    return const SizedBox.shrink();
  }

  final current = selectedVersion == null
      ? null
      : _selectionVersionValue(language, selectedVersion);
  final currentLabel = selectedVersion == null
      ? menuLanguage.ui.selectVersion
      : _versionLabel(language.code, selectedVersion);
  return _toolbarDropdownButton<String>(
    context: context,
    icon: Icons.menu_book_outlined,
    label: '${menuLanguage.ui.translation}: $currentLabel',
    enabled: versions.length > 1,
    popupKey: popupKey,
    onCanceled: onCanceled,
    items: versions
        .map(
          (version) => _checkedMenuItem<String>(
            value: version.id,
            label: version.label,
            selected:
                current != null &&
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
    this.showDiacriticsToggle = false,
    this.withDiacritics = false,
    this.diacriticsToggleEnabled = true,
    this.onDiacriticsToggled,
    this.onTranslationChanged,
    this.maxContentWidth = _maxPageContentWidth,
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
  final bool showDiacriticsToggle;
  final bool withDiacritics;
  final bool diacriticsToggleEnabled;
  final VoidCallback? onDiacriticsToggled;
  final ToolbarTranslationChanged? onTranslationChanged;
  final double maxContentWidth;

  @override
  State<AppToolbar> createState() => _AppToolbarState();
}

class _AppToolbarState extends State<AppToolbar> {
  final GlobalKey<PopupMenuButtonState<String>> _versionMenuKey =
      GlobalKey<PopupMenuButtonState<String>>();
  LanguageOption? _versionGuidanceLanguage;

  LanguageOption get _versionLanguage =>
      _versionGuidanceLanguage ?? widget.language;

  String? get _versionValue {
    final guidanceLanguage = _versionGuidanceLanguage;
    if (guidanceLanguage == null) {
      return widget.version;
    }
    return null;
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
  void didUpdateWidget(covariant AppToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.language.code != widget.language.code ||
        oldWidget.version != widget.version) {
      _versionGuidanceLanguage = null;
    }
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
          language: _versionLanguage,
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
      if (widget.showDiacriticsToggle)
        _buildToolbarDiacriticsButton(
          context: context,
          menuLanguage: menuLanguage,
          withDiacritics: widget.withDiacritics,
          enabled:
              widget.diacriticsToggleEnabled &&
              widget.onDiacriticsToggled != null,
          onPressed: widget.onDiacriticsToggled,
        ),
      ...widget.primaryActions,
      ...widget.trailingActions,
    ].where((widget) => widget is! SizedBox).toList();

    return Directionality(
      textDirection: menuLanguage.direction,
      child: ResponsiveContentShell(
        maxWidth: widget.maxContentWidth,
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

String _gospelFilterLabel(
  String gospel,
  LocalizedUiLabels labels,
  LanguageOption uiLanguage,
) {
  final index = orderedGospels.indexOf(_normalizeGospelName(gospel));
  final gospelHeaders = uiLanguage.localizedGospelNames.length == 4
      ? uiLanguage.localizedGospelNames
      : labels.gospelHeaders;
  if (index >= 0 && index < gospelHeaders.length) {
    return gospelHeaders[index];
  }
  return _displayGospelName(gospel, uiLanguage);
}

String _includedGroupLabel(int count, LocalizedUiLabels labels) {
  switch (count) {
    case 4:
      return labels.fourIncludedGospels;
    case 3:
      return labels.threeIncludedGospels;
    case 2:
      return labels.twoIncludedGospels;
    default:
      return labels.oneIncludedGospel;
  }
}

String _excludedGroupLabel(int count, LocalizedUiLabels labels) {
  switch (count) {
    case 0:
      return labels.noExcludedGospels;
    case 1:
      return labels.oneExcludedGospel;
    case 2:
      return labels.twoExcludedGospels;
    default:
      return labels.threeExcludedGospels;
  }
}

String _localizedGospelName(
  Gospel gospel,
  LocalizedUiLabels labels,
  LanguageOption uiLanguage,
) {
  return _gospelFilterLabel(gospel.canonicalName, labels, uiLanguage);
}

String _combinationSummary(
  GospelFilterCombination combination,
  LanguageOption uiLanguage,
) {
  final labels = uiLanguage.ui;
  String namesFor(GospelConstraint constraint) {
    return combination
        .gospelsWith(constraint)
        .map((gospel) => _localizedGospelName(gospel, labels, uiLanguage))
        .join(', ');
  }

  final parts = <String>[
    combination.code,
    '${labels.included}: ${namesFor(GospelConstraint.included)}',
  ];
  final excluded = namesFor(GospelConstraint.excluded);
  if (excluded.isNotEmpty) {
    parts.add('${labels.excluded}: $excluded');
  }
  final unrestricted = namesFor(GospelConstraint.any);
  if (unrestricted.isNotEmpty) {
    parts.add('${labels.unrestricted}: $unrestricted');
  }
  return parts.join('. ');
}

String _normalizeFilterSearch(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '')
      .replaceAll('ـ', '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

const Map<Gospel, String> _arabicGospelSearchNames = <Gospel, String>{
  Gospel.matthew: 'متى',
  Gospel.mark: 'مرقس',
  Gospel.luke: 'لوقا',
  Gospel.john: 'يوحنا',
};

bool matchesGospelFilterSearch(
  GospelFilterCombination combination,
  String query,
  LanguageOption uiLanguage,
) {
  final normalizedQuery = _normalizeFilterSearch(query);
  if (normalizedQuery.isEmpty) {
    return true;
  }
  final codeMatch = RegExp(r'\bc\d{2}\b').firstMatch(normalizedQuery);
  if (codeMatch != null &&
      codeMatch.group(0) != combination.code.toLowerCase()) {
    return false;
  }

  String names(GospelConstraint constraint, {required bool arabic}) {
    return combination
        .gospelsWith(constraint)
        .map(
          (gospel) =>
              arabic ? _arabicGospelSearchNames[gospel]! : gospel.canonicalName,
        )
        .join(' ');
  }

  final includedEnglish = names(GospelConstraint.included, arabic: false);
  final excludedEnglish = names(GospelConstraint.excluded, arabic: false);
  final anyEnglish = names(GospelConstraint.any, arabic: false);
  final includedArabic = names(GospelConstraint.included, arabic: true);
  final excludedArabic = names(GospelConstraint.excluded, arabic: true);
  final anyArabic = names(GospelConstraint.any, arabic: true);
  final mentionedGospels = <Gospel>{
    for (final gospel in Gospel.values)
      if (normalizedQuery.contains(gospel.canonicalName.toLowerCase()) ||
          normalizedQuery.contains(
            _normalizeFilterSearch(_arabicGospelSearchNames[gospel]!),
          ))
        gospel,
  };
  final hasExcludedKeyword = <String>[
    'exclude',
    'excluded',
    'without',
    'does not have',
    'مستبعد',
  ].any(normalizedQuery.contains);
  if (hasExcludedKeyword && mentionedGospels.isNotEmpty) {
    return mentionedGospels.every(
      (gospel) => combination.constraints[gospel] == GospelConstraint.excluded,
    );
  }
  final hasIncludedKeyword = <String>[
    'include',
    'included',
    'has reference',
    'مشمول',
  ].any(normalizedQuery.contains);
  if (hasIncludedKeyword && mentionedGospels.isNotEmpty) {
    return mentionedGospels.every(
      (gospel) => combination.constraints[gospel] == GospelConstraint.included,
    );
  }
  final hasOnlyKeyword =
      normalizedQuery.contains('only') || normalizedQuery.contains('فقط');
  if (hasOnlyKeyword && mentionedGospels.isNotEmpty) {
    return combination.includedCount == mentionedGospels.length &&
        combination.excludedCount ==
            Gospel.values.length - mentionedGospels.length &&
        mentionedGospels.every(
          (gospel) =>
              combination.constraints[gospel] == GospelConstraint.included,
        );
  }
  final hasUnrestrictedKeyword = <String>[
    'any',
    'unrestricted',
    'غير مقيد',
    'أي',
  ].any(normalizedQuery.contains);
  if (hasUnrestrictedKeyword && mentionedGospels.isNotEmpty) {
    return mentionedGospels.every(
      (gospel) => combination.constraints[gospel] == GospelConstraint.any,
    );
  }
  if (mentionedGospels.isNotEmpty) {
    return mentionedGospels.every(
      (gospel) => combination.constraints[gospel] == GospelConstraint.included,
    );
  }
  final exactOnly =
      combination.includedCount == 1 && combination.excludedCount == 3
      ? 'only $includedEnglish فقط $includedArabic'
      : '';
  final haystack = _normalizeFilterSearch(
    <String>[
      combination.code,
      _combinationSummary(combination, uiLanguage),
      'included include has reference $includedEnglish',
      if (excludedEnglish.isNotEmpty)
        'excluded exclude without does not have $excludedEnglish',
      if (anyEnglish.isNotEmpty) 'any unrestricted $anyEnglish',
      'مشمولة مشمول $includedArabic',
      if (excludedArabic.isNotEmpty) 'مستبعدة مستبعد $excludedArabic',
      if (anyArabic.isNotEmpty) 'غير مقيد أي $anyArabic',
      exactOnly,
    ].join(' '),
  );
  return normalizedQuery
      .split(' ')
      .where((term) => term.isNotEmpty)
      .every(haystack.contains);
}

String _localizedResultsLabel(LanguageOption uiLanguage, int count) {
  final number = uiLanguage.code == 'arabic'
      ? toArabicIndicDigits(count.toString())
      : count.toString();
  return '$number ${uiLanguage.ui.results}';
}

Widget _buildHarmonyResultCountChip({
  required BuildContext context,
  required LanguageOption uiLanguage,
  required int count,
}) {
  final theme = Theme.of(context);
  return Chip(
    key: const ValueKey<String>('visible-topic-count'),
    visualDensity: VisualDensity.compact,
    avatar: Icon(
      Icons.format_list_numbered,
      size: 18,
      color: theme.colorScheme.primary,
    ),
    label: Text(_localizedResultsLabel(uiLanguage, count)),
    side: BorderSide(color: theme.colorScheme.outlineVariant),
    backgroundColor: theme.colorScheme.surface,
  );
}

String _localizedReferenceCount(LanguageOption uiLanguage, int count) {
  final number = uiLanguage.code == 'arabic'
      ? toArabicIndicDigits(count.toString())
      : count.toString();
  return '$number ${uiLanguage.ui.references}';
}

Widget _buildHarmonyReferenceCountChip({
  required BuildContext context,
  required LanguageOption uiLanguage,
  required int count,
}) {
  final theme = Theme.of(context);
  return Chip(
    key: const ValueKey<String>('visible-reference-count'),
    visualDensity: VisualDensity.compact,
    avatar: Icon(
      Icons.menu_book_outlined,
      size: 18,
      color: theme.colorScheme.primary,
    ),
    label: Text(_localizedReferenceCount(uiLanguage, count)),
    side: BorderSide(color: theme.colorScheme.outlineVariant),
    backgroundColor: theme.colorScheme.surface,
  );
}

class DraggableDialogShell extends StatefulWidget {
  const DraggableDialogShell({
    super.key,
    required this.title,
    required this.child,
    this.headerTrailing,
    this.footer,
    this.maxWidth = 600,
    this.maxHeight = 720,
    this.shrinkWrap = false,
  });

  final Widget title;
  final Widget child;
  final Widget? headerTrailing;
  final Widget? footer;
  final double maxWidth;
  final double maxHeight;
  final bool shrinkWrap;

  @override
  State<DraggableDialogShell> createState() => _DraggableDialogShellState();
}

class _DraggableDialogShellState extends State<DraggableDialogShell> {
  Offset _offset = Offset.zero;
  Size? _lastViewport;

  Offset _clampOffset(Offset value, Size viewport, Size dialogSize) {
    final horizontal = math.max(0.0, (viewport.width - dialogSize.width) / 2);
    final vertical = math.max(0.0, (viewport.height - dialogSize.height) / 2);
    return Offset(
      value.dx.clamp(-horizontal, horizontal).toDouble(),
      value.dy.clamp(-vertical, vertical).toDouble(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final fullScreen =
        !widget.shrinkWrap && (viewport.width < 600 || viewport.height < 650);
    final compactInset = viewport.width < 600 ? 16.0 : 24.0;
    final dialogSize = Size(
      fullScreen
          ? viewport.width
          : math.min(widget.maxWidth, viewport.width - (compactInset * 2)),
      fullScreen
          ? viewport.height
          : math.min(widget.maxHeight, viewport.height - (compactInset * 2)),
    );
    if (_lastViewport != viewport) {
      _lastViewport = viewport;
      _offset = _clampOffset(_offset, viewport, dialogSize);
    }

    final header = MouseRegion(
      cursor: fullScreen ? MouseCursor.defer : SystemMouseCursors.move,
      child: GestureDetector(
        key: const ValueKey<String>('draggable-dialog-header'),
        behavior: HitTestBehavior.opaque,
        onPanUpdate: fullScreen
            ? null
            : (details) {
                setState(() {
                  _offset = _clampOffset(
                    _offset + details.delta,
                    viewport,
                    dialogSize,
                  );
                });
              },
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 10, 10),
          child: Row(
            children: [
              if (!fullScreen) ...[
                const Icon(Icons.drag_indicator, size: 20),
                const SizedBox(width: 8),
              ],
              Expanded(child: widget.title),
              if (widget.headerTrailing != null) widget.headerTrailing!,
            ],
          ),
        ),
      ),
    );

    final dialog = Dialog(
      insetPadding: fullScreen ? EdgeInsets.zero : EdgeInsets.all(compactInset),
      shape: fullScreen
          ? const RoundedRectangleBorder()
          : RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        key: const ValueKey<String>('draggable-dialog-surface'),
        width: dialogSize.width,
        height: dialogSize.height,
        child: Column(
          children: [
            header,
            const Divider(height: 1),
            Expanded(child: widget.child),
            if (widget.footer != null) ...[
              const Divider(height: 1),
              widget.footer!,
            ],
          ],
        ),
      ),
    );
    final positioned = fullScreen
        ? SafeArea(child: dialog)
        : Transform.translate(
            key: const ValueKey<String>('draggable-dialog-transform'),
            offset: _offset,
            child: dialog,
          );
    return PopScope(canPop: true, child: positioned);
  }
}

class _GospelFilterDialogResult {
  const _GospelFilterDialogResult(this.combination);

  final GospelFilterCombination? combination;
}

class HarmonyFilterButton extends StatelessWidget {
  const HarmonyFilterButton({
    super.key,
    required this.filterState,
    required this.uiLanguage,
    required this.onChanged,
    required this.topics,
    required this.columns,
    this.currentResultCount,
    this.onInteractionEnd,
  });

  final GospelFilterState filterState;
  final LanguageOption uiLanguage;
  final ValueChanged<GospelFilterState> onChanged;
  final List<Topic> topics;
  final ColumnVisibilityState columns;
  final int? currentResultCount;
  final VoidCallback? onInteractionEnd;

  Future<void> _showFilterDialog(BuildContext context) async {
    final applied = await showBrowserSafeDialog<bool>(
      context: context,
      builder: (context) => _HarmonySetFilterDialog(
        initialState: filterState,
        uiLanguage: uiLanguage,
        topics: topics,
        columns: columns,
        currentResultCount: currentResultCount,
        onChanged: onChanged,
      ),
    );
    if (applied == true) {
      onInteractionEnd?.call();
    } else {
      onChanged(filterState);
    }
  }

  @override
  Widget build(BuildContext context) {
    final labels = uiLanguage.ui;
    final icon = Icon(
      !filterState.isActive ? Icons.filter_alt_outlined : Icons.filter_alt,
      size: 18,
    );
    if (filterState.isActive) {
      return FilledButton.icon(
        onPressed: () => _showFilterDialog(context),
        style: _toolbarFilledStyle(context),
        icon: icon,
        label: Text(labels.filter, overflow: TextOverflow.ellipsis),
      );
    }
    return OutlinedButton.icon(
      onPressed: () => _showFilterDialog(context),
      style: _toolbarOutlinedStyle(context),
      icon: icon,
      label: Text(labels.filter, overflow: TextOverflow.ellipsis),
    );
  }
}

class _HarmonyFilterDialog extends StatefulWidget {
  const _HarmonyFilterDialog({
    required this.initialCombination,
    required this.uiLanguage,
    required this.currentResultCount,
  });

  final GospelFilterCombination? initialCombination;
  final LanguageOption uiLanguage;
  final int? currentResultCount;

  @override
  State<_HarmonyFilterDialog> createState() => _HarmonyFilterDialogState();
}

class _HarmonyFilterDialogState extends State<_HarmonyFilterDialog> {
  final TextEditingController _searchController = TextEditingController();
  String? _selectedCode;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _selectedCode = widget.initialCombination?.code;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  GospelFilterCombination? get _selectedCombination =>
      gospelFilterCombinationForCode(_selectedCode);

  void _select(GospelFilterCombination? combination) {
    setState(() {
      _selectedCode = combination?.code;
    });
  }

  void _apply() {
    Navigator.of(context).pop(_GospelFilterDialogResult(_selectedCombination));
  }

  Widget _selectionIcon(bool selected) {
    return Icon(
      selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
      color: selected
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.onSurfaceVariant,
      size: 24,
    );
  }

  Widget _constraintChip({
    required Gospel gospel,
    required GospelConstraint constraint,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final (
      IconData icon,
      Color foreground,
      Color background,
    ) = switch (constraint) {
      GospelConstraint.included => (
        Icons.check_circle_outline,
        scheme.primary,
        scheme.primaryContainer.withValues(alpha: 0.55),
      ),
      GospelConstraint.excluded => (
        Icons.block,
        scheme.error,
        scheme.errorContainer.withValues(alpha: 0.55),
      ),
      GospelConstraint.any => (
        Icons.remove_circle_outline,
        scheme.onSurfaceVariant,
        scheme.surfaceContainerHighest,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: foreground.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: foreground),
          const SizedBox(width: 4),
          Text(
            _localizedGospelName(
              gospel,
              widget.uiLanguage.ui,
              widget.uiLanguage,
            ),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _constraintRow(
    GospelFilterCombination combination,
    GospelConstraint constraint,
  ) {
    final gospels = combination.gospelsWith(constraint).toList();
    if (gospels.isEmpty) {
      return const SizedBox.shrink();
    }
    final labels = widget.uiLanguage.ui;
    final label = switch (constraint) {
      GospelConstraint.included => labels.included,
      GospelConstraint.excluded => labels.excluded,
      GospelConstraint.any => labels.unrestricted,
    };
    final icon = switch (constraint) {
      GospelConstraint.included => Icons.check,
      GospelConstraint.excluded => Icons.block,
      GospelConstraint.any => Icons.remove,
    };
    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: widget.uiLanguage.code == 'arabic' ? 78 : 72,
            child: Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 14),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final gospel in gospels)
                  _constraintChip(gospel: gospel, constraint: constraint),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _combinationCard(GospelFilterCombination combination) {
    final selected = combination.code == _selectedCode;
    final scheme = Theme.of(context).colorScheme;
    final summary = _combinationSummary(combination, widget.uiLanguage);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        label: summary,
        selected: selected,
        button: true,
        child: Card(
          margin: EdgeInsets.zero,
          elevation: selected ? 1 : 0,
          color: selected
              ? scheme.primaryContainer.withValues(alpha: 0.35)
              : scheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _select(combination),
            canRequestFocus: true,
            child: Padding(
              padding: const EdgeInsets.all(13),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _selectionIcon(selected),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      combination.code,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _constraintRow(combination, GospelConstraint.included),
                        _constraintRow(combination, GospelConstraint.excluded),
                        _constraintRow(combination, GospelConstraint.any),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _allTopicsCard() {
    final selected = _selectedCode == null;
    final labels = widget.uiLanguage.ui;
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: labels.allTopics,
      selected: selected,
      button: true,
      child: Card(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        elevation: selected ? 1 : 0,
        color: selected
            ? scheme.primaryContainer.withValues(alpha: 0.35)
            : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _select(null),
          canRequestFocus: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                _selectionIcon(selected),
                const SizedBox(width: 12),
                Icon(Icons.view_list_outlined, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    labels.allTopics,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _filterGroups() {
    final labels = widget.uiLanguage.ui;
    final filtered = semanticallyOrderedGospelFilters
        .where(
          (combination) =>
              matchesGospelFilterSearch(combination, _query, widget.uiLanguage),
        )
        .toList();
    if (filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off, size: 42),
              const SizedBox(height: 12),
              Text(
                labels.noMatchingFilterCombinations,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        for (final includedCount in const <int>[4, 3, 2, 1])
          if (filtered.any(
            (combination) => combination.includedCount == includedCount,
          ))
            ExpansionTile(
              key: ValueKey<String>(
                'included-$includedCount-$_query-${_selectedCode ?? 'all'}',
              ),
              initiallyExpanded:
                  _query.isNotEmpty ||
                  _selectedCombination?.includedCount == includedCount ||
                  includedCount == 4,
              tilePadding: const EdgeInsets.symmetric(horizontal: 4),
              childrenPadding: EdgeInsets.zero,
              title: Text(
                _includedGroupLabel(includedCount, labels),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                filtered
                    .where(
                      (combination) =>
                          combination.includedCount == includedCount,
                    )
                    .length
                    .toString(),
              ),
              children: [
                for (final excludedCount in const <int>[0, 1, 2, 3])
                  if (filtered.any(
                    (combination) =>
                        combination.includedCount == includedCount &&
                        combination.excludedCount == excludedCount,
                  )) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          _excludedGroupLabel(excludedCount, labels),
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    ),
                    for (final combination in filtered.where(
                      (combination) =>
                          combination.includedCount == includedCount &&
                          combination.excludedCount == excludedCount,
                    ))
                      _combinationCard(combination),
                  ],
              ],
            ),
      ],
    );
  }

  Widget _header() {
    final labels = widget.uiLanguage.ui;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    labels.gospelCombinations,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (widget.currentResultCount != null)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 4),
                    child: Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text(
                        _localizedResultsLabel(
                          widget.uiLanguage,
                          widget.currentResultCount!,
                        ),
                      ),
                    ),
                  ),
                IconButton(
                  tooltip: labels.cancel,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: labels.searchFilters,
                hintText: 'C25 · Matthew · متى',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: labels.clearFilter,
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _query = '';
                          });
                        },
                        icon: const Icon(Icons.close),
                      ),
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() {
                  _query = value;
                });
              },
            ),
            const SizedBox(height: 6),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: _selectedCode == null ? null : () => _select(null),
                icon: const Icon(Icons.filter_alt_off, size: 18),
                label: Text(labels.clearFilter),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actions() {
    final labels = widget.uiLanguage.ui;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: OverflowBar(
          alignment: MainAxisAlignment.end,
          spacing: 8,
          overflowSpacing: 8,
          children: [
            TextButton.icon(
              onPressed: () => _select(null),
              icon: const Icon(Icons.filter_alt_off, size: 18),
              label: Text(labels.clearFilter),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(labels.cancel),
            ),
            FilledButton.icon(
              onPressed: _apply,
              icon: const Icon(Icons.check, size: 18),
              label: Text(labels.applyFilter),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final fullScreen = size.width < 640 || size.height < 680;
    final dialog = Dialog(
      insetPadding: fullScreen
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
      shape: fullScreen
          ? const RoundedRectangleBorder()
          : RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: fullScreen ? size.width : math.min(780, size.width - 48),
        height: fullScreen ? size.height : math.min(760, size.height - 44),
        child: Column(
          children: [
            _header(),
            const Divider(height: 1),
            _allTopicsCard(),
            Expanded(child: _filterGroups()),
            const Divider(height: 1),
            _actions(),
          ],
        ),
      ),
    );
    return Directionality(
      textDirection: widget.uiLanguage.direction,
      child: fullScreen ? SafeArea(child: dialog) : dialog,
    );
  }
}

String _localizedTopicCount(LanguageOption uiLanguage, int count) {
  final number = uiLanguage.code == 'arabic'
      ? toArabicIndicDigits(count.toString())
      : count.toString();
  return '$number ${uiLanguage.ui.topics}';
}

String _localizedGospelList(
  Iterable<Gospel> gospels,
  LanguageOption uiLanguage, {
  required String separator,
}) {
  return gospels
      .map((gospel) => _localizedGospelName(gospel, uiLanguage.ui, uiLanguage))
      .join(separator);
}

String _mathematicalFilterExpression(
  GospelFilterState state,
  LanguageOption uiLanguage,
) {
  if (!state.isActive) {
    return uiLanguage.ui.allTopics;
  }
  final operator = state.mode == GospelFilterMode.union ? ' ∪ ' : ' ∩ ';
  final included = _localizedGospelList(
    state.includedGospels,
    uiLanguage,
    separator: operator,
  );
  if (state.excludeMask == 0) {
    return included;
  }
  final excluded = _localizedGospelList(
    state.excludedGospels,
    uiLanguage,
    separator: ' ∪ ',
  );
  return '($included) − $excluded';
}

String _wordedFilterExpression(
  GospelFilterState state,
  LanguageOption uiLanguage,
) {
  if (!state.isActive) {
    return state.mode == GospelFilterMode.union
        ? uiLanguage.ui.union
        : uiLanguage.ui.intersection;
  }
  final isArabic = uiLanguage.code == 'arabic';
  final operationConnector = state.mode == GospelFilterMode.union
      ? (isArabic ? ' أو ' : ' union ')
      : (isArabic ? ' و' : ' intersection ');
  final included = _localizedGospelList(
    state.includedGospels,
    uiLanguage,
    separator: operationConnector,
  );
  final buffer = StringBuffer(included);
  if (state.excludeMask != 0) {
    final excluded = _localizedGospelList(
      state.excludedGospels,
      uiLanguage,
      separator: isArabic ? ' و' : ' and ',
    );
    buffer.write(isArabic ? '، مع استبعاد $excluded' : ', excluding $excluded');
  }
  return buffer.toString();
}

Widget _buildActiveSetFilterChip({
  required BuildContext context,
  required GospelFilterState state,
  required LanguageOption uiLanguage,
  required VoidCallback onDeleted,
}) {
  return Tooltip(
    message: _wordedFilterExpression(state, uiLanguage),
    child: InputChip(
      avatar: const Icon(Icons.functions, size: 17),
      label: Text(
        _mathematicalFilterExpression(state, uiLanguage),
        overflow: TextOverflow.ellipsis,
      ),
      onDeleted: onDeleted,
      deleteButtonTooltipMessage: uiLanguage.ui.clearFilter,
      visualDensity: VisualDensity.compact,
      side: BorderSide(color: Theme.of(context).colorScheme.primary),
    ),
  );
}

class _HarmonySetFilterDialog extends StatefulWidget {
  const _HarmonySetFilterDialog({
    required this.initialState,
    required this.uiLanguage,
    required this.topics,
    required this.columns,
    required this.onChanged,
    this.currentResultCount,
  });

  final GospelFilterState initialState;
  final LanguageOption uiLanguage;
  final List<Topic> topics;
  final ColumnVisibilityState columns;
  final ValueChanged<GospelFilterState> onChanged;
  final int? currentResultCount;

  @override
  State<_HarmonySetFilterDialog> createState() =>
      _HarmonySetFilterDialogState();
}

class _HarmonySetFilterDialogState extends State<_HarmonySetFilterDialog> {
  late GospelFilterState _state;

  @override
  void initState() {
    super.initState();
    _state = widget.initialState.isActive
        ? widget.initialState
        : const GospelFilterState();
  }

  int get _finalCount => processHarmonyTopics(
    widget.topics,
    _state,
    const GospelSortState(),
    widget.columns,
  ).visibleTopicCount;

  void _update(GospelFilterState state) {
    if (state == _state) {
      return;
    }
    setState(() {
      _state = state;
    });
    widget.onChanged(state);
  }

  Widget _sectionTitle(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Widget _gospelChips({required bool exclusion}) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final gospel in Gospel.values)
          FilterChip(
            key: ValueKey<String>(
              '${exclusion ? 'exclude' : 'include'}-${gospel.name}',
            ),
            label: Text(
              _localizedGospelName(
                gospel,
                widget.uiLanguage.ui,
                widget.uiLanguage,
              ),
            ),
            avatar: Icon(
              exclusion ? Icons.block_outlined : Icons.menu_book_outlined,
              size: 17,
            ),
            selected: exclusion
                ? _state.excludes(gospel)
                : _state.includes(gospel),
            onSelected:
                exclusion && (!_state.isActive || _state.includes(gospel))
                ? null
                : (_) => _update(
                    exclusion
                        ? _state.toggleExcluded(gospel)
                        : _state.toggleIncluded(gospel),
                  ),
          ),
      ],
    );
  }

  Widget _expressionCard() {
    final scheme = Theme.of(context).colorScheme;
    final expression = _state.isActive
        ? _mathematicalFilterExpression(_state, widget.uiLanguage)
        : (_state.mode == GospelFilterMode.union
              ? widget.uiLanguage.ui.union
              : widget.uiLanguage.ui.intersection);
    return Semantics(
      label: _wordedFilterExpression(_state, widget.uiLanguage),
      liveRegion: true,
      child: Container(
        key: const ValueKey<String>('filter-expression-row'),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.38),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          children: [
            const Icon(Icons.functions, size: 20),
            const SizedBox(width: 9),
            Expanded(
              child: SelectableText(
                expression,
                key: const ValueKey<String>('filter-final-expression'),
                maxLines: 1,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: scheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              _localizedTopicCount(widget.uiLanguage, _finalCount),
              key: const ValueKey<String>('filter-final-count'),
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final labels = widget.uiLanguage.ui;
    return Directionality(
      textDirection: widget.uiLanguage.direction,
      child: DraggableDialogShell(
        title: Text(
          labels.filter,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        headerTrailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Chip(
              visualDensity: VisualDensity.compact,
              label: Text(
                _localizedTopicCount(widget.uiLanguage, _finalCount),
                key: const ValueKey<String>('filter-header-count'),
              ),
            ),
            IconButton(
              tooltip: labels.cancel,
              onPressed: () => Navigator.of(context).pop(false),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        // Kept before footer so the dialog reads header/content/actions.
        // ignore: sort_child_properties_last
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle(labels.operation),
              SegmentedButton<GospelFilterMode>(
                key: const ValueKey<String>('filter-operation'),
                showSelectedIcon: false,
                segments: [
                  ButtonSegment<GospelFilterMode>(
                    value: GospelFilterMode.intersection,
                    icon: const Icon(Icons.join_inner, size: 18),
                    label: Text(labels.intersection),
                  ),
                  ButtonSegment<GospelFilterMode>(
                    value: GospelFilterMode.union,
                    icon: const Icon(Icons.join_full, size: 18),
                    label: Text(labels.union),
                  ),
                ],
                selected: {_state.mode},
                onSelectionChanged: (selection) =>
                    _update(_state.copyWith(mode: selection.single)),
              ),
              const SizedBox(height: 20),
              _sectionTitle(labels.includeGospels),
              _gospelChips(exclusion: false),
              const SizedBox(height: 20),
              _sectionTitle(labels.exclude),
              _gospelChips(exclusion: true),
              const SizedBox(height: 20),
              _expressionCard(),
              const SizedBox(height: 10),
              Text(
                labels.filterUpdatesLive,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        footer: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: OverflowBar(
            alignment: MainAxisAlignment.spaceBetween,
            overflowAlignment: OverflowBarAlignment.end,
            spacing: 8,
            overflowSpacing: 8,
            children: [
              TextButton.icon(
                onPressed: !_state.isActive && _state.excludeMask == 0
                    ? null
                    : () => _update(const GospelFilterState()),
                icon: const Icon(Icons.filter_alt_off, size: 18),
                label: Text(labels.clearFilter),
              ),
              FilledButton(
                key: const ValueKey<String>('apply-filter'),
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(labels.applyFilter),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HarmonySortButton extends StatelessWidget {
  const HarmonySortButton({
    super.key,
    required this.state,
    required this.columns,
    required this.uiLanguage,
    required this.onChanged,
    required this.onColumnsChanged,
    this.onInteractionEnd,
  });

  final GospelSortState state;
  final ColumnVisibilityState columns;
  final LanguageOption uiLanguage;
  final ValueChanged<GospelSortState> onChanged;
  final ValueChanged<ColumnVisibilityState> onColumnsChanged;
  final VoidCallback? onInteractionEnd;

  Future<void> _showDialog(BuildContext context) async {
    await showBrowserSafeDialog<void>(
      context: context,
      builder: (context) => _HarmonySortAndColumnsDialog(
        initialSort: state,
        initialColumns: columns,
        uiLanguage: uiLanguage,
        onSortChanged: onChanged,
        onColumnsChanged: onColumnsChanged,
      ),
    );
    onInteractionEnd?.call();
  }

  @override
  Widget build(BuildContext context) {
    final labels = uiLanguage.ui;
    final active = !state.isDefault || columns.visibleMask != allGospelsMask;
    final icon = const Icon(Icons.sort, size: 18);
    final label = Text(labels.sort, overflow: TextOverflow.ellipsis);
    return active
        ? FilledButton.icon(
            key: const ValueKey<String>('sort-button'),
            onPressed: () => _showDialog(context),
            style: _toolbarFilledStyle(context),
            icon: icon,
            label: label,
          )
        : OutlinedButton.icon(
            key: const ValueKey<String>('sort-button'),
            onPressed: () => _showDialog(context),
            style: _toolbarOutlinedStyle(context),
            icon: icon,
            label: label,
          );
  }
}

class _HarmonySortAndColumnsDialog extends StatefulWidget {
  const _HarmonySortAndColumnsDialog({
    required this.initialSort,
    required this.initialColumns,
    required this.uiLanguage,
    required this.onSortChanged,
    required this.onColumnsChanged,
  });

  final GospelSortState initialSort;
  final ColumnVisibilityState initialColumns;
  final LanguageOption uiLanguage;
  final ValueChanged<GospelSortState> onSortChanged;
  final ValueChanged<ColumnVisibilityState> onColumnsChanged;

  @override
  State<_HarmonySortAndColumnsDialog> createState() =>
      _HarmonySortAndColumnsDialogState();
}

class _HarmonySortAndColumnsDialogState
    extends State<_HarmonySortAndColumnsDialog> {
  late GospelSortState _sort;
  late ColumnVisibilityState _columns;

  @override
  void initState() {
    super.initState();
    _sort = widget.initialSort;
    _columns = widget.initialColumns;
  }

  void _setSort(TopicSortMode mode) {
    final next = GospelSortState(mode: mode);
    if (next == _sort) return;
    setState(() => _sort = next);
    widget.onSortChanged(next);
  }

  void _toggleColumn(Gospel gospel) {
    final next = _columns.toggle(gospel);
    if (next == _columns) return;
    setState(() => _columns = next);
    widget.onColumnsChanged(next);
  }

  void _resetColumns() {
    final next = _columns.reset();
    if (next == _columns) return;
    setState(() => _columns = next);
    widget.onColumnsChanged(next);
  }

  String _columnToggleTooltip(Gospel gospel, LocalizedUiLabels labels) {
    final gospelName = _localizedGospelName(gospel, labels, widget.uiLanguage);
    final isVisible = _columns.isVisible(gospel);
    if (widget.uiLanguage.code == 'arabic') {
      return isVisible ? 'إخفاء عمود $gospelName' : 'إظهار عمود $gospelName';
    }
    return isVisible ? 'Hide $gospelName column' : 'Show $gospelName column';
  }

  @override
  Widget build(BuildContext context) {
    final labels = widget.uiLanguage.ui;
    final sortOptionStyle = Theme.of(
      context,
    ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w400);
    return Directionality(
      textDirection: widget.uiLanguage.direction,
      child: DraggableDialogShell(
        maxWidth: 700,
        maxHeight: 820,
        shrinkWrap: true,
        title: SizedBox(
          height: 60,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              labels.sort,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
        ),
        headerTrailing: IconButton(
          tooltip: labels.done,
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close),
        ),
        // Kept before footer so the dialog reads header/content/actions.
        // ignore: sort_child_properties_last
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                labels.sortBy,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 280),
                  child: RadioGroup<TopicSortMode>(
                    groupValue: _sort.mode,
                    onChanged: (value) {
                      if (value != null) _setSort(value);
                    },
                    child: Column(
                      children: [
                        SizedBox(
                          height: 50,
                          child: RadioListTile<TopicSortMode>(
                            key: const ValueKey<String>('sort-default'),
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            value: TopicSortMode.defaultOrder,
                            title: Text(
                              labels.defaultSort,
                              style: sortOptionStyle,
                            ),
                          ),
                        ),
                        for (final gospel in Gospel.values)
                          SizedBox(
                            height: 50,
                            child: RadioListTile<TopicSortMode>(
                              key: ValueKey<String>('sort-${gospel.name}'),
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              value: TopicSortMode.forGospel(gospel),
                              title: Text(
                                widget.uiLanguage.code == 'arabic'
                                    ? '${labels.chronology} ${_localizedGospelName(gospel, labels, widget.uiLanguage)}'
                                    : '${_localizedGospelName(gospel, labels, widget.uiLanguage)} ${labels.chronology}',
                                style: sortOptionStyle,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const Divider(height: 28),
              Text(
                labels.visibleColumns,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 23),
              LayoutBuilder(
                builder: (context, constraints) {
                  final selectorWidth = math.min(constraints.maxWidth, 508.0);
                  final columnCount = constraints.maxWidth >= 508 ? 4 : 2;
                  final itemWidth = selectorWidth / columnCount;
                  final outline = Theme.of(context).colorScheme.outline;
                  return Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: SizedBox(
                      key: const ValueKey<String>('visible-columns-row'),
                      width: selectorWidth,
                      child: Wrap(
                        spacing: 0,
                        runSpacing: 8,
                        textDirection: widget.uiLanguage.direction,
                        children: [
                          for (final gospel in Gospel.values)
                            SizedBox(
                              key: ValueKey<String>('column-${gospel.name}'),
                              width: itemWidth,
                              height: 48,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  border: Border.all(color: outline),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Padding(
                                        padding:
                                            const EdgeInsetsDirectional.only(
                                              start: 12,
                                            ),
                                        child: Text(
                                          _localizedGospelName(
                                            gospel,
                                            labels,
                                            widget.uiLanguage,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodyLarge,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: _columnToggleTooltip(
                                        gospel,
                                        labels,
                                      ),
                                      onPressed:
                                          _columns.isVisible(gospel) &&
                                              _columns.visibleCount == 1
                                          ? null
                                          : () => _toggleColumn(gospel),
                                      icon: Icon(
                                        _columns.isVisible(gospel)
                                            ? Icons.remove_circle_outline
                                            : Icons.add_circle_outline,
                                        size: 26,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 64),
              OutlinedButton.icon(
                key: const ValueKey<String>('reset-columns'),
                onPressed: _columns.visibleMask == allGospelsMask
                    ? null
                    : _resetColumns,
                icon: const Icon(Icons.restart_alt, size: 18),
                label: Text(labels.resetColumns),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(236, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  textStyle: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                labels.atLeastOneColumnVisible,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
          ),
        ),
        footer: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(12, 10, 12, 14),
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              style: FilledButton.styleFrom(
                minimumSize: const Size(92, 46),
                textStyle: Theme.of(context).textTheme.titleMedium,
              ),
              child: Text(labels.done),
            ),
          ),
        ),
      ),
    );
  }
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
  _syncSelectedContentLanguage(option);
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
  final profileController = UserProfileController.instance;
  if (profileController.profile != null) {
    final current = profileController.preferences;
    // Loading the selected translation must not wait for a Firestore profile
    // write. The controller applies the new preference locally before its
    // queued remote write; any remote failure is handled independently so the
    // first selection still navigates immediately.
    unawaited(
      _updateUserPreferencesBestEffort(
        current.copyWith(
          menuLanguage: option.code,
          topicLanguage: option.code,
          contentLanguage: option.code,
          preferredVersion: _sanitizeVersionForLanguage(option, version),
          showDiacritics: option.code == 'arabic' && withDiacritics != null
              ? withDiacritics
              : current.showDiacritics,
        ),
      ),
    );
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
  await TopicLanguageSelectionController.instance.initialize();
  await MenuLanguageController.instance.initialize(
    fallbackLanguageCode: LanguageSelectionController.instance.languageCode,
  );
  PrimaryLanguageController.instance.select(
    LanguageSelectionController.instance.languageCode,
  );
  await ZoomController.instance.initialize();
  runApp(GospelApp());
}

class GospelApp extends StatefulWidget {
  const GospelApp({super.key});

  @override
  State<GospelApp> createState() => _GospelAppState();
}

class _GospelAppState extends State<GospelApp> {
  String? _lastAppliedProfileLanguage;

  @override
  void initState() {
    super.initState();
    UserProfileController.instance.addListener(_applyLoadedPreferences);
  }

  @override
  void dispose() {
    UserProfileController.instance.removeListener(_applyLoadedPreferences);
    super.dispose();
  }

  void _applyLoadedPreferences() {
    final profile = UserProfileController.instance.profile;
    if (profile == null) {
      _lastAppliedProfileLanguage = null;
      return;
    }
    final preferences = profile.preferences;
    ZoomController.instance.update(preferences.zoomLevel);
    final primaryLanguage = _coercePrimaryLanguageOption(
      _languageOptionForCode(preferences.contentLanguage),
    ).code;
    if (_lastAppliedProfileLanguage == primaryLanguage) {
      return;
    }
    _lastAppliedProfileLanguage = primaryLanguage;
    PrimaryLanguageController.instance.select(primaryLanguage);
  }

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
    final rawPrimaryLanguage = primaryLanguageQueryParameter(uri);

    if (path == '/') {
      final rawVersion = uri.queryParameters['version'];
      return MaterialPageRoute(
        settings: settings,
        builder: (_) => AuthGate(
          builder: (context) => TopicListScreen(
            initialLanguage: rawPrimaryLanguage,
            initialVersion: rawVersion,
            initialFilterCode: uri.queryParameters['filter'],
            initialFilterMode: uri.queryParameters['filterMode'],
            initialIncludedGospels: uri.queryParameters['include'],
            initialExcludedGospels: uri.queryParameters['exclude'],
            initialSortGospel: uri.queryParameters['sort'],
            initialVisibleColumns: uri.queryParameters['columns'],
          ),
        ),
      );
    }

    if (path == '/admin') {
      return MaterialPageRoute(
        settings: settings,
        builder: (_) =>
            AuthGate(builder: (context) => AdminPortal(apiBaseUrl: apiBaseUrl)),
      );
    }

    if (path == '/reference') {
      final rawLanguage = rawPrimaryLanguage ?? defaultLanguage;
      final rawVersion = uri.queryParameters['version'] ?? defaultVersion;
      final languageOption = _resolvePrimaryLanguageOption(
        languageParam: rawLanguage,
        versionParam: rawVersion,
      );
      final language = languageOption.apiLanguage;
      final version = _sanitizeVersionForLanguage(languageOption, rawVersion);
      final bookDisplay =
          uri.queryParameters['bookDisplay'] ??
          uri.queryParameters['book'] ??
          '';
      final bookId =
          uri.queryParameters['bookId'] ?? uri.queryParameters['book'] ?? '';
      final chapter = int.tryParse(uri.queryParameters['chapter'] ?? '') ?? 0;
      final verses = uri.queryParameters['verses'] ?? '';
      final topicName = uri.queryParameters['topic'] ?? '';
      final label = uri.queryParameters['label'] ?? '';
      final source = uri.queryParameters['source'] ?? '';
      final topicId = uri.queryParameters['topicId'] ?? '';
      final topicNumber = uri.queryParameters['topicNumber'] ?? '';
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
            topicLanguage: languageOption.code,
            topicName: topicName,
            referenceLabelOverride: label,
            source: source,
            topicId: topicId,
            topicNumber: topicNumber,
            gospel: gospel,
            comparisonState: comparisons,
          ),
        ),
      );
    }

    if (path == '/topic') {
      final initialLanguage = rawPrimaryLanguage ?? defaultLanguage;
      final initialVersion = uri.queryParameters['version'] ?? defaultVersion;
      final initialTopicId = uri.queryParameters['topicId'] ?? '';
      final initialTopicNumber = uri.queryParameters['topicNumber'] ?? '';
      final comparisons = uri.queryParameters['comparisons'] ?? '';

      final languageOption = _resolvePrimaryLanguageOption(
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
            topicLanguage: languageOption.code,
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
      builder: (_) => AuthGate(
        builder: (context) =>
            TopicListScreen(initialLanguage: rawPrimaryLanguage),
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
        final user = snapshot.data;
        if (user != null) {
          return _AuthenticatedProfileGate(
            key: ValueKey<String>(user.uid),
            user: user,
            builder: builder,
          );
        }
        UserProfileController.instance.clear();
        return const AuthScreen();
      },
    );
  }
}

class _AuthenticatedProfileGate extends StatefulWidget {
  const _AuthenticatedProfileGate({
    super.key,
    required this.user,
    required this.builder,
  });

  final User user;
  final WidgetBuilder builder;

  @override
  State<_AuthenticatedProfileGate> createState() =>
      _AuthenticatedProfileGateState();
}

class _AuthenticatedProfileGateState extends State<_AuthenticatedProfileGate> {
  late Future<UserProfile> _loadFuture;

  @override
  void initState() {
    super.initState();
    UserProfileController.instance.addListener(_profileChanged);
    _loadFuture = _load();
  }

  @override
  void didUpdateWidget(covariant _AuthenticatedProfileGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.uid != widget.user.uid) {
      _loadFuture = _load();
    }
  }

  @override
  void dispose() {
    UserProfileController.instance.removeListener(_profileChanged);
    super.dispose();
  }

  Future<UserProfile> _load({bool force = false}) async {
    final profile = await UserProfileController.instance.loadForUser(
      widget.user,
      force: force,
    );
    _applyUserPreferencesToLegacyControllers(profile.preferences);
    return profile;
  }

  void _profileChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserProfile>(
      future: _loadFuture,
      builder: (context, snapshot) {
        final controller = UserProfileController.instance;
        final cachedProfile = controller.hasProfileFor(widget.user.uid)
            ? controller.profile
            : null;
        if (snapshot.connectionState != ConnectionState.done &&
            cachedProfile == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          final menuLanguage = MenuLanguageController.instance.languageCode;
          final arabic = menuLanguage == 'arabic';
          return Scaffold(
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        arabic
                            ? 'تعذر تحميل إعدادات الحساب.'
                            : 'Your account settings could not be loaded.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () {
                          setState(() {
                            _loadFuture = _load(force: true);
                          });
                        },
                        icon: const Icon(Icons.refresh),
                        label: Text(arabic ? 'إعادة المحاولة' : 'Try again'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        final profile = cachedProfile ?? snapshot.data;
        if (profile == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (!profile.profileCompleted) {
          return ProfileSetupScreen(profile: profile);
        }
        return widget.builder(context);
      },
    );
  }
}

void _applyUserPreferencesToLegacyControllers(UserPreferences preferences) {
  final primaryLanguage = _coercePrimaryLanguageOption(
    _languageOptionForCode(preferences.contentLanguage),
  ).code;
  PrimaryLanguageController.instance.select(primaryLanguage);
  ZoomController.instance.update(preferences.zoomLevel);
}

Future<void> _updateUserPreferencesBestEffort(
  UserPreferences preferences,
) async {
  try {
    await UserProfileController.instance.updatePreferences(preferences);
  } catch (_) {
    // Immediate toolbar settings stay usable while a later save or retry can
    // restore remote persistence after a transient connection failure.
  }
}

class TopicDetailScreen extends StatefulWidget {
  const TopicDetailScreen({
    super.key,
    required this.languageOption,
    required this.topicLanguage,
    required this.apiVersion,
    required this.topicId,
    this.topicNumber = '',
    this.comparisonState = '',
  });

  final LanguageOption languageOption;
  final String topicLanguage;
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
    _syncSelectedContentLanguage(widget.languageOption);
    _loadTopic();
    unawaited(_refreshTopicLanguageMetadata());
  }

  Future<void> _refreshTopicLanguageMetadata() async {
    try {
      await _loadTopicLanguages();
      if (mounted) setState(() {});
    } catch (_) {
      // The selected localization still loads through the topics API; keep the
      // bundled direction/header fallback if catalog metadata is unavailable.
    }
  }

  Future<void> _loadTopic() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final topics = await _ApiCache.fetchTopics(
        topicLanguage: widget.topicLanguage,
      );
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
    final textDirection = _topicLanguageOptionForCode(
      widget.topicLanguage,
    ).direction;

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
    this.initialFilterCode,
    this.initialFilterMode,
    this.initialIncludedGospels,
    this.initialExcludedGospels,
    this.initialSortGospel,
    this.initialVisibleColumns,
  });

  final String? initialTopicId;
  final String? initialLanguage;
  final String? initialVersion;
  final String? initialFilterCode;
  final String? initialFilterMode;
  final String? initialIncludedGospels;
  final String? initialExcludedGospels;
  final String? initialSortGospel;
  final String? initialVisibleColumns;
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
  String _selectedTopicLanguageCode =
      TopicLanguageSelectionController.instance.languageCode;
  bool _arabicWithDiacritics = false;
  final Map<String, String> _selectedVersions = {};
  SharedPreferences? _prefs;
  String? _pendingTopicId;
  bool _isAdmin = false;
  bool _routeProvidedInitialVersion = false;
  bool _topicsLoadRequested = false;
  late GospelFilterState _filterState;
  late GospelSortState _sortState;
  late ColumnVisibilityState _columnVisibility;
  late String _committedControlSignature;
  StreamSubscription<Uri>? _browserHistorySubscription;

  LanguageOption get _languageOption =>
      _languageOptionForCode(_selectedLanguageCode);
  TopicLanguageOption get _topicLanguageOption =>
      _topicLanguageOptionForCode(_selectedTopicLanguageCode);

  @override
  void initState() {
    super.initState();
    _filterState = GospelFilterState.fromQueryParameters(<String, String>{
      if (widget.initialFilterMode != null)
        'filterMode': widget.initialFilterMode!,
      if (widget.initialIncludedGospels != null)
        'include': widget.initialIncludedGospels!,
      if (widget.initialExcludedGospels != null)
        'exclude': widget.initialExcludedGospels!,
    }, legacyCode: widget.initialFilterCode);
    _sortState = GospelSortState.fromQueryValue(widget.initialSortGospel);
    _columnVisibility = ColumnVisibilityState.fromQueryValue(
      widget.initialVisibleColumns,
    );
    _committedControlSignature = _controlSignature;
    _browserHistorySubscription = BrowserRouteHistory.changes.listen(
      _restoreControlStateFromUri,
    );
    final initialLanguage = widget.initialLanguage?.trim();
    final initialVersion = widget.initialVersion?.trim();
    if (initialLanguage != null && initialLanguage.isNotEmpty) {
      final resolved = _resolvePrimaryLanguageOption(
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
    _selectedTopicLanguageCode = _selectedLanguageCode;
    _pendingTopicId = widget.initialTopicId?.trim().isNotEmpty == true
        ? widget.initialTopicId!.trim()
        : null;
    _syncSelectedContentLanguage(_languageOption);
    _initializePreferences();
    _refreshLanguagesFromFirestore();
    _refreshTopicLanguages();
    _loadAdminState();
    catalogRevision.addListener(_catalogChanged);
  }

  @override
  void dispose() {
    _browserHistorySubscription?.cancel();
    catalogRevision.removeListener(_catalogChanged);
    super.dispose();
  }

  void _catalogChanged() {
    _languageOptionsLoadFuture = null;
    _topicLanguageOptionsLoadFuture = null;
    _ApiCache.clear();
    unawaited(_refreshLanguagesFromFirestore());
    unawaited(_refreshTopicLanguages());
  }

  Future<void> _refreshTopicLanguages() async {
    try {
      final options = await _loadTopicLanguages();
      if (!mounted) return;
      var selected = _coercePrimaryLanguageOption(
        _languageOptionForCode(_selectedLanguageCode),
      ).code;
      if (!options.any((option) => option.code == selected)) {
        selected = _primaryLanguageOptions()
            .firstWhere(
              (option) => option.code == defaultLanguage,
              orElse: () => _primaryLanguageOptions().first,
            )
            .code;
      }
      setState(() {
        _supportedTopicLanguages = options;
        _selectedLanguageCode = selected;
        _selectedTopicLanguageCode = selected;
      });
      _syncSelectedContentLanguage(_languageOptionForCode(selected));
      await fetchTopics();
    } catch (_) {
      // Keep the bundled topic localization when the remote catalog fails.
    }
  }

  void _restoreControlStateFromUri(Uri uri) {
    if (!mounted || (uri.path.isNotEmpty && uri.path != '/')) {
      return;
    }
    final filter = GospelFilterState.fromQueryParameters(uri.queryParameters);
    final sort = GospelSortState.fromQueryValue(uri.queryParameters['sort']);
    final columns = ColumnVisibilityState.fromQueryValue(
      uri.queryParameters['columns'],
    );
    setState(() {
      _filterState = filter;
      _sortState = sort;
      _columnVisibility = columns;
      _committedControlSignature = _controlSignature;
    });
  }

  Future<void> _loadAdminState() async {
    final isAdmin = await adminAccess.currentUserIsAdmin();
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
        _arabicWithDiacritics =
            prefs.getBool('arabic_with_diacritics') ?? false;
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
      if (mounted) {
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

      final primaryLanguages = _primaryLanguageOptions();
      final hasSelection = primaryLanguages.any(
        (option) => option.code == _selectedLanguageCode,
      );
      if (!hasSelection && primaryLanguages.isNotEmpty) {
        final fallbackCode = primaryLanguages.first.code;
        setState(() {
          _selectedLanguageCode = fallbackCode;
          _selectedTopicLanguageCode = fallbackCode;
        });
        _syncSelectedContentLanguage(_languageOptionForCode(fallbackCode));
        await fetchTopics();
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
      if (mounted && !_topicsLoadRequested) {
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
                withDiacritics: _arabicWithDiacritics,
                preferredVersion: versionId,
              ) ??
              _sanitizeVersionForLanguage(option, versionId))
        : _sanitizeVersionForLanguage(option, versionId);
    if (normalized.isEmpty) {
      return;
    }
    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      _prefs = prefs;
      await prefs.setString('selected_version_${option.code}', normalized);
      if (option.code == 'arabic') {
        await prefs.setBool('arabic_with_diacritics', _arabicWithDiacritics);
      }
    } catch (_) {
      // Ignore persistence errors to keep UX smooth.
    }
    if (mounted && option.code == _selectedLanguageCode) {
      Navigator.of(context).pushReplacementNamed(
        _mainTableUri(
          language: option,
          version: normalized,
          filterState: _filterState,
          sortState: _sortState,
          columnVisibility: _columnVisibility,
        ).toString(),
      );
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedVersions[option.code] = normalized;
    });
  }

  Future<void> _updateContentTranslation(
    LanguageOption option,
    String versionId,
  ) async {
    final normalized = option.code == 'arabic'
        ? (_resolveArabicVersion(
                option,
                withDiacritics: _arabicWithDiacritics,
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
      withDiacritics: option.code == 'arabic' ? _arabicWithDiacritics : null,
    );
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushReplacementNamed(
      _mainTableUri(
        language: option,
        version: normalized,
        filterState: _filterState,
        sortState: _sortState,
        columnVisibility: _columnVisibility,
      ).toString(),
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

  Future<void> fetchTopics() async {
    _topicsLoadRequested = true;
    final expectedTopicLanguage = _selectedTopicLanguageCode;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final topics = await _ApiCache.fetchTopics(
        topicLanguage: expectedTopicLanguage,
      );
      if (!mounted) {
        return;
      }
      if (_selectedTopicLanguageCode != expectedTopicLanguage) {
        return;
      }
      setState(() {
        _topics = topics;
        _loading = false;
      });
      _openPendingTopicIfNeeded();
    } catch (e) {
      if (!mounted) {
        return;
      }
      if (_selectedTopicLanguageCode != expectedTopicLanguage) {
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

  HarmonyTopicProcessingResult _processedTopics() {
    return processHarmonyTopics(
      _topics,
      _filterState,
      _sortState,
      _columnVisibility,
    );
  }

  String get _controlSignature => <Object>[
    _filterState.mode.name,
    _filterState.includeMask,
    _filterState.excludeMask,
    _sortState.mode.name,
    _columnVisibility.visibleMask,
  ].join(':');

  void _setFilterState(GospelFilterState state) {
    if (state == _filterState || !mounted) {
      return;
    }
    setState(() {
      _filterState = state;
    });
  }

  void _setColumnVisibility(ColumnVisibilityState state) {
    if (state == _columnVisibility || !mounted) {
      return;
    }
    setState(() {
      _columnVisibility = state;
    });
  }

  void _setSortState(GospelSortState state) {
    if (state == _sortState || !mounted) {
      return;
    }
    setState(() {
      _sortState = state;
    });
  }

  void _commitControlState() {
    if (!mounted || _committedControlSignature == _controlSignature) {
      return;
    }
    _committedControlSignature = _controlSignature;
    BrowserRouteHistory.update(
      _mainTableUri(
        language: _languageOption,
        version: _apiVersionFor(_languageOption),
        filterState: _filterState,
        sortState: _sortState,
        columnVisibility: _columnVisibility,
      ),
    );
  }

  void _clearFilter() {
    _setFilterState(const GospelFilterState());
    _commitControlState();
  }

  @override
  Widget build(BuildContext context) {
    final languageOption = _languageOption;
    final menuLanguage = MenuLanguageScope.of(context);
    final processed = _processedTopics();
    return Directionality(
      textDirection: _topicLanguageOption.direction,
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
        showAdmin: _isAdmin,
        adminLabel: menuLanguage.code == 'arabic' ? 'الإدارة' : 'Admin',
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(child: Text(_error!))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppToolbar(
                    maxContentWidth: _maxHarmonyTableWidth,
                    language: languageOption,
                    version: _apiVersionFor(languageOption),
                    languages: _primaryLanguageOptions(),
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
                      HarmonySortButton(
                        state: _sortState,
                        columns: _columnVisibility,
                        uiLanguage: menuLanguage,
                        onChanged: _setSortState,
                        onColumnsChanged: _setColumnVisibility,
                        onInteractionEnd: _commitControlState,
                      ),
                      HarmonyFilterButton(
                        filterState: _filterState,
                        uiLanguage: menuLanguage,
                        topics: _topics,
                        columns: _columnVisibility,
                        currentResultCount: processed.visibleTopicCount,
                        onChanged: _setFilterState,
                        onInteractionEnd: _commitControlState,
                      ),
                      _buildHarmonyResultCountChip(
                        context: context,
                        uiLanguage: menuLanguage,
                        count: processed.visibleTopicCount,
                      ),
                      _buildHarmonyReferenceCountChip(
                        context: context,
                        uiLanguage: menuLanguage,
                        count: processed.visibleReferenceCount,
                      ),
                      if (_filterState.isActive)
                        _buildActiveSetFilterChip(
                          context: context,
                          state: _filterState,
                          uiLanguage: menuLanguage,
                          onDeleted: _clearFilter,
                        ),
                    ],
                  ),
                  const Divider(height: 0),
                  Expanded(
                    child: HarmonyTable(
                      key: _tableKey,
                      topics: processed.topics,
                      topicDisplayIndexes: processed.sourceIndexes,
                      languageOption: languageOption,
                      topicLanguage: _topicLanguageOption,
                      apiVersion: _apiVersionFor(languageOption),
                      visibleGospels: _columnVisibility.visibleGospels.toList(),
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
    required this.topicLanguage,
    required this.apiVersion,
    this.topicDisplayIndexes,
    this.visibleGospels,
  });

  final List<Topic> topics;
  final LanguageOption languageOption;
  final TopicLanguageOption topicLanguage;
  final String apiVersion;
  final List<int>? topicDisplayIndexes;
  final List<Gospel>? visibleGospels;

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
      final key =
          _canonicalGospelForReference(reference)?.canonicalName ??
          _normalizeGospelName(reference.book);
      map.putIfAbsent(key, () => <GospelReference>[]).add(reference);
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
      widget.topicLanguage,
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
            child: BrowserFindText(
              text: topic.name,
              style: textStyle,
              textAlign: textAlign,
              textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
              maxLines: 1,
              child: Text(
                topic.name,
                style: textStyle,
                textAlign: textAlign,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(String label, TextStyle? style, TextAlign align) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: BrowserFindText(
        text: label,
        style: style,
        textAlign: align,
        maxLines: 1,
        child: Text(
          label,
          style: style,
          textAlign: align,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
        ),
      ),
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

  int _displayIndexForRow(int rowIndex) {
    final displayIndexes = widget.topicDisplayIndexes;
    if (displayIndexes == null || rowIndex >= displayIndexes.length) {
      return rowIndex;
    }
    return displayIndexes[rowIndex];
  }

  List<Gospel> get _visibleGospels => widget.visibleGospels ?? Gospel.values;

  double _harmonyTableWidthFor(double availableWidth) {
    final minimumWidth = 280.0 + (120.0 * _visibleGospels.length);
    return math.max(
      math.min(_minHarmonyTableWidth, minimumWidth),
      _responsiveContentWidth(availableWidth, maxWidth: _maxHarmonyTableWidth),
    );
  }

  Map<int, TableColumnWidth> _harmonyColumnWidths(double tableWidth) {
    final referenceWidth = switch (tableWidth) {
      < 840 => 116.0,
      < 1000 => 128.0,
      _ => 136.0,
    };
    final subjectWidth = math.max(
      280.0,
      tableWidth - (referenceWidth * _visibleGospels.length),
    );
    return {
      0: FixedColumnWidth(subjectWidth),
      for (var i = 0; i < _visibleGospels.length; i++)
        i + 1: FixedColumnWidth(referenceWidth),
    };
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

  String _displayVerseRange(String verses) => verses.replaceAll('-', '–');

  String _displayReferenceLabel(List<GospelReference> references, int index) {
    final reference = references[index];
    final verses = reference.verses.trim();
    final verseParts = verses.split('-');
    final nextIsContinuous =
        index + 1 < references.length &&
        references[index + 1].separatorBefore == '+';

    if (nextIsContinuous && reference.chapter > 0 && verseParts.isNotEmpty) {
      return '${reference.chapter}:${verseParts.first.trim()}';
    }
    if (reference.separatorBefore == '+' &&
        reference.chapter > 0 &&
        verseParts.isNotEmpty) {
      return '${reference.chapter}:${verseParts.last.trim()}';
    }
    if (reference.separatorBefore == ',' &&
        index > 0 &&
        reference.chapter == references[index - 1].chapter) {
      return _displayVerseRange(verses);
    }
    return _displayVerseRange(reference.formattedReference);
  }

  String _displaySeparatorBefore(GospelReference reference, int index) {
    if (index == 0) return '';
    final isArabic = widget.languageOption.code == 'arabic';
    return switch (reference.separatorBefore) {
      '+' => ' ',
      ',' => isArabic ? '، ' : ', ',
      _ => isArabic ? '؛ ' : '; ',
    };
  }

  Widget _buildReferenceCell(
    Topic topic,
    int displayIndex,
    String gospel,
    List<GospelReference> refs,
    TextStyle? style,
    TextAlign align,
  ) {
    final filteredRefs = refs
        .where(_referenceHasData)
        .where((ref) => ref.formattedReference.trim().isNotEmpty)
        .toList();

    if (filteredRefs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: BrowserFindText(
          text: '—',
          style: style,
          textAlign: align,
          maxLines: 1,
          child: Text('—', style: style, textAlign: align),
        ),
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

    final referenceDirection = widget.languageOption.direction;
    final wrapAlignment = _wrapAlignmentForTextAlign(align, referenceDirection);
    final tooltipMessage = MenuLanguageScope.of(
      context,
    ).ui.clickToReadInChapter;
    final topicNumber = _topicNumberForDisplay(
      topic,
      zeroBasedIndex: displayIndex,
    );
    final useCombinedHoverPreview = filteredRefs.length > 1;
    final children = <Widget>[];
    for (var index = 0; index < filteredRefs.length; index++) {
      final ref = filteredRefs[index];
      final relationLabel = switch (ref.separatorBefore) {
        '+' => 'continuous with the previous reference',
        ';' => 'separate non-contiguous reference',
        ',' => 'additional selection in the same chapter',
        _ => '',
      };
      final referenceLink = ReferenceHoverText(
        key: ValueKey(
          [
            widget.languageOption.apiLanguage,
            widget.apiVersion,
            topic.id,
            ref.bookId,
            ref.book,
            ref.chapter,
            ref.verses,
            ref.separatorBefore,
          ].join('|'),
        ),
        reference: ref,
        textStyle: style,
        textAlign: align,
        textDirection: referenceDirection,
        topicName: topic.name,
        topicLanguage: widget.topicLanguage.code,
        displayBook: widget
            .topicLanguage
            .gospelNames[orderedGospels.indexOf(_normalizeGospelName(gospel))],
        topicId: topic.id.isNotEmpty ? topic.id : topic.name,
        topicNumber: topicNumber,
        sourceContext: 'harmony',
        gospel: gospel,
        language: widget.languageOption.apiLanguage,
        version: widget.apiVersion,
        withDiacritics: widget.languageOption.code == 'arabic'
            ? !_isArabicWithoutDiacritics(widget.apiVersion)
            : null,
        tooltipMessage: tooltipMessage,
        labelOverride: _displayReferenceLabel(filteredRefs, index),
        enableHoverPreview: !useCombinedHoverPreview,
        showHoverTooltip: false,
        openInNewTab: true,
        compact: useCombinedHoverPreview,
      );
      final semanticLink = relationLabel.isEmpty
          ? referenceLink
          : Semantics(label: relationLabel, child: referenceLink);
      final separator = _displaySeparatorBefore(ref, index);
      if (separator.isNotEmpty) {
        children.add(Text(separator, style: style));
      }
      children.add(semanticLink);
    }

    final cellContent = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
      child: Align(
        alignment: cellAlignment,
        child: Wrap(
          alignment: wrapAlignment,
          runAlignment: wrapAlignment,
          crossAxisAlignment: WrapCrossAlignment.center,
          textDirection: referenceDirection,
          spacing: 0,
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
          widget.languageOption.code == 'arabic'
              ? !_isArabicWithoutDiacritics(widget.apiVersion)
              : '',
          topic.id,
          gospel,
          ...filteredRefs.map(
            (ref) => [
              ref.bookId,
              ref.book,
              ref.chapter,
              ref.verses,
              ref.separatorBefore,
            ].join(':'),
          ),
        ].join('|'),
      ),
      references: filteredRefs,
      textDirection: referenceDirection,
      topicName: topic.name,
      topicLanguage: widget.topicLanguage.code,
      displayBook: widget
          .topicLanguage
          .gospelNames[orderedGospels.indexOf(_normalizeGospelName(gospel))],
      topicId: topic.id.isNotEmpty ? topic.id : topic.name,
      topicNumber: topicNumber,
      sourceContext: 'harmony',
      gospel: gospel,
      language: widget.languageOption.apiLanguage,
      version: widget.apiVersion,
      withDiacritics: widget.languageOption.code == 'arabic'
          ? !_isArabicWithoutDiacritics(widget.apiVersion)
          : null,
      tooltipMessage: tooltipMessage,
      openInNewTab: true,
      child: SizedBox(width: double.infinity, child: cellContent),
    );
  }

  @override
  Widget build(BuildContext context) {
    assert(
      widget.topicLanguage.code.toLowerCase() ==
          widget.languageOption.code.toLowerCase(),
      'HarmonyTable requires one primary language for topics and Bible text.',
    );
    final theme = Theme.of(context);
    final menuLanguage = MenuLanguageScope.of(context);
    final labels = menuLanguage.ui;
    final isRtl = widget.topicLanguage.direction == TextDirection.rtl;
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
      widget.topicLanguage.gospelNames.length == orderedGospels.length,
      'gospelHeaders must match number of gospels',
    );

    final headerRow = TableRow(
      decoration: BoxDecoration(color: headerBackground),
      children: [
        _buildHeaderCell(
          widget.topicLanguage.subjectsLabel,
          headerStyle,
          subjectAlign,
        ),
        for (final gospel in _visibleGospels)
          _buildHeaderCell(
            widget.topicLanguage.gospelNames[Gospel.values.indexOf(gospel)],
            headerStyle,
            TextAlign.center,
          ),
      ],
    );
    final bodyRows = <TableRow>[];

    for (var i = 0; i < widget.topics.length; i++) {
      final topic = widget.topics[i];
      final displayIndex = _displayIndexForRow(i);
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
                message: labels.clickToReadAllReferences,
                waitDuration: const Duration(milliseconds: 400),
                child: BrowserRouteLink(
                  uri: _topicRouteUri(topic, displayIndex),
                  builder: (context, followLink) => TableRowInkWell(
                    onTap: followLink,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      child: _buildNumberedTopic(
                        index: displayIndex,
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
            for (final gospel in _visibleGospels)
              TableCell(
                verticalAlignment: TableCellVerticalAlignment.top,
                child: _buildReferenceCell(
                  topic,
                  displayIndex,
                  gospel.canonicalName,
                  grouped[gospel.canonicalName] ?? const <GospelReference>[],
                  referenceStyle,
                  referenceAlign,
                ),
              ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final tableWidth = _harmonyTableWidthFor(availableWidth);
        final horizontalFrameWidth = math.max(availableWidth, tableWidth);
        final columnWidths = _harmonyColumnWidths(tableWidth);

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
                        verticalInside: BorderSide(
                          color: borderColor,
                          width: 0.6,
                        ),
                        top: BorderSide(color: borderColor, width: 0.8),
                        bottom: BorderSide(color: borderColor, width: 0.6),
                        left: BorderSide(color: borderColor, width: 0.8),
                        right: BorderSide(color: borderColor, width: 0.8),
                      ),
                      columnWidths: columnWidths,
                      defaultVerticalAlignment:
                          TableCellVerticalAlignment.middle,
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
                                bottom: BorderSide(
                                  color: borderColor,
                                  width: 0.8,
                                ),
                                left: BorderSide(
                                  color: borderColor,
                                  width: 0.8,
                                ),
                                right: BorderSide(
                                  color: borderColor,
                                  width: 0.8,
                                ),
                              ),
                              columnWidths: columnWidths,
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
      },
    );
  }
}

const _referencePreviewHoverDelay = Duration(milliseconds: 1500);

class _ReferencePreviewDelay {
  Timer? _timer;

  void schedule(VoidCallback callback) {
    cancel();
    _timer = Timer(_referencePreviewHoverDelay, () {
      _timer = null;
      callback();
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
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
    this.topicLanguage = '',
    this.displayBook = '',
    this.language = defaultLanguage,
    this.version = defaultVersion,
    this.tooltipMessage = 'Click to read in chapter',
    this.labelOverride = '',
    this.enableHoverPreview = true,
    this.withDiacritics,
    this.topicId = '',
    this.topicNumber = '',
    this.sourceContext = '',
    this.gospel = '',
    this.showHoverTooltip = true,
    this.openInNewTab = false,
    this.compact = false,
  });

  final GospelReference reference;
  final TextStyle? textStyle;
  final TextAlign textAlign;
  final TextDirection textDirection;
  final String topicName;
  final String topicLanguage;
  final String displayBook;
  final String language;
  final String version;
  final String tooltipMessage;
  final String labelOverride;
  final bool enableHoverPreview;
  final bool? withDiacritics;
  final String topicId;
  final String topicNumber;
  final String sourceContext;
  final String gospel;
  final bool showHoverTooltip;
  final bool openInNewTab;
  final bool compact;

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
  final _previewDelay = _ReferencePreviewDelay();
  final GlobalKey _anchorKey = GlobalKey();
  final GlobalKey _previewKey = GlobalKey();
  Size _previewSize = const Size(280, 220);
  bool _pendingPreviewMeasurement = false;
  int _previewLoadGeneration = 0;

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
    final displayBook = widget.displayBook.trim().isNotEmpty
        ? widget.displayBook.trim()
        : reference.book.trim();
    final bookParam = reference.bookId.trim().isNotEmpty
        ? reference.bookId.trim()
        : (reference.book.trim().isNotEmpty
              ? reference.book.trim()
              : displayBook);
    if (bookParam.isEmpty || reference.chapter <= 0) {
      return null;
    }

    final primaryLanguage = _previewLanguageOption();
    final queryParameters = <String, String>{
      'menuLanguage': primaryLanguage.code,
      'book': bookParam,
      'bookDisplay': displayBook,
      'chapter': reference.chapter.toString(),
      'topicLanguage': primaryLanguage.code,
      'bibleLanguage': primaryLanguage.apiLanguage,
      'language': primaryLanguage.apiLanguage,
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
    if (widget.topicNumber.trim().isNotEmpty) {
      queryParameters['topicNumber'] = widget.topicNumber.trim();
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

  void _schedulePreviewShow() {
    if (_previewEntry != null) {
      return;
    }
    _previewDelay.schedule(() {
      if (!mounted || !_isTriggerHovered || !widget.enableHoverPreview) {
        return;
      }
      _showPreview();
      _loadPreview();
    });
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
    return '${widget.language}|${_previewVersionForRequest()}|${_previewWithDiacritics()}|$bookParam|${reference.chapter}|${reference.verses.trim()}';
  }

  LanguageOption _previewLanguageOption() {
    return _languageOptionForApiLanguage(widget.language) ??
        _languageOptionForCode(defaultLanguage);
  }

  bool _previewWithDiacritics() {
    final option = _previewLanguageOption();
    if (option.code != 'arabic') {
      return true;
    }
    return widget.withDiacritics ?? !_isArabicWithoutDiacritics(widget.version);
  }

  String _previewVersionForRequest() {
    final option = _previewLanguageOption();
    if (option.code == 'arabic') {
      return _resolveArabicVersion(
            option,
            withDiacritics: _previewWithDiacritics(),
            preferredVersion: widget.version,
          ) ??
          widget.version;
    }
    return widget.version;
  }

  String _previewHeading() {
    final languageOption = _languageOptionForApiLanguage(widget.language);
    final book = widget.displayBook.trim().isNotEmpty
        ? widget.displayBook.trim()
        : _displayGospelName(
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
    final displayedLabel = widget.labelOverride.trim();
    final reference = displayedLabel.isNotEmpty
        ? displayedLabel
        : _compactReferenceLabel([widget.reference]);
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
    final generation = ++_previewLoadGeneration;

    final verseParam = reference.verses.trim().isEmpty
        ? '1'
        : reference.verses.trim();

    try {
      final verses = _normalizeVerseLinesForDisplay(
        await _ApiCache.fetchVerseRange(
          language: widget.language,
          version: _previewVersionForRequest(),
          book: bookParam,
          chapter: reference.chapter,
          verse: verseParam,
        ),
        language: _previewLanguageOption(),
        withDiacritics: _previewWithDiacritics(),
      );
      if (!mounted || generation != _previewLoadGeneration) {
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
    } catch (_) {
      if (!mounted || generation != _previewLoadGeneration) {
        return;
      }
      setState(() {
        _previewLoaded = false;
        _loadingPreview = false;
        _previewError = _previewLanguageOption().ui.unableToOpenReference;
      });
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
                    textDirection: _previewLanguageOption().direction,
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
        oldWidget.withDiacritics != widget.withDiacritics ||
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
    _previewDelay.cancel();
    _cancelHideTimer();
    _isHovered = false;
    _isTriggerHovered = false;
    _isPreviewHovered = false;
    _loadingPreview = false;
    _previewLoaded = false;
    _previewLoadGeneration++;
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
          BrowserRouteLink(
            uri: uri,
            openInNewTab: widget.openInNewTab,
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
    _previewLoadGeneration++;
    _previewDelay.cancel();
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
    final browserFindText = formatVerseRef(text, widget.language);
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
          _schedulePreviewShow();
        }
      },
      onExit: (_) {
        _isTriggerHovered = false;
        _previewDelay.cancel();
        _updateHover(false);
        if (widget.enableHoverPreview) {
          _schedulePreviewHide();
        }
      },
      child: KeyedSubtree(
        key: _anchorKey,
        child: BrowserRouteLink(
          uri: text.isEmpty ? null : uri,
          openInNewTab: widget.openInNewTab,
          builder: (context, followLink) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: followLink,
            child: Align(
              alignment: alignment,
              widthFactor: 1,
              heightFactor: 1,
              child: Padding(
                padding: widget.compact
                    ? EdgeInsets.zero
                    : const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: BrowserFindText(
                  text: browserFindText.text,
                  style: _isHovered ? hoverStyle : baseStyle,
                  textAlign: widget.textAlign,
                  textDirection: browserFindText.dir ?? widget.textDirection,
                  maxLines: 1,
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
      ),
    );

    final helperText = widget.tooltipMessage.trim();
    if (text.isEmpty || helperText.isEmpty) {
      return link;
    }

    if (!widget.showHoverTooltip) {
      return Semantics(hint: helperText, child: link);
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
    this.topicLanguage = '',
    this.displayBook = '',
    this.language = defaultLanguage,
    this.version = defaultVersion,
    this.tooltipMessage = 'Click to read in chapter',
    this.withDiacritics,
    this.topicId = '',
    this.topicNumber = '',
    this.sourceContext = '',
    this.gospel = '',
    this.openInNewTab = false,
  });

  final List<GospelReference> references;
  final Widget child;
  final TextDirection textDirection;
  final String topicName;
  final String topicLanguage;
  final String displayBook;
  final String language;
  final String version;
  final String tooltipMessage;
  final bool? withDiacritics;
  final String topicId;
  final String topicNumber;
  final String sourceContext;
  final String gospel;
  final bool openInNewTab;

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
  final _previewDelay = _ReferencePreviewDelay();
  final GlobalKey _anchorKey = GlobalKey();
  final GlobalKey _previewKey = GlobalKey();
  Size _previewSize = const Size(320, 260);
  bool _pendingPreviewMeasurement = false;
  int _previewLoadGeneration = 0;
  Map<String, _ReferencePreviewCache> _previewResults =
      const <String, _ReferencePreviewCache>{};

  String _bookParam(GospelReference reference) {
    return reference.bookId.trim().isNotEmpty
        ? reference.bookId.trim()
        : reference.book.trim();
  }

  Uri? _buildReferenceUri(GospelReference reference) {
    final displayBook = widget.displayBook.trim().isNotEmpty
        ? widget.displayBook.trim()
        : reference.book.trim();
    final bookParam = _bookParam(reference);
    if (bookParam.isEmpty || reference.chapter <= 0) {
      return null;
    }

    final primaryLanguage = _previewLanguageOption();
    final queryParameters = <String, String>{
      'menuLanguage': primaryLanguage.code,
      'book': bookParam,
      'bookDisplay': displayBook,
      'chapter': reference.chapter.toString(),
      'topicLanguage': primaryLanguage.code,
      'bibleLanguage': primaryLanguage.apiLanguage,
      'language': primaryLanguage.apiLanguage,
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
    if (widget.topicNumber.trim().isNotEmpty) {
      queryParameters['topicNumber'] = widget.topicNumber.trim();
    }
    if (widget.sourceContext.trim().isNotEmpty) {
      queryParameters['source'] = widget.sourceContext.trim();
    }
    if (widget.gospel.trim().isNotEmpty) {
      queryParameters['gospel'] = widget.gospel.trim();
    }

    return Uri(path: '/reference', queryParameters: queryParameters);
  }

  Uri? _buildPreviewReferenceUri(List<GospelReference> references) {
    if (references.isEmpty) {
      return null;
    }
    final uri = _buildReferenceUri(references.first);
    if (uri == null || references.length == 1) {
      return uri;
    }

    final first = references.first;
    final isOneSameChapterSelection = references
        .skip(1)
        .every(
          (reference) =>
              _bookParam(reference) == _bookParam(first) &&
              reference.chapter == first.chapter &&
              ReferenceSeparator.fromSymbol(reference.separatorBefore) ==
                  ReferenceSeparator.sameChapter,
        );
    if (!isOneSameChapterSelection) {
      return uri;
    }

    final verses = references
        .map((reference) => reference.verses.trim())
        .where((value) => value.isNotEmpty)
        .join(',');
    return uri.replace(
      queryParameters: <String, String>{
        ...uri.queryParameters,
        if (verses.isNotEmpty) 'verses': verses,
        'label': _compactReferenceLabel(references),
      },
    );
  }

  LanguageOption _previewLanguageOption() {
    return _languageOptionForApiLanguage(widget.language) ??
        _languageOptionForCode(defaultLanguage);
  }

  bool _previewWithDiacritics() {
    final option = _previewLanguageOption();
    if (option.code != 'arabic') {
      return true;
    }
    return widget.withDiacritics ?? !_isArabicWithoutDiacritics(widget.version);
  }

  String _previewVersionForRequest() {
    final option = _previewLanguageOption();
    if (option.code == 'arabic') {
      return _resolveArabicVersion(
            option,
            withDiacritics: _previewWithDiacritics(),
            preferredVersion: widget.version,
          ) ??
          widget.version;
    }
    return widget.version;
  }

  String _previewCacheKey(GospelReference reference) {
    return '${widget.language}|${_previewVersionForRequest()}|${_previewWithDiacritics()}|${_bookParam(reference)}|${reference.chapter}|${reference.verses.trim()}';
  }

  String _previewHeading(List<GospelReference> references) {
    final reference = references.first;
    final languageOption = _languageOptionForApiLanguage(widget.language);
    final book = widget.displayBook.trim().isNotEmpty
        ? widget.displayBook.trim()
        : _displayGospelName(
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
    final formattedReference = _compactReferenceLabel(references);
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

  List<List<GospelReference>> _previewGroups(List<GospelReference> references) {
    return groupReferencePreviewSections<GospelReference>(
      references,
      separatorBefore: (reference) =>
          ReferenceSeparator.fromSymbol(reference.separatorBefore),
    );
  }

  void _cancelHideTimer() {
    _hidePreviewTimer?.cancel();
    _hidePreviewTimer = null;
  }

  void _schedulePreviewShow() {
    if (_previewEntry != null) {
      return;
    }
    _previewDelay.schedule(() {
      if (!mounted || !_isTriggerHovered) {
        return;
      }
      _showPreview();
      _loadPreview();
    });
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
    final language = widget.language;
    final version = _previewVersionForRequest();
    final languageOption = _previewLanguageOption();
    final withDiacritics = _previewWithDiacritics();
    final book = _bookParam(reference);
    final verseParam = reference.verses.trim().isEmpty
        ? '1'
        : reference.verses.trim();

    try {
      final cache = _ReferencePreviewCache(
        verses: _normalizeVerseLinesForDisplay(
          await _ApiCache.fetchVerseRange(
            language: language,
            version: version,
            book: book,
            chapter: reference.chapter,
            verse: verseParam,
          ),
          language: languageOption,
          withDiacritics: withDiacritics,
        ),
        error: null,
      );
      _ReferenceHoverTextState._previewCache[cacheKey] = cache;
      return MapEntry(cacheKey, cache);
    } catch (_) {
      return MapEntry(
        cacheKey,
        _ReferencePreviewCache(
          verses: const <_VerseLine>[],
          error: languageOption.ui.unableToOpenReference,
        ),
      );
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
    final generation = ++_previewLoadGeneration;

    final loadedResults = await Future.wait(
      missingReferences.map(_fetchPreview),
    );
    if (!mounted || generation != _previewLoadGeneration) {
      return;
    }

    final results = <String, _ReferencePreviewCache>{...cachedResults};
    for (final entry in loadedResults) {
      results[entry.key] = entry.value;
    }

    setState(() {
      _previewLoaded = !results.values.any((cache) => cache.error != null);
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
                    textDirection: _previewLanguageOption().direction,
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
        oldWidget.withDiacritics != widget.withDiacritics ||
        oldWidget.references.length != widget.references.length) {
      return true;
    }
    for (var i = 0; i < widget.references.length; i++) {
      final oldReference = oldWidget.references[i];
      final reference = widget.references[i];
      if (oldReference.book != reference.book ||
          oldReference.bookId != reference.bookId ||
          oldReference.chapter != reference.chapter ||
          oldReference.verses != reference.verses ||
          oldReference.separatorBefore != reference.separatorBefore) {
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
    _previewDelay.cancel();
    _cancelHideTimer();
    _isTriggerHovered = false;
    _isPreviewHovered = false;
    _loadingPreview = false;
    _previewLoaded = false;
    _previewLoadGeneration++;
    _previewResults = const <String, _ReferencePreviewCache>{};
  }

  Widget _buildPreviewHeader(
    ThemeData theme,
    List<GospelReference> references,
  ) {
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
    final uri = _buildPreviewReferenceUri(references);
    return Row(
      textDirection: widget.textDirection,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            _previewHeading(references),
            style: headingStyle,
            textAlign: TextAlign.start,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (helperText.isNotEmpty && uri != null) ...[
          const SizedBox(width: 8),
          BrowserRouteLink(
            uri: uri,
            openInNewTab: widget.openInNewTab,
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
    List<GospelReference> references,
    int index,
  ) {
    final bodyStyle = theme.textTheme.bodySmall?.copyWith(height: 1.4);
    final numberStyle = bodyStyle?.copyWith(fontWeight: FontWeight.w600);
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
          _buildPreviewHeader(theme, references),
          const SizedBox(height: 8),
          for (
            var referenceIndex = 0;
            referenceIndex < references.length;
            referenceIndex++
          ) ...[
            if (referenceIndex > 0 &&
                ReferenceSeparator.fromSymbol(
                      references[referenceIndex].separatorBefore,
                    ) ==
                    ReferenceSeparator.sameChapter)
              SizedBox(
                key: ValueKey<String>(
                  'same-chapter-selection-gap-$referenceIndex',
                ),
                height: 10,
              ),
            Builder(
              builder: (context) {
                final cache =
                    _previewResults[_previewCacheKey(
                      references[referenceIndex],
                    )];
                final error = cache?.error;
                if (error != null) {
                  return Text(
                    error,
                    style: bodyStyle?.copyWith(color: theme.colorScheme.error),
                  );
                }
                final verses = cache?.verses ?? const <_VerseLine>[];
                if (verses.isEmpty) {
                  return Text(noPassageText, style: bodyStyle);
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final verse in verses)
                      _buildPreviewVerse(verse, theme, bodyStyle, numberStyle),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPreviewContent(ThemeData theme) {
    final references = _previewReferences();
    final groups = _previewGroups(references);
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
                  for (var i = 0; i < groups.length; i++)
                    _buildPreviewSection(theme, groups[i], i),
                ],
              ),
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _previewLoadGeneration++;
    _previewDelay.cancel();
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
        _schedulePreviewShow();
      },
      onExit: (_) {
        _isTriggerHovered = false;
        _previewDelay.cancel();
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
    required this.topicLanguage,
    this.topicName = '',
    this.referenceLabelOverride = '',
    this.source = '',
    this.topicId = '',
    this.topicNumber = '',
    this.gospel = '',
    this.comparisonState = '',
  });

  final String displayBook;
  final String bookId;
  final int chapter;
  final String verses;
  final String language;
  final String version;
  final String topicLanguage;
  final String topicName;
  final String referenceLabelOverride;
  final String source;
  final String topicId;
  final String topicNumber;
  final String gospel;
  final String comparisonState;

  @override
  State<ReferenceViewerPage> createState() => _ReferenceViewerPageState();
}

class ChapterNav extends StatelessWidget {
  const ChapterNav({
    super.key,
    required this.bookTitle,
    required this.chapter,
    required this.previousBookUri,
    required this.previousChapterUri,
    required this.nextChapterUri,
    required this.nextBookUri,
  });

  final String bookTitle;
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
    final chapterTitle = '${labels.chapter} $chapterNumber';
    final title = bookTitle.trim().isEmpty
        ? chapterTitle
        : '${bookTitle.trim()} — $chapterTitle';

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
      return BrowserRouteLink(
        uri: uri,
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
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(
          textDirection: TextDirection.ltr,
          children: [
            ...leadingControls,
            Expanded(
              child: Directionality(
                textDirection: uiLanguage.direction,
                child: Text(
                  title,
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

class TranslationPanelCard extends StatelessWidget {
  const TranslationPanelCard({
    super.key,
    required this.title,
    required this.textDirection,
    required this.body,
    this.headerControls = const <Widget>[],
    this.isMain = false,
  });

  final String title;
  final TextDirection textDirection;
  final Widget body;
  final List<Widget> headerControls;
  final bool isMain;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
          textDirection: textDirection,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isMain) ...[
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compactHeader = constraints.maxWidth < 430;
                    if (compactHeader) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          titleWidget,
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 4,
                            runSpacing: 2,
                            textDirection: textDirection,
                            children: headerControls,
                          ),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: titleWidget),
                        Wrap(
                          spacing: 4,
                          runSpacing: 2,
                          textDirection: textDirection,
                          children: headerControls,
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 8),
              ],
              body,
            ],
          ),
        ),
      ),
    );
  }
}

class ReaderChapterLayout extends StatelessWidget {
  const ReaderChapterLayout({
    super.key,
    required this.topNavigation,
    required this.bottomNavigation,
    required this.panels,
    required this.textDirection,
    this.status = const <Widget>[],
  });

  final Widget topNavigation;
  final Widget bottomNavigation;
  final List<Widget> panels;
  final TextDirection textDirection;
  final List<Widget> status;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final count = panels.length;
        final spacing = availableWidth >= 760 ? 14.0 : 10.0;
        final columnCount = availableWidth < 760 || count <= 1
            ? 1
            : (availableWidth < 1180 ? math.min(2, count) : math.min(3, count));
        final maxSinglePanelWidth = count <= 1 ? 760.0 : availableWidth;
        final contentWidth = count <= 1
            ? math.min(availableWidth, maxSinglePanelWidth)
            : availableWidth;
        final itemWidth = columnCount == 1
            ? math.min(contentWidth, maxSinglePanelWidth)
            : (contentWidth - (spacing * (columnCount - 1))) / columnCount;

        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: contentWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                topNavigation,
                const SizedBox(height: 4),
                ...status,
                Wrap(
                  alignment: WrapAlignment.center,
                  runAlignment: WrapAlignment.center,
                  spacing: spacing,
                  runSpacing: spacing,
                  textDirection: textDirection,
                  children: [
                    for (final panel in panels)
                      SizedBox(width: itemWidth, child: panel),
                  ],
                ),
                const SizedBox(height: 12),
                bottomNavigation,
              ],
            ),
          ),
        );
      },
    );
  }
}

@visibleForTesting
bool shouldShowStickyChapterNavigation({
  required Rect viewport,
  required Rect topNavigation,
  required Rect bottomNavigation,
}) {
  return topNavigation.top <= viewport.top + 0.5 &&
      bottomNavigation.top > viewport.bottom - 0.5;
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
  final ScrollController _readerScrollController = ScrollController();
  final GlobalKey _readerViewportKey = GlobalKey();
  final GlobalKey _topChapterNavigationKey = GlobalKey();
  final GlobalKey _bottomChapterNavigationKey = GlobalKey();
  bool _stickyNavigationVisible = false;
  bool _stickyMeasurementScheduled = false;
  double _stickyNavigationWidth = _maxReadingContentWidth;

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
    _readerScrollController.addListener(_scheduleStickyNavigationUpdate);
    final savedPreferences = UserProfileController.instance.preferences;
    _textScale = ZoomController.instance.textScale;
    _showTopicNames = savedPreferences.showTopicNamesInChapter;
    _interlinearView = savedPreferences.interlinearEnabled;
    _syncSelectedContentLanguage(_languageOption);
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
    }
    _hydrateComparisonsFromRoute();
    _syncComparisonDiacriticsWithGlobal();
    _initializeDiacriticsPreferenceAndLoad();
    _refreshLanguagesForToolbar();
    unawaited(_refreshTopicLanguageMetadata());
  }

  @override
  void dispose() {
    _readerScrollController.removeListener(_scheduleStickyNavigationUpdate);
    _readerScrollController.dispose();
    super.dispose();
  }

  void _scheduleStickyNavigationUpdate() {
    if (_stickyMeasurementScheduled || !mounted) {
      return;
    }
    _stickyMeasurementScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _stickyMeasurementScheduled = false;
      _updateStickyNavigation();
    });
  }

  void _updateStickyNavigation() {
    if (!mounted) {
      return;
    }
    final viewportBox =
        _readerViewportKey.currentContext?.findRenderObject() as RenderBox?;
    final topBox =
        _topChapterNavigationKey.currentContext?.findRenderObject()
            as RenderBox?;
    final bottomBox =
        _bottomChapterNavigationKey.currentContext?.findRenderObject()
            as RenderBox?;
    if (viewportBox == null ||
        topBox == null ||
        bottomBox == null ||
        !viewportBox.hasSize ||
        !topBox.hasSize ||
        !bottomBox.hasSize) {
      if (_stickyNavigationVisible) {
        setState(() => _stickyNavigationVisible = false);
      }
      return;
    }

    Rect globalRect(RenderBox box) => box.localToGlobal(Offset.zero) & box.size;
    final viewportRect = globalRect(viewportBox);
    final topRect = globalRect(topBox);
    final bottomRect = globalRect(bottomBox);
    final shouldShow = shouldShowStickyChapterNavigation(
      viewport: viewportRect,
      topNavigation: topRect,
      bottomNavigation: bottomRect,
    );
    final measuredWidth = topBox.size.width;
    if (shouldShow != _stickyNavigationVisible ||
        (measuredWidth - _stickyNavigationWidth).abs() > 0.5) {
      setState(() {
        _stickyNavigationVisible = shouldShow;
        _stickyNavigationWidth = measuredWidth;
      });
    }
  }

  bool _handleReaderScrollNotification(ScrollNotification notification) {
    _scheduleStickyNavigationUpdate();
    return false;
  }

  Future<void> _refreshTopicLanguageMetadata() async {
    try {
      await _loadTopicLanguages();
      if (mounted) setState(() {});
    } catch (_) {
      // Keep the bundled table-label fallback when metadata cannot be loaded.
    }
  }

  Future<void> _initializeDiacriticsPreferenceAndLoad() async {
    final withDiacritics = await _loadArabicDiacriticsPreference();
    if (!mounted) {
      return;
    }
    setState(() {
      _withDiacritics = withDiacritics;
      _syncComparisonDiacriticsWithGlobal();
    });
    await _loadChapter();
    if (_isHarmonySource) {
      await _loadHarmonyTopics();
    }
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

  void _syncComparisonDiacriticsWithGlobal() {
    for (final entry in _comparisons) {
      if (entry.language.code == 'arabic') {
        entry.withDiacritics = _withDiacritics;
      }
    }
  }

  bool get _hasArabicTextInvolved =>
      _languageOption.code == 'arabic' ||
      _comparisons.any((entry) => entry.language.code == 'arabic');

  bool get _canDisplayDiacriticsForVisibleArabicText {
    if (_languageOption.code == 'arabic' &&
        _canDisplayArabicDiacritics(_languageOption, _selectedVersion)) {
      return true;
    }
    return _comparisons.any(
      (entry) =>
          entry.language.code == 'arabic' &&
          _canDisplayArabicDiacritics(entry.language, entry.version),
    );
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
            : (language.code == 'arabic' ? _withDiacritics : true);
        parsed.add(
          _ComparisonPassage(
            language: language,
            version: version,
            scopeMode: scopeMode,
            scopeStartVerse: scopeStartVerse,
            scopeEndVerse: scopeEndVerse,
            withDiacritics: language.code == 'arabic'
                ? _withDiacritics
                : withDiacritics,
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
      'menuLanguage': _languageOption.code,
      'book': book,
      'bookDisplay': book,
      'chapter': chapter.toString(),
      'topicLanguage': _languageOption.code,
      'bibleLanguage': _activeApiLanguage,
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
      if (widget.topicNumber.trim().isNotEmpty) {
        queryParameters['topicNumber'] = widget.topicNumber.trim();
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
    try {
      final list = await _ApiCache.fetchTopics(
        topicLanguage: widget.topicLanguage,
      );
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
    final menuLanguage = MenuLanguageScope.of(context);
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
      final option = _languageOptionForApiLanguage(apiLanguage);
      final displayLanguage = localizedLanguageNameForMenu(
        menuLanguage,
        option?.code ?? apiLanguage,
        option?.label ?? apiLanguage,
      );
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
      final verses = _normalizeVerseLinesForDisplay(
        await _ApiCache.fetchChapter(
          language: _activeApiLanguage,
          version: _activeVersion,
          book: bookParam,
          chapter: widget.chapter,
        ),
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
    if (!_hasArabicTextInvolved) {
      return;
    }
    final next = !_withDiacritics;
    if (next && !_canDisplayDiacriticsForVisibleArabicText) {
      return;
    }
    setState(() {
      _withDiacritics = next;
      _syncComparisonDiacriticsWithGlobal();
    });
    await _persistArabicDiacriticsPreference(next);
    await _loadChapter();
    if (_isHarmonySource) {
      await _loadHarmonyTopics();
    }
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
                withDiacritics: _withDiacritics,
                preferredVersion: versionId,
              ) ??
              _sanitizeVersionForLanguage(language, versionId))
        : _sanitizeVersionForLanguage(language, versionId);
    if (language.code == _languageOption.code && sanitized == _activeVersion) {
      return;
    }

    try {
      await _persistLanguageVersion(
        language,
        sanitized,
        withDiacritics: language.code == 'arabic' ? _withDiacritics : null,
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
      'menuLanguage': language.code,
      'book': _bookParameter,
      'bookDisplay': widget.displayBook.trim().isNotEmpty
          ? widget.displayBook.trim()
          : _bookParameter,
      'chapter': widget.chapter.toString(),
      'topicLanguage': language.code,
      'bibleLanguage': language.apiLanguage,
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
    if (widget.topicNumber.trim().isNotEmpty) {
      queryParameters['topicNumber'] = widget.topicNumber.trim();
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

  ChapterNav _buildChapterNavigation({Key? key}) {
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
      key: key,
      bookTitle: _harmonyAppBarTitle,
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
        _buildChapterNavigation(key: _topChapterNavigationKey),
        const SizedBox(height: 4),
        ..._buildVerseGroupWidgets(
          verses: _chapterVerses,
          theme: theme,
          language: _languageOption,
          version: _activeVersion,
          registerScrollTargets: true,
        ),
        const SizedBox(height: 12),
        _buildChapterNavigation(key: _bottomChapterNavigationKey),
      ],
    );
  }

  String _currentVersionLabel() {
    final version = _activeVersion;
    final option = _languageOptionForVersion(version);
    final match = _versionOptionFor(option, version);
    return match?.label ?? option.versionLabel;
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
    final profileController = UserProfileController.instance;
    if (profileController.profile != null) {
      unawaited(
        _updateUserPreferencesBestEffort(
          profileController.preferences.copyWith(showTopicNamesInChapter: next),
        ),
      );
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
    final profileController = UserProfileController.instance;
    if (profileController.profile != null) {
      unawaited(
        _updateUserPreferencesBestEffort(
          profileController.preferences.copyWith(
            interlinearEnabled: _interlinearView,
          ),
        ),
      );
    }
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
    final menuLanguage = MenuLanguageScope.of(context);

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

    showBrowserSafeDialog<void>(
      context: context,
      builder: (context) {
        return DraggableDialogShell(
          maxWidth: 720,
          maxHeight: 680,
          title: Text(
            labels.selectTranslationToAdd,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          headerTrailing: IconButton(
            tooltip: labels.cancel,
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
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

              if (!choices.any((choice) => choice.version == selectedVersion) &&
                  choices.isNotEmpty) {
                selectedVersion = choices.first.version;
              }

              return Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
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
                              child: Text(
                                localizedLanguageNameForMenu(
                                  menuLanguage,
                                  option.code,
                                  option.label,
                                ),
                              ),
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
      withDiacritics: option.code == 'arabic' ? _withDiacritics : true,
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
      final comparisonVersion = _comparisonVersion(
        entry.language,
        entry.version,
        withDiacritics: entry.withDiacritics,
      );
      final verses = _normalizeVerseLinesForDisplay(
        await _ApiCache.fetchChapter(
          language: entry.language.apiLanguage,
          version: comparisonVersion,
          book: bookParam,
          chapter: widget.chapter,
        ),
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

  Future<void> _showComparisonColumnSelector(_ComparisonPassage entry) async {
    final labels = _labels;
    final menuLanguage = MenuLanguageScope.of(context);
    LanguageOption selectedLanguage = entry.language;
    String selectedVersion = _sanitizeVersionForLanguage(
      selectedLanguage,
      entry.version,
    );

    await showBrowserSafeDialog<void>(
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
                            child: Text(
                              localizedLanguageNameForMenu(
                                menuLanguage,
                                option.code,
                                option.label,
                              ),
                            ),
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
                      entry.withDiacritics = selectedLanguage.code == 'arabic'
                          ? _withDiacritics
                          : true;
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
    final menuLanguage = MenuLanguageScope.of(context);
    final title =
        '${localizedLanguageNameForMenu(menuLanguage, language.code, language.label)} · $versionLabel';
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
      TextButton(
        onPressed: entry == null
            ? null
            : () => _showComparisonColumnSelector(entry),
        child: Text(labels.changeTranslation),
      ),
      if (entry != null)
        IconButton(
          onPressed: () => _removeComparison(entry),
          icon: const Icon(Icons.close),
          tooltip: labels.removeComparison,
        ),
    ];
    return TranslationPanelCard(
      key: ValueKey<String>(
        isMain ? 'translation-panel-main' : 'translation-panel-comparison',
      ),
      title: title,
      textDirection: language.direction,
      headerControls: headerControls,
      isMain: isMain,
      body: body,
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
    final panels = <Widget>[
      _buildTranslationPanel(
        theme: theme,
        language: _languageOption,
        version: _activeVersion,
        verses: _chapterVerses,
        isMain: true,
      ),
      for (final entry in _comparisons)
        _buildTranslationPanel(
          theme: theme,
          language: entry.language,
          version: _comparisonVersion(
            entry.language,
            entry.version,
            withDiacritics: entry.withDiacritics,
          ),
          verses: _scopedComparisonVerses(entry),
          entry: entry,
        ),
    ];

    return ReaderChapterLayout(
      topNavigation: _buildChapterNavigation(key: _topChapterNavigationKey),
      bottomNavigation: _buildChapterNavigation(
        key: _bottomChapterNavigationKey,
      ),
      panels: panels,
      textDirection: _languageOption.direction,
      status: [
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
    final translations = <InterlinearTranslation>[
      InterlinearTranslation(
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
      final menuLanguage = MenuLanguageScope.of(context);
      final label =
          '${localizedLanguageNameForMenu(menuLanguage, entry.language.code, entry.language.label)} · $versionLabel';
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
        InterlinearTranslation(
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
          (number) => InterlinearVerseGroup(
            verseNumber: number,
            translations: translations,
            language: _activeApiLanguage,
            version: _activeVersion,
            textScale: _textScale,
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

  String get _harmonyAppBarTitle {
    final book = _displayBookLabel.isNotEmpty
        ? _displayBookLabel
        : _currentCanonicalBook;
    if (book.isEmpty) {
      return _labels.reference;
    }
    if (MenuLanguageScope.of(context).code == 'arabic') {
      return 'إنجيل $book';
    }
    return 'Gospel of $book';
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
    final primaryActions = <Widget>[
      _buildAddComparisonButton(),
      _buildInterlinearToggleButton(),
      _buildTopicNamesToggleButton(),
      _buildZoomControl(),
    ].where((button) => button is! SizedBox).toList();
    _scheduleStickyNavigationUpdate();

    return Directionality(
      textDirection: direction,
      child: Column(
        children: [
          Material(
            color: theme.colorScheme.surface,
            elevation: 1,
            surfaceTintColor: theme.colorScheme.surfaceTint,
            child: AppToolbar(
              language: _languageOption,
              version: _activeVersion,
              languages: _primaryLanguageOptions(),
              languagesLoading: _languagesLoading,
              onLanguageChanged: _updateReferenceLanguage,
              onVersionChanged: _updateSelectedVersion,
              onTranslationChanged: _updateReferenceTranslation,
              showDiacriticsToggle: _hasArabicTextInvolved,
              withDiacritics: _withDiacritics,
              diacriticsToggleEnabled:
                  _withDiacritics || _canDisplayDiacriticsForVisibleArabicText,
              onDiacriticsToggled: _toggleReferenceDiacritics,
              primaryActions: primaryActions,
            ),
          ),
          const Divider(height: 0),
          Expanded(
            child: Stack(
              key: _readerViewportKey,
              children: [
                Positioned.fill(
                  child: NotificationListener<ScrollNotification>(
                    onNotification: _handleReaderScrollNotification,
                    child: SingleChildScrollView(
                      controller: _readerScrollController,
                      child: ResponsiveContentShell(
                        maxWidth: _maxPageContentWidth,
                        padding: EdgeInsets.symmetric(
                          horizontal: _responsiveHorizontalInset(
                            MediaQuery.sizeOf(context).width,
                          ),
                          vertical: 8,
                        ),
                        child: Directionality(
                          textDirection: _languageOption.direction,
                          child: _wrapWithTextScale(
                            context,
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_interlinearView &&
                                    _comparisons.isNotEmpty) ...[
                                  Align(
                                    alignment: AlignmentDirectional.topCenter,
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: _maxReadingContentWidth,
                                      ),
                                      child: _buildInterlinearReferenceSection(
                                        theme,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Align(
                                    alignment: AlignmentDirectional.topCenter,
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: _maxReadingContentWidth,
                                      ),
                                      child: _buildChapterSection(theme),
                                    ),
                                  ),
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
                if (_stickyNavigationVisible)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: _stickyNavigationWidth,
                        ),
                        child: SizedBox(
                          key: const ValueKey<String>(
                            'sticky-chapter-navigation',
                          ),
                          width: _stickyNavigationWidth,
                          child: Material(
                            color: theme.scaffoldBackgroundColor,
                            elevation: 2,
                            child: Directionality(
                              textDirection: _languageOption.direction,
                              child: _wrapWithTextScale(
                                context,
                                _buildChapterNavigation(),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
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

class InterlinearTranslation {
  const InterlinearTranslation({
    required this.label,
    required this.direction,
    required this.verses,
  });

  final String label;
  final TextDirection direction;
  final Map<int, String> verses;
}

class InterlinearVerseGroup extends StatelessWidget {
  const InterlinearVerseGroup({
    super.key,
    required this.verseNumber,
    required this.translations,
    required this.language,
    required this.textScale,
    this.version,
    this.textStyle,
    this.labelStyle,
    this.emphasized = false,
  });

  final int verseNumber;
  final List<InterlinearTranslation> translations;
  final String language;
  final double textScale;
  final String? version;
  final TextStyle? textStyle;
  final TextStyle? labelStyle;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scaler = TextScaler.linear(
      textScale.clamp(_zoomMin, _zoomMax).toDouble(),
    );
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
            formatVerseMarker(
              verseNumber,
              language: language,
              version: version,
            ),
            textScaler: scaler,
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
                  textScaler: scaler,
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
  final List<HarmonyReferenceCell> referenceCells;
  final int canonicalOrder;
  final int gospelPresenceMask;
  final Map<Gospel, GospelChronologyAnchor> earliestGospelAnchors;

  Topic({
    required this.id,
    required this.name,
    required this.references,
    this.referenceCells = const <HarmonyReferenceCell>[],
    int? canonicalOrder,
  }) : canonicalOrder = canonicalOrder ?? int.tryParse(id.trim()) ?? 0,
       gospelPresenceMask = _gospelPresenceMask(references),
       earliestGospelAnchors = _earliestGospelAnchors(references);

  factory Topic.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] ?? '').toString();
    final rawOrder =
        json['canonicalOrder'] ??
        json['canonical_order'] ??
        json['topicNumber'] ??
        json['topic_number'] ??
        json['sequence'] ??
        json['order'] ??
        id;
    final referenceCells = _topicReferenceCellsFromJson(json['referenceCells']);
    return Topic(
      id: id,
      name: (json['name'] ?? json['topic'] ?? '').toString().trim(),
      canonicalOrder: _parseReferenceNumber(rawOrder),
      references: referenceCells.isNotEmpty
          ? _flattenReferenceCells(referenceCells)
          : _topicReferencesFromJson(
              json['references'] ?? json['entries'] ?? const <dynamic>[],
            ),
      referenceCells: referenceCells,
    );
  }

  Topic copyWithName(String localizedName) => Topic(
    id: id,
    name: localizedName,
    references: references,
    referenceCells: referenceCells,
    canonicalOrder: canonicalOrder,
  );
}

List<HarmonyReferenceCell> _topicReferenceCellsFromJson(Object? raw) {
  if (raw is! List) return const <HarmonyReferenceCell>[];
  final cells = <HarmonyReferenceCell>[];
  var malformed = false;
  for (final item in raw) {
    if (item is! Map) {
      malformed = true;
      continue;
    }
    try {
      cells.add(HarmonyReferenceCell.fromJson(Map<String, dynamic>.from(item)));
    } on FormatException {
      malformed = true;
    }
  }
  if (malformed) {
    // Never expose a partial structured cell list; use the complete legacy
    // projection when any v2 cell is malformed.
    return const <HarmonyReferenceCell>[];
  }
  return List<HarmonyReferenceCell>.unmodifiable(cells);
}

List<GospelReference> _flattenReferenceCells(List<HarmonyReferenceCell> cells) {
  final references = <GospelReference>[];
  for (var cellIndex = 0; cellIndex < cells.length; cellIndex++) {
    final cell = cells[cellIndex];
    var logicalGroup = 0;
    for (
      var segmentIndex = 0;
      segmentIndex < cell.segments.length;
      segmentIndex++
    ) {
      final segment = cell.segments[segmentIndex];
      if (segmentIndex == 0 ||
          segment.separatorBefore != ReferenceSeparator.continuous) {
        logicalGroup++;
      }
      references.add(
        GospelReference(
          book: cell.book,
          chapter: segment.chapter,
          verses: segment.verses,
          canonicalGospel: Gospel.fromCanonicalName(
            _normalizeGospelName(cell.book),
          ),
          separatorBefore: segment.separatorBefore?.symbol ?? '',
          relation: cell.relation.jsonValue,
          groupId: '${cell.book}|$cellIndex|$logicalGroup',
          sourceOrder: references.length,
        ),
      );
    }
  }
  return references;
}

List<GospelReference> _topicReferencesFromJson(Object? raw) {
  final references = <GospelReference>[];

  void addValue(Object? value, {Gospel? fallbackGospel}) {
    if (value == null) {
      return;
    }
    if (value is List) {
      for (final item in value) {
        addValue(item, fallbackGospel: fallbackGospel);
      }
      return;
    }
    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      final looksLikeReference = map.keys.any(
        const <String>{
          'book',
          'gospel',
          'gospelId',
          'canonicalGospel',
          'chapter',
          'verses',
          'verse',
          'reference',
        }.contains,
      );
      if (looksLikeReference) {
        references.add(
          GospelReference.fromJson(map, fallbackGospel: fallbackGospel),
        );
        return;
      }
      for (final entry in map.entries) {
        final gospel = Gospel.fromCanonicalName(
          _normalizeGospelName(entry.key),
        );
        addValue(entry.value, fallbackGospel: gospel ?? fallbackGospel);
      }
      return;
    }
    final text = value.toString().trim();
    references.add(
      GospelReference.fromLooseReference(text, canonicalGospel: fallbackGospel),
    );
  }

  addValue(raw);
  return references;
}

class GospelReference {
  final String book;
  final int chapter;
  final String verses;
  final String bookId;
  final Gospel? canonicalGospel;
  final String separatorBefore;
  final String relation;
  final String groupId;
  final int sourceOrder;

  const GospelReference({
    required this.book,
    required this.chapter,
    required this.verses,
    this.bookId = '',
    this.canonicalGospel,
    this.separatorBefore = '',
    this.relation = 'single',
    this.groupId = '',
    this.sourceOrder = 0,
  });

  factory GospelReference.fromJson(
    Map<String, dynamic> json, {
    Gospel? fallbackGospel,
  }) {
    final rawChapter = json['chapter'];
    final parsedChapter = rawChapter is int
        ? rawChapter
        : _parseReferenceNumber(rawChapter);
    final rawBookId =
        json['book_id'] ?? json['bookId'] ?? json['documentId'] ?? '';
    final rawCanonicalGospel =
        json['gospel'] ??
        json['gospelId'] ??
        json['canonicalGospel'] ??
        json['canonical_gospel'] ??
        json['canonicalBook'];
    final book = (json['book'] ?? rawCanonicalGospel ?? '').toString().trim();
    final canonicalGospel = Gospel.fromCanonicalName(
      _normalizeGospelName(rawCanonicalGospel?.toString() ?? book),
    );
    return GospelReference(
      book: book.isNotEmpty
          ? book
          : (canonicalGospel ?? fallbackGospel)?.canonicalName ?? '',
      chapter: parsedChapter,
      verses: (json['verses'] ?? json['verse'] ?? json['reference'] ?? '')
          .toString()
          .trim(),
      bookId: rawBookId.toString().trim(),
      canonicalGospel: canonicalGospel ?? fallbackGospel,
      separatorBefore: (json['separatorBefore'] ?? '').toString().trim(),
      relation: (json['relation'] ?? 'single').toString().trim(),
      groupId: (json['groupId'] ?? '').toString().trim(),
      sourceOrder: _parseReferenceNumber(json['sourceOrder']),
    );
  }

  factory GospelReference.fromLooseReference(
    String value, {
    Gospel? canonicalGospel,
  }) {
    final normalized = _normalizeReferenceDigits(value.trim());
    final separatorIndex = normalized.indexOf(':');
    final chapter = separatorIndex < 0
        ? 0
        : int.tryParse(normalized.substring(0, separatorIndex).trim()) ?? 0;
    final verses = separatorIndex < 0
        ? normalized
        : normalized.substring(separatorIndex + 1).trim();
    return GospelReference(
      book: canonicalGospel?.canonicalName ?? '',
      chapter: chapter,
      verses: verses,
      canonicalGospel: canonicalGospel,
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

class _ApiCache {
  static Future<List<Topic>>? _canonicalTopics;
  static final Map<String, Future<Map<String, String>>> _topicLocalizations =
      {};
  static final Map<String, Future<List<Topic>>> _topicsByLanguage = {};
  static final Map<String, Future<List<_VerseLine>>> _chapters = {};
  static final Map<String, Future<List<_VerseLine>>> _verseRanges = {};

  static String _key(List<Object?> parts) {
    return parts.map((part) => (part ?? '').toString().trim()).join('|');
  }

  static void clear() {
    _canonicalTopics = null;
    _topicLocalizations.clear();
    _topicsByLanguage.clear();
    _chapters.clear();
    _verseRanges.clear();
  }

  static Future<T> _cached<T>(
    Map<String, Future<T>> cache,
    String key,
    Future<T> Function() loader,
  ) async {
    final cached = cache[key];
    if (cached != null) {
      return cached;
    }

    final future = loader();
    cache[key] = future;
    try {
      return await future;
    } catch (_) {
      if (identical(cache[key], future)) {
        cache.remove(key);
      }
      rethrow;
    }
  }

  static Future<List<Topic>> fetchTopics({required String topicLanguage}) {
    final normalized = topicLanguage.trim().toLowerCase();
    final key = _key(['topics', normalized]);
    return _cached(_topicsByLanguage, key, () async {
      final canonical = await _fetchCanonicalTopics();
      final localizedNames = await _fetchTopicLocalization(normalized);
      return canonical
          .map(
            (topic) =>
                topic.copyWithName(localizedNames[topic.id] ?? topic.name),
          )
          .toList(growable: false);
    });
  }

  static Future<List<Topic>> _fetchCanonicalTopics() {
    final cached = _canonicalTopics;
    if (cached != null) return cached;
    final future = () async {
      final uri = Uri.parse('$apiBaseUrl/harmony/topics');
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        throw Exception('Error ${response.statusCode}');
      }
      final decoded = json.decode(response.body);
      final rawTopics = decoded is Map ? decoded['topics'] : null;
      if (rawTopics is! List) {
        return const <Topic>[];
      }
      return rawTopics
          .whereType<Map>()
          .map((item) => Topic.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false);
    }();
    _canonicalTopics = future;
    return future.catchError((Object error) {
      if (identical(_canonicalTopics, future)) _canonicalTopics = null;
      throw error;
    });
  }

  static Future<Map<String, String>> _fetchTopicLocalization(String language) {
    final key = _key(['topic-localization', language]);
    return _cached(_topicLocalizations, key, () async {
      final uri = Uri.parse(
        '$apiBaseUrl/topic-localizations/${Uri.encodeComponent(language)}',
      );
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        throw Exception('Error ${response.statusCode}');
      }
      final decoded = json.decode(response.body);
      final rawTopics = decoded is Map ? decoded['topics'] : null;
      if (rawTopics is! List) return const <String, String>{};
      return <String, String>{
        for (final item in rawTopics.whereType<Map>())
          if ((item['id'] ?? '').toString().trim().isNotEmpty)
            (item['id'] ?? '').toString().trim(): (item['name'] ?? '')
                .toString()
                .trim(),
      };
    });
  }

  static Future<List<_VerseLine>> fetchChapter({
    required String language,
    required String version,
    required String book,
    required int chapter,
  }) {
    final key = _key(['chapter', language, version, book, chapter]);
    return _cached(_chapters, key, () async {
      final uri = Uri.parse('$apiBaseUrl/get_chapter').replace(
        queryParameters: {
          'language': language,
          'version': version,
          'book': book,
          'chapter': chapter.toString(),
        },
      );
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        throw Exception('Error ${response.statusCode}');
      }
      return _parseVerseLines(response.body);
    });
  }

  static Future<List<_VerseLine>> fetchVerseRange({
    required String language,
    required String version,
    required String book,
    required int chapter,
    required String verse,
  }) {
    final key = _key(['verse', language, version, book, chapter, verse]);
    return _cached(_verseRanges, key, () async {
      final uri = Uri.parse('$apiBaseUrl/get_verse').replace(
        queryParameters: {
          'language': language,
          'version': version,
          'book': book,
          'chapter': chapter.toString(),
          'verse': verse,
        },
      );
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        throw Exception('Error ${response.statusCode}');
      }
      return _parseVerseLines(response.body);
    });
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
                      child: Text(
                        '${localizedLanguageNameForMenu(menuLanguage, option.code, option.label)} · ${option.versionLabel}',
                      ),
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
  bool _withDiacritics = false;
  bool _interlinearView = false;
  double _textScale = 1.0;
  late LanguageOption _languageOption;
  late String _apiVersion;
  late Topic _topic;
  bool _languagesLoading = false;

  LocalizedUiLabels get _labels => MenuLanguageScope.of(context).ui;
  TopicLanguageOption get _topicLanguage => _topicLanguageOptionForCode(
    TopicLanguageSelectionController.instance.languageCode,
  );

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
    final index = orderedGospels.indexOf(_normalizeGospelName(author));
    return index >= 0 && index < _topicLanguage.gospelNames.length
        ? _topicLanguage.gospelNames[index]
        : _normalizeGospelName(author);
  }

  String _entryKey(GospelReference reference) {
    final normalizedBook = _normalizeGospelName(reference.book);
    final bookParam = reference.bookId.trim().isNotEmpty
        ? reference.bookId.trim()
        : reference.book.trim();
    return '${normalizedBook.toLowerCase()}|$bookParam|${reference.chapter}|${reference.verses.trim()}|${reference.separatorBefore}|${reference.groupId}';
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

  void _syncTopicComparisonDiacriticsWithGlobal() {
    for (final template in _comparisonTemplates) {
      if (template.language.code == 'arabic') {
        template.withDiacritics = _withDiacritics;
      }
    }
    for (final entry in _entryComparisons.values.expand((entries) => entries)) {
      if (entry.language.code == 'arabic') {
        entry.withDiacritics = _withDiacritics;
      }
    }
  }

  bool get _hasArabicTextInvolved =>
      _languageOption.code == 'arabic' ||
      _comparisonTemplates.any((entry) => entry.language.code == 'arabic') ||
      _entryComparisons.values
          .expand((entries) => entries)
          .any((entry) => entry.language.code == 'arabic');

  bool get _canDisplayDiacriticsForVisibleArabicText {
    if (_languageOption.code == 'arabic' &&
        _canDisplayArabicDiacritics(_languageOption, _apiVersion)) {
      return true;
    }
    for (final entry in _comparisonTemplates) {
      if (entry.language.code == 'arabic' &&
          _canDisplayArabicDiacritics(entry.language, entry.version)) {
        return true;
      }
    }
    for (final entry in _entryComparisons.values.expand((entries) => entries)) {
      if (entry.language.code == 'arabic' &&
          _canDisplayArabicDiacritics(entry.language, entry.version)) {
        return true;
      }
    }
    return false;
  }

  String get _languageVersionSummary {
    final option = _languageOption;
    final versionLabel = _versionLabel(option.code, _activeVersion);
    final menuLanguage = MenuLanguageScope.of(context);
    return '${localizedLanguageNameForMenu(menuLanguage, option.code, option.label)} · $versionLabel';
  }

  String get _topicToolbarTitle => _numberedTopicTitle(
    _topic,
    _topicLanguage,
    topicNumber: widget.topicNumber,
  );

  @override
  void initState() {
    super.initState();
    final savedPreferences = UserProfileController.instance.preferences;
    _textScale = ZoomController.instance.textScale;
    _interlinearView = savedPreferences.interlinearEnabled;
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
    }
    _syncSelectedContentLanguage(_languageOption);
    _topic = widget.topic;
    _allAuthors =
        _topic.references
            .map((e) => _normalizeGospelName(e.book))
            .toSet()
            .toList()
          ..sort(_compareBooks);
    _selected = widget.initialAuthors.map(_normalizeGospelName).toSet();
    _hydrateTopicComparisonsFromRoute();
    _syncTopicComparisonDiacriticsWithGlobal();
    _initializeDiacriticsPreferenceAndFetchTexts();
    _refreshLanguagesForToolbar();
    unawaited(_refreshTopicLanguageMetadata());
  }

  Future<void> _refreshTopicLanguageMetadata() async {
    try {
      await _loadTopicLanguages();
      if (mounted) setState(() {});
    } catch (_) {
      // Topic content remains usable with the bundled label fallback.
    }
  }

  Future<void> _initializeDiacriticsPreferenceAndFetchTexts() async {
    final withDiacritics = await _loadArabicDiacriticsPreference();
    if (!mounted) {
      return;
    }
    setState(() {
      _withDiacritics = withDiacritics;
      _syncTopicComparisonDiacriticsWithGlobal();
    });
    await fetchTexts(preserveComparisons: true);
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

  Future<void> fetchTexts({
    bool preserveComparisons = false,
    bool reloadAllComparisons = false,
  }) async {
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
          final verseLines = _normalizeVerseLinesForDisplay(
            await _ApiCache.fetchVerseRange(
              language: option.apiLanguage,
              version: version,
              book: bookId,
              chapter: ref.chapter,
              verse: ref.verses.trim().isEmpty ? '1' : ref.verses.trim(),
            ),
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
          final baseTitle = refLabel.isEmpty
              ? displayAuthor
              : _combineBookAndReference(
                  displayAuthor,
                  refLabel,
                  direction,
                  isArabic: option.code == 'arabic',
                );
          final title = baseTitle;
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
        _syncComparisonTemplatesToVisibleReferences(
          reloadMissing: true,
          reloadAll: reloadAllComparisons,
        );
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

  Future<void> _toggleTopicDiacritics() async {
    if (!_hasArabicTextInvolved) {
      return;
    }
    final next = !_withDiacritics;
    if (next && !_canDisplayDiacriticsForVisibleArabicText) {
      return;
    }
    setState(() {
      _withDiacritics = next;
      _syncTopicComparisonDiacriticsWithGlobal();
    });
    await _persistArabicDiacriticsPreference(next);
    await fetchTexts(preserveComparisons: true, reloadAllComparisons: true);
  }

  Future<void> _changeMainTranslation(
    LanguageOption language,
    String version,
  ) async {
    final sanitizedVersion = _sanitizeVersionForLanguage(language, version);
    final nextVersion = language.code == 'arabic'
        ? (_resolveArabicVersion(
                language,
                withDiacritics: _withDiacritics,
                preferredVersion: sanitizedVersion,
              ) ??
              sanitizedVersion)
        : sanitizedVersion;
    await _persistLanguageVersion(
      language,
      nextVersion,
      withDiacritics: language.code == 'arabic' ? _withDiacritics : null,
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
                ? (language.code == 'arabic'
                      ? _withDiacritics
                      : mapItem['withDiacritics'] as bool)
                : (language.code == 'arabic' ? _withDiacritics : true),
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
          withDiacritics: language.code == 'arabic' ? _withDiacritics : true,
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
      final menuLanguage = MenuLanguageScope.of(context);
      final label =
          '${localizedLanguageNameForMenu(menuLanguage, entry.language.code, entry.language.label)} · $versionLabel';
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

    showBrowserSafeDialog<void>(
      context: context,
      builder: (context) {
        return DraggableDialogShell(
          maxWidth: 760,
          maxHeight: 700,
          title: Text(
            labels.selectTranslationToAdd,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          headerTrailing: IconButton(
            tooltip: labels.done,
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
          child: StatefulBuilder(
            builder: (context, setModalState) {
              final choices = buildChoices(selectedLanguage);
              final currentDropdownValue =
                  selectedVersion != null &&
                      choices.any((choice) => choice.version == selectedVersion)
                  ? selectedVersion
                  : null;

              return Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
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
                              child: Text(
                                localizedLanguageNameForMenu(
                                  MenuLanguageScope.of(context),
                                  option.code,
                                  option.label,
                                ),
                              ),
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
                            '${labels.selectVersions} (${localizedLanguageNameForMenu(MenuLanguageScope.of(context), selectedLanguage.code, selectedLanguage.label)})',
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
                                  style: Theme.of(context).textTheme.bodyMedium
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
                                selectedTemplates.map(_comparisonTemplateFrom),
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
      final verses = _normalizeVerseLinesForDisplay(
        await _ApiCache.fetchVerseRange(
          language: entry.language.apiLanguage,
          version: _comparisonVersionFor(
            entry.language,
            entry.version,
            withDiacritics: entry.withDiacritics,
          ),
          book: bookParam,
          chapter: reference.chapter,
          verse: verseParam,
        ),
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
    final menuLanguage = MenuLanguageScope.of(context);
    final header =
        '${localizedLanguageNameForMenu(menuLanguage, entry.language.code, entry.language.label)} · $versionLabel';
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
                  (verse) => _buildComparisonVerse(
                    verse,
                    theme,
                    language: entry.language,
                    version: resolvedVersion,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildComparisonVerse(
    _VerseLine verse,
    ThemeData theme, {
    LanguageOption? language,
    String? version,
  }) {
    final markerLanguage = language ?? _languageOption;
    final markerVersion = version ?? _activeVersion;
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
                    '${formatVerseMarker(verse.number!, language: markerLanguage.apiLanguage, version: markerVersion)}. ',
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
    final profileController = UserProfileController.instance;
    if (profileController.profile != null) {
      unawaited(
        _updateUserPreferencesBestEffort(
          profileController.preferences.copyWith(
            interlinearEnabled: _interlinearView,
          ),
        ),
      );
    }
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
    final translations = <InterlinearTranslation>[
      InterlinearTranslation(
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
      final menuLanguage = MenuLanguageScope.of(context);
      final label =
          '${localizedLanguageNameForMenu(menuLanguage, comparison.language.code, comparison.language.label)} · $versionLabel';
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
        InterlinearTranslation(
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
          (number) => InterlinearVerseGroup(
            verseNumber: number,
            translations: translations,
            language: _languageOption.apiLanguage,
            version: _activeVersion,
            textScale: _textScale,
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
                entry.reference.separatorBefore,
              ].join('|'),
            ),
            reference: entry.reference,
            textStyle: headingStyle,
            textAlign: TextAlign.start,
            textDirection: option.direction,
            topicName: _topic.name,
            topicId: _topic.id.isNotEmpty ? _topic.id : _topic.name,
            topicNumber: widget.topicNumber,
            sourceContext: 'harmony',
            gospel: _normalizeGospelName(entry.reference.book),
            language: option.apiLanguage,
            version: _activeVersion,
            withDiacritics: option.code == 'arabic' ? _withDiacritics : null,
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
        final horizontalPadding = _responsiveHorizontalInset(availableWidth);
        final maxInnerWidth = _responsiveContentWidth(
          availableWidth,
          maxWidth: _maxPageContentWidth,
        );
        final innerWidth = math.max(
          0.0,
          math.min(availableWidth - (horizontalPadding * 2), maxInnerWidth),
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
      textDirection: _topicLanguage.direction,
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
              titleWidget: Directionality(
                textDirection: _topicLanguage.direction,
                child: _buildTopicTitleNavigation(),
              ),
              language: option,
              version: _activeVersion,
              languages: _primaryLanguageOptions(),
              languagesLoading: _languagesLoading,
              onLanguageChanged: _handleToolbarLanguageChanged,
              onVersionChanged: _handleToolbarVersionChanged,
              onTranslationChanged: _changeMainTranslation,
              showDiacriticsToggle: _hasArabicTextInvolved,
              withDiacritics: _withDiacritics,
              diacriticsToggleEnabled:
                  _withDiacritics || _canDisplayDiacriticsForVisibleArabicText,
              onDiacriticsToggled: _toggleTopicDiacritics,
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
            ResponsiveContentShell(
              maxWidth: _maxPageContentWidth,
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
