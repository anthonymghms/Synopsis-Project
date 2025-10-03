import 'dart:collection';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'auth_screen.dart';
import 'firebase_options.dart';
import 'main_scaffold.dart';

// ---- CONFIGURATION ----
const apiBaseUrl = "http://164.68.108.181:8000"; // Change if your backend is hosted elsewhere
const defaultTopicsLanguage = "arabic";
const defaultTopicCollection = "topics";
const defaultBibleLanguage = "arabic";
const defaultBibleVersion = "van dyck";

const List<String> gospelOrder = ['Matthew', 'Mark', 'Luke', 'John'];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const GospelApp());
}

class GospelApp extends StatelessWidget {
  const GospelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Harmony of the Gospels',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
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
  final Map<String, List<VerseText>> _verseCache = {};

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
      'language': defaultTopicsLanguage,
      'collection': defaultTopicCollection,
    });

    try {
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        setState(() {
          _loading = false;
          _error = "Error: ${response.statusCode}";
        });
        return;
      }

      final List<dynamic> data = json.decode(utf8.decode(response.bodyBytes));
      final topics = data
          .map((e) => Topic.fromJson(e as Map<String, dynamic>))
          .toList();

      if (!mounted) return;
      setState(() {
        _topics = topics;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Failed to fetch topics: $e";
      });
    }
  }

  LinkedHashMap<String, List<Topic>> _groupTopics() {
    final grouped = LinkedHashMap<String, List<Topic>>();

    for (final topic in _topics) {
      final groupName = topic.groupName;
      grouped.putIfAbsent(groupName, () => []).add(topic);
    }

    for (final topics in grouped.values) {
      topics.sort((a, b) {
        final orderComparison = a.order.compareTo(b.order);
        if (orderComparison != 0) {
          return orderComparison;
        }
        return a.name.compareTo(b.name);
      });
    }

    return grouped;
  }

  String _cacheKey(ReferenceEntry entry) {
    return '${entry.book}|${entry.chapter}|${entry.verses}';
  }

  Future<List<VerseText>> _fetchVerseText(ReferenceEntry entry) async {
    final key = _cacheKey(entry);
    if (_verseCache.containsKey(key)) {
      return _verseCache[key]!;
    }

    final uri = Uri.parse('$apiBaseUrl/get_verse').replace(queryParameters: {
      'language': defaultBibleLanguage,
      'version': defaultBibleVersion,
      'book': entry.book,
      'chapter': entry.chapter,
      'verse': entry.verses,
    });

    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch verse (${response.statusCode})');
    }

    final List<dynamic> data = json.decode(utf8.decode(response.bodyBytes));
    final verses = data
        .map((e) => VerseText.fromJson(e as Map<String, dynamic>))
        .toList();
    _verseCache[key] = verses;
    return verses;
  }

  void _showReferenceSheet(ReferenceEntry entry) {
    if (entry.referenceText.isEmpty) {
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.75,
          child: _ReferenceSheet(
            entry: entry,
            loader: () => _fetchVerseText(entry),
          ),
        );
      },
    );
  }

  Widget _buildIntroCard(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.primaryContainer.withOpacity(0.25),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Harmony of the Gospels',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Explore parallel Gospel passages side-by-side. '
              'Select any reference to read the passage instantly.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }

  TableRow _buildHeaderRow(BuildContext context) {
    final theme = Theme.of(context);
    final headerStyle = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w700,
      color: theme.colorScheme.onSurfaceVariant,
    );

    Widget headerCell(String title) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        color: theme.colorScheme.surfaceVariant.withOpacity(0.45),
        child: Text(title, style: headerStyle),
      );
    }

    return TableRow(
      children: [
        headerCell('Subjects'),
        for (final gospel in gospelOrder) headerCell(gospel),
      ],
    );
  }

  Widget _buildTopicCell(Topic topic) {
    final subtitle = topic.subtitle;
    final description = topic.description;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          topic.name,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (subtitle != null && subtitle.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Text(
              subtitle,
              style: const TextStyle(
                fontSize: 14,
                fontStyle: FontStyle.italic,
                color: Colors.black87,
              ),
            ),
          ),
        if (description != null && description.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6.0),
            child: Text(
              description,
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
          ),
      ],
    );
  }

  Widget _buildReferenceCell(List<ReferenceEntry> entries) {
    if (entries.isEmpty) {
      return const SizedBox.shrink();
    }

    final sortedEntries = entries.toList()
      ..sort((a, b) {
        final orderComparison = a.order.compareTo(b.order);
        if (orderComparison != 0) {
          return orderComparison;
        }
        final chapterComparison = a.chapterNumber.compareTo(b.chapterNumber);
        if (chapterComparison != 0) {
          return chapterComparison;
        }
        return a.verses.compareTo(b.verses);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < sortedEntries.length; i++)
          _ReferenceCellEntry(
            entry: sortedEntries[i],
            onTap: () => _showReferenceSheet(sortedEntries[i]),
            isLast: i == sortedEntries.length - 1,
          ),
      ],
    );
  }

  TableRow _buildTopicRow(Topic topic) {
    final cells = [
      _buildTopicCell(topic),
      for (final gospel in gospelOrder)
        _buildReferenceCell(topic.referencesForBook(gospel)),
    ];

    return TableRow(
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.96)),
      children: [
        for (final cell in cells)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
            child: cell,
          ),
      ],
    );
  }

  Widget _buildSection(BuildContext context, String title, List<Topic> topics) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          color: theme.colorScheme.surfaceVariant.withOpacity(0.6),
          child: Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Table(
          border: TableBorder.all(color: theme.dividerColor.withOpacity(0.4)),
          columnWidths: const {
            0: FlexColumnWidth(3),
            1: FlexColumnWidth(2),
            2: FlexColumnWidth(2),
            3: FlexColumnWidth(2),
            4: FlexColumnWidth(2),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.top,
          children: [
            _buildHeaderRow(context),
            for (final topic in topics) _buildTopicRow(topic),
          ],
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: fetchTopics,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final groupedTopics = _groupTopics();

    return RefreshIndicator(
      onRefresh: fetchTopics,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _buildIntroCard(context),
          const SizedBox(height: 24),
          if (groupedTopics.isEmpty)
            const Text('No topics found.', textAlign: TextAlign.center)
          else
            for (final entry in groupedTopics.entries)
              _buildSection(context, entry.key, entry.value),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MainScaffold(
      title: 'Harmony of the Gospels',
      body: _buildContent(context),
    );
  }
}

class Topic {
  final String id;
  final String name;
  final String? group;
  final String? subtitle;
  final String? description;
  final int order;
  final List<ReferenceEntry> references;

  Topic({
    required this.id,
    required this.name,
    required this.references,
    this.group,
    this.subtitle,
    this.description,
    this.order = 9999,
  });

  factory Topic.fromJson(Map<String, dynamic> json) {
    final rawReferences = json['references'] as List<dynamic>? ?? [];
    final references = <ReferenceEntry>[];
    for (final ref in rawReferences) {
      if (ref is Map<String, dynamic>) {
        references.add(ReferenceEntry.fromJson(ref));
      } else if (ref is Map) {
        references.add(ReferenceEntry.fromJson(Map<String, dynamic>.from(ref)));
      }
    }

    final rawOrder = json['order'];
    int order = 9999;
    if (rawOrder is int) {
      order = rawOrder;
    } else if (rawOrder is String) {
      order = int.tryParse(rawOrder) ?? 9999;
    }

    return Topic(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      references: references,
      group: json['group']?.toString() ?? json['category']?.toString(),
      subtitle: json['subtitle']?.toString(),
      description: json['description']?.toString(),
      order: order,
    );
  }

  String get groupName => (group?.isNotEmpty ?? false) ? group! : 'Subjects';

  List<ReferenceEntry> referencesForBook(String book) {
    return references
        .where((ref) => ref.book.toLowerCase() == book.toLowerCase())
        .toList();
  }
}

class ReferenceEntry {
  final String book;
  final String chapter;
  final String verses;
  final String? label;
  final String? note;
  final int order;

  ReferenceEntry({
    required this.book,
    required this.chapter,
    required this.verses,
    this.label,
    this.note,
    this.order = 9999,
  });

  factory ReferenceEntry.fromJson(Map<String, dynamic> json) {
    final rawOrder = json['order'];
    int order = 9999;
    if (rawOrder is int) {
      order = rawOrder;
    } else if (rawOrder is String) {
      order = int.tryParse(rawOrder) ?? 9999;
    }

    return ReferenceEntry(
      book: json['book']?.toString() ?? '',
      chapter: json['chapter']?.toString() ?? json['chap']?.toString() ?? '',
      verses: json['verses']?.toString() ?? json['verse']?.toString() ?? '',
      label: json['label']?.toString() ?? json['title']?.toString(),
      note: json['note']?.toString(),
      order: order,
    );
  }

  String get referenceText {
    if (chapter.isEmpty && verses.isEmpty) {
      return '';
    }
    if (chapter.isNotEmpty && verses.isNotEmpty) {
      return '$chapter:$verses';
    }
    return chapter.isNotEmpty ? chapter : verses;
  }

  int get chapterNumber => int.tryParse(chapter) ?? 0;
}

class VerseText {
  final String verse;
  final String text;

  VerseText({required this.verse, required this.text});

  factory VerseText.fromJson(Map<String, dynamic> json) {
    return VerseText(
      verse: json['verse']?.toString() ?? '',
      text: json['text']?.toString() ?? '',
    );
  }
}

class _ReferenceCellEntry extends StatelessWidget {
  final ReferenceEntry entry;
  final VoidCallback onTap;
  final bool isLast;

  const _ReferenceCellEntry({
    required this.entry,
    required this.onTap,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final reference = entry.referenceText;
    final label = entry.label;
    final note = entry.note;

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null && label.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 2.0),
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (reference.isNotEmpty)
            TextButton(
              onPressed: onTap,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 0),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                alignment: Alignment.centerLeft,
              ),
              child: Text(
                reference,
                style: const TextStyle(fontSize: 16),
              ),
            )
          else if (label != null && label.isNotEmpty)
            const SizedBox.shrink()
          else
            const Text('—'),
          if (note != null && note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text(
                note,
                style: const TextStyle(fontSize: 12.5, color: Colors.black54),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReferenceSheet extends StatelessWidget {
  final ReferenceEntry entry;
  final Future<List<VerseText>> Function() loader;

  const _ReferenceSheet({required this.entry, required this.loader});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${entry.book} ${entry.referenceText}',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            if (entry.label != null && entry.label!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4.0, bottom: 12.0),
                child: Text(
                  entry.label!,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            Expanded(
              child: FutureBuilder<List<VerseText>>(
                future: loader(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'Unable to load verses\n${snapshot.error}',
                        textAlign: TextAlign.center,
                      ),
                    );
                  }
                  final verses = snapshot.data ?? [];
                  if (verses.isEmpty) {
                    return const Center(child: Text('No verses found for this reference.'));
                  }
                  return ListView.separated(
                    itemCount: verses.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final verse = verses[index];
                      return RichText(
                        text: TextSpan(
                          style: theme.textTheme.bodyLarge,
                          children: [
                            TextSpan(
                              text: '${verse.verse}. ',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            TextSpan(text: verse.text),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
