/// Lossless, language-neutral representation of one Harmony Gospel cell.
///
/// The backend is the authority for CSV validation. This parser exists for
/// backward-compatible loose string payloads and tests; normal frontend reads
/// consume the structured `referenceCells` JSON emitted by Flask.
enum ReferenceSeparator {
  continuous('+'),
  nonContinuous(';'),
  sameChapter(',');

  const ReferenceSeparator(this.symbol);
  final String symbol;

  static ReferenceSeparator? fromSymbol(Object? value) {
    final symbol = value?.toString().trim() ?? '';
    for (final separator in values) {
      if (separator.symbol == symbol) return separator;
    }
    return null;
  }

  /// Whether the segment after this separator belongs in the same preview
  /// section as the segment before it.
  ///
  /// A comma keeps multiple selections from one chapter together, while a
  /// plus keeps the pieces of one continuous passage together. A semicolon
  /// deliberately starts a new, visibly separated preview section.
  bool get continuesPreviewSection => this == continuous || this == sameChapter;
}

enum HarmonyReferenceRelation {
  single('single'),
  sameChapterMultiple('sameChapterMultiple'),
  continuous('continuous'),
  nonContinuous('nonContinuous'),
  mixed('mixed');

  const HarmonyReferenceRelation(this.jsonValue);
  final String jsonValue;
}

String _normalizeReferenceText(String value) {
  const digits = <String, String>{
    '٠': '0',
    '١': '1',
    '٢': '2',
    '٣': '3',
    '٤': '4',
    '٥': '5',
    '٦': '6',
    '٧': '7',
    '٨': '8',
    '٩': '9',
    '۰': '0',
    '۱': '1',
    '۲': '2',
    '۳': '3',
    '۴': '4',
    '۵': '5',
    '۶': '6',
    '۷': '7',
    '۸': '8',
    '۹': '9',
  };
  return value
      .split('')
      .map((character) => digits[character] ?? character)
      .join()
      .replaceAll('–', '-')
      .replaceAll('—', '-')
      .trim();
}

class HarmonyReferenceSegment {
  const HarmonyReferenceSegment({
    required this.chapter,
    required this.verses,
    this.separatorBefore,
  });

  final int chapter;
  final String verses;
  final ReferenceSeparator? separatorBefore;

  String get displayReference => '$chapter:$verses';

  int get startVerse {
    final match = RegExp(r'^\s*(\d+)').firstMatch(verses);
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'chapter': chapter,
    'verses': verses,
    if (separatorBefore != null) 'separatorBefore': separatorBefore!.symbol,
  };

  factory HarmonyReferenceSegment.fromJson(Map<String, dynamic> json) {
    final chapter = int.tryParse(json['chapter']?.toString() ?? '') ?? 0;
    final verses = _normalizeReferenceText(
      (json['verses'] ?? json['verse'] ?? '').toString(),
    );
    if (chapter < 1 || !RegExp(r'^\d+(?:\s*-\s*\d+)?$').hasMatch(verses)) {
      throw const FormatException('Invalid structured reference segment.');
    }
    return HarmonyReferenceSegment(
      chapter: chapter,
      verses: verses.replaceAll(RegExp(r'\s+'), ''),
      separatorBefore: ReferenceSeparator.fromSymbol(json['separatorBefore']),
    );
  }
}

/// Groups parsed reference segments into the logical sections shown by
/// previews. Callers supply already-parsed separator metadata; display code
/// must not infer reference grammar by splitting formatted strings.
List<List<T>> groupReferencePreviewSections<T>(
  Iterable<T> values, {
  required ReferenceSeparator? Function(T value) separatorBefore,
}) {
  final groups = <List<T>>[];
  for (final value in values) {
    final separator = separatorBefore(value);
    if (groups.isNotEmpty && separator?.continuesPreviewSection == true) {
      groups.last.add(value);
    } else {
      groups.add(<T>[value]);
    }
  }
  return groups;
}

