enum Gospel {
  matthew('Matthew', 0x1),
  mark('Mark', 0x2),
  luke('Luke', 0x4),
  john('John', 0x8);

  const Gospel(this.canonicalName, this.bit);

  final String canonicalName;
  final int bit;

  static Gospel? fromCanonicalName(String value) {
    switch (value.trim().toLowerCase()) {
      case 'matthew':
        return Gospel.matthew;
      case 'mark':
        return Gospel.mark;
      case 'luke':
        return Gospel.luke;
      case 'john':
        return Gospel.john;
    }
    return null;
  }
}

enum GospelConstraint { any, included, excluded }

class GospelFilterCombination {
  GospelFilterCombination({
    required this.code,
    required GospelConstraint matthew,
    required GospelConstraint mark,
    required GospelConstraint luke,
    required GospelConstraint john,
  }) : constraints = Map<Gospel, GospelConstraint>.unmodifiable(
         <Gospel, GospelConstraint>{
           Gospel.matthew: matthew,
           Gospel.mark: mark,
           Gospel.luke: luke,
           Gospel.john: john,
         },
       ),
       includeMask =
           (matthew == GospelConstraint.included ? Gospel.matthew.bit : 0) |
           (mark == GospelConstraint.included ? Gospel.mark.bit : 0) |
           (luke == GospelConstraint.included ? Gospel.luke.bit : 0) |
           (john == GospelConstraint.included ? Gospel.john.bit : 0),
       excludeMask =
           (matthew == GospelConstraint.excluded ? Gospel.matthew.bit : 0) |
           (mark == GospelConstraint.excluded ? Gospel.mark.bit : 0) |
           (luke == GospelConstraint.excluded ? Gospel.luke.bit : 0) |
           (john == GospelConstraint.excluded ? Gospel.john.bit : 0) {
    assert(RegExp(r'^C\d{2}$').hasMatch(code));
    assert(includeMask != 0);
    assert(includeMask & excludeMask == 0);
  }

  final String code;
  final Map<Gospel, GospelConstraint> constraints;
  final int includeMask;
  final int excludeMask;

  int get includedCount => _bitCount(includeMask);
  int get excludedCount => _bitCount(excludeMask);
  int get unrestrictedCount =>
      Gospel.values.length - includedCount - excludedCount;

  Iterable<Gospel> gospelsWith(GospelConstraint constraint) sync* {
    for (final gospel in Gospel.values) {
      if (constraints[gospel] == constraint) {
        yield gospel;
      }
    }
  }

  bool matchesPresenceMask(int topicMask) {
    return (topicMask & includeMask) == includeMask &&
        (topicMask & excludeMask) == 0;
  }

  String get logicalKey => '$includeMask:$excludeMask';
}

int _bitCount(int value) {
  var remaining = value;
  var count = 0;
  while (remaining != 0) {
    count += remaining & 1;
    remaining >>= 1;
  }
  return count;
}

const GospelConstraint _a = GospelConstraint.any;
const GospelConstraint _i = GospelConstraint.included;
const GospelConstraint _e = GospelConstraint.excluded;

