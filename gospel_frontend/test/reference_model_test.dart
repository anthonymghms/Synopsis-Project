import 'package:flutter_test/flutter_test.dart';
import 'package:gospel_frontend/reference_model.dart';

void main() {
  group('HarmonyReferenceCell grammar', () {
    test('parses one selection', () {
      final cell = HarmonyReferenceCell.parse('John 8:1', book: 'John');

      expect(cell.physicalSegmentCount, 1);
      expect(cell.logicalSelectionCount, 1);
      expect(cell.relation, HarmonyReferenceRelation.single);
      expect(cell.segments.single.displayReference, '8:1');
    });

    test('comma inherits the chapter without becoming a range', () {
      final cell = HarmonyReferenceCell.parse(
        'John 8:1-12, 20-25',
        book: 'John',
      );

      expect(cell.segments.map((segment) => segment.displayReference), [
        '8:1-12',
        '8:20-25',
      ]);
      expect(cell.logicalSelectionCount, 2);
      expect(cell.relation, HarmonyReferenceRelation.sameChapterMultiple);
    });

    test('semicolon preserves non-contiguous selections', () {
      final cell = HarmonyReferenceCell.parse(
        'Matthew 5:31-32 ; 19:9',
        book: 'Matthew',
      );

      expect(cell.segments.map((segment) => segment.displayReference), [
        '5:31-32',
        '19:9',
      ]);
      expect(cell.logicalSelectionCount, 2);
      expect(cell.relation, HarmonyReferenceRelation.nonContinuous);
    });

    test('plus preserves two segments as one logical selection', () {
      final cell = HarmonyReferenceCell.parse(
        'Luke 1:78-80 + 2:1-7',
        book: 'Luke',
      );

      expect(cell.physicalSegmentCount, 2);
      expect(cell.logicalSelectionCount, 1);
      expect(cell.relation, HarmonyReferenceRelation.continuous);
      expect(cell.segments.last.separatorBefore, ReferenceSeparator.continuous);
    });

    test('structured JSON round trip retains separators', () {
      final original = HarmonyReferenceCell.parse(
        'Luke 1:78-80 + 2:1-7; 6:17-19, 27-36',
        book: 'Luke',
      );

      final restored = HarmonyReferenceCell.fromJson(original.toJson());

      expect(restored.displayValue, original.displayValue);
      expect(restored.displayValue, '1:78-80 2:1-7 6:17-19 6:27-36');
      expect(restored.displayValue, isNot(contains(RegExp(r'[+;,]'))));
      expect(restored.logicalSelectionCount, 3);
      expect(restored.relation, HarmonyReferenceRelation.mixed);
    });
  });
}