/// Formats one preview section exactly as it appears in the Harmony table.
/// Comma selections omit the repeated chapter, and continuous cross-chapter
/// pieces collapse to the same compact outer endpoints used by the cell.
String formatReferencePreviewSection(Iterable<HarmonyReferenceSegment> values) {
  return formatHarmonyReferenceCellDisplay(values);
}

class HarmonyReferenceCell {
  const HarmonyReferenceCell({
    required this.book,
    required this.raw,
    required this.segments,
  });

  final String book;
  final String raw;
  final List<HarmonyReferenceSegment> segments;

  int get physicalSegmentCount => segments.length;

  int get logicalSelectionCount {
    if (segments.isEmpty) return 0;
    return 1 +
        segments
            .skip(1)
            .where(
              (segment) =>
                  segment.separatorBefore != ReferenceSeparator.continuous,
            )
            .length;
  }

  HarmonyReferenceRelation get relation {
    final separators = segments
        .skip(1)
        .map((segment) => segment.separatorBefore)
        .whereType<ReferenceSeparator>()
        .toSet();
    if (separators.isEmpty) return HarmonyReferenceRelation.single;
    if (separators.length != 1) return HarmonyReferenceRelation.mixed;
    return switch (separators.single) {
      ReferenceSeparator.continuous => HarmonyReferenceRelation.continuous,
      ReferenceSeparator.nonContinuous =>
        HarmonyReferenceRelation.nonContinuous,
      ReferenceSeparator.sameChapter =>
        HarmonyReferenceRelation.sameChapterMultiple,
    };
  }

  String get displayValue {
    return formatHarmonyReferenceCellDisplay(segments);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'book': book,
    'raw': raw,
    'relation': relation.jsonValue,
    'logicalSelectionCount': logicalSelectionCount,
    'segments': segments.map((segment) => segment.toJson()).toList(),
  };

  factory HarmonyReferenceCell.fromJson(Map<String, dynamic> json) {
    final book = (json['book'] ?? json['gospel'] ?? '').toString().trim();
    final rawSegments = json['segments'];
    if (book.isEmpty || rawSegments is! List) {
      throw const FormatException('Invalid structured reference cell.');
    }
    final segments = <HarmonyReferenceSegment>[];
    for (final value in rawSegments) {
      if (value is Map) {
        segments.add(
          HarmonyReferenceSegment.fromJson(Map<String, dynamic>.from(value)),
        );
      }
    }
    if (segments.isEmpty) {
      throw const FormatException(
        'A reference cell needs at least one segment.',
      );
    }
    return HarmonyReferenceCell(
      book: book,
      raw: (json['raw'] ?? '').toString().trim(),
      segments: List<HarmonyReferenceSegment>.unmodifiable(segments),
    );
  }

