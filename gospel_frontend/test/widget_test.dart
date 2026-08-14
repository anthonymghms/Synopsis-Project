import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gospel_frontend/browser_route_link.dart';
import 'package:gospel_frontend/gospel_filter.dart';
import 'package:gospel_frontend/main.dart';

void main() {
  test('placeholder smoke test', () {
    expect(true, isTrue);
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

  Widget harmonyTableFor(
    List<GospelReference> references, {
    double width = 1000,
    double height = 500,
    LanguageOption? languageOption,
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
                Topic(
                  id: '34',
                  name: 'Teaching and healings',
                  references: references,
                ),
              ],
              languageOption: option,
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
        Topic(id: 'missing-leading', name: 'Leading', references: const []),
        Topic(
          id: 'chapter-2',
          name: 'Chapter 2',
          references: const [
            GospelReference(book: 'Mark', chapter: 2, verses: '1'),
          ],
        ),
        Topic(id: 'missing-near-2', name: 'Related', references: const []),
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
          ],
        ),
        Topic(
          id: 'earlier',
          name: 'Earlier',
          references: const [
            GospelReference(book: 'Luke', chapter: 1, verses: '20'),
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
        ),
        [1, 0],
      );
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
                topicPresenceMasks: masks,
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
    expect(find.text('تقاطع'), findsOneWidget);
    expect(find.text('إزالة التصفية'), findsWidgets);
    expect(find.text('٣ موضوعًا'), findsWidgets);
    expect(
      Directionality.of(tester.element(find.text('العملية'))),
      TextDirection.rtl,
    );

    await tester.tap(find.text('تقاطع'));
    await tester.tap(find.byKey(const ValueKey<String>('include-mark')));
    await tester.tap(find.byKey(const ValueKey<String>('include-luke')));
    await tester.pump();

    expect(selected.mode, GospelFilterMode.intersection);
    expect(selected.includeMask, Gospel.mark.bit | Gospel.luke.bit);
    expect(find.text('مرقس ∩ لوقا'), findsOneWidget);
    expect(find.text('١ موضوعًا'), findsWidgets);
  });

  testWidgets(
    'English set filter builds union then exclusion with live counts',
    (tester) async {
      var selected = const GospelFilterState();
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
                  topicPresenceMasks: masks,
                  currentResultCount: 5,
                  onChanged: (state) => selected = state,
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Filter'));
      await tester.pumpAndSettle();

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
      expect(find.text('Apply filter'), findsNothing);
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
                    topicPresenceMasks: masks,
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
              topicPresenceMasks: const <int>[],
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
    expect(find.text('Done'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Escape closes the Gospel filter browser', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HarmonyFilterButton(
            filterState: const GospelFilterState(),
            uiLanguage: kBaseLanguageOptions.first,
            topicPresenceMasks: const <int>[],
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
      'book': 'luke',
      'bookDisplay': 'Luke',
      'chapter': '4',
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
    await tester.tap(find.text('العربية').last);
    await tester.pumpAndSettle();

    expect(selectedLanguage, isNull);
    expect(selectedVersion, isNull);
    expect(find.text('الترجمة: اختر الترجمة'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNothing);

    await tester.tap(find.text('كتاب الحياة').last);
    await tester.pumpAndSettle();

    expect(selectedLanguage?.code, 'arabic');
    expect(selectedVersion, 'New Arabic Version');
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
        GospelReference(book: 'Luke', chapter: 4, verses: '42-44'),
        GospelReference(book: 'Luke', chapter: 6, verses: '17-19'),
      ], languageOption: arabic),
    );

    final combined = tester.widget<ReferenceCellHoverPreview>(
      find.byType(ReferenceCellHoverPreview),
    );
    expect(combined.textDirection, TextDirection.rtl);
    expect(combined.language, arabic.apiLanguage);
    expect(combined.openInNewTab, isTrue);
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

  testWidgets('column picker prevents hiding all and can re-enable columns', (
    tester,
  ) async {
    var state = const ColumnVisibilityState();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HarmonyColumnsButton(
            state: state,
            uiLanguage: kBaseLanguageOptions.first,
            onChanged: (value) => state = value,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey<String>('columns-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('column-luke')));
    await tester.tap(find.byKey(const ValueKey<String>('column-john')));
    await tester.tap(find.byKey(const ValueKey<String>('column-matthew')));
    await tester.pump();

    expect(state.visibleGospels, [Gospel.mark]);
    final finalChip = tester.widget<FilterChip>(
      find.byKey(const ValueKey<String>('column-mark')),
    );
    expect(finalChip.onSelected, isNull);

    await tester.tap(find.byKey(const ValueKey<String>('column-luke')));
    await tester.pump();
    expect(state.visibleGospels, [Gospel.mark, Gospel.luke]);
  });

  testWidgets('sort picker exposes all localized Gospel chronologies', (
    tester,
  ) async {
    var state = const GospelSortState();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HarmonySortButton(
            state: state,
            uiLanguage: kBaseLanguageOptions.first,
            onChanged: (value) => state = value,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey<String>('sort-button')));
    await tester.pumpAndSettle();
    expect(find.text('Matthew chronology'), findsOneWidget);
    expect(find.text('Mark chronology'), findsOneWidget);
    expect(find.text('Luke chronology'), findsOneWidget);
    expect(find.text('John chronology'), findsOneWidget);

    await tester.tap(find.text('Luke chronology'));
    await tester.pumpAndSettle();
    expect(state.gospel, Gospel.luke);
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
