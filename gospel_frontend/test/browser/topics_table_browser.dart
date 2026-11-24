// ignore_for_file: deprecated_member_use
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gospel_frontend/topics_table_document.dart';
import 'package:gospel_frontend/topics_table_output.dart';
import 'package:gospel_frontend/admin_content_scope.dart';
import 'package:gospel_frontend/browser_route_link.dart';
import 'package:gospel_frontend/browser_find_text.dart';
import 'package:gospel_frontend/main.dart';
import 'package:gospel_frontend/topic_language_catalog.dart';

void main() {
  testWidgets(
    'large searchable table mounts visible links and reveals a distant chapter cell',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 740));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final subjects = [
        for (var i = 1; i <= 289; i++)
          Topic(
            id: '$i',
            name: 'Study subject $i',
            references: [
              GospelReference(book: 'John', chapter: 1, verses: '$i'),
            ],
          ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HarmonyTable(
              topics: subjects,
              languageOption: kBaseLanguageOptions.first,
              topicLanguage: bundledTopicLanguages.first,
              apiVersion: 'kjv',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final mounted = find.byType(ReferenceHoverText).evaluate().length;
      expect(mounted, inInclusiveRange(1, 60));
      expect(find.text('Study subject 289'), findsNothing);
      final index = tester.widget<BrowserTableFindIndex>(
        find.byType(BrowserTableFindIndex),
      );
      final row = index.buildRows().last;
      expect(row[1], 'Study subject 289');
      expect(row.last, '1:289');
      index.onMatch(288, 5);
      await tester.pumpAndSettle();
      final last = find.byWidgetPredicate(
        (w) => w is ReferenceHoverText && w.topicId == '289',
      );
      expect(last, findsOneWidget);
      final center = tester.getCenter(last);
      expect(center.dx, inInclusiveRange(0, 390));
      expect(center.dy, inInclusiveRange(0, 740));
      expect(find.byType(ReferenceHoverText).evaluate().length, lessThan(65));
      final href = tester
          .widget<BrowserRouteLink>(
            find.descendant(of: last, matching: find.byType(BrowserRouteLink)),
          )
          .uri!;
      expect(href.queryParameters['topicId'], '289');
      expect(href.queryParameters['book'], 'John');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'admin links allow selection without a native navigation overlay',
    (tester) async {
      for (final admin in [false, true]) {
        await tester.pumpWidget(
          MaterialApp(
            home: AdminContentScope(
              enabled: admin,
              child: BrowserRouteLink(
                uri: Uri.parse('/topic?topicId=1'),
                builder: (_, follow) =>
                    GestureDetector(onTap: follow, child: const Text('Topic')),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final semantics = tester
            .widgetList<Semantics>(
              find.descendant(
                of: find.byType(BrowserRouteLink),
                matching: find.byType(Semantics),
              ),
            )
            .firstWhere((widget) => widget.properties.link == true);
        expect(
          semantics.properties.linkUrl,
          admin ? isNull : Uri.parse('/topic?topicId=1'),
        );
        expect(
          find.byType(HtmlElementView),
          admin ? findsNothing : findsOneWidget,
        );
      }
    },
  );

  testWidgets(
    'browser printing uses all rows, current state and active route',
    (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      final current = ValueNotifier(
        TopicsTableDocument(
          title: 'المواضيع',
          isRtl: true,
          headers: ['المواضيع', 'متى', 'مرقس', 'لوقا', 'يوحنا'],
          rows: [
            for (var i = 1; i <= 289; i++)
              ['$i الموضوع', '1:1', '2:2', '3:3', '4:4'],
          ],
        ),
      );
      var builds = 0;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: ValueListenableBuilder<TopicsTableDocument>(
            valueListenable: current,
            builder: (context, document, _) => TopicsTablePrintScope(
              buildDocument: () {
                builds++;
                return document;
              },
              child: const Scaffold(body: Text('Screen viewport')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(builds, 0);
      html.window.dispatchEvent(html.Event('beforeprint'));
      expect(builds, 1);
      expect(
        html.document.querySelectorAll('#harmony-print-root tbody tr'),
        hasLength(289),
      );
      expect(
        html.document.querySelectorAll('#harmony-print-root th'),
        hasLength(5),
      );
      expect(
        html.document.querySelector('#harmony-print-root')!.text,
        contains('289 الموضوع'),
      );
      expect(
        html.document
            .querySelector('#harmony-print-root section')!
            .getAttribute('dir'),
        'rtl',
      );
      expect(html.document.body!.classes, contains('harmony-printing'));
      html.window.dispatchEvent(html.Event('afterprint'));
      expect(html.document.querySelector('#harmony-print-root'), isNull);
      expect(html.document.body!.classes, isNot(contains('harmony-printing')));

      current.value = const TopicsTableDocument(
        title: 'Filtered',
        headers: ['Topics', 'Luke'],
        rows: [
          ['Last topic', '3:3'],
        ],
      );
      await tester.pump();
      html.window.dispatchEvent(html.Event('beforeprint'));
      expect(
        html.document.querySelectorAll('#harmony-print-root tbody tr'),
        hasLength(1),
      );
      expect(
        html.document.querySelectorAll('#harmony-print-root th'),
        hasLength(2),
      );
      expect(
        html.document.querySelector('#harmony-print-root')!.text,
        contains('Last topic'),
      );
      html.window.dispatchEvent(html.Event('afterprint'));

      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Another page')),
        ),
      );
      await tester.pumpAndSettle();
      html.window.dispatchEvent(html.Event('beforeprint'));
      expect(html.document.querySelector('#harmony-print-root'), isNull);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      html.window.dispatchEvent(html.Event('beforeprint'));
      expect(html.document.querySelector('#harmony-print-root'), isNotNull);
      await tester.pumpWidget(const SizedBox());
      expect(html.document.querySelector('#harmony-print-root'), isNull);
      expect(html.document.body!.classes, isNot(contains('harmony-printing')));
      current.dispose();
    },
  );
}
