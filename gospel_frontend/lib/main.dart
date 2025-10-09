import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:gospel_frontend/auth_screen.dart';
import 'package:gospel_frontend/main_scaffold.dart';
import 'firebase_options.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math' as math;

// ---- CONFIGURATION ----
const apiBaseUrl = "http://164.68.108.181:8000"; // Change if your backend is hosted elsewhere
const defaultLanguage = "english";
// Default version key used when fetching topics and verses
const defaultVersion = "kjv";

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

int _gospelIndex(String book) {
  return canonicalGospelsIndex[book] ?? canonicalGospelsIndex.length;
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
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasData) {
            return const TopicListScreen();
          }
          return const AuthScreen();
        },
      ),
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

  @override
  void initState() {
    super.initState();
    fetchTopics();
  }

  Future<void> fetchTopics() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final uri = Uri.parse('$apiBaseUrl/topics').replace(queryParameters: {
      'language': defaultLanguage,
      'version': defaultVersion,
    });
    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        List data = json.decode(response.body);
        setState(() {
          _topics = data.map((e) => Topic.fromJson(e)).toList();
          _loading = false;
        });
      } else {
        setState(() {
          _error = "Error: ${response.statusCode}";
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = "Failed to fetch topics: $e";
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MainScaffold(
      title: "Harmony of the Gospels",
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Harmony of the Gospels',
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Explore a side-by-side overview of the key events '
                            'recorded by Matthew, Mark, Luke, and John. Tap a '
                            'subject to read the passages together.',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: Colors.grey.shade700),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            children: [
                              FilledButton.icon(
                                onPressed: () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                          'PDF download will be available soon.'),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.picture_as_pdf_outlined),
                                label: const Text('Download PDF'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () {
                                  _tableKey.currentState?.resetScroll();
                                },
                                icon: const Icon(Icons.refresh),
                                label: const Text('Reset Table'),
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
                      ),
                    ),
                  ],
                ),
    );
  }

  void _openTopic(Topic topic) {
    final authors = topic.references.map((e) => e.book).toSet().toList()
      ..sort(_compareBooks);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AuthorComparisonScreen(
        language: defaultLanguage,
        version: defaultVersion,
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
  });

  final List<Topic> topics;
  final ValueChanged<Topic>? onTopicSelected;

  @override
  State<HarmonyTable> createState() => _HarmonyTableState();
}

class _HarmonyTableState extends State<HarmonyTable> {
  late final ScrollController _verticalController;
  late final ScrollController _horizontalController;

  @override
  void initState() {
    super.initState();
    _verticalController = ScrollController();
    _horizontalController = ScrollController();
  }

  @override
  void dispose() {
    _verticalController.dispose();
    _horizontalController.dispose();
    super.dispose();
  }

