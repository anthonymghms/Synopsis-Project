import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:gospel_frontend/auth_screen.dart';
import 'package:gospel_frontend/main_scaffold.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'reference_link_opener.dart';

// ---- CONFIGURATION ----
const apiBaseUrl = "http://164.68.108.181:8000"; // Change if your backend is hosted elsewhere
const defaultLanguage = "english";
// Default version key used when fetching topics and verses
const defaultVersion = "kjv";

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

class LanguageOption {
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
  });
}

const List<LanguageOption> kSupportedLanguages = [
  LanguageOption(
    code: 'english',
    label: 'English',
    apiLanguage: 'english',
    apiVersion: 'kjv',
    versionLabel: 'KJV',
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
    apiVersion: 'van dyck',
    versionLabel: 'Van Dyck',
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

LanguageOption _languageOptionForCode(String code) {
  return kSupportedLanguages.firstWhere(
    (option) => option.code == code,
    orElse: () => kSupportedLanguages.first,
  );
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
    return kSupportedLanguages.firstWhere(
      (option) => option.apiLanguage.toLowerCase() == canonical,
    );
  } catch (_) {
    return null;
  }
}

LanguageOption _languageOptionForVersion(String version) {
  final normalized = version.trim().toLowerCase();
  for (final option in kSupportedLanguages) {
    if (option.apiVersion.toLowerCase() == normalized ||
        option.code == normalized ||
        option.label.toLowerCase() == normalized) {
      return option;
    }
  }
  if (normalized == 'arabic2') {
    return _languageOptionForCode('arabic');
  }
  if (normalized.contains('van') && normalized.contains('dyck')) {
    return _languageOptionForCode('arabic');
  }
  return _languageOptionForCode(defaultLanguage);
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
      final version = languageOption.apiVersion;
      final bookDisplay =
          uri.queryParameters['bookDisplay'] ?? uri.queryParameters['book'] ?? '';
      final bookId = uri.queryParameters['bookId'] ?? '';
      final chapter = int.tryParse(uri.queryParameters['chapter'] ?? '') ?? 0;
      final verses = uri.queryParameters['verses'] ?? '';
      final topicName = uri.queryParameters['topic'] ?? '';
      final label = uri.queryParameters['label'] ?? '';

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

class TopicListScreen extends StatefulWidget {
  const TopicListScreen({super.key});
  @override
  State<TopicListScreen> createState() => _TopicListScreenState();
}

class _TopicListScreenState extends State<TopicListScreen> {
  final GlobalKey<_HarmonyTableState> _tableKey =
      GlobalKey<_HarmonyTableState>();
  List<Topic> _topics = [];
  bool _loading = true;
  String? _error;
  String _selectedLanguageCode =
      LanguageSelectionController.instance.languageCode;

  LanguageOption get _languageOption =>
      _languageOptionForCode(_selectedLanguageCode);

  @override
  void initState() {
    super.initState();
    LanguageSelectionController.instance.update(_selectedLanguageCode);
    fetchTopics();
  }

  Future<void> fetchTopics([LanguageOption? option]) async {
    final languageOption = option ?? _languageOption;
    setState(() {
      _loading = true;
      _error = null;
    });
    final uri = Uri.parse('$apiBaseUrl/topics').replace(queryParameters: {
      'language': languageOption.apiLanguage,
      'version': languageOption.apiVersion,
    });
    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        List data = json.decode(response.body);
        if (!mounted) {
          return;
        }
        if (_languageOption.apiLanguage != languageOption.apiLanguage ||
            _languageOption.apiVersion != languageOption.apiVersion) {
          return;
        }
        setState(() {
          _topics = data.map((e) => Topic.fromJson(e)).toList();
          _loading = false;
        });
      } else {
        if (!mounted) {
          return;
        }
        if (_languageOption.apiLanguage != languageOption.apiLanguage ||
            _languageOption.apiVersion != languageOption.apiVersion) {
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
      if (_languageOption.apiLanguage != languageOption.apiLanguage ||
          _languageOption.apiVersion != languageOption.apiVersion) {
        return;
      }
      setState(() {
        _error = "Failed to fetch topics: $e";
        _loading = false;
      });
    }
  }

  Widget _buildLanguageDropdown(BuildContext context) {
    final theme = Theme.of(context);
    return DropdownButtonHideUnderline(
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
            items: kSupportedLanguages
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
  }

  @override
  Widget build(BuildContext context) {
    final languageOption = _languageOption;
    return Directionality(
      textDirection: languageOption.direction,
      child: MainScaffold(
        title: languageOption.title,
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding:
                            const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              languageOption.title,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              languageOption.description,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: Colors.grey.shade700,
                                  ),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 12,
                              runSpacing: 8,
                              children: [
                                _buildLanguageDropdown(context),
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
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AuthorComparisonScreen(
        languageOption: _languageOption,
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
  });

  final List<Topic> topics;
  final ValueChanged<Topic>? onTopicSelected;
  final LanguageOption languageOption;

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

  Widget _buildHeaderCell(String label, TextStyle? style, TextAlign align) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      child: Text(label, style: style, textAlign: align),
    );
  }

  Widget _buildReferenceCell(Topic topic, List<GospelReference> refs,
      TextStyle? style, TextAlign align) {
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
              topicName: topic.name,
              language: widget.languageOption.apiLanguage,
              version: widget.languageOption.apiVersion,
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
                  child: Text(
                    topic.name,
                    style: subjectStyle,
                    textAlign: subjectAlign,
                  ),
                ),
              ),
            ),
            for (final gospel in orderedGospels)
              TableCell(
                verticalAlignment: TableCellVerticalAlignment.top,
                child: _buildReferenceCell(
                  topic,
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
    this.topicName = '',
    this.language = defaultLanguage,
    this.version = defaultVersion,
    this.tooltipMessage = 'Click to view more',
  });

  final GospelReference reference;
  final TextStyle? textStyle;
  final TextAlign textAlign;
  final String topicName;
  final String language;
  final String version;
  final String tooltipMessage;

  @override
  State<ReferenceHoverText> createState() => _ReferenceHoverTextState();
}

class _ReferenceHoverTextState extends State<ReferenceHoverText> {
  bool _isHovered = false;
  bool _isLaunching = false;

  Alignment _alignmentForTextAlign(TextAlign align) {
    switch (align) {
      case TextAlign.center:
        return Alignment.center;
      case TextAlign.right:
        return Alignment.centerRight;
      case TextAlign.left:
      case TextAlign.start:
        return Alignment.centerLeft;
      case TextAlign.end:
        return Alignment.centerRight;
      case TextAlign.justify:
        return Alignment.centerLeft;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseStyle = widget.textStyle ?? theme.textTheme.bodyMedium;
    final hoverStyle = baseStyle?.copyWith(
      color: theme.colorScheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: theme.colorScheme.primary,
    );
    final text = widget.reference.formattedReference;
    final alignment = _alignmentForTextAlign(widget.textAlign);

    return Tooltip(
      message: widget.tooltipMessage,
      waitDuration: const Duration(milliseconds: 150),
      child: MouseRegion(
        cursor:
            text.isEmpty ? SystemMouseCursors.basic : SystemMouseCursors.click,
        onEnter: (_) => _updateHover(true),
        onExit: (_) => _updateHover(false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: text.isEmpty ? null : _handleTap,
          child: Align(
            alignment: alignment,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                text,
                style: _isHovered ? hoverStyle : baseStyle,
                textAlign: widget.textAlign,
                softWrap: true,
              ),
            ),
          ),
        ),
      ),
    );
  }
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
  });

  final String displayBook;
  final String bookId;
  final int chapter;
  final String verses;
  final String language;
  final String version;
  final String topicName;
  final String referenceLabelOverride;

  @override
  State<ReferenceViewerPage> createState() => _ReferenceViewerPageState();
}