/// The canonical C01-C65 assignments transcribed from
/// `65_Gospel_Combinations.pdf`, in PDF code order.
final List<GospelFilterCombination> gospelFilterCombinations =
    List<GospelFilterCombination>.unmodifiable(<GospelFilterCombination>[
      GospelFilterCombination(
        code: 'C01',
        matthew: _i,
        mark: _i,
        luke: _i,
        john: _i,
      ),
      GospelFilterCombination(
        code: 'C02',
        matthew: _i,
        mark: _i,
        luke: _i,
        john: _e,
      ),
      GospelFilterCombination(
        code: 'C03',
        matthew: _i,
        mark: _i,
        luke: _i,
        john: _a,
      ),
      GospelFilterCombination(
        code: 'C04',
        matthew: _i,
        mark: _i,
        luke: _e,
        john: _i,
      ),
      GospelFilterCombination(
        code: 'C05',
        matthew: _i,
        mark: _i,
        luke: _e,
        john: _e,
      ),
      GospelFilterCombination(
        code: 'C06',
        matthew: _i,
        mark: _i,
        luke: _e,
        john: _a,
      ),
      GospelFilterCombination(
        code: 'C07',
        matthew: _i,
        mark: _i,
        luke: _a,
        john: _i,
      ),
      GospelFilterCombination(
        code: 'C08',
        matthew: _i,
        mark: _i,
        luke: _a,
        john: _e,
      ),
      GospelFilterCombination(
        code: 'C09',
        matthew: _i,
        mark: _i,
        luke: _a,
        john: _a,
      ),
      GospelFilterCombination(
        code: 'C10',
        matthew: _i,
        mark: _e,
        luke: _i,
        john: _i,
      ),
      GospelFilterCombination(
        code: 'C11',
        matthew: _i,
        mark: _e,
        luke: _i,
        john: _e,
      ),
      GospelFilterCombination(
        code: 'C12',
        matthew: _i,
        mark: _e,
        luke: _i,
        john: _a,
      ),
      GospelFilterCombination(
        code: 'C13',
        matthew: _i,
        mark: _e,
        luke: _e,
        john: _i,
      ),
      GospelFilterCombination(
        code: 'C14',
        matthew: _i,
        mark: _e,
        luke: _e,
        john: _e,
      ),
      GospelFilterCombination(
        code: 'C15',
        matthew: _i,
        mark: _e,
        luke: _e,
        john: _a,
      ),
      GospelFilterCombination(
        code: 'C16',
        matthew: _i,
        mark: _e,
        luke: _a,
        john: _i,
      ),
      GospelFilterCombination(
        code: 'C17',
        matthew: _i,
        mark: _e,
        luke: _a,
        john: _e,
      ),
      GospelFilterCombination(
        code: 'C18',
        matthew: _i,
        mark: _e,
        luke: _a,
        john: _a,
      ),
      GospelFilterCombination(
        code: 'C19',
        matthew: _i,
        mark: _a,
        luke: _i,
        john: _i,
      ),
      GospelFilterCombination(
        code: 'C20',
        matthew: _i,
        mark: _a,
        luke: _i,
        john: _e,
      ),
      GospelFilterCombination(
        code: 'C21',
        matthew: _i,
        mark: _a,
        luke: _i,
        john: _a,
      ),
      GospelFilterCombination(
        code: 'C22',
        matthew: _i,
        mark: _a,
        luke: _e,
        john: _i,
      ),
      GospelFilterCombination(
        code: 'C23',
        matthew: _i,
        mark: _a,
        luke: _e,
        john: _e,
      ),
      GospelFilterCombination(
        code: 'C24',
        matthew: _i,
        mark: _a,
        luke: _e,
        john: _a,
      ),
      GospelFilterCombination(
        code: 'C25',
        matthew: _i,
        mark: _a,
        luke: _a,
        john: _i,
      ),
      GospelFilterCombination(
        code: 'C26',
        matthew: _i,
        mark: _a,
        luke: _a,
        john: _e,
      ),
      GospelFilterCombination(
        code: 'C27',
        matthew: _i,
        mark: _a,
        luke: _a,
        john: _a,
      ),
      GospelFilterCombination(
        code: 'C28',
        matthew: _e,
        mark: _i,
        luke: _i,
        john: _i,
      ),
      GospelFilterCombination(
        code: 'C29',
        matthew: _e,
        mark: _i,
        luke: _i,
        john: _e,
      ),
      GospelFilterCombination(
        code: 'C30',
        matthew: _e,
        mark: _i,
        luke: _i,
        john: _a,
      ),
      GospelFilterCombination(
        code: 'C31',
        matthew: _e,
        mark: _i,
        luke: _e,
        john: _i,
      ),
      GospelFilterCombination(
        code: 'C32',
        matthew: _e,
        mark: _i,
        luke: _e,
        john: _e,
      ),
      GospelFilterCombination(
        code: 'C33',
        matthew: _e,
        mark: _i,
        luke: _e,
        john: _a,
      ),
      GospelFilterCombination(
        code: 'C34',
        matthew: _e,
        mark: _i,
        luke: _a,
        john: _i,
      ),
      GospelFilterCombination(
        code: 'C35',
        matthew: _e,
        mark: _i,
        luke: _a,
        john: _e,
      ),
      GospelFilterCombination(
        code: 'C36',
        matthew: _e,
        mark: _i,
        luke: _a,
        john: _a,
      ),
      GospelFilterCombination(
        code: 'C37',
        matthew: _e,
        mark: _e,
        luke: _i,
        john: _i,
      ),
      GospelFilterCombination(
        code: 'C38',
        matthew: _e,
        mark: _e,
        luke: _i,
        john: _e,
      ),
      GospelFilterCombination(
        code: 'C39',
        matthew: _e,
        mark: _e,
        luke: _i,
        john: _a,
      ),
      GospelFilterCombination(
        code: 'C40',
        matthew: _e,
        mark: _e,
        luke: _e,
        john: _i,
      ),
      GospelFilterCombination(
        code: 'C41',
        matthew: _e,
        mark: _e,
        luke: _a,
        john: _i,
      ),
      GospelFilterCombination(
        code: 'C42',
        matthew: _e,
        mark: _a,
        luke: _i,
        john: _i,
      ),
      GospelFilterCombination(
        code: 'C43',
        matthew: _e,
        mark: _a,
        luke: _i,
        john: _e,
      ),
      GospelFilterCombination(
        code: 'C44',
        matthew: _e,
        mark: _a,
        luke: _i,
        john: _a,
      ),
      GospelFilterCombination(
        code: 'C45',
        matthew: _e,
        mark: _a,
        luke: _e,
        john: _i,
      ),
      GospelFilterCombination(
        code: 'C46',
        matthew: _e,
        mark: _a,
        luke: _a,
        john: _i,
      ),
      GospelFilterCombination(
        code: 'C47',
        matthew: _a,
        mark: _i,
        luke: _i,
        john: _i,
      ),
      GospelFilterCombination(
        code: 'C48',
        matthew: _a,
        mark: _i,
        luke: _i,
        john: _e,
      ),
      GospelFilterCombination(
        code: 'C49',
        matthew: _a,
        mark: _i,
        luke: _i,
        john: _a,
      ),
      GospelFilterCombination(
        code: 'C50',
        matthew: _a,
        mark: _i,
        luke: _e,
        john: _i,
      ),
      GospelFilterCombination(
        code: 'C51',
        matthew: _a,
        mark: _i,
        luke: _e,
        john: _e,
      ),
      GospelFilterCombination(
        code: 'C52',
        matthew: _a,
        mark: _i,
        luke: _e,
        john: _a,
      ),
      GospelFilterCombination(
        code: 'C53',
        matthew: _a,
        mark: _i,
        luke: _a,
        john: _i,
      ),
      GospelFilterCombination(
        code: 'C54',
        matthew: _a,
        mark: _i,
        luke: _a,
        john: _e,
      ),
      GospelFilterCombination(
        code: 'C55',
        matthew: _a,
        mark: _i,
        luke: _a,
        john: _a,
      ),
      GospelFilterCombination(
        code: 'C56',
        matthew: _a,
        mark: _e,
        luke: _i,
        john: _i,
      ),
      GospelFilterCombination(
        code: 'C57',
        matthew: _a,
        mark: _e,
        luke: _i,
        john: _e,
      ),
      GospelFilterCombination(
        code: 'C58',
        matthew: _a,
        mark: _e,
        luke: _i,
        john: _a,
      ),
      GospelFilterCombination(
        code: 'C59',
        matthew: _a,
        mark: _e,
        luke: _e,
        john: _i,
      ),
      GospelFilterCombination(
        code: 'C60',
        matthew: _a,
        mark: _e,
        luke: _a,
        john: _i,
      ),
      GospelFilterCombination(
        code: 'C61',
        matthew: _a,
        mark: _a,
        luke: _i,
        john: _i,
      ),
      GospelFilterCombination(
        code: 'C62',
        matthew: _a,
        mark: _a,
        luke: _i,
        john: _e,
      ),
      GospelFilterCombination(
        code: 'C63',
        matthew: _a,
        mark: _a,
        luke: _i,
        john: _a,
      ),
      GospelFilterCombination(
        code: 'C64',
        matthew: _a,
        mark: _a,
        luke: _e,
        john: _i,
      ),
      GospelFilterCombination(
        code: 'C65',
        matthew: _a,
        mark: _a,
        luke: _a,
        john: _i,
      ),
    ]);

