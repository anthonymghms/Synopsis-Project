import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:gospel_frontend/auth_screen.dart';
import 'package:gospel_frontend/main_scaffold.dart';
import 'firebase_options.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

// ---- CONFIGURATION ----
const apiBaseUrl = "http://164.68.108.181:8000"; // Change if your backend is hosted elsewhere
const defaultLanguage = "arabic";
const defaultVersion = "van%20dyck";
// Unencoded version string used when fetching verses
const defaultVersionName = "van dyck";

// Order in which gospel references should appear.
// Accept both common spellings for Matthew to maintain sort order.
const Map<String, int> canonicalGospelsIndex = {
  'Matthew': 0,
  'Mathew': 0,
  'Mark': 1,
  'Luke': 2,
  'John': 3,
};

int _gospelIndex(String book) {
  return canonicalGospelsIndex[book] ?? canonicalGospelsIndex.length;
}

String canonicalGospelName(String book) {
  final trimmed = book.trim();
  if (canonicalGospelsIndex.containsKey(trimmed)) {
    return trimmed;
  }
  final lower = trimmed.toLowerCase();
  if (lower.startsWith('mat')) {
    return 'Matthew';
  }
  if (lower.startsWith('mar')) {
    return 'Mark';
  }
  if (lower.startsWith('luk')) {
    return 'Luke';
  }
  if (lower.startsWith('joh')) {
    return 'John';
  }
  return trimmed;
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
    final url =
        "$apiBaseUrl/topics?language=$defaultLanguage&version=$defaultVersion";
    try {
      final response = await http.get(Uri.parse(url));
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
    final theme = Theme.of(context);
    return MainScaffold(
      title: "Harmony of the Gospels",
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: fetchTopics,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 24),
                        children: [
                          _buildHeroSection(theme),
                          const SizedBox(height: 20),
                          if (_topics.isEmpty)
                            _buildEmptyState(theme)
                          else
                            _buildHarmonyTable(context, theme),
                        ],
                      );
                    },
                  ),
                ),
    );
  }

  Widget _buildHeroSection(ThemeData theme) {
    final headline = theme.textTheme.headlineMedium?.copyWith(
      fontWeight: FontWeight.bold,
    );
    final bodyStyle =
        theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Harmony of the Gospels', style: headline),
        const SizedBox(height: 8),
        Text(
          'A comparative study of Matthew, Mark, Luke, and John. '
          'Explore the life and teachings of Jesus Christ through a '
          'carefully curated table of parallel passages.',
          style: bodyStyle,
        ),
      ],
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.topic_outlined,
              size: 48, color: theme.colorScheme.outlineVariant),
          const SizedBox(height: 16),
          Text(
            'No topics available',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Topics from Firestore will appear here once they are added.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }

  Widget _buildHarmonyTable(BuildContext context, ThemeData theme) {
    final headerTitles = const ['Subjects', 'Matthew', 'Mark', 'Luke', 'John'];
    final headerStyle = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w700,
      color: theme.colorScheme.onSurfaceVariant,
      letterSpacing: 0.2,
    );
    return Card(
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: theme.colorScheme.surfaceVariant,
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
            child: Text(
              'Subjects and Parallel Gospel References',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 720),
              child: Table(
                columnWidths: const {
                  0: FlexColumnWidth(3),
                  1: FlexColumnWidth(2),
                  2: FlexColumnWidth(2),
                  3: FlexColumnWidth(2),
                  4: FlexColumnWidth(2),
                },
                defaultVerticalAlignment: TableCellVerticalAlignment.top,
                border: TableBorder(
                  horizontalInside: BorderSide(
                    color: theme.colorScheme.surfaceVariant,
                    width: 1,
                  ),
                  verticalInside: BorderSide(
                    color: theme.colorScheme.surfaceVariant,
                    width: 1,
                  ),
                  top: BorderSide(color: theme.colorScheme.surfaceVariant),
                  bottom: BorderSide(color: theme.colorScheme.surfaceVariant),
                  left: BorderSide(color: theme.colorScheme.surfaceVariant),
                  right: BorderSide(color: theme.colorScheme.surfaceVariant),
                ),
                children: [
                  TableRow(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceVariant.withOpacity(0.65),
                    ),
                    children: headerTitles
                        .map(
                          (title) => Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16.0, vertical: 12.0),
                            child: Text(title, style: headerStyle),
                          ),
                        )
                        .toList(),
                  ),
                  ..._topics
                      .asMap()
                      .entries
                      .map(
                        (entry) => _buildTopicRow(
                          context,
                          theme,
                          entry.value,
                          entry.key,
                        ),
                      )
                      .toList(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  TableRow _buildTopicRow(
      BuildContext context, ThemeData theme, Topic topic, int index) {
    if (topic.isSectionHeader) {
      return TableRow(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceVariant.withOpacity(0.45),
        ),
        children: [
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: Text(
              topic.name,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox.shrink(),
          const SizedBox.shrink(),
          const SizedBox.shrink(),
          const SizedBox.shrink(),
        ],
      );
    }

    final backgroundColor = index.isOdd
        ? theme.colorScheme.surfaceVariant.withOpacity(0.18)
        : Colors.transparent;
    final groupedReferences = _referencesByGospel(topic.references);
    final gospels = const ['Matthew', 'Mark', 'Luke', 'John'];

    return TableRow(
      decoration: BoxDecoration(color: backgroundColor),
      children: [
        _buildSubjectCell(context, theme, topic),
        ...gospels.map(
          (gospel) => _buildReferenceCell(
            theme,
            groupedReferences[gospel] ?? <TopicReference>[],
          ),
        ),
      ],
    );
  }

  Map<String, List<TopicReference>> _referencesByGospel(
      List<TopicReference> references) {
    final Map<String, List<TopicReference>> grouped = {};
    for (final reference in references) {
      final canonical = reference.canonicalBook;
      if (canonical.isEmpty) continue;
      grouped.putIfAbsent(canonical, () => []).add(reference);
    }
    return grouped;
  }

  List<String> _authorsForTopic(Topic topic) {
    final authors = topic.references
        .map((ref) => canonicalGospelName(ref.book))
        .where((name) => canonicalGospelsIndex.containsKey(name))
        .toSet()
        .toList();
    authors.sort((a, b) => _gospelIndex(a).compareTo(_gospelIndex(b)));
    return authors;
  }

  Widget _buildSubjectCell(
      BuildContext context, ThemeData theme, Topic topic) {
    final authors = _authorsForTopic(topic);
    final hasTapTarget = authors.isNotEmpty;
    final additionalReferences = topic.references
        .where(
            (ref) => !canonicalGospelsIndex.containsKey(ref.canonicalBook))
        .toList();
    final additionalSummary = additionalReferences
        .map(_formatAdditionalReference)
        .where((value) => value.isNotEmpty)
        .toList();
    final idStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.primary,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.3,
    );
    final titleStyle = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w700,
    );
    final subtitleStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.outline,
    );

    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (topic.id.isNotEmpty)
            Text(
              topic.id,
              style: idStyle,
            ),
          Text(topic.name, style: titleStyle),
          if (topic.subtitle?.isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text(topic.subtitle!, style: subtitleStyle),
            ),
          if (topic.description?.isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(topic.description!, style: subtitleStyle),
            ),
          if (authors.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12.0),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: authors
                    .map(
                      (author) => Chip(
                        label: Text(author),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        labelStyle: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                        backgroundColor:
                            theme.colorScheme.primary.withOpacity(0.08),
                        side: BorderSide(color: theme.colorScheme.primary),
                        visualDensity: VisualDensity.compact,
                      ),
                    )
                    .toList(),
              ),
            ),
          if (additionalSummary.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: authors.isNotEmpty ? 12.0 : 8.0),
              child: Text(
                "Additional references: ${additionalSummary.join(', ')}",
                style: subtitleStyle,
              ),
            ),
        ],
      ),
    );

    if (!hasTapTarget) {
      return content;
    }

    return Tooltip(
      message: 'View parallel passages',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openTopic(context, topic, authors),
          child: content,
        ),
      ),
    );
  }

  void _openTopic(BuildContext context, Topic topic, List<String> authors) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AuthorComparisonScreen(
          language: defaultLanguage,
          version: defaultVersionName,
          topic: topic,
          initialAuthors: authors,
        ),
      ),
    );
  }

  Widget _buildReferenceCell(
      ThemeData theme, List<TopicReference> references) {
    if (references.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < references.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == references.length - 1 ? 0 : 12),
              child: _ReferenceTile(
                reference: references[i],
              ),
            ),
        ],
      ),
    );
  }

  String _formatAdditionalReference(TopicReference reference) {
    final referenceDisplay = reference.referenceDisplay;
    if (reference.book.isEmpty && referenceDisplay.isEmpty) {
      return '';
    }
    if (reference.book.isEmpty) {
      return referenceDisplay;
    }
    if (referenceDisplay.isEmpty) {
      return reference.book;
    }
    return '${reference.book} $referenceDisplay';
  }
}

