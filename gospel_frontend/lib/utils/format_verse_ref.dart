import 'package:flutter/widgets.dart';

final RegExp _verseRefPattern = RegExp(r'^(\d+):(\d+)(?:-(\d+))?$');
final RegExp _digitPattern = RegExp(r'\d');
const Map<String, String> _arabicIndicDigits = {
  '0': '٠',
  '1': '١',
  '2': '٢',
  '3': '٣',
  '4': '٤',
  '5': '٥',
  '6': '٦',
  '7': '٧',
  '8': '٨',
  '9': '٩',
};

class ParsedVerseRef {
  const ParsedVerseRef({
    required this.chapter,
    required this.start,
    this.end,
  });

  final String chapter;
  final String start;
  final String? end;
}

class FormattedVerseRef {
  const FormattedVerseRef({required this.text, this.dir});

  final String text;
  final TextDirection? dir;
}

ParsedVerseRef? parseVerseRef(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  final match = _verseRefPattern.firstMatch(trimmed);
  if (match == null) {
    return null;
  }
  return ParsedVerseRef(
    chapter: match.group(1)!,
    start: match.group(2)!,
    end: match.group(3),
  );
}

String toArabicIndicDigits(String input) => input.replaceAllMapped(
    _digitPattern, (match) => _arabicIndicDigits[match.group(0)]!);

FormattedVerseRef formatVerseRef(String input, String lang) {
  final trimmed = input.trim();
  if (trimmed.isEmpty || trimmed == '—' || trimmed == '-') {
    return FormattedVerseRef(text: input);
  }

  final normalizedLang = lang.trim().toLowerCase();
  final isArabic =
      normalizedLang == 'arabic' || normalizedLang == 'arabic2' || normalizedLang == 'ar';
  if (!isArabic) {
    return FormattedVerseRef(text: input);
  }

  final parsed = parseVerseRef(trimmed);
  if (parsed == null) {
    return FormattedVerseRef(text: input);
  }

  final chapter = toArabicIndicDigits(parsed.chapter);
  final start = toArabicIndicDigits(parsed.start);
  final end = parsed.end == null ? null : toArabicIndicDigits(parsed.end!);
  final formatted = end == null ? '$chapter:$start' : '$chapter:$start-$end';

  // Use LRI/PDI so verse references keep logical C:V-V order in RTL UI.
  return FormattedVerseRef(text: '\u2066$formatted\u2069', dir: TextDirection.ltr);
}
