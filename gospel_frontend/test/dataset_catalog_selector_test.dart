import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gospel_frontend/main.dart';
import 'package:gospel_frontend/topic_dataset.dart';

const fourthTableCatalog = [
  ...builtinDatasetCatalog,
  DatasetCatalogEntry(
    datasetId: 'fourth-table',
    labels: {
      'english': 'Fourth table',
      'arabic': 'جدول رابع',
      'french': 'Quatrième tableau',
    },
    published: true,
  ),
];

void main() {
  testWidgets('four tables use a compact dropdown with dynamic selection', (
    tester,
  ) async {
    var selected = 'harmony';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => DatasetSelector(
              datasetId: selected,
              language: 'french',
              catalog: fourthTableCatalog,
              onChanged: (id) => setState(() => selected = id),
            ),
          ),
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey('dataset-selector-dropdown')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('dataset-selector-tabs')), findsNothing);
    expect(find.text('Tableau'), findsOneWidget);
    expect(
      tester.getSize(find.byType(DropdownButtonFormField<String>)).width,
      lessThanOrEqualTo(460),
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quatrième tableau').last);
    await tester.pumpAndSettle();
    expect(selected, 'fourth-table');
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byType(DropdownButtonFormField<String>),
          )
          .initialValue,
      'fourth-table',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('cold custom route stays selectable before catalog arrives', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DatasetSelector(
            datasetId: 'fourth-table',
            language: 'arabic',
            onChanged: (_) {},
          ),
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey('dataset-selector-dropdown')),
      findsOneWidget,
    );
    expect(find.text('fourth-table'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DatasetSelector(
            datasetId: 'fourth-table',
            language: 'arabic',
            catalog: fourthTableCatalog,
            onChanged: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('جدول رابع'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow fourth-table selector remains within viewport', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: DatasetSelector(
              datasetId: 'fourth-table',
              language: 'arabic',
              catalog: fourthTableCatalog,
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    expect(find.text('الجدول'), findsOneWidget);
    expect(find.text('جدول رابع'), findsOneWidget);
    expect(
      tester.getSize(find.byType(DropdownButtonFormField<String>)).width,
      lessThanOrEqualTo(320),
    );
    expect(tester.takeException(), isNull);
  });
}
