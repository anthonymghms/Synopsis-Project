import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gospel_frontend/browser_route_link.dart';
import 'package:gospel_frontend/gospel_filter.dart';
import 'package:gospel_frontend/main.dart';
import 'package:gospel_frontend/topic_language_catalog.dart';
import 'package:gospel_frontend/widgets/verse_ref_text.dart';

void main() {
  test('placeholder smoke test', () {
    expect(true, isTrue);
  });

  test('language names follow the menu locale, not the content locale', () {
    final english = kBaseLanguageOptions.firstWhere(
      (option) => option.code == 'english',
    );
    final arabic = kBaseLanguageOptions.firstWhere(
      (option) => option.code == 'arabic',
    );

    expect(
      localizedLanguageNameForMenu(arabic, english.code, english.label),
      'الإنجليزية',
    );
    expect(
      localizedLanguageNameForMenu(arabic, arabic.code, arabic.label),
      'العربية',
    );
    expect(
      localizedLanguageNameForMenu(english, arabic.code, arabic.label),
      'Arabic',
    );
  });

  testWidgets(
    'one primary language keeps menu, topic, and Bible state aligned',
    (tester) async {
      PrimaryLanguageController.instance.select('arabic');

      await tester.pumpWidget(
        MaterialApp(
          home: MenuLanguageScope(
            notifier: MenuLanguageController.instance.notifier,
            child: Builder(
              builder: (context) =>
                  Text(MenuLanguageScope.of(context).ui.settings),
            ),
          ),
        ),
      );
      expect(find.text('الإعدادات'), findsOneWidget);
      expect(TopicLanguageSelectionController.instance.languageCode, 'arabic');
      expect(LanguageSelectionController.instance.languageCode, 'arabic');

      PrimaryLanguageController.instance.select('english');
      await tester.pump();
      expect(find.text('Settings'), findsOneWidget);
      expect(TopicLanguageSelectionController.instance.languageCode, 'english');
      expect(LanguageSelectionController.instance.languageCode, 'english');
    },
  );

  test('comparison-only translations are not offered as a primary locale', () {
    final english = kBaseLanguageOptions.first;
    final french = english.copyWith(
      code: 'french',
      label: 'Français',
      apiLanguage: 'french',
      apiVersion: 'lsg',
      versions: const <BibleVersion>[BibleVersion(id: 'lsg', label: 'LSG')],
    );
    final fullBibleCatalog = <LanguageOption>[english, french];

    final primary = primaryLanguageOptionsFor(
      bibleLanguages: fullBibleCatalog,
      topicLanguages: <TopicLanguageOption>[
        bundledTopicLanguages.first,
        const TopicLanguageOption(
          code: 'french',
          label: 'Français',
          direction: TextDirection.ltr,
          gospelNames: <String>['Matthieu', 'Marc', 'Luc', 'Jean'],
          subjectsLabel: 'Sujets',
          topicCount: 100,
          canonicalTopicCount: 100,
          complete: true,
        ),
      ],
    );

    expect(fullBibleCatalog.map((option) => option.code), contains('french'));
    expect(primary.map((option) => option.code), <String>['english']);

    PrimaryLanguageController.instance.select('french');
    expect(PrimaryLanguageController.instance.languageCode, 'english');
    expect(TopicLanguageSelectionController.instance.languageCode, 'english');
    expect(MenuLanguageController.instance.languageCode, 'english');
  });

  test('mixed legacy routes use the Bible language as the primary locale', () {
    final mixed = Uri.parse(
      '/topic?menuLanguage=arabic&topicLanguage=english&bibleLanguage=english',
    );
    final blankCanonical = Uri.parse(
      '/topic?bibleLanguage=%20%20&language=arabic&topicLanguage=english',
    );

    expect(primaryLanguageQueryParameter(mixed), 'english');
    expect(primaryLanguageQueryParameter(blankCanonical), 'arabic');
  });

  Topic topicWith(String id, List<String> gospels) {
    return Topic(
      id: id,
      name: 'Topic $id',
      references: [
        for (final gospel in gospels)
          GospelReference(book: gospel, chapter: 1, verses: '1'),
      ],
    );
  }

  List<Topic> topicsFromMasks(List<int> masks) => [
    for (var index = 0; index < masks.length; index++)
      topicWith('${index + 1}', [
        for (final gospel in Gospel.values)
          if (masks[index] & gospel.bit != 0) gospel.canonicalName,
      ]),
  ];

  Widget harmonyTableFor(
    List<GospelReference> references, {
    double width = 1000,
    double height = 500,
    LanguageOption? languageOption,
    TopicLanguageOption? topicLanguage,
    String topicName = 'Teaching and healings',
    List<Gospel>? visibleGospels,
  }) {
    final option = languageOption ?? kBaseLanguageOptions.first;
    return MaterialApp(
      home: Scaffold(
        body: MenuLanguageScope(
          notifier: ValueNotifier<String>('english'),
          child: SizedBox(
            width: width,
            height: height,
            child: HarmonyTable(
              topics: [
                Topic(id: '34', name: topicName, references: references),
              ],
              languageOption: option,
              topicLanguage:
                  topicLanguage ??
                  (option.code == 'arabic'
                      ? bundledTopicLanguages.last
                      : bundledTopicLanguages.first),
              apiVersion: option.apiVersion,
              visibleGospels: visibleGospels,
            ),
          ),
        ),
      ),
    );
  }

  Widget interlinearGroupFor(double textScale) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 280,
              child: InterlinearVerseGroup(
                verseNumber: 1,
                language: 'english',
                version: 'kjv',
                textScale: textScale,
                translations: const [
                  InterlinearTranslation(
                    label: 'English · KJV',
                    direction: TextDirection.ltr,
                    verses: {
                      1: 'In the beginning was the Word, and the Word was with God.',
                    },
                  ),
                  InterlinearTranslation(
                    label: 'العربية · البستاني فاندايك',
                    direction: TextDirection.rtl,
                    verses: {1: 'في البدء كان الكلمة والكلمة كان عند الله.'},
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<TestGesture> hoverOver(WidgetTester tester, Finder finder) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: const Offset(-1, -1));
    await gesture.moveTo(tester.getCenter(finder));
    await tester.pump();
    return gesture;
  }

  Future<void> moveOutsideAndRemove(
    WidgetTester tester,
    TestGesture gesture,
  ) async {
    await gesture.moveTo(const Offset(2000, 2000));
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.removePointer();
  }

  String withoutDirectionalMarks(String value) {
    return value.replaceAll(RegExp('[\u200E\u200F\u2066\u2067\u2069]'), '');
  }

  group('Gospel combination matching', () {
    final johnAndMark = topicWith('john-mark', ['John', 'Mark']);
    final markLuke = topicWith('mark-luke', ['Mark', 'Luke']);
    final matthewMarkLuke = topicWith('matthew-mark-luke', [
      'Matthew',
      'Mark',
      'Luke',
    ]);
    final markLukeJohn = topicWith('mark-luke-john', ['Mark', 'Luke', 'John']);
    final matthewJohn = topicWith('matthew-john', ['Matthew', 'John']);
    final allFour = topicWith('all-four', ['Matthew', 'Mark', 'Luke', 'John']);

    GospelFilterCombination combination(String code) =>
        gospelFilterCombinationForCode(code)!;

    test('matches representative combinations from every Included group', () {
      expect(matchesFilter(allFour, combination('C01')), isTrue);
      expect(matchesFilter(matthewMarkLuke, combination('C01')), isFalse);

      expect(matchesFilter(matthewMarkLuke, combination('C02')), isTrue);
      expect(matchesFilter(allFour, combination('C02')), isFalse);

      expect(matchesFilter(matthewJohn, combination('C25')), isTrue);
      expect(matchesFilter(allFour, combination('C25')), isTrue);
      expect(matchesFilter(johnAndMark, combination('C25')), isFalse);

      expect(
        matchesFilter(
          topicWith('only-matthew', ['Matthew']),
          combination('C14'),
        ),
        isTrue,
      );
      expect(matchesFilter(matthewMarkLuke, combination('C14')), isFalse);
    });

    test('respects unrestricted Gospels without weakening Included ones', () {
      expect(matchesFilter(markLukeJohn, combination('C47')), isTrue);
      expect(matchesFilter(allFour, combination('C47')), isTrue);
      expect(matchesFilter(markLuke, combination('C47')), isFalse);

      expect(matchesFilter(johnAndMark, combination('C65')), isTrue);
      expect(
        matchesFilter(topicWith('only-john', ['John']), combination('C65')),
        isTrue,
      );
      expect(matchesFilter(markLuke, combination('C65')), isFalse);
    });

    test('exact one-Gospel assignments use the same canonical matcher', () {
      expect(
        matchesFilter(topicWith('only-mark', ['Mark']), combination('C32')),
        isTrue,
      );
      expect(matchesFilter(johnAndMark, combination('C32')), isFalse);
      expect(
        matchesFilter(topicWith('only-luke', ['Luke']), combination('C38')),
        isTrue,
      );
      expect(
        matchesFilter(topicWith('only-john', ['John']), combination('C40')),
        isTrue,
      );
    });

    test('All topics is the null reset state', () {
      expect(matchesFilter(markLuke, null), isTrue);
      expect(matchesFilter(allFour, null), isTrue);
    });

    test('precomputes presence and ignores empty placeholders', () {
      final topic = Topic(
        id: 'dash',
        name: 'Dash',
        references: const [
          GospelReference(book: 'John', chapter: 0, verses: '—'),
          GospelReference(book: 'Matthew', chapter: 0, verses: '   '),
          GospelReference(book: 'Luke', chapter: 2, verses: ''),
          GospelReference(book: 'Luke', chapter: 2, verses: '4-5'),
        ],
      );
      final empty = Topic(id: 'empty', name: 'Empty', references: const []);

      expect(topic.gospelPresenceMask, Gospel.luke.bit);
      expect(empty.gospelPresenceMask, 0);
      expect(hasReference(topic, 'John'), isFalse);
      expect(hasReference(topic, 'Matthew'), isFalse);
      expect(hasReference(topic, 'Luke'), isTrue);
      expect(getReferencedGospels(topic), {'Luke'});
    });
  });

  group('advanced Gospel processing pipeline', () {
    test('filters union, intersection, and post-operation exclusion', () {
      final topics = <Topic>[
        topicWith('mark', ['Mark']),
        topicWith('luke', ['Luke']),
        topicWith('both', ['Mark', 'Luke']),
        topicWith('both-john', ['Mark', 'Luke', 'John']),
      ];
      final union = GospelFilterState(
        mode: GospelFilterMode.union,
        includeMask: Gospel.mark.bit | Gospel.luke.bit,
      );
      final intersection = GospelFilterState(
        mode: GospelFilterMode.intersection,
        includeMask: Gospel.mark.bit | Gospel.luke.bit,
      );
      final excluded = union.copyWith(excludeMask: Gospel.john.bit);

      expect(
        processHarmonyTopicIndexes(
          topics,
          union,
          const GospelSortState(gospel: Gospel.mark),
        ).toSet(),
        {0, 1, 2, 3},
      );
      expect(
        processHarmonyTopicIndexes(
          topics,
          intersection,
          const GospelSortState(gospel: Gospel.mark),
        ).toSet(),
        {2, 3},
      );
      expect(
        processHarmonyTopicIndexes(
          topics,
          excluded,
          const GospelSortState(gospel: Gospel.mark),
        ).toSet(),
        {0, 1, 2},
      );
    });

    test('sorts numeric chapter and verse using the earliest reference', () {
      final topics = <Topic>[
        Topic(
          id: 'missing-leading',
          name: 'Leading',
          references: const [
            GospelReference(book: 'Matthew', chapter: 1, verses: '1'),
          ],
        ),
        Topic(
          id: 'chapter-2',
          name: 'Chapter 2',
          references: const [
            GospelReference(book: 'Mark', chapter: 2, verses: '1'),
          ],
        ),
        Topic(
          id: 'missing-near-2',
          name: 'Related',
          references: const [
            GospelReference(book: 'Luke', chapter: 1, verses: '1'),
          ],
        ),
        Topic(
          id: 'verse-14',
          name: 'Verse 14',
          references: const [
            GospelReference(book: 'Mark', chapter: 1, verses: '14'),
          ],
        ),
        Topic(
          id: 'multiple',
          name: 'Multiple',
          references: const [
            GospelReference(book: 'Mark', chapter: 3, verses: '5'),
            GospelReference(book: 'Mark', chapter: 1, verses: '2-4'),
          ],
        ),
      ];

      final indexes = processHarmonyTopicIndexes(
        topics,
        const GospelFilterState(),
        const GospelSortState(gospel: Gospel.mark),
      );

      expect(indexes, [0, 4, 3, 1, 2]);
      expect(
        topics[4].earliestGospelAnchors[Gospel.mark],
        const GospelChronologyAnchor(chapter: 1, verse: 2),
      );
    });

    test('localized digits parse into canonical chronology metadata', () {
      final reference = GospelReference.fromJson({
        'book': 'مرقس',
        'chapter': '٢',
        'verses': '١٤-١٥',
      });
      final topic = Topic(id: 'ar', name: 'Arabic', references: [reference]);

      expect(hasGospelReference(topic, Gospel.mark), isTrue);
      expect(
        topic.earliestGospelAnchors[Gospel.mark],
        const GospelChronologyAnchor(chapter: 2, verse: 14),
      );
    });

    test('Luke chronology remains available while Luke is hidden', () {
      final topics = <Topic>[
        Topic(
          id: 'later',
          name: 'Later',
          references: const [
            GospelReference(book: 'Luke', chapter: 2, verses: '1'),
            GospelReference(book: 'Matthew', chapter: 4, verses: '1'),
          ],
        ),
        Topic(
          id: 'earlier',
          name: 'Earlier',
          references: const [
            GospelReference(book: 'Luke', chapter: 1, verses: '20'),
            GospelReference(book: 'Matthew', chapter: 5, verses: '1'),
          ],
        ),
      ];
      final columns = ColumnVisibilityState(
        visibleMask: Gospel.matthew.bit | Gospel.mark.bit | Gospel.john.bit,
      );

      expect(columns.isVisible(Gospel.luke), isFalse);
      expect(
        processHarmonyTopicIndexes(
          topics,
          const GospelFilterState(),
          const GospelSortState(gospel: Gospel.luke),
          columns,
        ),
        [1, 0],
      );
    });

    test('hidden columns prune rows only after advanced filtering', () {
      final topics = <Topic>[
        topicWith('only-luke', ['Luke']),
        topicWith('matthew-luke', ['Matthew', 'Luke']),
        topicWith('luke-john', ['Luke', 'John']),
      ];
      final withoutLuke = ColumnVisibilityState(
        visibleMask: Gospel.matthew.bit | Gospel.mark.bit | Gospel.john.bit,
      );
      final withoutLukeOrJohn = ColumnVisibilityState(
        visibleMask: Gospel.matthew.bit | Gospel.mark.bit,
      );

      expect(
        processHarmonyTopicIndexes(
          topics,
          const GospelFilterState(),
          const GospelSortState(),
          withoutLuke,
        ),
        [1, 2],
      );
      expect(
        processHarmonyTopicIndexes(
          topics,
          const GospelFilterState(),
          const GospelSortState(),
          withoutLukeOrJohn,
        ),
        [1],
      );

      final lukeFilter = GospelFilterState(includeMask: Gospel.luke.bit);
      expect(
        processHarmonyTopicIndexes(
          topics,
          lukeFilter,
          const GospelSortState(gospel: Gospel.luke),
          withoutLuke,
        ),
        [1, 2],
      );
    });

    test(
      'Default uses canonical source order and every chronology is valid',
      () {
        final topics = <Topic>[
          Topic(
            id: 'three',
            canonicalOrder: 3,
            name: 'Three',
            references: const [
              GospelReference(book: 'Matthew', chapter: 3, verses: '1'),
              GospelReference(book: 'Mark', chapter: 3, verses: '1'),
              GospelReference(book: 'Luke', chapter: 3, verses: '1'),
              GospelReference(book: 'John', chapter: 3, verses: '1'),
            ],
          ),
          Topic(
            id: 'one',
            canonicalOrder: 1,
            name: 'One',
            references: const [
              GospelReference(book: 'Matthew', chapter: 1, verses: '1'),
              GospelReference(book: 'Mark', chapter: 1, verses: '1'),
              GospelReference(book: 'Luke', chapter: 1, verses: '1'),
              GospelReference(book: 'John', chapter: 1, verses: '1'),
            ],
          ),
          Topic(
            id: 'two',
            canonicalOrder: 2,
            name: 'Two',
            references: const [
              GospelReference(book: 'Matthew', chapter: 2, verses: '1'),
              GospelReference(book: 'Mark', chapter: 2, verses: '1'),
              GospelReference(book: 'Luke', chapter: 2, verses: '1'),
              GospelReference(book: 'John', chapter: 2, verses: '1'),
            ],
          ),
        ];

        expect(
          processHarmonyTopics(
            topics,
            const GospelFilterState(),
            const GospelSortState(),
            const ColumnVisibilityState(),
          ).topics.map((topic) => topic.id),
          ['one', 'two', 'three'],
        );
        for (final gospel in Gospel.values) {
          expect(
            processHarmonyTopics(
              topics,
              const GospelFilterState(),
              GospelSortState.forGospel(gospel),
              const ColumnVisibilityState(),
            ).topics.map((topic) => topic.id),
            ['one', 'two', 'three'],
          );
        }
      },
    );

    test('counts visible topic rows and individual visible references', () {
      final topics = <Topic>[
        Topic(
          id: '1',
          name: 'Many',
          references: const [
            GospelReference(book: 'Matthew', chapter: 1, verses: '1'),
            GospelReference(book: 'Mark', chapter: 1, verses: '2'),
            GospelReference(book: 'Mark', chapter: 1, verses: '3'),
            GospelReference(book: 'John', chapter: 1, verses: '4'),
          ],
        ),
        topicWith('only-john', ['John']),
      ];
      final columns = ColumnVisibilityState(
        visibleMask: Gospel.matthew.bit | Gospel.mark.bit,
      );
      final result = processHarmonyTopics(
        topics,
        const GospelFilterState(),
        const GospelSortState(),
        columns,
      );

      expect(result.visibleTopicCount, 1);
      expect(result.visibleReferenceCount, 3);
    });

    test('structured separators count logical selections', () {
      Topic structuredTopic(String raw, List<Map<String, Object?>> segments) {
        return Topic.fromJson({
          'id': '1',
          'name': 'Structured',
          'referenceCells': [
            {'book': 'Luke', 'raw': raw, 'segments': segments},
          ],
        });
      }

      final continuous = structuredTopic('1:78-80 + 2:1-7', [
        {'chapter': 1, 'verses': '78-80'},
        {'chapter': 2, 'verses': '1-7', 'separatorBefore': '+'},
      ]);
      final sameChapter = structuredTopic('6:17-19, 27-36', [
        {'chapter': 6, 'verses': '17-19'},
        {'chapter': 6, 'verses': '27-36', 'separatorBefore': ','},
      ]);
      final nonContinuous = structuredTopic('5:31-32; 19:9', [
        {'chapter': 5, 'verses': '31-32'},
        {'chapter': 19, 'verses': '9', 'separatorBefore': ';'},
      ]);

      expect(continuous.references, hasLength(2));
      expect(continuous.referenceCells.single.logicalSelectionCount, 1);
      expect(
        countVisibleReferences([continuous], const ColumnVisibilityState()),
        1,
      );
      expect(
        countVisibleReferences([sameChapter], const ColumnVisibilityState()),
        2,
      );
      expect(
        countVisibleReferences([nonContinuous], const ColumnVisibilityState()),
        2,
      );
    });
  });

  group('cross-language canonical reference presence', () {
    Topic translatedTopic({
      required String id,
      required int mask,
      required bool arabic,
    }) {
      final arabicNames = <Gospel, String>{
        Gospel.matthew: 'متى',
        Gospel.mark: 'مرقس',
        Gospel.luke: 'لوقا',
        Gospel.john: 'يوحنا',
      };
      return Topic.fromJson({
        'id': id,
        'canonicalOrder': int.parse(id),
        'name': arabic ? 'موضوع $id' : 'Topic $id',
        'references': [
          for (final gospel in Gospel.values)
            if (mask & gospel.bit != 0)
              {
                'gospel': gospel.canonicalName,
                'book': arabic ? arabicNames[gospel] : gospel.canonicalName,
                'chapter': arabic ? '١' : 1,
                'verses': arabic ? '٢-٣' : '2-3',
              },
        ],
      });
    }

    test('English and Arabic datasets match every requested set operation', () {
      final masks = <int>[
        Gospel.mark.bit,
        Gospel.luke.bit,
        Gospel.mark.bit | Gospel.luke.bit,
        Gospel.mark.bit | Gospel.luke.bit | Gospel.john.bit,
        Gospel.matthew.bit | Gospel.mark.bit,
        Gospel.matthew.bit | Gospel.mark.bit | Gospel.luke.bit,
      ];
      final english = [
        for (var index = 0; index < masks.length; index++)
          translatedTopic(
            id: '${index + 1}',
            mask: masks[index],
            arabic: false,
          ),
      ];
      final arabic = [
        for (var index = 0; index < masks.length; index++)
          translatedTopic(id: '${index + 1}', mask: masks[index], arabic: true),
      ];
      expect(
        arabic.map((topic) => topic.gospelPresenceMask),
        english.map((topic) => topic.gospelPresenceMask),
      );

      final filters = <GospelFilterState>[
        GospelFilterState(
          mode: GospelFilterMode.union,
          includeMask: Gospel.mark.bit | Gospel.luke.bit,
        ),
        GospelFilterState(
          mode: GospelFilterMode.intersection,
          includeMask: Gospel.mark.bit | Gospel.luke.bit,
        ),
        GospelFilterState(
          mode: GospelFilterMode.union,
          includeMask: Gospel.mark.bit | Gospel.luke.bit,
          excludeMask: Gospel.john.bit,
        ),
        GospelFilterState(
          mode: GospelFilterMode.intersection,
          includeMask: Gospel.matthew.bit | Gospel.mark.bit,
          excludeMask: Gospel.luke.bit,
        ),
      ];
      for (final filter in filters) {
        final englishIds = processHarmonyTopics(
          english,
          filter,
          const GospelSortState(),
          const ColumnVisibilityState(),
        ).topics.map((topic) => topic.id);
        final arabicIds = processHarmonyTopics(
          arabic,
          filter,
          const GospelSortState(),
          const ColumnVisibilityState(),
        ).topics.map((topic) => topic.id);
        expect(arabicIds, englishIds);
      }
    });

    test('version-shaped datasets preserve active table state', () {
      final filter = GospelFilterState(
        mode: GospelFilterMode.union,
        includeMask: Gospel.mark.bit | Gospel.luke.bit,
        excludeMask: Gospel.john.bit,
      );
      final columns = ColumnVisibilityState(
        visibleMask: Gospel.matthew.bit | Gospel.mark.bit,
      );
      final datasets = <List<Topic>>[
        for (final arabic in [false, false, true])
          [
            translatedTopic(id: '1', mask: Gospel.mark.bit, arabic: arabic),
            translatedTopic(
              id: '2',
              mask: Gospel.matthew.bit | Gospel.luke.bit,
              arabic: arabic,
            ),
            translatedTopic(
              id: '3',
              mask: Gospel.mark.bit | Gospel.john.bit,
              arabic: arabic,
            ),
          ],
      ];

      for (final dataset in datasets) {
        final result = processHarmonyTopics(
          dataset,
          filter,
          const GospelSortState(gospel: Gospel.luke),
          columns,
        );
        expect(result.topics.map((topic) => topic.id), ['1', '2']);
        expect(result.visibleReferenceCount, 2);
      }
    });

    test('loose maps, lists, nulls, whitespace, and dashes parse once', () {
      final topic = Topic.fromJson({
        'id': '1',
        'name': 'Loose',
        'references': {
          'Luke': [null, '', '   ', '–', '2:1', '2:3'],
          'Mark': '—',
        },
      });

      expect(topic.gospelPresenceMask, Gospel.luke.bit);
      expect(hasGospelReference(topic, Gospel.luke), isTrue);
      expect(hasGospelReference(topic, Gospel.mark), isFalse);
      expect(countVisibleReferences([topic], const ColumnVisibilityState()), 2);
    });

    test('malformed structured cells fall back to complete legacy entries', () {
      final topic = Topic.fromJson({
        'id': '1',
        'name': 'Fallback',
        'referenceCells': [
          {
            'book': 'Luke',
            'segments': [
              {'chapter': 1, 'verses': '1'},
            ],
          },
          {
            'book': 'John',
            'segments': [
              {'chapter': 0, 'verses': 'invalid'},
            ],
          },
        ],
        'references': [
          {'book': 'Luke', 'chapter': 1, 'verses': '1'},
          {'book': 'John', 'chapter': 8, 'verses': '34'},
        ],
      });

      expect(topic.referenceCells, isEmpty);
      expect(topic.references, hasLength(2));
      expect(topic.gospelPresenceMask, Gospel.luke.bit | Gospel.john.bit);
    });
  });

  testWidgets('interlinear rows apply zoom to LTR and RTL text immediately', (
    tester,
  ) async {
    await tester.pumpWidget(interlinearGroupFor(1.0));

    final richTextFinder = find.descendant(
      of: find.byType(InterlinearVerseGroup),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is RichText && widget.text.toPlainText().contains('('),
      ),
    );
    expect(richTextFinder, findsNWidgets(2));
    final normalHeight = tester.getSize(richTextFinder.first).height;
    for (final richText in tester.widgetList<RichText>(richTextFinder)) {
      expect(richText.textScaler.scale(16), closeTo(16, 0.01));
    }
    expect(
      Directionality.of(tester.element(richTextFinder.at(0))),
      TextDirection.ltr,
    );
    expect(
      Directionality.of(tester.element(richTextFinder.at(1))),
      TextDirection.rtl,
    );

    await tester.pumpWidget(interlinearGroupFor(1.6));

    final zoomedHeight = tester.getSize(richTextFinder.first).height;
    expect(zoomedHeight, greaterThan(normalHeight));
    for (final richText in tester.widgetList<RichText>(richTextFinder)) {
      expect(richText.textScaler.scale(16), closeTo(25.6, 0.01));
    }
    final verseMarker = tester.widget<Text>(find.text('1'));
    expect(verseMarker.textScaler!.scale(16), closeTo(25.6, 0.01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Arabic set filter is localized, live, and RTL', (tester) async {
    final arabic = kBaseLanguageOptions.firstWhere(
      (option) => option.code == 'arabic',
    );
    var selected = const GospelFilterState();
    final masks = <int>[
      Gospel.mark.bit,
      Gospel.luke.bit,
      Gospel.mark.bit | Gospel.luke.bit,
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: MenuLanguageScope(
          notifier: ValueNotifier<String>('arabic'),
          child: Scaffold(
            body: Center(
              child: HarmonyFilterButton(
                filterState: selected,
                uiLanguage: arabic,
                topics: topicsFromMasks(masks),
                columns: const ColumnVisibilityState(),
                currentResultCount: 3,
                onChanged: (state) => selected = state,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('تصفية'), findsOneWidget);
    await tester.tap(find.text('تصفية'));
    await tester.pumpAndSettle();

    expect(find.text('العملية'), findsOneWidget);
    expect(find.text('اتحاد'), findsOneWidget);
    expect(find.text('تقاطع'), findsWidgets);
    expect(find.text('إزالة التصفية'), findsWidgets);
    expect(find.text('٣ موضوعًا'), findsWidgets);
    expect(
      Directionality.of(tester.element(find.text('العملية'))),
      TextDirection.rtl,
    );
    final operation = tester.widget<SegmentedButton<GospelFilterMode>>(
      find.byKey(const ValueKey<String>('filter-operation')),
    );
    expect(operation.segments.map((segment) => segment.value), [
      GospelFilterMode.intersection,
      GospelFilterMode.union,
    ]);
    expect(operation.selected, {GospelFilterMode.intersection});
    expect(operation.showSelectedIcon, isFalse);
    expect(find.byIcon(Icons.join_full), findsOneWidget);
    expect(find.byIcon(Icons.join_inner), findsOneWidget);

    await tester.tap(find.text('تقاطع').first);
    await tester.tap(find.byKey(const ValueKey<String>('include-mark')));
    await tester.tap(find.byKey(const ValueKey<String>('include-luke')));
    await tester.pump();

    expect(selected.mode, GospelFilterMode.intersection);
    expect(find.byIcon(Icons.join_inner), findsOneWidget);
    expect(selected.includeMask, Gospel.mark.bit | Gospel.luke.bit);
    expect(find.text('مرقس ∩ لوقا'), findsOneWidget);
    expect(find.text('١ موضوعًا'), findsWidgets);
  });

  testWidgets(
    'English set filter builds union then exclusion with live counts',
    (tester) async {
      var selected = const GospelFilterState();
      var commits = 0;
      final masks = <int>[
        Gospel.mark.bit,
        Gospel.luke.bit,
        Gospel.mark.bit | Gospel.luke.bit,
        Gospel.mark.bit | Gospel.luke.bit | Gospel.john.bit,
        Gospel.matthew.bit,
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: MenuLanguageScope(
            notifier: ValueNotifier<String>('english'),
            child: Scaffold(
              body: Center(
                child: HarmonyFilterButton(
                  filterState: selected,
                  uiLanguage: kBaseLanguageOptions.first,
                  topics: topicsFromMasks(masks),
                  columns: const ColumnVisibilityState(),
                  currentResultCount: 5,
                  onChanged: (state) => selected = state,
                  onInteractionEnd: () => commits++,
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Filter'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Union').first);
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey<String>('include-mark')));
      await tester.pump();
      expect(find.text('Mark'), findsWidgets);
      expect(find.text('3 topics'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey<String>('include-luke')));
      await tester.pump();
      expect(find.text('Mark ∪ Luke'), findsOneWidget);
      expect(find.text('4 topics'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey<String>('exclude-john')));
      await tester.pump();
      expect(find.text('(Mark ∪ Luke) − John'), findsOneWidget);
      expect(find.text('3 topics'), findsWidgets);
      expect(selected.mode, GospelFilterMode.union);
      expect(selected.includeMask, Gospel.mark.bit | Gospel.luke.bit);
      expect(selected.excludeMask, Gospel.john.bit);
      expect(find.text('Apply filter'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('apply-filter')));
      await tester.pumpAndSettle();
      expect(find.text('Operation'), findsNothing);
      expect(commits, 1);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HarmonyFilterButton(
              filterState: selected,
              uiLanguage: kBaseLanguageOptions.first,
              topics: topicsFromMasks(masks),
              columns: const ColumnVisibilityState(),
              onChanged: (state) => selected = state,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Filter'));
      await tester.pumpAndSettle();
      final reopenedOperation = tester
          .widget<SegmentedButton<GospelFilterMode>>(
            find.byKey(const ValueKey<String>('filter-operation')),
          );
      expect(reopenedOperation.selected, {GospelFilterMode.union});
    },
  );

  testWidgets('filter changes update the outside count live', (tester) async {
    var state = const GospelFilterState();
    final masks = <int>[Gospel.mark.bit, Gospel.luke.bit, Gospel.john.bit];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              final count = masks.where(state.matchesPresenceMask).length;
              return Column(
                children: [
                  HarmonyFilterButton(
                    filterState: state,
                    uiLanguage: kBaseLanguageOptions.first,
                    topics: topicsFromMasks(masks),
                    columns: const ColumnVisibilityState(),
                    currentResultCount: count,
                    onChanged: (value) {
                      setState(() {
                        state = value;
                      });
                    },
                  ),
                  Text('outside-count-$count'),
                ],
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Filter'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('include-mark')));
    await tester.pump();

    expect(find.text('outside-count-1'), findsOneWidget);
    expect(find.text('1 topics'), findsWidgets);
  });

  testWidgets('filter browser uses a full-height mobile layout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: HarmonyFilterButton(
              filterState: const GospelFilterState(),
              uiLanguage: kBaseLanguageOptions.first,
              topics: const <Topic>[],
              columns: const ColumnVisibilityState(),
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Filter'));
    await tester.pumpAndSettle();

    final dialogSize = tester.getSize(find.byType(Dialog));
    expect(dialogSize.width, greaterThanOrEqualTo(380));
    expect(dialogSize.height, greaterThanOrEqualTo(760));
    expect(find.text('Include Gospels'), findsOneWidget);
    expect(find.text('Apply filter'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Escape closes the Gospel filter browser', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HarmonyFilterButton(
            filterState: const GospelFilterState(),
            uiLanguage: kBaseLanguageOptions.first,
            topics: const <Topic>[],
            columns: const ColumnVisibilityState(),
            onChanged: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('Filter'));
    await tester.pumpAndSettle();
    expect(find.text('Operation'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('Operation'), findsNothing);
  });

  testWidgets('browser route links ignore taps while navigation is blocked', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        routes: {'/topic': (_) => const Scaffold(body: Text('Topic page'))},
        home: Scaffold(
          body: BrowserRouteLink(
            uri: Uri(path: '/topic'),
            builder: (context, followLink) => TextButton(
              onPressed: followLink,
              child: const Text('Open topic'),
            ),
          ),
        ),
      ),
    );

    BrowserRouteLinkNavigation.pushBlock();
    addTearDown(BrowserRouteLinkNavigation.popBlock);

    await tester.tap(find.text('Open topic'));
    await tester.pumpAndSettle();

    expect(find.text('Topic page'), findsNothing);
    expect(find.text('Open topic'), findsOneWidget);
  });

  testWidgets('single-reference harmony cells keep per-reference hover', (
    tester,
  ) async {
    await tester.pumpWidget(
      harmonyTableFor(const [
        GospelReference(book: 'Luke', chapter: 4, verses: '42-44'),
      ]),
    );

    expect(find.byType(ReferenceCellHoverPreview), findsNothing);
    final reference = tester.widget<ReferenceHoverText>(
      find.byType(ReferenceHoverText),
    );
    expect(reference.enableHoverPreview, isTrue);
    expect(reference.showHoverTooltip, isFalse);
    expect(reference.openInNewTab, isTrue);
  });

  testWidgets('main-table reference URI is complete and opens in a new tab', (
    tester,
  ) async {
    const reference = GospelReference(
      book: 'Luke',
      bookId: 'luke',
      chapter: 4,
      verses: '42-44',
    );
    final option = kBaseLanguageOptions.first;

    await tester.pumpWidget(harmonyTableFor(const [reference]));

    final routeLink = tester.widget<BrowserRouteLink>(
      find.descendant(
        of: find.byType(ReferenceHoverText),
        matching: find.byType(BrowserRouteLink),
      ),
    );
    expect(routeLink.openInNewTab, isTrue);
    expect(routeLink.uri?.path, '/reference');
    expect(routeLink.uri?.queryParameters, {
      'menuLanguage': 'english',
      'book': 'luke',
      'bookDisplay': 'Luke',
      'chapter': '4',
      'topicLanguage': 'english',
      'bibleLanguage': option.apiLanguage,
      'language': option.apiLanguage,
      'version': option.apiVersion,
      'label': '4:42-44',
      'verses': '42-44',
      'topic': 'Teaching and healings',
      'topicId': '34',
      'topicNumber': '34',
      'source': 'harmony',
      'gospel': 'Luke',
    });

    final topicLink = tester
        .widgetList<BrowserRouteLink>(find.byType(BrowserRouteLink))
        .singleWhere((link) => link.uri?.path == '/topic');
    expect(topicLink.openInNewTab, isFalse);
  });

  testWidgets('reference links mirror the primary language in every field', (
    tester,
  ) async {
    const reference = GospelReference(
      book: 'Luke',
      bookId: 'luke',
      chapter: 2,
      verses: '1-7',
    );
    final combinations = <(TopicLanguageOption, LanguageOption, String)>[
      (bundledTopicLanguages.last, kBaseLanguageOptions.last, 'ميلاد يسوع'),
      (
        bundledTopicLanguages.first,
        kBaseLanguageOptions.first,
        'Birth of Jesus',
      ),
    ];

    for (final (topicLanguage, bibleLanguage, title) in combinations) {
      await tester.pumpWidget(
        harmonyTableFor(
          const [reference],
          languageOption: bibleLanguage,
          topicLanguage: topicLanguage,
          topicName: title,
        ),
      );
      await tester.pump();

      expect(find.text(title), findsOneWidget);
      expect(find.text(topicLanguage.subjectsLabel), findsOneWidget);
      expect(find.text(topicLanguage.gospelNames[2]), findsOneWidget);
      final hover = tester.widget<ReferenceHoverText>(
        find.byType(ReferenceHoverText),
      );
      expect(hover.language, bibleLanguage.apiLanguage);
      expect(hover.version, bibleLanguage.apiVersion);

      final link = tester.widget<BrowserRouteLink>(
        find.descendant(
          of: find.byType(ReferenceHoverText),
          matching: find.byType(BrowserRouteLink),
        ),
      );
      expect(link.uri?.queryParameters['menuLanguage'], bibleLanguage.code);
      expect(link.uri?.queryParameters['topicLanguage'], bibleLanguage.code);
      expect(
        link.uri?.queryParameters['bibleLanguage'],
        bibleLanguage.apiLanguage,
      );
    }
  });

  testWidgets('single-reference preview waits and cancels an early hover', (
    tester,
  ) async {
    await tester.pumpWidget(
      harmonyTableFor(const [
        GospelReference(book: 'Luke', chapter: 4, verses: '42-44'),
      ]),
    );

    final reference = find.byType(ReferenceHoverText);
    final gesture = await hoverOver(tester, reference);

    await tester.pump(const Duration(milliseconds: 1000));
    expect(find.text('Click to read in chapter'), findsNothing);

    await gesture.moveTo(const Offset(2000, 2000));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Click to read in chapter'), findsNothing);

    await gesture.moveTo(tester.getCenter(reference));
    await tester.pump(const Duration(milliseconds: 1499));
    expect(find.text('Click to read in chapter'), findsNothing);

    await tester.pump(const Duration(milliseconds: 1));
    expect(find.text('Click to read in chapter'), findsOneWidget);

    final referenceLinks = tester
        .widgetList<BrowserRouteLink>(find.byType(BrowserRouteLink))
        .where((link) => link.uri?.path == '/reference');
    expect(referenceLinks, hasLength(2));
    expect(referenceLinks.every((link) => link.openInNewTab), isTrue);

    await moveOutsideAndRemove(tester, gesture);
  });

  testWidgets('main-table references have no redundant hover tooltip', (
    tester,
  ) async {
    await tester.pumpWidget(
      harmonyTableFor(const [
        GospelReference(book: 'Luke', chapter: 4, verses: '42-44'),
      ]),
    );

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Tooltip && widget.message == 'Click to read in chapter',
      ),
      findsNothing,
    );
  });

  testWidgets('topic hover tooltip only shows helper text', (tester) async {
    await tester.pumpWidget(
      harmonyTableFor(const [
        GospelReference(book: 'Luke', chapter: 4, verses: '42-44'),
      ]),
    );

    final tooltipFinder = find.byWidgetPredicate(
      (widget) =>
          widget is Tooltip && widget.message == 'Click to read all references',
    );

    expect(tooltipFinder, findsOneWidget);
    final tooltip = tester.widget<Tooltip>(tooltipFinder);
    expect(tooltip.message, isNot(contains('Teaching and healings')));
  });

  testWidgets('version menu has no check while awaiting explicit choice', (
    tester,
  ) async {
    LanguageOption? selectedLanguage;
    String? selectedVersion;
    var translationChanges = 0;
    MenuLanguageController.instance.notifier.value = 'english';

    await tester.pumpWidget(
      MenuLanguageScope(
        notifier: MenuLanguageController.instance.notifier,
        child: MaterialApp(
          home: Scaffold(
            body: AppToolbar(
              language: kBaseLanguageOptions.first,
              version: 'kjv',
              languages: kBaseLanguageOptions,
              onLanguageChanged: (_) {},
              onVersionChanged: (_) {},
              onTranslationChanged: (language, version) {
                translationChanges++;
                selectedLanguage = language;
                selectedVersion = version;
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Language: English'));
    await tester.pumpAndSettle();
    expect(BrowserRouteLinkNavigation.isBlocked, isTrue);
    await tester.tap(find.text('Arabic').last);
    await tester.pumpAndSettle();

    expect(selectedLanguage, isNull);
    expect(selectedVersion, isNull);
    expect(BrowserRouteLinkNavigation.isBlocked, isTrue);
    expect(find.text('Translation: Select version'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNothing);

    await tester.tap(find.text('كتاب الحياة').last);
    await tester.pumpAndSettle();

    expect(selectedLanguage?.code, 'arabic');
    expect(selectedVersion, 'New Arabic Version');
    expect(translationChanges, 1);
  });

  testWidgets('language selector caption and names follow Arabic UI', (
    tester,
  ) async {
    MenuLanguageController.instance.update('arabic');

    await tester.pumpWidget(
      MenuLanguageScope(
        notifier: MenuLanguageController.instance.notifier,
        child: MaterialApp(
          home: Scaffold(
            body: AppToolbar(
              language: kBaseLanguageOptions.last,
              version: 'Van Dyke-',
              languages: kBaseLanguageOptions,
              onLanguageChanged: (_) {},
              onVersionChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.byTooltip('اللغة: العربية'), findsOneWidget);
    await tester.tap(find.byTooltip('اللغة: العربية'));
    await tester.pumpAndSettle();
    expect(find.text('الإنجليزية'), findsOneWidget);
    expect(find.text('العربية'), findsWidgets);

    MenuLanguageController.instance.update('english');
  });

  testWidgets('desktop configuration dialogs drag and stay in the viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HarmonyFilterButton(
            filterState: const GospelFilterState(),
            uiLanguage: kBaseLanguageOptions.first,
            topics: [
              topicWith('1', ['Mark']),
            ],
            columns: const ColumnVisibilityState(),
            onChanged: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('Filter'));
    await tester.pumpAndSettle();
    final header = find.byKey(
      const ValueKey<String>('draggable-dialog-header'),
    );
    final dialog = find.byKey(
      const ValueKey<String>('draggable-dialog-surface'),
    );
    final transform = find.byKey(
      const ValueKey<String>('draggable-dialog-transform'),
    );
    expect(transform, findsOneWidget);
    final initialTopLeft = tester.getTopLeft(dialog);

    final gesture = await tester.startGesture(
      tester.getTopLeft(header) + const Offset(36, 24),
    );
    await gesture.moveBy(const Offset(30, 20));
    await tester.pump();
    await gesture.moveBy(const Offset(90, 50));
    await gesture.up();
    await tester.pump();
    final movedTransform = tester.widget<Transform>(transform);
    expect(movedTransform.transform.getTranslation().x, greaterThan(0));
    expect(tester.getTopLeft(dialog).dx, greaterThan(initialTopLeft.dx));
    expect(tester.getTopLeft(dialog).dy, greaterThan(initialTopLeft.dy));

    await tester.drag(header, const Offset(-5000, -5000));
    await tester.pump();
    final clampedRect = tester.getRect(dialog);
    expect(clampedRect.left, greaterThanOrEqualTo(0));
    expect(clampedRect.top, greaterThanOrEqualTo(0));
  });

  testWidgets('multi-reference harmony cells use one combined hover target', (
    tester,
  ) async {
    await tester.pumpWidget(
      harmonyTableFor(const [
        GospelReference(book: 'Luke', chapter: 4, verses: '42-44'),
        GospelReference(book: 'Luke', chapter: 6, verses: '17-19'),
      ]),
    );

    expect(find.byType(ReferenceCellHoverPreview), findsOneWidget);
    final referenceLinks = tester.widgetList<ReferenceHoverText>(
      find.byType(ReferenceHoverText),
    );
    expect(referenceLinks, hasLength(2));
    expect(
      referenceLinks.every((reference) => !reference.enableHoverPreview),
      isTrue,
    );
    expect(
      referenceLinks.every((reference) => !reference.showHoverTooltip),
      isTrue,
    );
    expect(referenceLinks.every((reference) => reference.openInNewTab), isTrue);
    expect(
      tester
          .widget<ReferenceCellHoverPreview>(
            find.byType(ReferenceCellHoverPreview),
          )
          .openInNewTab,
      isTrue,
    );
  });

  testWidgets('reference relation separators use compact synopsis notation', (
    tester,
  ) async {
    await tester.pumpWidget(
      harmonyTableFor(const [
        GospelReference(book: 'Luke', chapter: 4, verses: '42-44'),
        GospelReference(
          book: 'Luke',
          chapter: 5,
          verses: '1-2',
          separatorBefore: '+',
        ),
        GospelReference(
          book: 'Luke',
          chapter: 6,
          verses: '17-19',
          separatorBefore: ';',
        ),
        GospelReference(
          book: 'Luke',
          chapter: 6,
          verses: '27-36',
          separatorBefore: ',',
        ),
      ]),
    );

    final referenceLinks = tester.widgetList<ReferenceHoverText>(
      find.byType(ReferenceHoverText),
    );
    expect(referenceLinks.map((link) => link.labelOverride), [
      '4:42',
      '5:2',
      '6:17–19',
      '27–36',
    ]);
    expect(find.text(' '), findsOneWidget);
    expect(find.text('–'), findsNothing);
    expect(find.text('; '), findsOneWidget);
    expect(find.text(', '), findsOneWidget);
    expect(find.text('+'), findsNothing);
  });

  testWidgets('continuous preview keeps the exact compact cell reference', (
    tester,
  ) async {
    await tester.pumpWidget(
      harmonyTableFor(const [
        GospelReference(book: 'Matthew', chapter: 10, verses: '40-42'),
        GospelReference(
          book: 'Matthew',
          chapter: 11,
          verses: '1',
          separatorBefore: '+',
        ),
      ]),
    );

    final gesture = await hoverOver(
      tester,
      find.byType(ReferenceCellHoverPreview),
    );
    await tester.pump(const Duration(milliseconds: 1500));

    expect(find.text('10:40'), findsOneWidget);
    expect(find.text('11:1'), findsOneWidget);
    expect(find.text('Matthew 10:40 11:1'), findsOneWidget);
    expect(find.textContaining('10:40-42'), findsNothing);
    expect(find.text('Click to read in chapter'), findsOneWidget);
    expect(find.text('+'), findsNothing);

    await moveOutsideAndRemove(tester, gesture);
  });

  testWidgets('comma preview uses one compact heading and no divider', (
    tester,
  ) async {
    await tester.pumpWidget(
      harmonyTableFor(const [
        GospelReference(book: 'Matthew', chapter: 9, verses: '18-19'),
        GospelReference(
          book: 'Matthew',
          chapter: 9,
          verses: '23-26',
          separatorBefore: ',',
        ),
      ]),
    );

    final referenceLinks = tester.widgetList<ReferenceHoverText>(
      find.byType(ReferenceHoverText),
    );
    expect(referenceLinks, hasLength(2));
    expect(referenceLinks.map((link) => link.reference.verses), [
      '18-19',
      '23-26',
    ]);
    final routeLinks = tester
        .widgetList<BrowserRouteLink>(find.byType(BrowserRouteLink))
        .where((link) => link.uri?.path == '/reference');
    expect(
      routeLinks.map((link) => link.uri?.queryParameters['verses']).toSet(),
      {'18-19', '23-26'},
    );

    final gesture = await hoverOver(
      tester,
      find.byType(ReferenceCellHoverPreview),
    );
    await tester.pump(const Duration(milliseconds: 1500));

    expect(find.text('Matthew 9:18–19, 23–26'), findsOneWidget);
    expect(find.textContaining('&'), findsNothing);
    expect(find.byType(Divider), findsNothing);
    final selectionGap = find.byKey(
      const ValueKey<String>('same-chapter-selection-gap-1'),
    );
    expect(selectionGap, findsOneWidget);
    expect(tester.widget<SizedBox>(selectionGap).height, 10);
    expect(find.text('Click to read in chapter'), findsOneWidget);

    final combinedRoute = tester
        .widgetList<BrowserRouteLink>(find.byType(BrowserRouteLink))
        .singleWhere(
          (link) =>
              link.uri?.path == '/reference' &&
              link.uri?.queryParameters['verses'] == '18-19,23-26',
        );
    expect(combinedRoute.uri?.queryParameters['label'], '9:18–19, 23–26');

    await moveOutsideAndRemove(tester, gesture);
  });

  testWidgets('semicolon preview keeps separate sections and a divider', (
    tester,
  ) async {
    await tester.pumpWidget(
      harmonyTableFor(const [
        GospelReference(book: 'John', chapter: 8, verses: '1-12'),
        GospelReference(
          book: 'John',
          chapter: 8,
          verses: '20-25',
          separatorBefore: ';',
        ),
      ]),
    );

    final gesture = await hoverOver(
      tester,
      find.byType(ReferenceCellHoverPreview),
    );
    await tester.pump(const Duration(milliseconds: 1500));

    expect(find.text('John 8:1–12'), findsOneWidget);
    expect(find.text('John 8:20–25'), findsOneWidget);
    expect(find.byType(Divider), findsOneWidget);
    expect(find.text('Click to read in chapter'), findsNWidgets(2));

    await moveOutsideAndRemove(tester, gesture);
  });

  testWidgets('combined preview also waits for the hover delay', (
    tester,
  ) async {
    await tester.pumpWidget(
      harmonyTableFor(const [
        GospelReference(book: 'Luke', chapter: 4, verses: '42-44'),
        GospelReference(book: 'Luke', chapter: 6, verses: '17-19'),
      ]),
    );

    final combinedCell = find.byType(ReferenceCellHoverPreview);
    final gesture = await hoverOver(tester, combinedCell);

    await tester.pump(const Duration(milliseconds: 1499));
    expect(find.text('Click to read in chapter'), findsNothing);

    await tester.pump(const Duration(milliseconds: 1));
    expect(find.text('Click to read in chapter'), findsNWidgets(2));

    await moveOutsideAndRemove(tester, gesture);
  });

  testWidgets('Arabic main-table references preserve RTL hover configuration', (
    tester,
  ) async {
    final arabic = kBaseLanguageOptions.firstWhere(
      (option) => option.code == 'arabic',
    );
    await tester.pumpWidget(
      harmonyTableFor(const [
        GospelReference(book: 'Matthew', chapter: 9, verses: '18-19'),
        GospelReference(
          book: 'Matthew',
          chapter: 9,
          verses: '23-26',
          separatorBefore: ',',
        ),
      ], languageOption: arabic),
    );

    final combined = tester.widget<ReferenceCellHoverPreview>(
      find.byType(ReferenceCellHoverPreview),
    );
    expect(combined.textDirection, TextDirection.rtl);
    expect(combined.language, arabic.apiLanguage);
    expect(combined.openInNewTab, isTrue);
    final referenceRoutes = tester
        .widgetList<BrowserRouteLink>(find.byType(BrowserRouteLink))
        .where((link) => link.uri?.path == '/reference');
    expect(
      referenceRoutes.every(
        (link) => link.uri?.queryParameters['book'] == 'Matthew',
      ),
      isTrue,
    );
    expect(
      referenceRoutes.every(
        (link) => link.uri?.queryParameters['bookDisplay'] == 'متى',
      ),
      isTrue,
    );
    final cellWrap = tester.widget<Wrap>(
      find
          .descendant(
            of: find.byType(ReferenceCellHoverPreview),
            matching: find.byType(Wrap),
          )
          .first,
    );
    expect(cellWrap.textDirection, TextDirection.rtl);
    expect(find.text('، '), findsOneWidget);

    final displayedReferences = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(VerseRefText),
            matching: find.byType(Text),
          ),
        )
        .map((text) => withoutDirectionalMarks(text.data ?? ''))
        .toList();
    expect(displayedReferences, containsAllInOrder(['٩:١٨–١٩', '٢٣–٢٦']));
    expect(
      tester.getCenter(find.byType(VerseRefText).first).dx,
      greaterThan(tester.getCenter(find.byType(VerseRefText).last).dx),
    );

    final gesture = await hoverOver(
      tester,
      find.byType(ReferenceCellHoverPreview),
    );
    await tester.pump(const Duration(milliseconds: 1500));
    final visibleText = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => withoutDirectionalMarks(text.data ?? ''));
    expect(visibleText, contains('متى ٩:١٨–١٩، ٢٣–٢٦'));
    expect(visibleText.any((text) => text.contains('&')), isFalse);

    await moveOutsideAndRemove(tester, gesture);
  });

  testWidgets('hidden Gospel columns do not render their references', (
    tester,
  ) async {
    await tester.pumpWidget(
      harmonyTableFor(
        const [
          GospelReference(book: 'Matthew', chapter: 1, verses: '1'),
          GospelReference(book: 'Mark', chapter: 1, verses: '2'),
          GospelReference(book: 'Luke', chapter: 1, verses: '3'),
          GospelReference(book: 'John', chapter: 1, verses: '4'),
        ],
        visibleGospels: const [Gospel.matthew, Gospel.mark],
      ),
    );

    expect(find.text('Matthew'), findsOneWidget);
    expect(find.text('Mark'), findsOneWidget);
    expect(find.text('Luke'), findsNothing);
    expect(find.text('John'), findsNothing);
    expect(find.byType(ReferenceHoverText), findsNWidgets(2));
  });

  testWidgets('combined sort control manages columns and resets visibility', (
    tester,
  ) async {
    var sort = const GospelSortState();
    var columns = const ColumnVisibilityState();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HarmonySortButton(
            state: sort,
            columns: columns,
            uiLanguage: kBaseLanguageOptions.first,
            onChanged: (value) => sort = value,
            onColumnsChanged: (value) => columns = value,
          ),
        ),
      ),
    );

    expect(find.text('Sort & Columns'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('sort-button')));
    await tester.pumpAndSettle();
    final columnTops = Gospel.values
        .map(
          (gospel) => tester
              .getTopLeft(find.byKey(ValueKey<String>('column-${gospel.name}')))
              .dy,
        )
        .toSet();
    expect(columnTops, hasLength(1));
    expect(find.byIcon(Icons.visibility_outlined), findsNothing);
    expect(find.byIcon(Icons.visibility_off_outlined), findsNothing);
    expect(find.byIcon(Icons.remove_circle_outline), findsNWidgets(4));
    final matthewButton = tester.widget<IconButton>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('column-matthew')),
        matching: find.byType(IconButton),
      ),
    );
    expect(matthewButton.tooltip, 'Hide Matthew column');
    Future<void> toggle(Gospel gospel) async {
      final button = find.descendant(
        of: find.byKey(ValueKey<String>('column-${gospel.name}')),
        matching: find.byType(IconButton),
      );
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pump();
    }

    await toggle(Gospel.luke);
    await toggle(Gospel.john);
    await toggle(Gospel.matthew);
    await tester.pump();

    expect(columns.visibleGospels, [Gospel.mark]);
    final finalButton = tester.widget<IconButton>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('column-mark')),
        matching: find.byType(IconButton),
      ),
    );
    expect(finalButton.onPressed, isNull);

    final reset = find.byKey(const ValueKey<String>('reset-columns'));
    await tester.ensureVisible(reset);
    await tester.pumpAndSettle();
    await tester.tap(reset);
    await tester.pump();
    expect(columns, const ColumnVisibilityState());
    expect(sort.isDefault, isTrue);
  });

  testWidgets('combined sort control uses a two-row narrow layout', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(500, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HarmonySortButton(
            state: const GospelSortState(),
            columns: const ColumnVisibilityState(),
            uiLanguage: kBaseLanguageOptions.first,
            onChanged: (_) {},
            onColumnsChanged: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey<String>('sort-button')));
    await tester.pumpAndSettle();

    final matthewTop = tester
        .getTopLeft(find.byKey(const ValueKey<String>('column-matthew')))
        .dy;
    final markTop = tester
        .getTopLeft(find.byKey(const ValueKey<String>('column-mark')))
        .dy;
    final lukeTop = tester
        .getTopLeft(find.byKey(const ValueKey<String>('column-luke')))
        .dy;
    final johnTop = tester
        .getTopLeft(find.byKey(const ValueKey<String>('column-john')))
        .dy;
    expect(markTop, matthewTop);
    expect(johnTop, lukeTop);
    expect(lukeTop, greaterThan(matthewTop));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Arabic combined sort control matches the roomy RTL layout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final arabic = kBaseLanguageOptions.firstWhere(
      (option) => option.code == 'arabic',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HarmonySortButton(
            state: const GospelSortState(),
            columns: const ColumnVisibilityState(),
            uiLanguage: arabic,
            onChanged: (_) {},
            onColumnsChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('الترتيب والأعمدة'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('sort-button')));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(
        find.byKey(const ValueKey<String>('draggable-dialog-surface')),
      ),
      const Size(700, 820),
    );
    expect(find.text('الترتيب بحسب'), findsOneWidget);
    expect(find.text('التنسيق العام'), findsOneWidget);
    expect(find.text('إنجيل متى'), findsOneWidget);
    expect(find.text('إنجيل مرقس'), findsOneWidget);
    expect(find.text('إنجيل لوقا'), findsOneWidget);
    expect(find.text('إنجيل يوحنا'), findsOneWidget);
    final defaultSortText = tester.widget<Text>(find.text('التنسيق العام'));
    for (final label in const [
      'إنجيل متى',
      'إنجيل مرقس',
      'إنجيل لوقا',
      'إنجيل يوحنا',
    ]) {
      expect(
        tester.widget<Text>(find.text(label)).style,
        defaultSortText.style,
      );
    }
    final arabicMatthewButton = tester.widget<IconButton>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('column-matthew')),
        matching: find.byType(IconButton),
      ),
    );
    expect(arabicMatthewButton.tooltip, 'إخفاء عمود متى');
    final columnLefts = Gospel.values
        .map(
          (gospel) => tester
              .getTopLeft(find.byKey(ValueKey<String>('column-${gospel.name}')))
              .dx,
        )
        .toList();
    expect(
      columnLefts,
      orderedEquals(columnLefts.toList()..sort((a, b) => b.compareTo(a))),
    );
    expect(find.textContaining('Matthew'), findsNothing);
    expect(find.textContaining('Mark'), findsNothing);
    expect(find.textContaining('Luke'), findsNothing);
    expect(find.textContaining('John'), findsNothing);
  });

  testWidgets('sort button never includes the active chronology', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HarmonySortButton(
            state: const GospelSortState(mode: TopicSortMode.luke),
            columns: const ColumnVisibilityState(),
            uiLanguage: kBaseLanguageOptions.first,
            onChanged: (_) {},
            onColumnsChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Sort & Columns'), findsOneWidget);
    expect(find.textContaining('Luke'), findsNothing);
  });

  testWidgets('chapter navigation combines the book and chapter title', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MenuLanguageScope(
          notifier: ValueNotifier<String>('english'),
          child: const Scaffold(
            body: ChapterNav(
              bookTitle: 'Gospel of Matthew',
              chapter: 10,
              previousBookUri: null,
              previousChapterUri: null,
              nextChapterUri: null,
              nextBookUri: null,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Gospel of Matthew — Chapter 10'), findsOneWidget);
  });

  testWidgets('Arabic chapter navigation localizes its combined title', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MenuLanguageScope(
          notifier: ValueNotifier<String>('arabic'),
          child: const Scaffold(
            body: ChapterNav(
              bookTitle: 'إنجيل متى',
              chapter: 10,
              previousBookUri: null,
              previousChapterUri: null,
              nextChapterUri: null,
              nextBookUri: null,
            ),
          ),
        ),
      ),
    );

    expect(find.text('إنجيل متى — الفصل ١٠'), findsOneWidget);
  });

  testWidgets('chapter controls keep the same width as a single reader panel', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const navigation = ChapterNav(
      bookTitle: 'Gospel of Luke',
      chapter: 1,
      previousBookUri: null,
      previousChapterUri: null,
      nextChapterUri: null,
      nextBookUri: null,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MenuLanguageScope(
          notifier: ValueNotifier<String>('english'),
          child: const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(20),
              child: ReaderChapterLayout(
                topNavigation: navigation,
                bottomNavigation: navigation,
                panels: <Widget>[
                  TranslationPanelCard(
                    title: 'English · KJV',
                    textDirection: TextDirection.ltr,
                    isMain: true,
                    body: Text('Chapter text'),
                  ),
                ],
                textDirection: TextDirection.ltr,
              ),
            ),
          ),
        ),
      ),
    );

    double topNavigationWidth() =>
        tester.getSize(find.byType(ChapterNav).first).width;
    double bottomNavigationWidth() =>
        tester.getSize(find.byType(ChapterNav).last).width;
    double panelWidth() =>
        tester.getSize(find.byType(TranslationPanelCard)).width;

    expect(topNavigationWidth(), closeTo(760, 0.1));
    expect(bottomNavigationWidth(), closeTo(760, 0.1));
    expect(panelWidth(), closeTo(760, 0.1));

    await tester.binding.setSurfaceSize(const Size(620, 900));
    await tester.pump();

    expect(topNavigationWidth(), closeTo(580, 0.1));
    expect(bottomNavigationWidth(), closeTo(580, 0.1));
    expect(panelWidth(), closeTo(580, 0.1));
  });

  test(
    'sticky chapter controls stop when the bottom controls become visible',
    () {
      const viewport = Rect.fromLTWH(0, 100, 760, 500);

      expect(
        shouldShowStickyChapterNavigation(
          viewport: viewport,
          topNavigation: const Rect.fromLTWH(0, 100, 760, 60),
          bottomNavigation: const Rect.fromLTWH(0, 700, 760, 60),
        ),
        isTrue,
      );
      expect(
        shouldShowStickyChapterNavigation(
          viewport: viewport,
          topNavigation: const Rect.fromLTWH(0, 101, 760, 60),
          bottomNavigation: const Rect.fromLTWH(0, 700, 760, 60),
        ),
        isFalse,
      );
      expect(
        shouldShowStickyChapterNavigation(
          viewport: viewport,
          topNavigation: const Rect.fromLTWH(0, 20, 760, 60),
          bottomNavigation: const Rect.fromLTWH(0, 590, 760, 60),
        ),
        isFalse,
      );
    },
  );

  testWidgets('main chapter translation has no duplicated card header', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TranslationPanelCard(
            title: 'English · KJV',
            textDirection: TextDirection.ltr,
            isMain: true,
            headerControls: [
              TextButton(
                onPressed: () {},
                child: const Text('Change translation'),
              ),
            ],
            body: const Text('In the beginning of the chapter.'),
          ),
        ),
      ),
    );

    expect(find.text('English · KJV'), findsNothing);
    expect(find.text('Change translation'), findsNothing);
    expect(find.textContaining('In the beginning'), findsOneWidget);
  });

  testWidgets('added translations retain their header and change action', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TranslationPanelCard(
            title: 'العربية · البستاني فاندايك',
            textDirection: TextDirection.rtl,
            headerControls: [
              TextButton(
                onPressed: () {},
                child: const Text('Change translation'),
              ),
              IconButton(onPressed: () {}, icon: const Icon(Icons.close)),
            ],
            body: const Text('نص المقارنة.'),
          ),
        ),
      ),
    );

    expect(find.text('العربية · البستاني فاندايك'), findsOneWidget);
    expect(find.text('Change translation'), findsOneWidget);
    expect(find.text('نص المقارنة.'), findsOneWidget);
  });

  testWidgets('combined sort picker exposes Default and all chronologies', (
    tester,
  ) async {
    var state = const GospelSortState();
    var columns = const ColumnVisibilityState();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HarmonySortButton(
            state: state,
            columns: columns,
            uiLanguage: kBaseLanguageOptions.first,
            onChanged: (value) => state = value,
            onColumnsChanged: (value) => columns = value,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey<String>('sort-button')));
    await tester.pumpAndSettle();
    expect(find.text('Default'), findsOneWidget);
    expect(find.text('Matthew chronology'), findsOneWidget);
    expect(find.text('Mark chronology'), findsOneWidget);
    expect(find.text('Luke chronology'), findsOneWidget);
    expect(find.text('John chronology'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('sort-luke')));
    await tester.pump();
    expect(state.gospel, Gospel.luke);
    expect(columns, const ColumnVisibilityState());
  });

  testWidgets('harmony table caps and centers on wide screens', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      harmonyTableFor(
        const [GospelReference(book: 'Luke', chapter: 4, verses: '42-44')],
        width: 1600,
        height: 700,
      ),
    );

    final headerTable = find.byType(Table).first;
    expect(tester.getSize(headerTable).width, closeTo(1120, 0.1));
    expect(tester.getTopLeft(headerTable).dx, closeTo(240, 0.1));
  });

  testWidgets('harmony table keeps a readable scroll width on narrow screens', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      harmonyTableFor(
        const [GospelReference(book: 'Luke', chapter: 4, verses: '42-44')],
        width: 390,
        height: 600,
      ),
    );

    final headerTable = find.byType(Table).first;
    expect(tester.getSize(headerTable).width, closeTo(760, 0.1));
    expect(tester.getTopLeft(headerTable).dx, closeTo(0, 0.1));
  });
}