  void resetScroll() {
    if (_verticalController.hasClients) {
      _verticalController.animateTo(0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic);
    }
    if (_horizontalController.hasClients) {
      _horizontalController.animateTo(0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic);
    }
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

  String _normalizeGospelName(String name) {
    if (name.toLowerCase() == 'mathew') {
      return 'Matthew';
    }
    return name;
  }

  Widget _buildHeaderCell(String label, TextStyle? style, TextAlign align) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      child: Text(label, style: style, textAlign: align),
    );
  }

  Widget _buildReferenceCell(
      List<GospelReference> refs, TextStyle? style, TextAlign align) {
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

    final rows = <TableRow>[
      TableRow(
        decoration: BoxDecoration(color: headerBackground),
        children: [
          _buildHeaderCell('Subjects', headerStyle, TextAlign.left),
          for (final gospel in orderedGospels)
            _buildHeaderCell(gospel, headerStyle, TextAlign.center),
        ],
      ),
    ];

    for (var i = 0; i < widget.topics.length; i++) {
      final topic = widget.topics[i];
      final grouped = _groupReferences(topic);
      final isEvenRow = i.isEven;
      final baseColor = theme.colorScheme.surface;
      final alternateColor =
          theme.colorScheme.surfaceVariant.withOpacity(0.35);
      rows.add(
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
                  ),
                ),
              ),
            ),
            for (final gospel in orderedGospels)
              TableCell(
                verticalAlignment: TableCellVerticalAlignment.top,
                child: _buildReferenceCell(
                  grouped[gospel] ?? const <GospelReference>[],
                  referenceStyle,
                  TextAlign.center,
                ),
              ),
          ],
        ),
      );
    }

    final availableWidth = MediaQuery.of(context).size.width;
    final minTableWidth = availableWidth < 720 ? 720.0 : availableWidth;

    return Scrollbar(
      controller: _verticalController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _verticalController,
        child: Scrollbar(
          controller: _horizontalController,
          thumbVisibility: true,
          notificationPredicate: (notification) =>
              notification.metrics.axis == Axis.horizontal,
          child: SingleChildScrollView(
            controller: _horizontalController,
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: minTableWidth),
              child: Table(
                border: TableBorder(
                  horizontalInside: BorderSide(color: borderColor, width: 0.6),
                  verticalInside: BorderSide(color: borderColor, width: 0.6),
                  top: BorderSide(color: borderColor, width: 0.8),
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
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                children: rows,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ReferenceHoverText extends StatefulWidget {
  const ReferenceHoverText({
    super.key,
    required this.reference,
    this.textStyle,
    this.textAlign = TextAlign.center,
  });

  final GospelReference reference;
  final TextStyle? textStyle;
  final TextAlign textAlign;

  @override
  State<ReferenceHoverText> createState() => _ReferenceHoverTextState();
}

class _ReferenceHoverTextState extends State<ReferenceHoverText> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _isFetching = false;
  String? _verseText;
  String? _error;
  bool _isHovered = false;

  @override
  void dispose() {
    _hideOverlay();
    super.dispose();
  }

  Future<void> _fetchIfNeeded() async {
    if (_verseText != null || _error != null || _isFetching) {
      return;
    }
    setState(() {
      _isFetching = true;
    });
    _overlayEntry?.markNeedsBuild();
    try {
      final queryParameters = {
        'language': defaultLanguage,
        'version': defaultVersion,
        'book': widget.reference.bookId.isNotEmpty
            ? widget.reference.bookId
            : widget.reference.book,
        'chapter': widget.reference.chapter.toString(),
        'verse': widget.reference.verses,
      };
      final uri = Uri.parse('$apiBaseUrl/get_verse')
          .replace(queryParameters: queryParameters);
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final List<dynamic> verses = json.decode(response.body);
        final text = verses
            .map((v) => "${v['verse']}. ${v['text']}")
            .join('\n')
            .trim();
        _verseText = text.isEmpty ? 'No text available.' : text;
        _error = null;
      } else {
        _error = 'Failed to load reference (${response.statusCode}).';
      }
    } catch (e) {
      _error = 'Failed to load reference.';
    } finally {
      if (mounted) {
        setState(() {
          _isFetching = false;
        });
        _overlayEntry?.markNeedsBuild();
      }
    }
  }

  void _showOverlay() {
    if (_overlayEntry != null) {
      return;
    }
    final overlay = Overlay.of(context);
    if (overlay == null) {
      return;
    }
    final targetBox = context.findRenderObject() as RenderBox?;
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;

    const double tooltipMaxWidth = 360.0;
    const double tooltipVerticalPadding = 8.0;
    double maxWidth = tooltipMaxWidth;
    double? maxHeight;
    if (overlayBox != null) {
      final availableWidth = overlayBox.size.width - 32.0;
      if (availableWidth.isFinite && availableWidth > 0) {
        maxWidth = math.min(tooltipMaxWidth, availableWidth);
      }
      maxHeight = overlayBox.size.height * 0.6;
    }

    bool alignRight = false;
    bool showAbove = false;
    if (targetBox != null && overlayBox != null) {
      final targetTopLeft =
          targetBox.localToGlobal(Offset.zero, ancestor: overlayBox);
      final targetBottomRight = targetBox.localToGlobal(
        targetBox.size.bottomRight(Offset.zero),
        ancestor: overlayBox,
      );
      final spaceRight = overlayBox.size.width - targetBottomRight.dx;
      final spaceLeft = targetTopLeft.dx;
      final spaceBelow = overlayBox.size.height - targetBottomRight.dy;
      final spaceAbove = targetTopLeft.dy;

      if (spaceRight < maxWidth && spaceLeft > spaceRight) {
        alignRight = true;
      }

      final estimatedHeight =
          maxHeight ?? math.min(overlayBox.size.height * 0.6, 280.0);
      if (spaceBelow < estimatedHeight && spaceAbove > spaceBelow) {
        showAbove = true;
      }
    }

    final Alignment followerAnchor;
    final Alignment targetAnchor;
    final Offset offset;
    if (showAbove) {
      followerAnchor = alignRight ? Alignment.bottomRight : Alignment.bottomLeft;
      targetAnchor = alignRight ? Alignment.topRight : Alignment.topLeft;
      offset = const Offset(0, -tooltipVerticalPadding);
    } else {
      followerAnchor = alignRight ? Alignment.topRight : Alignment.topLeft;
      targetAnchor = alignRight ? Alignment.bottomRight : Alignment.bottomLeft;
      offset = const Offset(0, tooltipVerticalPadding);
    }

    final BoxConstraints constraints = maxHeight != null
        ? BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight!)
        : BoxConstraints(maxWidth: maxWidth);

    _overlayEntry = OverlayEntry(
      builder: (context) {
        final theme = Theme.of(context);
        final content = _error ?? _verseText ?? 'Loading...';
        return Positioned.fill(
          child: IgnorePointer(
            child: CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              offset: offset,
              followerAnchor: followerAnchor,
              targetAnchor: targetAnchor,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  constraints: constraints,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                    border: Border.all(
                      color: theme.dividerColor.withOpacity(0.4),
                    ),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text(
                      content,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(_overlayEntry!);
  }

  void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _handlePointerEnter(PointerEvent event) {
    if (!_isHovered) {
      setState(() {
        _isHovered = true;
      });
    }
    _showOverlay();
    _fetchIfNeeded();
  }

  void _handlePointerExit(PointerEvent event) {
    if (_isHovered) {
      setState(() {
        _isHovered = false;
      });
    }
    _hideOverlay();
  }

  void _handleTap() {
    if (_overlayEntry == null) {
      setState(() {
        _isHovered = true;
      });
      _showOverlay();
      _fetchIfNeeded();
    } else {
      _hideOverlay();
      if (_isHovered) {
        setState(() {
          _isHovered = false;
        });
      }
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
    return CompositedTransformTarget(
      link: _layerLink,
      child: MouseRegion(
        onEnter: _handlePointerEnter,
        onExit: _handlePointerExit,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _handleTap,
          child: Text(
            widget.reference.formattedReference,
            style: _isHovered ? hoverStyle : baseStyle,
            textAlign: widget.textAlign,
            softWrap: true,
          ),
        ),
      ),
    );
  }
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
  // Placeholder list of versions. Later, fetch from backend.
  final List<String> availableVersions = [
    "van dyck", // Arabic
    "kjv", // English
    // Add more as needed
  ];

  String? _selected;

  @override
  Widget build(BuildContext context) {
    return MainScaffold(
      title: "Choose Version",
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: availableVersions.length,
              itemBuilder: (context, idx) {
                final version = availableVersions[idx];
                return RadioListTile<String>(
                  title: Text(version),
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
                          language: defaultLanguage,
                          version: widget.version,
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
  final String language;
  final String version;
  final Topic topic;
  final List<String> initialAuthors;
  const AuthorComparisonScreen({
    super.key,
    required this.language,
    required this.version,
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
      final futures = _selected.map((author) async {
        final refs = widget.topic.references.where((r) => r.book == author);
        final parts = <Map<String, String>>[];
        for (final ref in refs) {
          final bookId = ref.bookId.isNotEmpty ? ref.bookId : ref.book;
          final url = "$apiBaseUrl/get_verse"
              "?language=${Uri.encodeComponent(widget.language)}"
              "&version=${Uri.encodeComponent(widget.version)}"
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
    return MainScaffold(
      title: widget.topic.name,
      body: Column(
        children: [
          Wrap(
            spacing: 8,
            children: _allAuthors
                .map((author) => FilterChip(
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
                    ))
                .toList(),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _selected.isEmpty
                ? const Center(child: Text('Select authors to compare'))
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
                                    i: FixedColumnWidth(width)
                                };
                                final maxLen = selectedSorted
                                    .map((a) => _texts[a]?.length ?? 0)
                                    .fold<int>(0, (prev, e) => e > prev ? e : prev);
                                return Table(
                                  border: TableBorder.all(
                                      color: Colors.grey.shade300),
                                  columnWidths: columnWidths,
                                  children: [
                                    TableRow(
                                      children: selectedSorted
                                          .map((a) => Padding(
                                                padding:
                                                    const EdgeInsets.all(8.0),
                                                child: Text(a,
                                                    style: const TextStyle(
                                                        fontSize: 18,
                                                        fontWeight:
                                                            FontWeight.bold)),
                                              ))
                                          .toList(),
                                    ),
                                    for (int i = 0; i < maxLen; i++)
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
                                                    Text(entry['title']!,
                                                        style: const TextStyle(
                                                            fontSize: 16,
                                                            fontWeight:
                                                                FontWeight
                                                                    .w600)),
                                                    const SizedBox(height: 4),
                                                    Text(entry['text']!,
                                                        style: const TextStyle(
                                                            fontSize: 16)),
                                                  ],
                                                );
                                              }(),
                                            ),
                                        ],
                                      ),
                                  ],
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}



