import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gospel_frontend/main.dart';

void main() {
  test('placeholder smoke test', () {
    expect(true, isTrue);
  });

  Widget harmonyTableFor(List<GospelReference> references) {
    return MaterialApp(
      home: Scaffold(
        body: MenuLanguageScope(
          notifier: ValueNotifier<String>('english'),
          child: SizedBox(
            width: 1000,
            height: 500,
            child: HarmonyTable(
              topics: [
                Topic(
                  id: '34',
                  name: 'Teaching and healings',
                  references: references,
                ),
              ],
              languageOption: kBaseLanguageOptions.first,
              apiVersion: 'kjv',
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
}
