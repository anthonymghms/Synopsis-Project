import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

// ---- CONFIGURATION ----
const apiBaseUrl = "http://172.20.10.3:5050"; // Change if your backend is hosted elsewhere
const defaultLanguage = "arabic";
const defaultVersion = "van%20dyck";

void main() {
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
      home: TopicListScreen(),
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
    return Scaffold(
      appBar: AppBar(
        title: Text('Topics'),
      ),
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
class ChooseVersionScreen extends StatelessWidget {
  final Topic topic;
  // Placeholder list of versions. Later, you can fetch versions from your backend.
  final List<String> availableVersions = [
    "van dyck", // Arabic
    "kjv",      // English, etc.
    // Add more as you add support
  ];

 ChooseVersionScreen({super.key, required this.topic});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Choose Version"),
      ),
      body: ListView.builder(
        itemCount: availableVersions.length,
        itemBuilder: (context, idx) {
          final version = availableVersions[idx];
          return ListTile(
            title: Text(version),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => BookListScreen(topic: topic, version: version),
              ));
            },

          );
        },
      ),
    );
  }
}


class BookListScreen extends StatelessWidget {
  final Topic topic;
  final String version;
  const BookListScreen({super.key, required this.topic, required this.version});

  @override
  Widget build(BuildContext context) {
    // You need to know which books are relevant for the topic and version.
    // These can be obtained from the 'references' field in your Topic object.
    final entries = topic.references; // Add references field to Topic
    final books = entries.map((e) => e['book']).toSet().toList(); // Unique books

    return Scaffold(
      appBar: AppBar(title: Text("Choose Book")),
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
                  version: version,
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
  final String version;
  final String book;
  const ReferenceListScreen({super.key, required this.topic, required this.version, required this.book});

  @override
  Widget build(BuildContext context) {
    final references = topic.references.where((e) => e['book'] == book).toList();
    return Scaffold(
      appBar: AppBar(title: Text("Choose Reference")),
      body: ListView.builder(
        itemCount: references.length,
        itemBuilder: (context, idx) {
          final ref = references[idx];
          final label = "Chapter ${ref['chapter']}, Verses ${ref['verses']}";
          return ListTile(
            title: Text(label),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => ReferenceTextScreen(
                  language: defaultLanguage,
                  version: version,
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


class ReferenceTextScreen extends StatefulWidget {
  final String language, version, book, chapter, verses;
  const ReferenceTextScreen({super.key, required this.language, required this.version, required this.book, required this.chapter, required this.verses});
  @override
  State<ReferenceTextScreen> createState() => _ReferenceTextScreenState();
}

class _ReferenceTextScreenState extends State<ReferenceTextScreen> {
  String? _text;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    fetchVerseText();
  }

  Future<void> fetchVerseText() async {
    final url = "$apiBaseUrl/get_verse"
        "?language=${Uri.encodeComponent(widget.language)}"
        "&version=${Uri.encodeComponent(widget.version)}"
        "&book=${Uri.encodeComponent(widget.book)}"
        "&chapter=${widget.chapter}"
        "&verse=${Uri.encodeComponent(widget.verses)}";
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final List<dynamic> verses = json.decode(response.body);
        setState(() {
          _text = verses.map((v) => "${v['verse']}. ${v['text']}").join(" ");
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
        _error = "Failed to fetch: $e";
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Verse Text")),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_text ?? "", style: TextStyle(fontSize: 18)),
                ),
    );
  }
}