class Topic {
  final String id;
  final String name;
  final List<TopicReference> references;
  final String? subtitle;
  final String? description;
  final bool isSectionHeader;

  Topic({
    required this.id,
    required this.name,
    required this.references,
    this.subtitle,
    this.description,
    this.isSectionHeader = false,
  });

  factory Topic.fromJson(Map<String, dynamic> json) {
    final rawReferences = json['references'] ?? json['entries'] ?? [];
    final references = rawReferences is List
        ? rawReferences
            .whereType<Map<String, dynamic>>()
            .map(TopicReference.fromJson)
            .toList()
        : <TopicReference>[];
    final bool isHeader = json['isSectionHeader'] == true ||
        json['type'] == 'heading' ||
        (references.isEmpty && (json['hasReferences'] != true));

    return Topic(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      references: references,
      subtitle: json['subtitle']?.toString(),
      description: json['description']?.toString(),
      isSectionHeader: isHeader,
    );
  }
}

class TopicReference {
  final String book;
  final String? chapter;
  final String? verses;
  final String? title;
  final String? note;

  const TopicReference({
    required this.book,
    this.chapter,
    this.verses,
    this.title,
    this.note,
  });

  factory TopicReference.fromJson(Map<String, dynamic> json) {
    final book = (json['book'] ?? '').toString().trim();
    final chapterValue = json['chapter'];
    final chapter =
        chapterValue != null ? chapterValue.toString().trim() : null;
    final versesValue = json['verses'] ?? json['verse'];
    final verses = versesValue != null ? versesValue.toString().trim() : null;
    final titleValue = json['title'];
    final noteValue = json['note'];
    final title = titleValue != null ? titleValue.toString().trim() : null;
    final note = noteValue != null ? noteValue.toString().trim() : null;
    return TopicReference(
      book: book,
      chapter: chapter?.isNotEmpty == true ? chapter : null,
      verses: verses?.isNotEmpty == true ? verses : null,
      title: title?.isNotEmpty == true ? title : null,
      note: note?.isNotEmpty == true ? note : null,
    );
  }

