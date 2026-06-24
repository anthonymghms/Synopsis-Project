import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gospel_frontend/main.dart';

void main() {
  test('placeholder smoke test', () {
    expect(true, isTrue);
  });

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