  factory HarmonyReferenceCell.parse(String value, {required String book}) {
    final normalized = _normalizeReferenceText(value);
    if (normalized.isEmpty || normalized == '-' || normalized == '—') {
      return HarmonyReferenceCell(
        book: book,
        raw: normalized,
        segments: const [],
      );
    }

    final tokens = <String>[];
    var cursor = 0;
    for (final match in RegExp(r'[+;,]').allMatches(normalized)) {
      tokens.add(normalized.substring(cursor, match.start));
      tokens.add(match.group(0)!);
      cursor = match.end;
    }
    tokens.add(normalized.substring(cursor));

    final segments = <HarmonyReferenceSegment>[];
    ReferenceSeparator? pendingSeparator;
    int? inheritedChapter;
    final fullReference = RegExp(r'^(\d+)\s*:\s*(\d+)(?:\s*-\s*(\d+))?$');
    final inheritedReference = RegExp(r'^(\d+)(?:\s*-\s*(\d+))?$');

    for (var index = 0; index < tokens.length; index++) {
      if (index.isOdd) {
        pendingSeparator = ReferenceSeparator.fromSymbol(tokens[index]);
        continue;
      }
      var piece = tokens[index].trim();
      if (piece.isEmpty) {
        throw const FormatException('Empty reference segment.');
      }
      final prefixed = RegExp(r'^([^\d:+;,]+?)\s+(\d.*)$').firstMatch(piece);
      if (prefixed != null) {
        piece = prefixed.group(2)!.trim();
      }

      final explicit = fullReference.firstMatch(piece);
      final inherited = explicit == null
          ? inheritedReference.firstMatch(piece)
          : null;
      if (explicit == null && (inherited == null || inheritedChapter == null)) {
        throw FormatException('Invalid reference segment: $piece');
      }
      final chapter = explicit == null
          ? inheritedChapter!
          : int.parse(explicit.group(1)!);
      final start = int.parse(
        (explicit ?? inherited)!.group(explicit == null ? 1 : 2)!,
      );
      final endText = (explicit ?? inherited)!.group(explicit == null ? 2 : 3);
      final end = endText == null ? null : int.parse(endText);
      if (chapter < 1 || start < 1 || (end != null && end < start)) {
        throw FormatException('Invalid reference segment: $piece');
      }
      if (pendingSeparator == ReferenceSeparator.sameChapter &&
          inheritedChapter != null &&
          chapter != inheritedChapter) {
        throw const FormatException('Comma references must share one chapter.');
      }
      if (pendingSeparator == ReferenceSeparator.continuous &&
          segments.isNotEmpty &&
          (chapter != segments.last.chapter + 1 || start != 1)) {
        throw const FormatException(
          "References joined with '+' must cross to the next chapter at verse 1.",
        );
      }
      segments.add(
        HarmonyReferenceSegment(
          chapter: chapter,
          verses: end == null ? '$start' : '$start-$end',
          separatorBefore: segments.isEmpty ? null : pendingSeparator,
        ),
      );
      inheritedChapter = chapter;
      pendingSeparator = null;
    }

    return HarmonyReferenceCell(
      book: book,
      raw: normalized,
      segments: List<HarmonyReferenceSegment>.unmodifiable(segments),
    );
  }
}

String _displayVerseRange(String verses) => verses.replaceAll('-', '–');

String _startVerse(String verses) => verses.split('-').first.trim();

String _endVerse(String verses) => verses.split('-').last.trim();

/// Formats a Harmony table cell using the compact notation from the source
/// synopsis: commas omit a repeated chapter, semicolons separate passages,
/// and continuous cross-chapter passages collapse to their outer endpoints,
/// separated by a space.
String formatHarmonyReferenceCellDisplay(
  Iterable<HarmonyReferenceSegment> values,
) {
  final segments = values.toList(growable: false);
  if (segments.isEmpty) return '';

  final buffer = StringBuffer();
  var groupStart = 0;
  while (groupStart < segments.length) {
    var groupEnd = groupStart;
    while (groupEnd + 1 < segments.length &&
        segments[groupEnd + 1].separatorBefore ==
            ReferenceSeparator.continuous) {
      groupEnd++;
    }

    final first = segments[groupStart];
    final last = segments[groupEnd];
    final separator = first.separatorBefore;
    final omitChapter =
        groupStart > 0 &&
        separator == ReferenceSeparator.sameChapter &&
        first.chapter == segments[groupStart - 1].chapter &&
        groupStart == groupEnd;

    if (groupStart > 0) {
      buffer.write(separator == ReferenceSeparator.sameChapter ? ', ' : '; ');
    }

    if (groupEnd > groupStart) {
      buffer
        ..write('${first.chapter}:${_startVerse(first.verses)}')
        ..write(' ')
        ..write('${last.chapter}:${_endVerse(last.verses)}');
    } else if (omitChapter) {
      buffer.write(_displayVerseRange(first.verses));
    } else {
      buffer.write('${first.chapter}:${_displayVerseRange(first.verses)}');
    }

    groupStart = groupEnd + 1;
  }

  return buffer.toString();
}
