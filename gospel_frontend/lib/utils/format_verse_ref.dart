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

const String _rlm = '\u200F';

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


bool shouldUseArabicIndicDigits({
  required String language,
  String? version,
}) {
  final normalizedLanguage = language.trim().toLowerCase();
  if (normalizedLanguage == 'arabic' ||
      normalizedLanguage == 'arabic2' ||
      normalizedLanguage == 'ar') {
    return true;
  }

  final normalizedVersion = (version ?? '').trim().toLowerCase();
  if (normalizedVersion.isEmpty) {
    return false;
  }

  return normalizedVersion.contains('van dyke') ||
      normalizedVersion.contains('arabic');
}

String formatVerseMarker(
  int verseNumber, {
  required String language,
  String? version,
}) {
  final value = verseNumber.toString();
  if (!shouldUseArabicIndicDigits(language: language, version: version)) {
    return value;
  }
  return toArabicIndicDigits(value);
}

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

  // RTL hardening: keep RTL wrapper and lock separators with RLM marks.
  final formatted = end == null
      ? '$chapter$_rlm:$_rlm$start'
      : '$chapter$_rlm:$_rlm$start$_rlm-$_rlm$end';

  // Flutter has no CSS unicode-bidi isolate-override; use RLI/PDI + RTL direction.
  return FormattedVerseRef(text: '\u2067$formatted\u2069', dir: TextDirection.rtl);
}
