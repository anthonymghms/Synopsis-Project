import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:gospel_frontend/auth_screen.dart';
import 'package:gospel_frontend/main_scaffold.dart';
import 'package:http/http.dart' as http;

import 'config.dart';
import 'firebase_options.dart';

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
            return const LanguageSelectionScreen();
          }
          return const AuthScreen();
        },
      ),
    );
  }
}

// ----- First Screen: Choose Language -----
class LanguageSelectionScreen extends StatefulWidget {
  const LanguageSelectionScreen({super.key});

  @override
  State<LanguageSelectionScreen> createState() => _LanguageSelectionScreenState();
}

class _LanguageSelectionScreenState extends State<LanguageSelectionScreen> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final languages = languageVersions.keys.toList();
    return MainScaffold(
      title: 'Choose Language',
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: languages.length,
              itemBuilder: (context, idx) {
                final lang = languages[idx];
                return RadioListTile<String>(
                  title: Text(lang),
                  value: lang,
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
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => VersionSelectionScreen(language: _selected!),
                        ),
                      );
                    },
              child: const Text('Continue'),
            ),
          ),
        ],
      ),
    );
  }
}

// ----- Second Screen: Choose Version -----
class VersionSelectionScreen extends StatefulWidget {
  final String language;
  const VersionSelectionScreen({super.key, required this.language});

  @override
  State<VersionSelectionScreen> createState() => _VersionSelectionScreenState();
}

class _VersionSelectionScreenState extends State<VersionSelectionScreen> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final versions = languageVersions[widget.language] ?? [];
    return MainScaffold(
      title: 'Choose Version',
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: versions.length,
              itemBuilder: (context, idx) {
                final version = versions[idx];
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
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TopicListScreen(
                            language: widget.language,
                            version: _selected!,
                          ),
                        ),
                      );
                    },
              child: const Text('Continue'),
            ),
          ),
        ],
      ),
    );
  }
}

// ----- Third Screen: List Topics -----
class TopicListScreen extends StatefulWidget {
  final String language;
  final String version;
  const TopicListScreen({super.key, required this.language, required this.version});

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
        "$apiBaseUrl/topics?language=${Uri.encodeComponent(widget.language)}&version=${Uri.encodeComponent(widget.version)}";
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
    return MainScaffold(
      title: 'Topics',
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView.separated(
                  itemCount: _topics.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, idx) {
                    final topic = _topics[idx];
                    return ListTile(
                      title: Text(topic.name),
                      trailing: const Icon(Icons.arrow_forward_ios),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ReferenceListScreen(
                              topic: topic,
                              language: widget.language,
                              version: widget.version,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
    );
  }
}

class Topic {
  final String id;
  final String name;
  final List<dynamic> references;
  Topic({required this.id, required this.name, required this.references});

  factory Topic.fromJson(Map<String, dynamic> json) => Topic(
        id: json['id'] ?? '',
        name: json['name'] ?? '',
        references: json['references'] ?? [],
      );
}

// ----- Fourth Screen: Show References -----
class ReferenceListScreen extends StatefulWidget {
  final Topic topic;
  final String language;
  final String version;
  const ReferenceListScreen({
    super.key,
    required this.topic,
    required this.language,
    required this.version,
  });

  @override
  State<ReferenceListScreen> createState() => _ReferenceListScreenState();
}

class _ReferenceListScreenState extends State<ReferenceListScreen> {
  final Map<String, String> _texts = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    fetchTexts();
  }

  Future<void> fetchTexts() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = <MapEntry<String, String>>[];
      for (final ref in widget.topic.references) {
        final url = "$apiBaseUrl/get_verse"
            "?language=${Uri.encodeComponent(widget.language)}"
            "&version=${Uri.encodeComponent(widget.version)}"
            "&book=${Uri.encodeComponent(ref['book'])}"
            "&chapter=${ref['chapter']}"
            "&verse=${Uri.encodeComponent(ref['verses'])}";
        final response = await http.get(Uri.parse(url));
        if (response.statusCode != 200) {
          throw Exception('Error ${response.statusCode}');
        }
        final List<dynamic> verses = json.decode(response.body);
        final text = verses.map((v) => "${v['verse']}. ${v['text']}").join("\n");
        final key = "${ref['book']} ${ref['chapter']}:${ref['verses']}";
        entries.add(MapEntry(key, text));
      }
      setState(() {
        _texts..clear()..addEntries(entries);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to fetch: $e';
        _loading = false;
      });
    }
  }

  Future<void> _addBookmark(String reference, String text) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final url = '$apiBaseUrl/bookmark';
    final body = json.encode({
      'user_id': user.uid,
      'bookmark': {
        'reference': reference,
        'text': text,
        'language': widget.language,
        'version': widget.version,
        'topic': widget.topic.name,
      }
    });
    try {
      final response = await http.post(Uri.parse(url),
          headers: {'Content-Type': 'application/json'}, body: body);
      if (response.statusCode == 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Bookmark added')));
      }
    } catch (_) {
      // Ignore errors for now
    }
  }

  @override
  Widget build(BuildContext context) {
    return MainScaffold(
      title: widget.topic.name,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  children: _texts.entries
                      .map(
                        (e) => ListTile(
                          title: Text(
                            e.key,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(e.value),
                          trailing: IconButton(
                            icon: const Icon(Icons.bookmark_border),
                            onPressed: () => _addBookmark(e.key, e.value),
                          ),
                        ),
                      )
                      .toList(),
                ),
    );
  }
}

