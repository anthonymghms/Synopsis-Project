import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'config.dart';
import 'main_scaffold.dart';

class BookmarksScreen extends StatefulWidget {
  const BookmarksScreen({super.key});

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  List<Map<String, dynamic>> _bookmarks = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    fetchBookmarks();
  }

  Future<void> fetchBookmarks() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _error = 'Not logged in';
        _loading = false;
      });
      return;
    }
    final url = '$apiBaseUrl/bookmarks?user_id=${user.uid}';
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        setState(() {
          _bookmarks = List<Map<String, dynamic>>.from(data);
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'Error: ${response.statusCode}';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to load bookmarks: $e';
        _loading = false;
      });
    }
  }

  Future<void> removeBookmark(String id) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final url = '$apiBaseUrl/bookmark/$id?user_id=${user.uid}';
    final response = await http.delete(Uri.parse(url));
    if (response.statusCode == 200) {
      setState(() {
        _bookmarks.removeWhere((b) => b['id'] == id);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MainScaffold(
      title: 'Bookmarks',
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView.builder(
                  itemCount: _bookmarks.length,
                  itemBuilder: (context, idx) {
                    final b = _bookmarks[idx];
                    return ListTile(
                      title: Text(b['reference'] ?? ''),
                      subtitle: b['text'] != null ? Text(b['text']) : null,
                      trailing: IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () => removeBookmark(b['id'] as String),
                      ),
                    );
                  },
                ),
    );
  }
}

