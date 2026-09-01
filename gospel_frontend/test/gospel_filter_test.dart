import 'package:flutter_test/flutter_test.dart';
import 'package:gospel_frontend/gospel_filter.dart';

void main() {
  group('canonical Gospel filter combinations', () {
    final expectedMasks = <String, (int, int)>{
      'C01': (0xf, 0x0),
      'C02': (0x7, 0x8),
      'C03': (0x7, 0x0),
      'C04': (0xb, 0x4),
      'C05': (0x3, 0xc),
      'C06': (0x3, 0x4),
      'C07': (0xb, 0x0),
      'C08': (0x3, 0x8),
      'C09': (0x3, 0x0),
      'C10': (0xd, 0x2),
      'C11': (0x5, 0xa),
      'C12': (0x5, 0x2),
      'C13': (0x9, 0x6),
      'C14': (0x1, 0xe),
      'C15': (0x1, 0x6),
      'C16': (0x9, 0x2),
      'C17': (0x1, 0xa),
      'C18': (0x1, 0x2),
      'C19': (0xd, 0x0),
      'C20': (0x5, 0x8),
      'C21': (0x5, 0x0),
      'C22': (0x9, 0x4),
      'C23': (0x1, 0xc),
      'C24': (0x1, 0x4),
      'C25': (0x9, 0x0),
      'C26': (0x1, 0x8),
      'C27': (0x1, 0x0),
      'C28': (0xe, 0x1),
      'C29': (0x6, 0x9),
      'C30': (0x6, 0x1),
      'C31': (0xa, 0x5),
      'C32': (0x2, 0xd),
      'C33': (0x2, 0x5),
      'C34': (0xa, 0x1),
      'C35': (0x2, 0x9),
      'C36': (0x2, 0x1),
      'C37': (0xc, 0x3),
      'C38': (0x4, 0xb),
      'C39': (0x4, 0x3),
      'C40': (0x8, 0x7),
      'C41': (0x8, 0x3),
      'C42': (0xc, 0x1),
      'C43': (0x4, 0x9),
      'C44': (0x4, 0x1),
      'C45': (0x8, 0x5),
      'C46': (0x8, 0x1),
      'C47': (0xe, 0x0),
      'C48': (0x6, 0x8),
      'C49': (0x6, 0x0),
      'C50': (0xa, 0x4),
      'C51': (0x2, 0xc),
      'C52': (0x2, 0x4),
      'C53': (0xa, 0x0),
      'C54': (0x2, 0x8),
      'C55': (0x2, 0x0),
      'C56': (0xc, 0x2),
      'C57': (0x4, 0xa),
      'C58': (0x4, 0x2),
      'C59': (0x8, 0x6),
      'C60': (0x8, 0x2),
      'C61': (0xc, 0x0),
      'C62': (0x4, 0x8),
      'C63': (0x4, 0x0),
      'C64': (0x8, 0x4),
      'C65': (0x8, 0x0),
    };

    test('contains every PDF code exactly once', () {
      expect(gospelFilterCombinations, hasLength(65));
      expect(gospelFilterCombinationsByCode, hasLength(65));
      expect(
        gospelFilterCombinations.map((combination) => combination.code),
        <String>[
          for (var number = 1; number <= 65; number++)
            'C${number.toString().padLeft(2, '0')}',
        ],
      );
    });

    test('matches every Included and Excluded cell in the PDF', () {
      for (final entry in expectedMasks.entries) {
        final combination = gospelFilterCombinationForCode(entry.key);
        expect(combination, isNotNull, reason: entry.key);
        expect(combination!.includeMask, entry.value.$1, reason: entry.key);
        expect(combination.excludeMask, entry.value.$2, reason: entry.key);
      }
    });

    test('all assignments are valid and logically unique', () {
      final logicalKeys = <String>{};
      for (final combination in gospelFilterCombinations) {
        expect(combination.constraints.keys.toSet(), Gospel.values.toSet());
        expect(combination.includeMask, isNot(0), reason: combination.code);
        expect(
          combination.includeMask & combination.excludeMask,
          0,
          reason: combination.code,
        );
        expect(
          logicalKeys.add(combination.logicalKey),
          isTrue,
          reason: combination.code,
        );
      }
      expect(logicalKeys, hasLength(65));
    });

    test('semantic ordering groups Included then Excluded counts', () {
      expect(semanticallyOrderedGospelFilters, hasLength(65));
      var previousIncluded = 5;
      var previousExcluded = -1;
      for (final combination in semanticallyOrderedGospelFilters) {
        expect(combination.includedCount, lessThanOrEqualTo(previousIncluded));
        if (combination.includedCount != previousIncluded) {
          previousIncluded = combination.includedCount;
          previousExcluded = -1;
        }
        expect(
          combination.excludedCount,
          greaterThanOrEqualTo(previousExcluded),
        );
        previousExcluded = combination.excludedCount;
      }
      expect(
        semanticallyOrderedGospelFilters
            .where(
              (combination) =>
                  combination.includedCount == 3 &&
                  combination.excludedCount == 0,
            )
            .map((combination) => combination.code),
        <String>['C03', 'C07', 'C19', 'C47'],
      );
      expect(
        semanticallyOrderedGospelFilters
            .where(
              (combination) =>
                  combination.includedCount == 2 &&
                  combination.excludedCount == 0,
            )
            .map((combination) => combination.code),
        <String>['C09', 'C21', 'C25', 'C49', 'C53', 'C61'],
      );
    });

    test('invalid and legacy-free route codes fall back to All topics', () {
      expect(gospelFilterCombinationForCode(null), isNull);
      expect(gospelFilterCombinationForCode(''), isNull);
      expect(gospelFilterCombinationForCode('C00'), isNull);
      expect(gospelFilterCombinationForCode('C66'), isNull);
      expect(gospelFilterCombinationForCode('custom'), isNull);
      expect(gospelFilterCombinationForCode(' c25 ')?.code, 'C25');
    });
  });

  group('GospelFilterState set operations', () {
    final markLuke = Gospel.mark.bit | Gospel.luke.bit;

    test('fresh and cleared filters default to intersection', () {
      const state = GospelFilterState();

      expect(state.mode, GospelFilterMode.intersection);
      expect(state.isActive, isFalse);
    });

    test('union matches either included Gospel', () {
      final state = GospelFilterState(
        mode: GospelFilterMode.union,
        includeMask: markLuke,
      );

      expect(state.matchesPresenceMask(Gospel.mark.bit), isTrue);
      expect(state.matchesPresenceMask(Gospel.luke.bit), isTrue);
      expect(state.matchesPresenceMask(markLuke), isTrue);
      expect(state.matchesPresenceMask(Gospel.john.bit), isFalse);
    });

    test('intersection requires every included Gospel', () {
      final state = GospelFilterState(
        mode: GospelFilterMode.intersection,
        includeMask: markLuke,
      );

      expect(state.matchesPresenceMask(Gospel.mark.bit), isFalse);
      expect(state.matchesPresenceMask(Gospel.luke.bit), isFalse);
      expect(state.matchesPresenceMask(markLuke), isTrue);
    });

    test('exclusion is applied after union or intersection', () {
      final union = GospelFilterState(
        mode: GospelFilterMode.union,
        includeMask: markLuke,
        excludeMask: Gospel.john.bit,
      );
      final intersection = GospelFilterState(
        mode: GospelFilterMode.intersection,
        includeMask: Gospel.matthew.bit | Gospel.mark.bit,
        excludeMask: Gospel.luke.bit,
      );

      expect(union.matchesBasePresenceMask(Gospel.mark.bit), isTrue);
      expect(
        union.matchesPresenceMask(Gospel.mark.bit | Gospel.john.bit),
        isFalse,
      );
      expect(
        union.matchesPresenceMask(Gospel.luke.bit | Gospel.john.bit),
        isFalse,
      );
      expect(
        intersection.matchesPresenceMask(Gospel.matthew.bit | Gospel.mark.bit),
        isTrue,
      );
      expect(
        intersection.matchesPresenceMask(
          Gospel.matthew.bit | Gospel.mark.bit | Gospel.luke.bit,
        ),
        isFalse,
      );

      final multipleExclusions = union.copyWith(
        excludeMask: Gospel.matthew.bit | Gospel.john.bit,
      );
      expect(multipleExclusions.matchesPresenceMask(Gospel.mark.bit), isTrue);
      expect(
        multipleExclusions.matchesPresenceMask(
          Gospel.mark.bit | Gospel.matthew.bit,
        ),
        isFalse,
      );
    });

    test('include/exclude conflicts are prevented', () {
      final included = const GospelFilterState().toggleIncluded(Gospel.mark);
      expect(included.toggleExcluded(Gospel.mark), included);

      final excluded = GospelFilterState(
        includeMask: Gospel.luke.bit,
        excludeMask: Gospel.mark.bit,
      );
      final movedToInclude = excluded.toggleIncluded(Gospel.mark);
      expect(movedToInclude.includes(Gospel.mark), isTrue);
      expect(movedToInclude.excludes(Gospel.mark), isFalse);
    });

    test('query parameters round-trip canonical identifiers', () {
      final state = GospelFilterState.fromQueryParameters({
        'filterMode': 'union',
        'include': 'mark,luke',
        'exclude': 'john',
      });

      expect(state.mode, GospelFilterMode.union);
      expect(gospelMaskToQueryValue(state.includeMask), 'mark,luke');
      expect(gospelMaskToQueryValue(state.excludeMask), 'john');
    });

    test('legacy C01-C65 URLs translate to intersection state', () {
      final state = GospelFilterState.fromQueryParameters(
        const {},
        legacyCode: 'C05',
      );

      expect(state.mode, GospelFilterMode.intersection);
      expect(state.includeMask, Gospel.matthew.bit | Gospel.mark.bit);
      expect(state.excludeMask, Gospel.luke.bit | Gospel.john.bit);
    });

    test('invalid query parameters safely fall back to all topics', () {
      final state = GospelFilterState.fromQueryParameters({
        'filterMode': 'invalid',
        'include': 'acts,romans',
        'exclude': 'john',
      });
      expect(state.isActive, isFalse);
      expect(state.matchesPresenceMask(0), isTrue);
    });
  });

  group('independent visibility and sort state', () {
    test('column state refuses to hide the final visible Gospel', () {
      var state = const ColumnVisibilityState();
      state = state.toggle(Gospel.luke).toggle(Gospel.john);
      expect(state.visibleGospels, [Gospel.matthew, Gospel.mark]);
      state = state.toggle(Gospel.matthew);
      expect(state.visibleGospels, [Gospel.mark]);
      expect(state.toggle(Gospel.mark), state);
    });

    test('column and sort query values use canonical identifiers', () {
      final columns = ColumnVisibilityState.fromQueryValue('matthew,mark,luke');
      final sort = GospelSortState.fromQueryValue('LuKe');

      expect(columns.visibleMask, 0x7);
      expect(sort.gospel, Gospel.luke);
      expect(ColumnVisibilityState.fromQueryValue('invalid').visibleMask, 0xf);
      expect(GospelSortState.fromQueryValue('invalid').isDefault, isTrue);
    });

    test('combined view URL state encodes only canonical non-defaults', () {
      final parameters = harmonyViewQueryParameters(
        filter: GospelFilterState(
          mode: GospelFilterMode.union,
          includeMask: Gospel.mark.bit | Gospel.luke.bit,
          excludeMask: Gospel.john.bit,
        ),
        sort: const GospelSortState(gospel: Gospel.mark),
        columns: ColumnVisibilityState(
          visibleMask: Gospel.matthew.bit | Gospel.mark.bit | Gospel.luke.bit,
        ),
      );

      expect(parameters, {
        'filterMode': 'union',
        'include': 'mark,luke',
        'exclude': 'john',
        'sort': 'mark',
        'columns': 'matthew,mark,luke',
      });
      expect(
        harmonyViewQueryParameters(
          filter: const GospelFilterState(),
          sort: const GospelSortState(),
          columns: const ColumnVisibilityState(),
        ),
        isEmpty,
      );
    });
  });
}
