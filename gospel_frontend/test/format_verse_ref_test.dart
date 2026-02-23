import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gospel_frontend/utils/format_verse_ref.dart';
import 'package:gospel_frontend/widgets/verse_ref_text.dart';

void main() {
  group('parseVerseRef', () {
    test('parses chapter and verse range', () {
      final parsed = parseVerseRef('3:23-38');
      expect(parsed, isNotNull);
      expect(parsed!.chapter, '3');
      expect(parsed.start, '23');
      expect(parsed.end, '38');
    });

    test('parses single verse', () {
      final parsed = parseVerseRef('1:1');
      expect(parsed, isNotNull);
      expect(parsed!.chapter, '1');
      expect(parsed.start, '1');
      expect(parsed.end, isNull);
    });

    test('returns null for invalid input', () {
      expect(parseVerseRef('—'), isNull);
      expect(parseVerseRef('chapter 1'), isNull);
      expect(parseVerseRef('1'), isNull);
    });
  });

  group('toArabicIndicDigits', () {
    test('converts all western digits to arabic-indic', () {
      expect(toArabicIndicDigits('12:3-45'), '١٢:٣-٤٥');
    });
  });

  group('formatVerseRef', () {
    test('formats range 1:1-4 in Arabic with stable bidi isolation', () {
      final formatted = formatVerseRef('1:1-4', 'arabic');
      expect(formatted.text, '\u2066١:١-٤\u2069');
      expect(formatted.dir, TextDirection.ltr);
    });

    test('formats range 1:2-24 in Arabic with correct order', () {
      final formatted = formatVerseRef('1:2-24', 'ar');
      expect(formatted.text, '\u2066١:٢-٢٤\u2069');
      expect(formatted.dir, TextDirection.ltr);
    });

    test('formats 12:3-45 in Arabic', () {
      final formatted = formatVerseRef('12:3-45', 'arabic2');
      expect(formatted.text, '\u2066١٢:٣-٤٥\u2069');
      expect(formatted.dir, TextDirection.ltr);
    });

    test('formats single verse in Arabic', () {
      final formatted = formatVerseRef('1:1', 'arabic');
      expect(formatted.text, '\u2066١:١\u2069');
      expect(formatted.dir, TextDirection.ltr);
    });

    test('returns unchanged placeholders', () {
      expect(formatVerseRef('—', 'arabic').text, '—');
      expect(formatVerseRef('-', 'arabic').text, '-');
      expect(formatVerseRef('', 'arabic').text, '');
    });

    test('returns unchanged for non-arabic', () {
      final formatted = formatVerseRef('1:2-24', 'english');
      expect(formatted.text, '1:2-24');
      expect(formatted.dir, isNull);
    });
  });

  testWidgets('VerseRefText applies isolated LTR direction for Arabic references',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: VerseRefText(value: '1:2-24', lang: 'arabic'),
        ),
      ),
    );

    final directionality = tester.widget<Directionality>(
      find.descendant(
        of: find.byType(VerseRefText),
        matching: find.byType(Directionality),
      ).first,
    );
    expect(directionality.textDirection, TextDirection.ltr);

    final textWidget = tester.widget<Text>(find.byType(Text));
    expect(textWidget.data, '\u2066١:٢-٢٤\u2069');
  });
}