class _ReferenceViewerPageState extends State<ReferenceViewerPage> {
  bool _loadingReference = true;
  String? _error;
  List<_VerseLine> _referenceVerses = const <_VerseLine>[];
  bool _loadingChapter = false;
  String? _chapterError;
  List<_VerseLine>? _chapterVerses;

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
    _loadReference();
  }

  String get _bookParameter {
    final trimmedBookId = widget.bookId.trim();
    if (trimmedBookId.isNotEmpty) {
      return trimmedBookId;
    }
    return widget.displayBook.trim();
  }

  String get _referenceHeading {
    final book = widget.displayBook.trim();
    final override = widget.referenceLabelOverride.trim();
    if (override.isNotEmpty) {
      if (book.isEmpty) {
        return override;
      }
      return '$book $override';
    }
    if (book.isEmpty) {
      return 'Reference';
    }
    if (widget.chapter <= 0) {
      return book;
    }
    final verses = widget.verses.trim();
    final base = '$book ${widget.chapter}';
    return verses.isEmpty ? base : '$base:$verses';
  }

  String get _metaSummary {
    final segments = <String>[];
    final version = widget.version.trim();
    if (version.isNotEmpty) {
      final versionOption = _languageOptionForVersion(version);
      if (versionOption.versionLabel.trim().isNotEmpty) {
        segments.add(versionOption.versionLabel);
      } else {
        segments.add(version);
      }
    }
    final apiLanguage = widget.language.trim();
    if (apiLanguage.isNotEmpty) {
      final displayLanguage =
          _languageOptionForApiLanguage(apiLanguage)?.label ?? apiLanguage;
      segments.add(displayLanguage);
    }
    return segments.join(' · ');
  }

  Future<void> _loadReference() async {
    final bookParam = _bookParameter;
    if (widget.chapter <= 0 || bookParam.isEmpty) {
      setState(() {
        _error = 'This reference is missing details needed to load the text.';
        _loadingReference = false;
      });
      return;
    }

    final verseParam = widget.verses.trim().isEmpty ? '1' : widget.verses.trim();

    setState(() {
      _loadingReference = true;
      _error = null;
    });

    try {
      final uri = Uri.parse('$apiBaseUrl/get_verse').replace(queryParameters: {
        'language': widget.language,
        'version': widget.version,
        'book': bookParam,
        'chapter': widget.chapter.toString(),
        'verse': verseParam,
      });
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        throw Exception('Error ${response.statusCode}');
      }
      final verses = _parseVerses(response.body);
      if (!mounted) {
        return;
      }
      setState(() {
        _referenceVerses = verses;
        _loadingReference = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Failed to load reference: $e';
        _loadingReference = false;
      });
    }
  }

  Future<void> _loadFullChapter() async {
    if (_loadingChapter) {
      return;
    }
    final bookParam = _bookParameter;
    if (widget.chapter <= 0 || bookParam.isEmpty) {
      setState(() {
        _chapterError = 'Unable to determine which chapter to load.';
      });
      return;
    }

    setState(() {
      _loadingChapter = true;
      _chapterError = null;
    });

    try {
      final uri = Uri.parse('$apiBaseUrl/get_chapter').replace(queryParameters: {
        'language': widget.language,
        'version': widget.version,
        'book': bookParam,
        'chapter': widget.chapter.toString(),
      });
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        throw Exception('Error ${response.statusCode}');
      }
      final verses = _parseVerses(response.body);
      if (!mounted) {
        return;
      }
      setState(() {
        _chapterVerses = verses;
        _loadingChapter = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _chapterError = 'Failed to load full chapter: $e';
        _loadingChapter = false;
      });
    }
  }

  List<_VerseLine> _parseVerses(String body) {
    final decoded = json.decode(body);
    if (decoded is! List) {
      return const <_VerseLine>[];
    }
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

  Widget _buildVerseParagraph(_VerseLine verse, ThemeData theme) {
    final TextStyle baseStyle =
        theme.textTheme.bodyLarge?.copyWith(height: 1.6) ??
            const TextStyle(fontSize: 16, height: 1.6);
    final TextStyle numberStyle =
        baseStyle.copyWith(fontWeight: FontWeight.w600);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: RichText(
        textAlign: TextAlign.start,
        text: TextSpan(
          style: baseStyle,
          children: [
            if (verse.number != null && verse.number! > 0)
              TextSpan(text: '${verse.number}. ', style: numberStyle),
            TextSpan(text: verse.text),
          ],
        ),
      ),
    );
  }

  Widget _buildChapterSection(ThemeData theme) {
    if (widget.chapter <= 0) {
      return const SizedBox.shrink();
    }

    if (_chapterVerses != null) {
      final verses = _chapterVerses!;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Full Chapter',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
            textAlign: TextAlign.start,
          ),
          const SizedBox(height: 12),
          if (verses.isEmpty)
            Text(
              'No chapter text is available for this passage yet.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.start,
            )
          else
            ...verses
                .map((verse) => _buildVerseParagraph(verse, theme))
                .toList(),
        ],
      );
    }

    if (_loadingChapter) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FilledButton.icon(
          onPressed: _loadFullChapter,
          icon: const Icon(Icons.menu_book_outlined),
          label: const Text('Read full chapter'),
        ),
        if (_chapterError != null) ...[
          const SizedBox(height: 12),
          Text(
            _chapterError!,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.error),
            textAlign: TextAlign.start,
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.topicName.trim().isNotEmpty
        ? widget.topicName
        : (widget.displayBook.trim().isNotEmpty
            ? widget.displayBook.trim()
            : 'Reference');
    return MainScaffold(
      title: title,
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loadingReference) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(color: Theme.of(context).colorScheme.error),
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    final meta = _metaSummary;
    final direction = _languageOption.direction;

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
                    Text(
                      _referenceHeading,
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                      textAlign: TextAlign.start,
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        meta,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.start,
                      ),
                    ],
                    if (widget.topicName.trim().isNotEmpty &&
                        widget.topicName.trim() != _referenceHeading) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Topic: ${widget.topicName}',
                        style: theme.textTheme.bodyMedium,
                        textAlign: TextAlign.start,
                      ),
                    ],
                    const SizedBox(height: 24),
                    if (_referenceVerses.isEmpty)
                      Text(
                        'No passage text is available for this reference yet.',
                        style: theme.textTheme.bodyMedium,
                        textAlign: TextAlign.start,
                      )
                    else
                      ..._referenceVerses
                          .map((verse) => _buildVerseParagraph(verse, theme))
                          .toList(),
                    const SizedBox(height: 32),
                    _buildChapterSection(theme),
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
  final List<LanguageOption> availableOptions = kSupportedLanguages;

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
        .map((e) => e.book)
        .toSet()
        .toList()
      ..sort(_compareBooks);
  }

  @override
  Widget build(BuildContext context) {
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
                  title: Text(author),
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
  const AuthorComparisonScreen({
    super.key,
    required this.languageOption,
    required this.topic,
    required this.initialAuthors,
  });

  @override
  State<AuthorComparisonScreen> createState() => _AuthorComparisonScreenState();
}

