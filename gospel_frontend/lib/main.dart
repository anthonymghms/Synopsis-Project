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


// ----- Second Screen: Choose Versions -----
class ChooseVersionScreen extends StatefulWidget {
  final Topic topic;
  ChooseVersionScreen({super.key, required this.topic});

  @override
  State<ChooseVersionScreen> createState() => _ChooseVersionScreenState();
}

class _ChooseVersionScreenState extends State<ChooseVersionScreen> {
  // Placeholder list of versions. Later, you can fetch versions from your backend.
  final List<String> availableVersions = [
    "van dyck", // Arabic
    "kjv", // English
    // Add more as you add support
  ];

  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    return MainScaffold(
      title: "Choose Versions",
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: availableVersions.length,
              itemBuilder: (context, idx) {
                final version = availableVersions[idx];
                return CheckboxListTile(
                  title: Text(version),
                  value: _selected.contains(version),
                  onChanged: (val) {
                    setState(() {
                      if (val == true) {
                        _selected.add(version);
                      } else {
                        _selected.remove(version);
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
                        builder: (_) => BookListScreen(
                          topic: widget.topic,
                          versions: _selected.toList(),
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


class BookListScreen extends StatelessWidget {
  final Topic topic;
  final List<String> versions;
  const BookListScreen({super.key, required this.topic, required this.versions});

  @override
  Widget build(BuildContext context) {
    // You need to know which books are relevant for the topic and version.
    // These can be obtained from the 'references' field in your Topic object.
    final entries = topic.references; // Add references field to Topic
    final books = entries.map((e) => e['book']).toSet().toList(); // Unique books

    return MainScaffold(
      title: "Choose Book",
      body: ListView.builder(
        itemCount: books.length,
        itemBuilder: (context, idx) {
          final book = books[idx];
          return ListTile(
            title: Text(book),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => ReferenceListScreen(
                  topic: topic,
                  versions: versions,
                  book: book,
                ),
              ));
            },
          );
        },
      ),
    );
  }
}



class ReferenceListScreen extends StatelessWidget {
  final Topic topic;
  final List<String> versions;
  final String book;
  const ReferenceListScreen({super.key, required this.topic, required this.versions, required this.book});

  @override
  Widget build(BuildContext context) {
    final references = topic.references.where((e) => e['book'] == book).toList();
    return MainScaffold(
      title: "Choose Reference",
      body: ListView.builder(
        itemCount: references.length,
        itemBuilder: (context, idx) {
          final ref = references[idx];
          final label = "Chapter ${ref['chapter']}, Verses ${ref['verses']}";
          return ListTile(
            title: Text(label),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => ReferenceComparisonScreen(
                  language: defaultLanguage,
                  versions: versions,
                  book: book,
                  chapter: ref['chapter'].toString(),
                  verses: ref['verses'],
                ),
              ));
            },
          );
        },
      ),
    );
  }
}

class ReferenceComparisonScreen extends StatefulWidget {
  final String language;
  final List<String> versions;
  final String book;
  final String chapter;
  final String verses;
  const ReferenceComparisonScreen({super.key, required this.language, required this.versions, required this.book, required this.chapter, required this.verses});

  @override
  State<ReferenceComparisonScreen> createState() => _ReferenceComparisonScreenState();
}

class _ReferenceComparisonScreenState extends State<ReferenceComparisonScreen> {
  Map<String, String> _texts = {};
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    fetchVerseTexts();
  }

  Future<void> fetchVerseTexts() async {
    try {
      final futures = widget.versions.map((version) async {
        final url = "$apiBaseUrl/get_verse"
            "?language=${Uri.encodeComponent(widget.language)}"
            "&version=${Uri.encodeComponent(version)}"
            "&book=${Uri.encodeComponent(widget.book)}"
            "&chapter=${widget.chapter}"
            "&verse=${Uri.encodeComponent(widget.verses)}";
        final response = await http.get(Uri.parse(url));
        if (response.statusCode != 200) {
          throw Exception("Error ${response.statusCode} for $version");
        }
        final List<dynamic> verses = json.decode(response.body);
        final text = verses.map((v) => "${v['verse']}. ${v['text']}").join("\n");
        return MapEntry(version, text);
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
      title: "Compare Versions",
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: widget.versions.map((v) {
                    final text = _texts[v] ?? "";
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(v, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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



