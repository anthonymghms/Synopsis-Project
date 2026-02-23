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


  group('formatVerseMarker', () {
    test('uses arabic-indic digits for arabic language', () {
      expect(formatVerseMarker(12, language: 'arabic', version: 'KJV'), '١٢');
    });

    test('uses arabic-indic digits for Arabic version', () {
      expect(formatVerseMarker(7, language: 'english', version: 'Van Dyke-'), '٧');
    });

    test('keeps western digits for non-arabic language/version', () {
      expect(formatVerseMarker(7, language: 'english', version: 'KJV'), '7');
    });
  });

  group('formatVerseRef', () {
    test('formats range 1:1-4 in Arabic with RTL isolation and RLM separators', () {
      final formatted = formatVerseRef('1:1-4', 'arabic');
      expect(formatted.text, '\u2067١\u200F:\u200F١\u200F-\u200F٤\u2069');
      expect(formatted.dir, TextDirection.rtl);
    });

    test('formats range 1:2-24 in Arabic with correct order', () {
      final formatted = formatVerseRef('1:2-24', 'ar');
      expect(formatted.text, '\u2067١\u200F:\u200F٢\u200F-\u200F٢٤\u2069');
      expect(formatted.dir, TextDirection.rtl);
    });

    test('formats 12:3-45 in Arabic', () {
      final formatted = formatVerseRef('12:3-45', 'arabic2');
      expect(formatted.text, '\u2067١٢\u200F:\u200F٣\u200F-\u200F٤٥\u2069');
      expect(formatted.dir, TextDirection.rtl);
    });

    test('formats single verse in Arabic', () {
      final formatted = formatVerseRef('1:1', 'arabic');
      expect(formatted.text, '\u2067١\u200F:\u200F١\u2069');
      expect(formatted.dir, TextDirection.rtl);
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

  testWidgets('VerseRefText applies isolated RTL direction for Arabic references',
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
    expect(directionality.textDirection, TextDirection.rtl);

    final textWidget = tester.widget<Text>(find.byType(Text));
    expect(textWidget.data, '\u2067١\u200F:\u200F٢\u200F-\u200F٢٤\u2069');
  });
}
