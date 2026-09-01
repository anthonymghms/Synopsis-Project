import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const topicLanguageApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8010',
);

class TopicLanguageOption {
  const TopicLanguageOption({
    required this.code,
    required this.label,
    required this.direction,
    required this.gospelNames,
    required this.subjectsLabel,
    this.topicCount = 0,
    this.canonicalTopicCount = 0,
    this.complete = false,
  });

  final String code;
  final String label;
  final TextDirection direction;
  final List<String> gospelNames;
  final String subjectsLabel;
  final int topicCount;
  final int canonicalTopicCount;
  final bool complete;

  bool get isRtl => direction == TextDirection.rtl;

  factory TopicLanguageOption.fromJson(Map<String, dynamic> json) {
    final code = (json['id'] ?? json['language'] ?? '').toString().trim();
    final direction =
        (json['direction'] ?? '').toString().toLowerCase() == 'rtl'
        ? TextDirection.rtl
        : TextDirection.ltr;
    final rawGospels = json['gospels'];
    final gospelMap = rawGospels is Map
        ? Map<String, dynamic>.from(rawGospels)
        : const <String, dynamic>{};
    const canonicalGospels = ['Matthew', 'Mark', 'Luke', 'John'];
    final gospelNames = [
      for (final gospel in canonicalGospels)
        (gospelMap[gospel] ?? gospel).toString().trim(),
    ];
    final subjects = (json['subjectsLabel'] ?? '').toString().trim();
    return TopicLanguageOption(
      code: code.toLowerCase(),
      label: (json['label'] ?? code).toString().trim(),
      direction: direction,
      gospelNames: gospelNames,
      subjectsLabel: subjects.isNotEmpty
          ? subjects
          : code.toLowerCase() == 'arabic'
          ? 'المواضيع'
          : 'Subjects',
      topicCount: _asInt(json['topicCount']),
      canonicalTopicCount: _asInt(json['canonicalTopicCount']),
      complete: json['complete'] == true,
    );
  }
}

const bundledTopicLanguages = <TopicLanguageOption>[
  TopicLanguageOption(
    code: 'english',
    label: 'English',
    direction: TextDirection.ltr,
    gospelNames: ['Matthew', 'Mark', 'Luke', 'John'],
    subjectsLabel: 'Subjects',
  ),
  TopicLanguageOption(
    code: 'arabic',
    label: 'العربية',
    direction: TextDirection.rtl,
    gospelNames: ['متى', 'مرقس', 'لوقا', 'يوحنا'],
    subjectsLabel: 'المواضيع',
  ),
];

class TopicLanguageCatalog {
  TopicLanguageCatalog({
    http.Client? client,
    this.baseUrl = topicLanguageApiBaseUrl,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  Future<List<TopicLanguageOption>> load() async {
    final response = await _client.get(Uri.parse('$baseUrl/topic-languages'));
    if (response.statusCode != 200) {
      throw StateError(
        'Topic-language catalog returned ${response.statusCode}.',
      );
    }
    final decoded = json.decode(response.body);
    final raw = decoded is Map ? decoded['languages'] : null;
    if (raw is! List) {
      throw const FormatException('Invalid topic-language catalog payload.');
    }
    final options = raw
        .whereType<Map>()
        .map(
          (item) =>
              TopicLanguageOption.fromJson(Map<String, dynamic>.from(item)),
        )
        .where((option) => option.code.isNotEmpty)
        .toList(growable: false);
    if (options.isEmpty) {
      return bundledTopicLanguages;
    }
    return options;
  }

  static TopicLanguageOption resolve(
    List<TopicLanguageOption> options,
    String code,
  ) {
    final normalized = code.trim().toLowerCase();
    for (final option in options) {
      if (option.code.toLowerCase() == normalized) return option;
    }
    for (final option in options) {
      if (option.code == 'english') return option;
    }
    return options.isNotEmpty ? options.first : bundledTopicLanguages.first;
  }
}

int _asInt(Object? value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
