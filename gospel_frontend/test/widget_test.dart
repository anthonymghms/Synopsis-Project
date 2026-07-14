import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gospel_frontend/browser_route_link.dart';
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

  group('HarmonyFilterState', () {
    final johnAndMark = topicWith('john-mark', ['John', 'Mark']);
    final markLuke = topicWith('mark-luke', ['Mark', 'Luke']);
    final matthewMarkLuke = topicWith('matthew-mark-luke', [
      'Matthew',
      'Mark',
      'Luke',
    ]);
    final markLukeJohn = topicWith('mark-luke-john', ['Mark', 'Luke', 'John']);
    final allFour = topicWith('all-four', ['Matthew', 'Mark', 'Luke', 'John']);

    test('matches only John and Mark references', () {
      final filter = HarmonyFilterState.custom(
        operator: HarmonyFilterOperator.onlySelected,
        selectedGospels: {'John', 'Mark'},
      );

      expect(matchesFilter(johnAndMark, filter), isTrue);
      expect(matchesFilter(markLuke, filter), isFalse);
      expect(matchesFilter(allFour, filter), isFalse);
    });

    test('matches Mark and Luke while excluding John', () {
      final filter = HarmonyFilterState.custom(
        operator: HarmonyFilterOperator.matchIndividualConditions,
        requirements: {
          'Mark': GospelReferenceRequirement.hasReference,
          'Luke': GospelReferenceRequirement.hasReference,
          'John': GospelReferenceRequirement.doesNotHaveReference,
        },
      );

      expect(matchesFilter(markLuke, filter), isTrue);
      expect(matchesFilter(matthewMarkLuke, filter), isTrue);
      expect(matchesFilter(markLukeJohn, filter), isFalse);
    });

    test('stacks condition rows with AND and OR logic', () {
      final andFilter = HarmonyFilterState.custom(
        operator: HarmonyFilterOperator.matchIndividualConditions,
        conditionMode: HarmonyFilterConditionMode.all,
        conditions: const [
          HarmonyFilterCondition(
            gospel: 'Matthew',
            requirement: GospelReferenceRequirement.hasReference,
          ),
          HarmonyFilterCondition(
            gospel: 'Luke',
            requirement: GospelReferenceRequirement.hasReference,
          ),
          HarmonyFilterCondition(
            gospel: 'John',
            requirement: GospelReferenceRequirement.doesNotHaveReference,
          ),
        ],
      );

      expect(matchesFilter(matthewMarkLuke, andFilter), isTrue);
      expect(matchesFilter(markLuke, andFilter), isFalse);
      expect(matchesFilter(allFour, andFilter), isFalse);

      final orFilter = HarmonyFilterState.custom(
        operator: HarmonyFilterOperator.matchIndividualConditions,
        conditionMode: HarmonyFilterConditionMode.any,
        conditions: const [
          HarmonyFilterCondition(
            gospel: 'Matthew',
            requirement: GospelReferenceRequirement.hasReference,
          ),
          HarmonyFilterCondition(
            gospel: 'John',
            requirement: GospelReferenceRequirement.hasReference,
          ),
        ],
      );

      expect(matchesFilter(markLuke, orFilter), isFalse);
      expect(matchesFilter(johnAndMark, orFilter), isTrue);
      expect(matchesFilter(matthewMarkLuke, orFilter), isTrue);
    });

    test('matches any selected gospel references', () {
      final filter = HarmonyFilterState.custom(
        operator: HarmonyFilterOperator.includesAnySelected,
        selectedGospels: {'Matthew', 'Luke'},
      );

      expect(matchesFilter(markLuke, filter), isTrue);
      expect(matchesFilter(topicWith('john', ['John']), filter), isFalse);
    });

    test('matches all selected gospel references', () {
      final filter = HarmonyFilterState.custom(
        operator: HarmonyFilterOperator.includesAllSelected,
        selectedGospels: {'Mark', 'Luke'},
      );

      expect(matchesFilter(markLuke, filter), isTrue);
      expect(matchesFilter(johnAndMark, filter), isFalse);
    });

    test('excludes selected gospel references', () {
      final filter = HarmonyFilterState.custom(
        operator: HarmonyFilterOperator.excludesSelected,
        selectedGospels: {'John'},
      );

      expect(matchesFilter(markLuke, filter), isTrue);
      expect(matchesFilter(johnAndMark, filter), isFalse);
    });

    test('matches all four, exactly one, at least two, and clear filter', () {
      expect(
        matchesFilter(
          allFour,
          HarmonyFilterState.preset(HarmonyFilterPreset.allFourGospels),
        ),
        isTrue,
      );
      expect(
        matchesFilter(
          markLuke,
          HarmonyFilterState.preset(HarmonyFilterPreset.allFourGospels),
        ),
        isFalse,
      );

      final exactlyOne = HarmonyFilterState.preset(
        HarmonyFilterPreset.exactlyOneGospel,
      );
      expect(
        matchesFilter(topicWith('only-luke', ['Luke']), exactlyOne),
        isTrue,
      );
      expect(matchesFilter(markLuke, exactlyOne), isFalse);

      final atLeastTwo = HarmonyFilterState.preset(
        HarmonyFilterPreset.atLeastTwoGospels,
      );
      expect(matchesFilter(markLuke, atLeastTwo), isTrue);
      expect(
        matchesFilter(topicWith('only-john', ['John']), atLeastTwo),
        isFalse,
      );

      expect(matchesFilter(markLuke, HarmonyFilterState.allTopics), isTrue);
      expect(matchesFilter(allFour, HarmonyFilterState.allTopics), isTrue);
    });

    test('dash placeholders do not count as references', () {
      final topic = Topic(
        id: 'dash',
        name: 'Dash',
        references: const [
          GospelReference(book: 'John', chapter: 0, verses: '—'),
          GospelReference(book: 'Luke', chapter: 2, verses: ''),
        ],
      );

      expect(hasReference(topic, 'John'), isFalse);
      expect(hasReference(topic, 'Luke'), isTrue);
      expect(getReferencedGospels(topic), {'Luke'});
    });
  });

  testWidgets('filter button and dialog use Arabic UI labels', (tester) async {
    final arabic = kBaseLanguageOptions.firstWhere(
      (option) => option.code == 'arabic',
    );
    HarmonyFilterState? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: MenuLanguageScope(
          notifier: ValueNotifier<String>('arabic'),
          child: Scaffold(
            body: Center(
              child: HarmonyFilterButton(
                filterState: HarmonyFilterState.allTopics,
                uiLanguage: arabic,
                onChanged: (filter) {
                  selected = filter;
                },
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('تصفية'), findsOneWidget);
    await tester.tap(find.text('تصفية'));
    await tester.pumpAndSettle();

    expect(find.text('كل المواضيع'), findsOneWidget);
    expect(find.text('إزالة التصفية'), findsOneWidget);
    expect(find.text('تطبيق'), findsOneWidget);

    await tester.tap(find.text('تطبيق'));
    await tester.pumpAndSettle();

    expect(selected, isNotNull);
    expect(selected!.isActive, isFalse);
  });

  testWidgets('custom filter dialog supports adding stacked conditions', (
    tester,
  ) async {
    HarmonyFilterState? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: MenuLanguageScope(
          notifier: ValueNotifier<String>('english'),
          child: Scaffold(
            body: Center(
              child: HarmonyFilterButton(
                filterState: HarmonyFilterState.custom(
                  operator: HarmonyFilterOperator.matchIndividualConditions,
                  conditions: const [
                    HarmonyFilterCondition(
                      gospel: 'Matthew',
                      requirement: GospelReferenceRequirement.hasReference,
                    ),
                  ],
                ),
                uiLanguage: kBaseLanguageOptions.first,
                onChanged: (filter) {
                  selected = filter;
                },
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Filter'));
    await tester.pumpAndSettle();

    expect(find.text('Match all conditions'), findsOneWidget);
    expect(find.text('Condition 1'), findsOneWidget);
    expect(find.text('Add condition'), findsOneWidget);

    await tester.tap(find.text('Add condition'));
    await tester.pumpAndSettle();

    expect(find.text('Condition 2'), findsOneWidget);

    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(selected, isNotNull);
    expect(selected!.operator, HarmonyFilterOperator.matchIndividualConditions);
    expect(selected!.conditionMode, HarmonyFilterConditionMode.all);
    expect(selected!.conditions, hasLength(2));
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
