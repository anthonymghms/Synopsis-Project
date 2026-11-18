import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gospel_frontend/account_access.dart';
import 'package:gospel_frontend/browser_route_link.dart';
import 'package:gospel_frontend/catalog_events.dart';
import 'package:gospel_frontend/main.dart';
import 'package:gospel_frontend/reader_language_route.dart';
import 'package:gospel_frontend/topic_dataset.dart';
import 'package:gospel_frontend/topic_language_catalog.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Synthetic, deliberately overlapping IDs exercise the actual reader widgets.
List<Map<String, dynamic>> canonical(String dataset) => [
  for (var id = 1; id <= 3; id++)
    {
      'id': '$id',
      'datasetId': dataset,
      'sourceNumber': '$id',
      'sourceOrder': id,
      if (dataset != 'harmony')
        'typeId': dataset == 'miracles'
            ? 'healing'
            : (id == 2 ? 'figure-of-speech' : 'parable'),
      'references': [
        {'book': id == 1 ? 'Mark' : 'Luke', 'chapter': 1, 'verses': '$id'},
      ],
    },
];
String subject(String dataset, Object id, String language) =>
    language == 'arabic'
    ? '$dataset موضوع تجريبي $id'
    : '$dataset fixture subject $id';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AccountAccessController originalAccess;
  late MockClient client;
  late List<Uri> requests;
  late Map<String, List<Map<String, dynamic>>> datasetRows;
  late bool customPublished;
  late bool catalogUnavailable;
  List<Map<String, dynamic>> rowsFor(String dataset) =>
      datasetRows[dataset] ?? canonical(dataset);

  setUpAll(() async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
          'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi.queryGet',
          (_) async => const StandardMessageCodec().encodeMessage([
            'unavailable',
            'Offline dataset fixture',
            null,
          ]),
        );
    originalAccess = accountAccess;
    accountAccess = AccountAccessController(
      tokenProvider: () async => 'dataset-reader-token',
    );
    accountAccess.beginSession('reader');
    requests = [];
    datasetRows = {};
    customPublished = false;
    catalogUnavailable = false;
    client = MockClient((request) async {
      requests.add(request.url);
      expectSync(
        request.headers['Authorization'],
        'Bearer dataset-reader-token',
      );
      final path = request.url.path;
      Object body;
      if (path == '/account/access') {
        body = {
          'uid': 'reader',
          'role': 'subscribed',
          'canRead': true,
          'accessStatus': 'active',
        };
      } else if (path == '/datasets') {
        if (catalogUnavailable) return http.Response('Unavailable', 503);
        body = {
          'datasets': [
            for (final entry in builtinDatasetCatalog)
              {
                'datasetId': entry.datasetId,
                'labels': entry.labels,
                'published': true,
              },
            if (customPublished)
              {
                'datasetId': 'journeys',
                'labels': {'english': 'Journeys', 'arabic': 'الرحلات'},
                'published': true,
              },
          ],
        };
      } else if (path == '/topic-languages') {
        body = {
          'languages': [
            {'id': 'english', 'direction': 'ltr'},
            {'id': 'arabic', 'direction': 'rtl'},
          ],
        };
      } else if (path == '/harmony/topics') {
        body = {'topics': canonical('harmony')};
      } else if (path.startsWith('/topic-localizations/')) {
        final language = path.split('/').last;
        body = {
          'topics': [
            for (var id = 1; id <= 3; id++)
              {'id': '$id', 'name': subject('harmony', id, language)},
          ],
        };
      } else if (path.startsWith('/datasets/')) {
        final parts = path.split('/');
        final dataset = parts[2];
        final revision = '$dataset-fixture-revision';
        if (parts[3] == 'topics') {
          body = {
            'datasetId': dataset,
            'revision': revision,
            'metadata': {
              'hasTypes': true,
              'itemCount': 3,
              'languages': ['english', 'arabic'],
              'types': dataset == 'miracles'
                  ? [
                      {
                        'id': 'healing',
                        'labels': {'english': 'Healing', 'arabic': 'شفاء'},
                        'count': 3,
                      },
                    ]
                  : [
                      {
                        'id': 'parable',
                        'labels': {'english': 'Parable', 'arabic': 'مثل'},
                        'count': 2,
                      },
                      {
                        'id': 'figure-of-speech',
                        'labels': {
                          'english': 'Figure of Speech',
                          'arabic': 'تعبير مجازي',
                        },
                        'count': 1,
                      },
                    ],
            },
            'topics': rowsFor(dataset),
          };
        } else {
          expectSync(parts[3], 'localizations');
          expectSync(request.url.queryParameters['revision'], revision);
          body = {
            'datasetId': dataset,
            'revision': revision,
            'topics': [
              for (final row in rowsFor(dataset))
                {
                  'id': row['id'],
                  'name': subject(dataset, row['id'], parts.last),
                },
            ],
          };
        }
      } else if (path == '/get_verse' || path == '/get_chapter') {
        final language = request.url.queryParameters['language'];
        expectSync(language, isIn(['english', 'arabic']));
        body = [
          for (var id = 1; id <= 3; id++)
            {'verse': id, 'text': '$language fixture verse $id'},
        ];
      } else {
        fail('Unexpected dataset reader request: ${request.url}');
      }
      return http.Response(
        jsonEncode(body),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    notifyCatalogChanged();
    await loadPrimaryLanguageCatalogs(
      bibleLoader: () async => kBaseLanguageOptions,
      topicLoader: () async => bundledTopicLanguages,
    );
    PrimaryLanguageController.instance.select('english');
  });
  tearDown(() async {
    accountAccess.dispose();
    accountAccess = originalAccess;
    client.close();
    await loadPrimaryLanguageCatalogs(
      bibleLoader: () async => kBaseLanguageOptions,
      topicLoader: () async => bundledTopicLanguages,
    );
    PrimaryLanguageController.instance.select('english');
  });

  Route<void> buildRoute(RouteSettings settings) {
    final uri = Uri.parse(settings.name!);
    final languages = resolveReaderLanguages(uri);
    final query = uri.queryParameters;
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => uri.path == '/topic'
          ? DatasetReaderLanguageRoute(
              uri: uri,
              builder: (selection) => TopicDetailScreen(
                datasetId: normalizeDatasetId(query['dataset']),
                languageOption: selection.bible,
                topicLanguage: selection.topic,
                apiVersion: query['version'] ?? 'kjv',
                topicId: query['topicId'] ?? '1',
                topicNumber: query['topicNumber'] ?? '1',
              ),
            )
          : ReaderLanguageRoute(
              onActivated: () => activateReaderLanguages(languages),
              child: TopicListScreen(
                initialDataset: query['dataset'],
                initialView: query['view'],
                initialTypes: query['types'],
                initialLanguage: languages.bible.code,
                initialTopicLanguage: languages.topic,
                initialVersion: query['version'],
                initialFilterMode: query['filterMode'],
                initialIncludedGospels: query['include'],
                initialExcludedGospels: query['exclude'],
                initialSortGospel: query['sort'],
                initialVisibleColumns: query['columns'],
              ),
            ),
    );
  }

  Widget app(String initialRoute) => MenuLanguageScope(
    notifier: MenuLanguageController.instance.notifier,
    child: MaterialApp(
      navigatorObservers: [readerLanguageRouteObserver],
      initialRoute: initialRoute,
      onGenerateInitialRoutes: (name) => [
        buildRoute(RouteSettings(name: name)),
      ],
      onGenerateRoute: buildRoute,
    ),
  );
  String route({
    String path = '/',
    String dataset = 'harmony',
    String bibleLanguage = 'english',
    String? tableLanguage,
    String? view,
    String? types,
    String? id,
  }) => Uri(
    path: path,
    queryParameters: {
      'bibleLanguage': bibleLanguage,
      'language': bibleLanguage,
      'version': bibleLanguage == 'arabic' ? 'Van Dyke-' : 'kjv',
      'topicLanguage': tableLanguage ?? bibleLanguage,
      'menuLanguage': tableLanguage ?? bibleLanguage,
      if (dataset != 'harmony') 'dataset': dataset,
      if (view != null) 'view': view,
      if (types != null) 'types': types,
      if (id != null) 'topicId': id,
      if (id != null) 'topicNumber': id,
    },
  ).toString();
  HarmonyTable table(WidgetTester tester) =>
      tester.widget<HarmonyTable>(find.byType(HarmonyTable));
  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> chooseArabicBible(WidgetTester tester) async {
    await tap(
      tester,
      find.byWidgetPredicate(
        (widget) =>
            widget is Tooltip && widget.message?.endsWith(': English') == true,
      ),
    );
    await tap(tester, find.text('العربية').last);
    if (find.text('البستاني فاندايك').evaluate().isNotEmpty) {
      await tap(tester, find.text('البستاني فاندايك').last);
    }
    expect(BrowserRouteLinkNavigation.isBlocked, isFalse);
  }

  Future<void> inReader(
    WidgetTester tester,
    String initial,
    Future<void> Function() run, {
    Size size = const Size(1600, 1100),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await http.runWithClient(() async {
      try {
        await accountAccess.refresh(force: true);
        await tester.pumpWidget(app(initial));
        await tester.pumpAndSettle();
        await run();
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        accountAccess.clear();
      }
    }, () => client);
  }

  void assertBible(WidgetTester tester, [String language = 'english']) {
    final toolbar = tester.widget<AppToolbar>(find.byType(AppToolbar));
    expect(toolbar.language.code, language);
    if (language == 'english') expect(toolbar.version.toLowerCase(), 'kjv');
  }

  int canonicalRequests() =>
      requests.where((uri) => uri.path.endsWith('/topics')).length;

  testWidgets(
    'published fourth table appears and keeps IDs, filters and readers separate',
    (tester) async {
      customPublished = true;
      await inReader(tester, route(), () async {
        Future<void> select(String label) async {
          await tap(
            tester,
            find.byKey(const ValueKey('dataset-selector-dropdown')),
          );
          await tap(tester, find.text(label).last);
        }

        await select('Journeys');
        expect(table(tester).topics.first.datasetId, 'journeys');
        expect(table(tester).topics.first.id, '1');
        expect(
          table(tester).topics.first.name,
          subject('journeys', 1, 'english'),
        );
        await tap(tester, find.text('Group by Type'));
        await tap(tester, find.byType(HarmonyFilterButton));
        await tap(tester, find.byKey(const ValueKey('type-filter-parable')));
        await tap(tester, find.byKey(const ValueKey('apply-filter')));
        expect(table(tester).topics.map((t) => t.id), ['1', '3']);
        final links = tester
            .widgetList<BrowserRouteLink>(find.byType(BrowserRouteLink))
            .where(
              (link) => const ['/topic', '/reference'].contains(link.uri?.path),
            );
        expect(links, isNotEmpty);
        for (final link in links) {
          expect(link.uri!.queryParameters['dataset'], 'journeys');
          expect(link.uri!.queryParameters['view'], 'grouped');
          expect(link.uri!.queryParameters['types'], 'parable');
          expect(link.uri!.queryParameters['bibleLanguage'], 'english');
          if (link.uri!.path == '/reference') expect(link.openInNewTab, isTrue);
        }
        await tap(tester, find.text(subject('journeys', 1, 'english')));
        expect(
          tester
              .widget<TopicDetailScreen>(find.byType(TopicDetailScreen))
              .datasetId,
          'journeys',
        );
        Navigator.of(tester.element(find.byType(TopicDetailScreen))).pop();
        await tester.pumpAndSettle();
        await select('Miracles');
        expect(table(tester).topics.length, 3);
        expect(
          table(tester).topics.first.name,
          subject('miracles', 1, 'english'),
        );
        await select('Journeys');
        expect(table(tester).groupedByType, isTrue);
        expect(table(tester).topics.map((t) => t.id), ['1', '3']);
        assertBible(tester);
        expect(canonicalRequests(), 3);
        expect(requests.where((uri) => uri.path == '/datasets').length, 1);
      });
    },
  );

  testWidgets(
    'a cold fourth-table link retains localization and identity while catalog retries',
    (tester) async {
      customPublished = true;
      catalogUnavailable = true;
      await inReader(
        tester,
        route(dataset: 'journeys', bibleLanguage: 'arabic'),
        () async {
          expect(table(tester).topics.first.datasetId, 'journeys');
          expect(
            table(tester).topics.first.name,
            subject('journeys', 1, 'arabic'),
          );
          expect(
            find.byKey(const ValueKey('retry-dataset-catalog')),
            findsOneWidget,
          );
          catalogUnavailable = false;
          await tap(
            tester,
            find.byKey(const ValueKey('retry-dataset-catalog')),
          );
          expect(
            find.byKey(const ValueKey('retry-dataset-catalog')),
            findsNothing,
          );
          expect(find.text('الرحلات'), findsWidgets);
          expect(canonicalRequests(), 1);
          assertBible(tester, 'arabic');
        },
      );
    },
  );

  testWidgets(
    'a newly published fourth table is discovered after catalog invalidation',
    (tester) async {
      await inReader(tester, route(), () async {
        expect(
          find.byKey(const ValueKey('dataset-selector-tabs')),
          findsOneWidget,
        );
        customPublished = true;
        notifyCatalogChanged();
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('dataset-selector-dropdown')),
          findsOneWidget,
        );
        await tap(
          tester,
          find.byKey(const ValueKey('dataset-selector-dropdown')),
        );
        expect(find.text('Journeys'), findsWidgets);
        await tap(tester, find.text('Journeys').last);
        expect(table(tester).topics.first.datasetId, 'journeys');
      });
    },
  );

  testWidgets(
    'all three tables isolate identical IDs and reuse loaded data when switching',
    (tester) async {
      await inReader(tester, route(), () async {
        expect(
          table(tester).topics.first.name,
          subject('harmony', 1, 'english'),
        );
        expect(find.byKey(const ValueKey('dataset-view-mode')), findsNothing);
        await tap(tester, find.text('Miracles'));
        expect(table(tester).topics.first.id, '1');
        expect(table(tester).topics.first.datasetId, 'miracles');
        expect(
          table(tester).topics.first.name,
          subject('miracles', 1, 'english'),
        );
        await tap(tester, find.text('Parables'));
        expect(table(tester).topics.first.id, '1');
        expect(
          table(tester).topics.first.name,
          subject('parables', 1, 'english'),
        );
        expect(
          table(tester).topics.map((item) => item.typeId),
          contains('figure-of-speech'),
        );
        await tap(tester, find.text('Harmony / All Topics'));
        expect(
          table(tester).topics.first.name,
          subject('harmony', 1, 'english'),
        );
        expect(canonicalRequests(), 3);
        assertBible(tester);
      });
    },
  );

  testWidgets(
    'Arabic Bible selection automatically localizes the table and preserves reference identity',
    (tester) async {
      await inReader(tester, route(dataset: 'parables'), () async {
        expect(
          find.byKey(const ValueKey('table-language-selector')),
          findsNothing,
        );
        await chooseArabicBible(tester);
        expect(table(tester).topicLanguage.code, 'arabic');
        expect(
          table(tester).topics.first.name,
          subject('parables', 1, 'arabic'),
        );
        expect(table(tester).topics.first.typeId, 'parable');
        expect(table(tester).topics.first.references.first.book, 'Mark');
        expect(canonicalRequests(), 1);
        assertBible(tester, 'arabic');
        expect(
          requests
              .where(
                (uri) => uri.path == '/datasets/parables/localizations/arabic',
              )
              .length,
          1,
        );
      });
    },
  );

  testWidgets(
    'Type filters update live and grouped state is restored only for its dataset without fetching',
    (tester) async {
      await inReader(tester, route(dataset: 'parables'), () async {
        await tap(tester, find.text('Group by Type'));
        await tap(tester, find.byType(HarmonyFilterButton));
        await tap(tester, find.byKey(const ValueKey('type-filter-parable')));
        expect(
          tester
              .widget<HarmonyTable>(
                find.byType(HarmonyTable, skipOffstage: false),
              )
              .topics
              .map((t) => t.id),
          ['1', '3'],
        );
        await tap(tester, find.byKey(const ValueKey('apply-filter')));
        expect(table(tester).groupedByType, isTrue);
        expect(table(tester).topics.map((t) => t.id), ['1', '3']);
        expect(canonicalRequests(), 1);
        await tap(tester, find.text('Miracles'));
        expect(table(tester).topics.length, 3);
        expect(table(tester).groupedByType, isFalse);
        await tap(tester, find.text('Parables'));
        expect(table(tester).groupedByType, isTrue);
        expect(table(tester).topics.map((t) => t.id), ['1', '3']);
        expect(canonicalRequests(), 2);
        await tap(tester, find.byType(HarmonyFilterButton));
        await tap(tester, find.byKey(const ValueKey('type-filter-all')));
        await tap(tester, find.byKey(const ValueKey('apply-filter')));
        expect(table(tester).topics.length, 3);
        expect(canonicalRequests(), 2);
      });
    },
  );

  testWidgets(
    'Back restores the selected Bible and matching table language after opening a topic',
    (tester) async {
      await inReader(tester, route(dataset: 'parables'), () async {
        await chooseArabicBible(tester);
        await tap(tester, find.text(subject('parables', 1, 'arabic')));
        expect(BrowserRouteLinkNavigation.isBlocked, isFalse);
        expect(find.byType(TopicDetailScreen), findsOneWidget);
        Navigator.of(tester.element(find.byType(TopicDetailScreen))).pop();
        await tester.pumpAndSettle();
        expect(MenuLanguageController.instance.languageCode, 'arabic');
        expect(
          TopicLanguageSelectionController.instance.languageCode,
          'arabic',
        );
        expect(table(tester).topicLanguage.code, 'arabic');
        expect(
          table(tester).topics.first.name,
          subject('parables', 1, 'arabic'),
        );
        assertBible(tester, 'arabic');
        expect(canonicalRequests(), 1);
      });
    },
  );

  testWidgets(
    'a refreshed dataset route reconstructs grouped filters and the Bible-matched table language',
    (tester) async {
      await inReader(
        tester,
        route(
          dataset: 'parables',
          view: 'grouped',
          types: 'figure-of-speech',
          bibleLanguage: 'arabic',
        ),
        () async {
          expect(table(tester).metadata.datasetId, 'parables');
          expect(table(tester).groupedByType, isTrue);
          expect(table(tester).topics.map((t) => t.id), ['2']);
          expect(
            table(tester).topics.single.name,
            subject('parables', 2, 'arabic'),
          );
          assertBible(tester, 'arabic');
          expect(canonicalRequests(), 1);
        },
      );
    },
  );

  testWidgets('topic detail and previous next stay in originating dataset', (
    tester,
  ) async {
    await inReader(
      tester,
      route(path: '/topic', dataset: 'parables', id: '1'),
      () async {
        expect(
          find.textContaining(subject('parables', 1, 'english')),
          findsWidgets,
        );
        expect(
          find.textContaining(subject('harmony', 1, 'english')),
          findsNothing,
        );
        await tap(tester, find.text('Next topic'));
        var detail = tester.widget<TopicDetailScreen>(
          find.byType(TopicDetailScreen),
        );
        expect(detail.datasetId, 'parables');
        expect(detail.topicId, '2');
        expect(
          find.textContaining(subject('parables', 2, 'english')),
          findsWidgets,
        );
        await tap(tester, find.text('Previous topic'));
        detail = tester.widget<TopicDetailScreen>(
          find.byType(TopicDetailScreen),
        );
        expect(detail.datasetId, 'parables');
        expect(detail.topicId, '1');
        expect(canonicalRequests(), 1);
        assertBible(tester);
      },
    );
  });

  testWidgets(
    'table links preserve dataset, view, Type and Bible choices on return',
    (tester) async {
      await inReader(
        tester,
        route(dataset: 'parables', view: 'grouped', types: 'parable'),
        () async {
          final links = tester
              .widgetList<BrowserRouteLink>(find.byType(BrowserRouteLink))
              .where(
                (link) =>
                    const ['/topic', '/reference'].contains(link.uri?.path),
              );
          expect(links, isNotEmpty);
          for (final link in links) {
            expect(link.uri!.queryParameters['dataset'], 'parables');
            expect(link.uri!.queryParameters['view'], 'grouped');
            expect(link.uri!.queryParameters['types'], 'parable');
            expect(link.uri!.queryParameters['bibleLanguage'], 'english');
            expect(link.uri!.queryParameters['version']?.toLowerCase(), 'kjv');
          }
          final referenceLinks = links.where(
            (link) => link.uri?.path == '/reference',
          );
          expect(referenceLinks, isNotEmpty);
          expect(referenceLinks.every((link) => link.openInNewTab), isTrue);
          await tap(tester, find.text(subject('parables', 1, 'english')));
          expect(
            tester
                .widget<TopicDetailScreen>(find.byType(TopicDetailScreen))
                .datasetId,
            'parables',
          );
          await tap(tester, find.text('Back to main table'));
          expect(table(tester).metadata.datasetId, 'parables');
          expect(table(tester).groupedByType, isTrue);
          expect(table(tester).topics.map((item) => item.id), ['1', '3']);
          expect(canonicalRequests(), 1);
          assertBible(tester);
        },
      );
    },
  );

  testWidgets(
    'dataset topic IDs differing only by case select the exact item',
    (tester) async {
      datasetRows['parables'] = [
        for (final id in ['A', 'a'])
          {
            'id': id,
            'sourceNumber': id,
            'datasetId': 'parables',
            'typeId': 'parable',
            'references': [
              {'book': 'Luke', 'chapter': 1, 'verses': '1'},
            ],
          },
      ];
      await inReader(
        tester,
        route(path: '/topic', dataset: 'parables', id: 'a'),
        () async {
          final reader = tester.widget<AuthorComparisonScreen>(
            find.byType(AuthorComparisonScreen),
          );
          expect(reader.topic.id, 'a');
          expect(reader.topic.name, subject('parables', 'a', 'english'));
          expect(
            find.textContaining(subject('parables', 'A', 'english')),
            findsNothing,
          );
        },
      );
    },
  );

  testWidgets(
    'dataset language resolver keeps Arabic even when Harmony localization is incomplete',
    (tester) async {
      await loadPrimaryLanguageCatalogs(
        bibleLoader: () async => kBaseLanguageOptions,
        topicLoader: () async => [
          TopicLanguageOption.fromJson({
            'id': 'english',
            'direction': 'ltr',
            'topicCount': 100,
            'canonicalTopicCount': 100,
            'complete': true,
          }),
          TopicLanguageOption.fromJson({
            'id': 'arabic',
            'direction': 'rtl',
            'topicCount': 10,
            'canonicalTopicCount': 100,
            'complete': false,
          }),
        ],
      );
      final selection = resolveReaderLanguages(
        Uri.parse(route(dataset: 'parables', bibleLanguage: 'arabic')),
      );
      expect(selection.bible.code, 'arabic');
      expect(selection.topic, 'arabic');
      expect(selection.menu, 'arabic');
      activateReaderLanguages(selection);
      String? menuLanguage;
      await tester.pumpWidget(
        MenuLanguageScope(
          notifier: MenuLanguageController.instance.notifier,
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                menuLanguage = MenuLanguageScope.of(context).code;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(menuLanguage, 'arabic');
      final harmony = resolveReaderLanguages(
        Uri.parse(route(bibleLanguage: 'arabic')),
      );
      expect(harmony.topic, 'arabic');
    },
  );

  testWidgets('full Parables toolbar and grouping fit a narrow screen', (
    tester,
  ) async {
    await inReader(tester, route(dataset: 'parables'), () async {
      expect(
        find.byKey(const ValueKey('dataset-selector-dropdown')),
        findsOneWidget,
      );
      await tap(tester, find.text('Group by Type'));
      expect(table(tester).groupedByType, isTrue);
      expect(table(tester).topics.length, 3);
      await tap(tester, find.byType(HarmonyFilterButton));
      await tap(tester, find.byKey(const ValueKey('type-filter-parable')));
      await tap(tester, find.byKey(const ValueKey('apply-filter')));
      expect(table(tester).topics.map((topic) => topic.id), ['1', '3']);
      assertBible(tester);
      expect(canonicalRequests(), 1);
    }, size: const Size(390, 844));
  });
}