class _AuthorComparisonScreenState extends State<AuthorComparisonScreen> {
  late final List<String> _allAuthors;
  late Set<String> _selected;
  Map<String, List<Map<String, String>>> _texts = {};
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    LanguageSelectionController.instance.update(widget.languageOption.code);
    _allAuthors = widget.topic.references
        .map((e) => e.book)
        .toSet()
        .toList();
    _allAuthors.sort(_compareBooks);
    _selected = widget.initialAuthors.toSet();
    fetchTexts();
  }

  Future<void> fetchTexts() async {
    if (_selected.isEmpty) {
      setState(() {
        _texts = {};
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final option = widget.languageOption;
      final futures = _selected.map((author) async {
        final refs = widget.topic.references.where((r) => r.book == author);
        final parts = <Map<String, String>>[];
        for (final ref in refs) {
          final bookId = ref.bookId.isNotEmpty ? ref.bookId : ref.book;
          final url = "$apiBaseUrl/get_verse"
              "?language=${Uri.encodeComponent(option.apiLanguage)}"
              "&version=${Uri.encodeComponent(option.apiVersion)}"
              "&book=${Uri.encodeComponent(bookId)}"
              "&chapter=${ref.chapter}"
              "&verse=${Uri.encodeComponent(ref.verses)}";
          final response = await http.get(Uri.parse(url));
          if (response.statusCode != 200) {
            throw Exception("Error ${response.statusCode} for $author");
          }
          final List<dynamic> verses = json.decode(response.body);
          final text =
              verses.map((v) => "${v['verse']}. ${v['text']}").join("\n");
          final refLabel = ref.formattedReference;
          final title = refLabel.isEmpty ? author : "$author $refLabel";
          parts.add({'title': title, 'text': text});
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

  @override
  Widget build(BuildContext context) {
    final option = widget.languageOption;
    return Directionality(
      textDirection: option.direction,
      child: MainScaffold(
        title: widget.topic.name,
        body: Column(
          children: [
            Wrap(
              spacing: 8,
              children: _allAuthors
                  .map(
                    (author) => FilterChip(
                      label: Text(author),
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
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _selected.isEmpty
                  ? Center(child: Text(option.comparePrompt))
                  : _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? Center(child: Text(_error!))
                          : SingleChildScrollView(
                              child: Builder(
                                builder: (context) {
                                  final selectedSorted =
                                      _selected.toList()..sort(_compareBooks);
                                  final width = MediaQuery.of(context).size.width /
                                      selectedSorted.length;
                                  final columnWidths = <int, TableColumnWidth>{
                                    for (int i = 0; i < selectedSorted.length; i++)
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
                                                final entries =
                                                    _texts[a] ?? [];
                                                if (i >= entries.length) {
                                                  return const SizedBox.shrink();
                                                }
                                                final entry = entries[i];
                                                return Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      entry['title'] ?? '',
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .titleSmall
                                                          ?.copyWith(
                                                            fontWeight:
                                                                FontWeight.w600,
                                                          ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(entry['text'] ?? ''),
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
          ],
        ),
      ),
    );
  }
}



