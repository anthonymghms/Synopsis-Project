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

  testWidgets('Arabic Gospel filter browser is localized and RTL', (
    tester,
  ) async {
    final arabic = kBaseLanguageOptions.firstWhere(
      (option) => option.code == 'arabic',
    );
    GospelFilterCombination? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: MenuLanguageScope(
          notifier: ValueNotifier<String>('arabic'),
          child: Scaffold(
            body: Center(
              child: HarmonyFilterButton(
                selectedCombination: null,
                uiLanguage: arabic,
                currentResultCount: 42,
                onChanged: (combination) {
                  selected = combination;
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

    expect(find.text('تركيبات الأناجيل'), findsOneWidget);
    expect(find.text('البحث في التصفيات'), findsOneWidget);
    expect(find.text('كل المواضيع'), findsOneWidget);
    expect(find.text('إزالة التصفية'), findsWidgets);
    expect(find.text('تطبيق التصفية'), findsOneWidget);
    expect(find.text('أربعة أناجيل مشمولة'), findsOneWidget);
    expect(find.text('٤٢ نتيجة'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.text('تركيبات الأناجيل'))),
      TextDirection.rtl,
    );

    await tester.tap(find.text('C01'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تطبيق التصفية'));
    await tester.pumpAndSettle();

    expect(selected?.code, 'C01');
  });

  testWidgets('English filter browser groups, searches, and selects by code', (
    tester,
  ) async {
    GospelFilterCombination? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: MenuLanguageScope(
          notifier: ValueNotifier<String>('english'),
          child: Scaffold(
            body: Center(
              child: HarmonyFilterButton(
                selectedCombination: null,
                uiLanguage: kBaseLanguageOptions.first,
                currentResultCount: 12,
                onChanged: (combination) {
                  selected = combination;
                },
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Filter'));
    await tester.pumpAndSettle();

    expect(find.text('Gospel combinations'), findsOneWidget);
    expect(find.text('Four included'), findsOneWidget);
    expect(find.text('Custom filter'), findsNothing);

    await tester.enterText(find.byType(TextField), 'C25');
    await tester.pumpAndSettle();

    expect(find.text('C25'), findsNWidgets(2));
    expect(find.text('C01'), findsNothing);
    expect(find.text('Two included'), findsOneWidget);
    expect(find.text('Included'), findsOneWidget);
    expect(find.text('Any'), findsOneWidget);
    expect(find.text('Excluded'), findsNothing);

    await tester.tap(find.text('C25').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply filter'));
    await tester.pumpAndSettle();

    expect(selected?.code, 'C25');
  });

  test('filter search understands codes, semantics, and Arabic names', () {
    final english = kBaseLanguageOptions.first;
    final c05 = gospelFilterCombinationForCode('C05')!;
    final c25 = gospelFilterCombinationForCode('C25')!;
    final c32 = gospelFilterCombinationForCode('C32')!;

    expect(matchesGospelFilterSearch(c25, 'C25', english), isTrue);
    expect(matchesGospelFilterSearch(c25, 'Matthew John', english), isTrue);
    expect(matchesGospelFilterSearch(c05, 'Matthew John', english), isFalse);
    expect(matchesGospelFilterSearch(c05, 'exclude Luke', english), isTrue);
    expect(matchesGospelFilterSearch(c32, 'only Mark', english), isTrue);
    expect(matchesGospelFilterSearch(c25, 'any Luke', english), isTrue);
    expect(matchesGospelFilterSearch(c05, 'any Luke', english), isFalse);
    expect(matchesGospelFilterSearch(c25, 'متى يوحنا', english), isTrue);
    expect(matchesGospelFilterSearch(c25, 'exclude Luke', english), isFalse);
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
              selectedCombination: null,
              uiLanguage: kBaseLanguageOptions.first,
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
    expect(find.text('Search filters'), findsOneWidget);
    expect(find.text('Apply filter'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Escape closes the Gospel filter browser', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HarmonyFilterButton(
            selectedCombination: null,
            uiLanguage: kBaseLanguageOptions.first,
            onChanged: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('Filter'));
    await tester.pumpAndSettle();
    expect(find.text('Gospel combinations'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('Gospel combinations'), findsNothing);
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
