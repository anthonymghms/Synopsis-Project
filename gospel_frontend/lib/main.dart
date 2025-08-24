import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:gospel_frontend/auth_screen.dart';
import 'package:gospel_frontend/main_scaffold.dart';
import 'firebase_options.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

// ---- CONFIGURATION ----
const apiBaseUrl = "http://192.168.20.183:5000"; // Change if your backend is hosted elsewhere
const defaultLanguage = "arabic";
const defaultVersion = "van%20dyck";

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
    return MainScaffold(
      title: "Topics",
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView.separated(
                  itemCount: _topics.length,
                  separatorBuilder: (_, __) => Divider(height: 1),
                  itemBuilder: (context, idx) {
                    final topic = _topics[idx];
                    return ListTile(
                      title: Text(topic.name),
                      trailing: Icon(Icons.arrow_forward_ios),
                      onTap: () {
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => ChooseVersionScreen(topic: topic),
                        ));
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
        .map((e) => e['book'] as String)
        .toSet()
        .toList();
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
                          authors: _selected.toList(),
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
  final List<String> authors;
  const AuthorComparisonScreen({super.key, required this.language, required this.version, required this.topic, required this.authors});

  @override
  State<AuthorComparisonScreen> createState() => _AuthorComparisonScreenState();
}

class _AuthorComparisonScreenState extends State<AuthorComparisonScreen> {
  Map<String, String> _texts = {};
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    fetchTexts();
  }

  Future<void> fetchTexts() async {
    try {
      final futures = widget.authors.map((author) async {
        final refs = widget.topic.references.where((r) => r['book'] == author);
        final parts = <String>[];
        for (final ref in refs) {
          final url = "$apiBaseUrl/get_verse"
              "?language=${Uri.encodeComponent(widget.language)}"
              "&version=${Uri.encodeComponent(widget.version)}"
              "&book=${Uri.encodeComponent(author)}"
              "&chapter=${ref['chapter']}"
              "&verse=${Uri.encodeComponent(ref['verses'])}";
          final response = await http.get(Uri.parse(url));
          if (response.statusCode != 200) {
            throw Exception("Error ${response.statusCode} for $author");
          }
          final List<dynamic> verses = json.decode(response.body);
          final text = verses.map((v) => "${v['verse']}. ${v['text']}").join("\n");
          parts.add(text);
        }
        return MapEntry(author, parts.join("\n\n"));
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
      title: "Compare Authors",
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: widget.authors.map((a) {
                    final text = _texts[a] ?? "";
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(a, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Text(text, style: const TextStyle(fontSize: 16)),
                        ],
                      ),
                    );
                  }).toList(),
                ),
    );
  }
}