final Map<String, GospelFilterCombination> gospelFilterCombinationsByCode =
    Map<String, GospelFilterCombination>.unmodifiable(
      <String, GospelFilterCombination>{
        for (final combination in gospelFilterCombinations)
          combination.code: combination,
      },
    );

final List<GospelFilterCombination> semanticallyOrderedGospelFilters =
    List<GospelFilterCombination>.unmodifiable(
      List<GospelFilterCombination>.from(gospelFilterCombinations)
        ..sort(_compareSemantically),
    );

GospelFilterCombination? gospelFilterCombinationForCode(String? rawCode) {
  final code = rawCode?.trim().toUpperCase() ?? '';
  if (code.isEmpty) {
    return null;
  }
  return gospelFilterCombinationsByCode[code];
}

int _compareSemantically(
  GospelFilterCombination first,
  GospelFilterCombination second,
) {
  final includedCount = second.includedCount.compareTo(first.includedCount);
  if (includedCount != 0) {
    return includedCount;
  }
  final excludedCount = first.excludedCount.compareTo(second.excludedCount);
  if (excludedCount != 0) {
    return excludedCount;
  }
  for (final gospel in Gospel.values) {
    final firstIncluded =
        first.constraints[gospel] == GospelConstraint.included;
    final secondIncluded =
        second.constraints[gospel] == GospelConstraint.included;
    if (firstIncluded != secondIncluded) {
      return firstIncluded ? -1 : 1;
    }
  }
  for (final gospel in Gospel.values) {
    final firstExcluded =
        first.constraints[gospel] == GospelConstraint.excluded;
    final secondExcluded =
        second.constraints[gospel] == GospelConstraint.excluded;
    if (firstExcluded != secondExcluded) {
      return firstExcluded ? -1 : 1;
    }
  }
  return first.code.compareTo(second.code);
}
