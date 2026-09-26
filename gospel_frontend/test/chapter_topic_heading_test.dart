import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gospel_frontend/browser_route_link.dart';
import 'package:gospel_frontend/main.dart';

void main() {
  tearDown(() => PrimaryLanguageController.instance.select('english'));

  testWidgets('chapter subject links to all its references in a new tab', (
    tester,
  ) async {
    final topic = Topic(
      id: '26',
      name: 'Temptation of Christ',
      references: const [],
    );
    final language = kBaseLanguageOptions.first;
    String? openedRoute;
    await tester.pumpWidget(
      MaterialApp(
        onGenerateRoute: (settings) {
          openedRoute = settings.name;
          return MaterialPageRoute<void>(
            builder: (_) =>
                const Scaffold(body: Text('All subject references')),
          );
        },
        home: Scaffold(
          body: ChapterTopicHeading(
            topic: topic,
            language: language,
            version: 'ASV',
          ),
        ),
      ),
    );

    final link = tester.widget<BrowserRouteLink>(find.byType(BrowserRouteLink));
    expect(link.openInNewTab, isTrue);
    expect(link.uri?.path, '/topic');
    expect(link.uri?.queryParameters, {
      'menuLanguage': 'english',
      'topicLanguage': 'english',
      'bibleLanguage': 'english',
      'language': 'english',
      'version': 'ASV',
      'topicId': '26',
      'topicNumber': '26',
    });
    expect(find.byTooltip('Click to read all references'), findsOneWidget);
    expect(find.byIcon(Icons.open_in_new), findsOneWidget);

    // Native tests use the same-tab fallback; the web link's new-tab flag above
    // exercises the existing BrowserRouteLink behavior used by reference links.
    await tester.tap(find.text('Temptation of Christ'));
    await tester.pumpAndSettle();
    expect(openedRoute, link.uri.toString());
    expect(find.text('All subject references'), findsOneWidget);
  });

  testWidgets('subjects with identical names keep separate destinations', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              for (final id in ['26', '27'])
                ChapterTopicHeading(
                  topic: Topic(
                    id: id,
                    name: 'The same subject title',
                    references: const [],
                  ),
                  language: kBaseLanguageOptions.first,
                  version: 'ASV',
                ),
            ],
          ),
        ),
      ),
    );
    final links = tester
        .widgetList<BrowserRouteLink>(find.byType(BrowserRouteLink))
        .toList();
    expect(links.map((link) => link.uri?.queryParameters['topicId']), [
      '26',
      '27',
    ]);
    expect(links.every((link) => link.openInNewTab), isTrue);
  });

  testWidgets(
    'Arabic headings preserve language and translation on narrow screens',
    (tester) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      PrimaryLanguageController.instance.select('arabic');
      final language = kBaseLanguageOptions.last;
      await tester.pumpWidget(
        MaterialApp(
          home: MenuLanguageScope(
            notifier: MenuLanguageController.instance.notifier,
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: ChapterTopicHeading(
                  topic: Topic(
                    id: '26',
                    name: 'تجربة المسيح',
                    references: const [],
                  ),
                  language: language,
                  version: 'Van Dyke-',
                ),
              ),
            ),
          ),
        ),
      );
      final link = tester.widget<BrowserRouteLink>(
        find.byType(BrowserRouteLink),
      );
      expect(link.openInNewTab, isTrue);
      expect(link.uri?.queryParameters['language'], 'arabic');
      expect(link.uri?.queryParameters['topicLanguage'], 'arabic');
      expect(link.uri?.queryParameters['version'], 'Van Dyke-');
      expect(link.uri?.queryParameters['topicId'], '26');
      expect(find.byTooltip('قراءة كل المراجع'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