  String get canonicalBook => canonicalGospelName(book);

  String get referenceDisplay {
    final hasChapter = chapter != null && chapter!.isNotEmpty;
    final hasVerses = verses != null && verses!.isNotEmpty;
    if (!hasChapter && !hasVerses) {
      return '';
    }
    if (!hasVerses) {
      return chapter!;
    }
    if (!hasChapter) {
      return verses!;
    }
    return '$chapter:$verses';
  }
}

class _ReferenceTile extends StatelessWidget {
  final TopicReference reference;

  const _ReferenceTile({required this.reference});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final referenceStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.primary,
      fontWeight: FontWeight.w600,
    );
    final supportingStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    final referenceText = reference.referenceDisplay;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (referenceText.isNotEmpty)
          Text(
            referenceText,
            style: referenceStyle,
          ),
        if (reference.title != null && reference.title!.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: referenceText.isNotEmpty ? 4.0 : 0.0),
            child: Text(reference.title!, style: supportingStyle),
          ),
        if (reference.note != null && reference.note!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Text(reference.note!, style: supportingStyle),
          ),
      ],
    );
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
        .map((ref) => canonicalGospelName(ref.book))
        .where((name) => canonicalGospelsIndex.containsKey(name))
        .toSet()
        .toList()
      ..sort((a, b) => _gospelIndex(a).compareTo(_gospelIndex(b)));
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
                          initialAuthors: _selected.toList(),
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
  late final Map<String, List<TopicReference>> _referencesByAuthor;
  Map<String, List<Map<String, String>>> _texts = {};
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _referencesByAuthor = {};
    for (final ref in widget.topic.references) {
      final canonical = canonicalGospelName(ref.book);
      if (!canonicalGospelsIndex.containsKey(canonical)) {
        continue;
      }
      _referencesByAuthor.putIfAbsent(canonical, () => []).add(ref);
    }
    _allAuthors = _referencesByAuthor.keys.toList()
      ..sort((a, b) => _gospelIndex(a).compareTo(_gospelIndex(b)));
    _selected = widget.initialAuthors
        .map(canonicalGospelName)
        .where((author) => _referencesByAuthor.containsKey(author))
        .toSet();
    if (_selected.isEmpty && _allAuthors.isNotEmpty) {
      _selected = {_allAuthors.first};
    }
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
        final refs = _referencesByAuthor[author] ?? const <TopicReference>[];
        final parts = <Map<String, String>>[];
        for (final ref in refs) {
          if ((ref.chapter ?? '').isEmpty || (ref.verses ?? '').isEmpty) {
            continue;
          }
          final url = "$apiBaseUrl/get_verse"
              "?language=${Uri.encodeComponent(widget.language)}"
              "&version=${Uri.encodeComponent(widget.version)}"
              "&book=${Uri.encodeComponent(ref.book)}"
              "&chapter=${Uri.encodeComponent(ref.chapter!)}"
              "&verse=${Uri.encodeComponent(ref.verses!)}";
          final response = await http.get(Uri.parse(url));
          if (response.statusCode != 200) {
            throw Exception("Error ${response.statusCode} for $author");
          }
          final List<dynamic> verses = json.decode(response.body);
          final text =
              verses.map((v) => "${v['verse']}. ${v['text']}").join("\n");
          final referenceLabel = ref.referenceDisplay;
          final baseTitle = [
            ref.book,
            if (referenceLabel.isNotEmpty) referenceLabel,
          ].join(' ').trim();
          final displayTitle = (ref.title != null && ref.title!.isNotEmpty)
              ? '$baseTitle — ${ref.title}'
              : baseTitle;
          final title = displayTitle.isNotEmpty ? displayTitle : author;
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
                                final selectedSorted = _selected
                                    .toList()
                                  ..sort((a, b) => _gospelIndex(a)
                                      .compareTo(_gospelIndex(b)));
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



