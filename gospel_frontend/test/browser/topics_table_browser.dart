// ignore_for_file: deprecated_member_use
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gospel_frontend/topics_table_document.dart';
import 'package:gospel_frontend/topics_table_output.dart';
import 'package:gospel_frontend/admin_content_scope.dart';
import 'package:gospel_frontend/browser_route_link.dart';

void main() {
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
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: ValueListenableBuilder<TopicsTableDocument>(
            valueListenable: current,
            builder: (context, document, _) => TopicsTablePrintScope(
              document: document,
              child: const Scaffold(body: Text('Screen viewport')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      html.window.dispatchEvent(html.Event('beforeprint'));
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
