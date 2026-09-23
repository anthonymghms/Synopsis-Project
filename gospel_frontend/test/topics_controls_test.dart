import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gospel_frontend/admin_content_scope.dart';
import 'package:gospel_frontend/gospel_filter.dart';
import 'package:gospel_frontend/main.dart';
import 'package:gospel_frontend/topic_language_catalog.dart';

void main() {
  for (final language in kBaseLanguageOptions) {
    testWidgets('${language.code} toolbar resets without opening a dialog', (
      tester,
    ) async {
      var filter = GospelFilterState(
        includeMask: Gospel.mark.bit,
        excludeMask: Gospel.john.bit,
      );
      var sort = const GospelSortState(mode: TopicSortMode.luke);
      var columns = ColumnVisibilityState(visibleMask: Gospel.mark.bit);
      var commits = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => Directionality(
                textDirection: language.direction,
                child: Wrap(
                  children: [
                    HarmonyFilterButton(
                      filterState: filter,
                      sortState: sort,
                      uiLanguage: language,
                      topics: const [],
                      columns: columns,
                      onChanged: (value) => setState(() => filter = value),
                      onSortChanged: (value) => setState(() => sort = value),
                      onInteractionEnd: () => commits++,
                    ),
                    HarmonySortButton(
                      state: sort,
                      columns: columns,
                      uiLanguage: language,
                      onChanged: (value) => setState(() => sort = value),
                      onColumnsChanged: (value) =>
                          setState(() => columns = value),
                      onInteractionEnd: () => commits++,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('clear-filter-button')));
      await tester.pumpAndSettle();
      expect(filter, const GospelFilterState());
      expect(sort.gospel, Gospel.luke);
      expect(columns.visibleMask, Gospel.mark.bit);
      expect(commits, 1);
      expect(find.byType(Dialog), findsNothing);
      expect(find.byKey(const ValueKey('clear-filter-button')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('clear-sort-button')));
      await tester.pumpAndSettle();
      expect(sort.isDefault, isTrue);
      expect(columns.visibleMask, allGospelsMask);
      expect(commits, 2);
      expect(find.byType(Dialog), findsNothing);
      expect(find.byKey(const ValueKey('clear-sort-button')), findsNothing);
    });

    testWidgets(
      '${language.code} filter width stays fixed through tablet rotation',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(900, 1200);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: HarmonyFilterButton(
                filterState: const GospelFilterState(),
                uiLanguage: language,
                topics: const [],
                columns: const ColumnVisibilityState(),
                onChanged: (_) {},
              ),
            ),
          ),
        );
        await tester.tap(find.text(language.ui.filter));
        await tester.pumpAndSettle();
        final surface = find.byKey(const ValueKey('draggable-dialog-surface'));
        expect(tester.getSize(surface).width, 760);
        tester.view.physicalSize = const Size(1280, 600);
        await tester.pumpAndSettle();
        expect(tester.getSize(surface).width, 760);
        expect(tester.getSize(surface).height, lessThanOrEqualTo(552));
        await tester.tap(find.byKey(const ValueKey('apply-filter')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('admin can select and copy topic names and references', (
    tester,
  ) async {
    String? copied;
    String? selected;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminContentScope(
            enabled: true,
            child: SelectionArea(
              onSelectionChanged: (content) => selected = content?.plainText,
              child: HarmonyTable(
                topics: [
                  Topic(
                    id: '289',
                    name: 'A selectable topic',
                    references: [
                      GospelReference(
                        book: 'Matthew',
                        chapter: 3,
                        verses: '1-4',
                      ),
                    ],
                  ),
                ],
                languageOption: kBaseLanguageOptions.first,
                topicLanguage: bundledTopicLanguages.first,
                apiVersion: 'kjv',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final start =
        tester.getTopLeft(find.text('A selectable topic')) + const Offset(1, 8);
    final drag = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    await drag.moveTo(start + const Offset(180, 0));
    await drag.up();
    await tester.pumpAndSettle();
    expect(selected, contains('selectable'));
    final selection = tester.state<SelectableRegionState>(
      find.byType(SelectableRegion),
    );
    selection.selectAll(SelectionChangedCause.keyboard);
    await tester.pump();
    selection.contextMenuButtonItems
        .firstWhere((item) => item.type == ContextMenuButtonType.copy)
        .onPressed!();
    await tester.pump();
    expect(copied, contains('A selectable topic'));
    expect(copied, contains('289'));
    expect(copied, contains('3:1–4'));
    expect(tester.takeException(), isNull);
  });
}
