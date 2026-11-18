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
import 'package:gospel_frontend/gospel_filter.dart';
import 'package:gospel_frontend/main.dart';
import 'package:gospel_frontend/reader_language_route.dart';
import 'package:gospel_frontend/topic_dataset.dart';
import 'package:gospel_frontend/topic_language_catalog.dart';
import 'package:gospel_frontend/user_profile.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Synthetic data: French exists only for Miracles, never in the Harmony or
// Bible catalogs. IDs and references deliberately overlap across all tables.
const _languages = ['english', 'arabic'];
Map<String, dynamic> _language(String code) => {
  'id': code,
  'label': code == 'french' ? 'Français' : code,
  'direction': code == 'arabic' ? 'rtl' : 'ltr',
  'subjectsLabel': switch (code) {
    'french' => 'Sujets traduits',
    'arabic' => 'المواضيع',
    _ => 'Subjects',
  },
  'gospels': switch (code) {
    'french' => {
      'Matthew': 'Matthieu localisé',
      'Mark': 'Marc localisé',
      'Luke': 'Luc localisé',
      'John': 'Jean localisé',
    },
    'arabic' => {
      'Matthew': 'متى',
      'Mark': 'مرقس',
      'Luke': 'لوقا',
      'John': 'يوحنا',
    },
    _ => {'Matthew': 'Matthew', 'Mark': 'Mark', 'Luke': 'Luke', 'John': 'John'},
  },
  'topicCount': 2,
  'canonicalTopicCount': 2,
  'complete': true,
};
String _name(String dataset, String id, String language) => switch (language) {
  'arabic' => '$dataset موضوع $id',
  'french' => '$dataset sujet français $id',
  _ => '$dataset subject $id',
};
List<Map<String, dynamic>> _canonical(String dataset) => [
  for (final id in ['10', '11'])
    {
      'id': id,
      'datasetId': dataset,
      'sourceNumber': id,
      'sourceOrder': int.parse(id),
      if (dataset != 'harmony') 'typeId': 'healing',
      'references': [
        {'book': 'Luke', 'chapter': 1, 'verses': id == '10' ? '5' : '6'},
      ],
    },
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AccountAccessController originalAccess;
  late MockClient client;
  late List<Uri> requests;

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
            'Offline universal language fixture',
            null,
          ]),
        );
    originalAccess = accountAccess;
    accountAccess = AccountAccessController(
      tokenProvider: () async => 'language-reader-token',
    )..beginSession('reader');
    requests = [];
    client = MockClient((request) async {
      requests.add(request.url);
      expect(request.headers['Authorization'], 'Bearer language-reader-token');
      final path = request.url.path;
      Object body;
      if (path == '/account/access') {
        body = {
          'uid': 'reader',
          'role': 'subscribed',
          'canRead': true,
          'accessStatus': 'active',
        };
      } else if (path == '/topic-languages') {
        body = {
          'languages': [for (final code in _languages) _language(code)],
        };
      } else if (path == '/harmony/topics' ||
          (path.startsWith('/datasets/') && path.endsWith('/topics'))) {
        final dataset = path == '/harmony/topics'
            ? 'harmony'
            : path.split('/')[2];
        final languages = [..._languages, if (dataset == 'miracles') 'french'];
        body = {
          'datasetId': dataset,
          'revision': '$dataset-fixture-1',
          'metadata': {
            'languages': languages,
            'itemCount': 2,
            'hasTypes': dataset != 'harmony',
            'languageMetadata': {
              // French headers are supplied only by its localization payload.
              for (final code in _languages) code: _language(code),
            },
            'types': [
              if (dataset != 'harmony')
                {
                  'id': 'healing',
                  'labels': {'english': 'Healing', 'arabic': 'شفاء'},
                  'count': 2,
                },
            ],
          },
          'topics': _canonical(dataset),
        };
      } else if (path.startsWith('/topic-localizations/') ||
          path.contains('/localizations/')) {
        final dataset = path.startsWith('/topic-localizations/')
            ? 'harmony'
            : path.split('/')[2];
        final language = path.split('/').last;
        if (language == 'french' && dataset != 'miracles') {
          return http.Response(
            jsonEncode({'error': 'French is available only for Miracles.'}),
            404,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        body = {
          'datasetId': dataset,
          'revision': '$dataset-fixture-1',
          'language': _language(language),
          'typeLabels': {
            if (dataset != 'harmony')
              'healing': switch (language) {
                'french' => 'Guérison',
                'arabic' => 'شفاء',
                _ => 'Healing',
              },
          },
          'topics': [
            for (final row in _canonical(dataset))
              {
                'id': row['id'],
                'name': _name(dataset, row['id'] as String, language),
                'nameLanguage': language,
                'fallback': false,
              },
          ],
        };
      } else if (path == '/get_verse' || path == '/get_chapter') {
        expect(request.url.queryParameters['language'], 'english');
        expect(request.url.queryParameters['version']?.toLowerCase(), 'kjv');
        body = [
          for (var verse = 1; verse <= 6; verse++)
            {'verse': verse, 'text': 'English KJV fixture $verse'},
        ];
      } else {
        fail('Unexpected universal language request: ${request.url}');
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
      topicLoader: () async => [
        for (final code in _languages)
          TopicLanguageOption.fromJson(_language(code)),
      ],
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
      builder: (_) => ReaderLanguageRoute(
        onActivated: () => activateReaderLanguages(languages),
        child: uri.path == '/topic'
            ? TopicDetailScreen(
                datasetId: normalizeDatasetId(query['dataset']),
                languageOption: languages.bible,
                topicLanguage: languages.topic,
                apiVersion: query['version'] ?? 'kjv',
                topicId: query['topicId']!,
                topicNumber: query['topicNumber'] ?? '',
              )
            : TopicListScreen(
                initialDataset: query['dataset'],
                initialView: query['view'],
                initialTypes: query['types'],
                initialLanguage: languages.bible.code,
                initialTopicLanguage: languages.topic,
                initialVersion: query['version'],
              ),
      ),
    );
  }

  Widget app(String route) => MenuLanguageScope(
    notifier: MenuLanguageController.instance.notifier,
    child: MaterialApp(
      navigatorObservers: [readerLanguageRouteObserver],
      initialRoute: route,
      onGenerateInitialRoutes: (name) => [
        buildRoute(RouteSettings(name: name)),
      ],
      onGenerateRoute: buildRoute,
    ),
  );
  String route(String dataset, String language, {bool grouped = false}) => Uri(
    path: '/',
    queryParameters: {
      if (dataset != 'harmony') 'dataset': dataset,
      'topicLanguage': language,
      'menuLanguage': language,
      'bibleLanguage': 'english',
      'language': 'english',
      'version': 'kjv',
      if (grouped) 'view': 'grouped',
      if (grouped) 'types': 'healing',
    },
  ).toString();
  HarmonyTable table(WidgetTester tester) =>
      tester.widget<HarmonyTable>(find.byType(HarmonyTable));
  List<BrowserRouteLink> links(WidgetTester tester) => tester
      .widgetList<BrowserRouteLink>(find.byType(BrowserRouteLink))
      .where((link) => ['/topic', '/reference'].contains(link.uri?.path))
      .toList();
  void assertBible(WidgetTester tester) {
    final toolbar = tester.widget<AppToolbar>(find.byType(AppToolbar));
    expect(toolbar.language.code, 'english');
    expect(toolbar.version.toLowerCase(), 'kjv');
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> inReader(
    WidgetTester tester,
    String initial,
    Future<void> Function() run,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1100));
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

  test(
    'applying stored preferences retains a table-only locale absent the Harmony and Bible catalogs',
    () {
      expect(
        readerLanguageOptions().map((option) => option.code),
        isNot(contains('french')),
      );
      applyUserPreferencesToLegacyControllers(
        const UserPreferences(
          topicLanguage: 'french',
          menuLanguage: 'french',
          contentLanguage: 'arabic',
        ),
      );
      expect(TopicLanguageSelectionController.instance.languageCode, 'french');
      expect(MenuLanguageController.instance.languageCode, 'french');
      expect(LanguageSelectionController.instance.languageCode, 'arabic');

      // A later Bible preference update also leaves the independent locale.
      applyUserPreferencesToLegacyControllers(
        const UserPreferences(
          topicLanguage: 'french',
          menuLanguage: 'french',
          contentLanguage: 'english',
        ),
      );
      expect(TopicLanguageSelectionController.instance.languageCode, 'french');
      expect(MenuLanguageController.instance.languageCode, 'french');
      expect(LanguageSelectionController.instance.languageCode, 'english');
    },
  );

  testWidgets(
    'Miracles-only French uses localized metadata without a Harmony or Bible locale',
    (tester) async {
      await inReader(tester, route('miracles', 'french'), () async {
        expect(
          readerLanguageOptions().map((option) => option.code),
          isNot(contains('french')),
        );
        final current = table(tester);
        expect(current.topicLanguage.code, 'french');
        expect(current.topicLanguage.subjectsLabel, 'Sujets traduits');
        expect(current.topicLanguage.gospelNames, [
          'Matthieu localisé',
          'Marc localisé',
          'Luc localisé',
          'Jean localisé',
        ]);
        expect(current.topics.first.name, _name('miracles', '10', 'french'));
        expect(find.text('Sujets traduits'), findsOneWidget);
        expect(find.text('Luc localisé'), findsOneWidget);
        expect(find.text('Guérison'), findsNWidgets(2));
        expect(
          resolveDatasetTopicLanguage('miracles', 'french').code,
          'french',
        );
        final exported = buildTopicsTableDocument(
          topics: current.topics,
          topicLanguage: resolveDatasetTopicLanguage('miracles', 'french'),
          visibleGospels: Gospel.values,
          title: 'Miracles',
          metadata: current.metadata,
        );
        expect(exported.headers.take(2), ['#', 'Sujets traduits']);
        expect(exported.rows.first.take(3), [
          '10',
          _name('miracles', '10', 'french'),
          'Guérison',
        ]);
        for (final link in links(tester)) {
          expect(link.uri!.queryParameters['dataset'], 'miracles');
          expect(link.uri!.queryParameters['topicLanguage'], 'french');
          expect(link.uri!.queryParameters['bibleLanguage'], 'english');
        }
        assertBible(tester);
        expect(
          requests.any((uri) => uri.path == '/topic-localizations/french'),
          isFalse,
        );
      });
    },
  );

  testWidgets(
    'French-only Miracles switches to a supported Harmony table language while keeping English Bible',
    (tester) async {
      await inReader(tester, route('miracles', 'french'), () async {
        expect(table(tester).topicLanguage.code, 'french');
        await tap(tester, find.text(datasetDisplayName('harmony', 'french')));
        expect(find.textContaining('Failed to fetch topics'), findsNothing);
        expect(find.byType(HarmonyTable), findsOneWidget);
        final current = table(tester);
        expect(
          current.topics.every((topic) => topic.datasetId == 'harmony'),
          isTrue,
        );
        expect(current.topicLanguage.code, 'english');
        expect(current.topics.map((topic) => topic.name), [
          _name('harmony', '10', 'english'),
          _name('harmony', '11', 'english'),
        ]);
        for (final link in links(tester)) {
          expect(link.uri!.queryParameters['dataset'], isNull);
          expect(link.uri!.queryParameters['topicLanguage'], 'english');
          expect(link.uri!.queryParameters['bibleLanguage'], 'english');
          expect(link.uri!.queryParameters['version']?.toLowerCase(), 'kjv');
        }
        assertBible(tester);
        await tap(tester, find.text(datasetDisplayName('miracles', 'english')));
        expect(table(tester).topicLanguage.code, 'french');
        expect(
          table(tester).topics.first.name,
          _name('miracles', '10', 'french'),
        );
        expect(table(tester).topicLanguage.gospelNames[2], 'Luc localisé');
        expect(
          table(tester).metadata.typeLabel('healing', 'french'),
          'Guérison',
        );
        for (final link in links(tester)) {
          expect(link.uri!.queryParameters['dataset'], 'miracles');
          expect(link.uri!.queryParameters['topicLanguage'], 'french');
          expect(link.uri!.queryParameters['bibleLanguage'], 'english');
        }
        assertBible(tester);
      });
    },
  );

  for (final dataset in topicDatasetIds) {
    testWidgets(
      '$dataset globe changes Arabic table names, Gospels and numbers independently of English Bible',
      (tester) async {
        await inReader(tester, route(dataset, 'english'), () async {
          expect(find.text('#'), findsOneWidget);
          expect(find.text('10'), findsOneWidget);
          expect(find.text('Table language: '), findsOneWidget);
          expect(find.textContaining('Bible language:'), findsOneWidget);
          await tap(
            tester,
            find.byKey(const ValueKey('table-language-selector')),
          );
          await tap(tester, find.text('العربية').last);
          expect(table(tester).topicLanguage.code, 'arabic');
          expect(
            table(tester).topics.first.name,
            _name(dataset, '10', 'arabic'),
          );
          expect(find.text('لوقا'), findsOneWidget);
          expect(find.text('١٠'), findsOneWidget);
          expect(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Text &&
                  widget.data
                          ?.replaceAll(RegExp('[\u200f\u2067\u2069]'), '')
                          .contains('١:٥') ==
                      true,
            ),
            findsWidgets,
          );
          if (dataset != 'harmony') expect(find.text('شفاء'), findsNWidgets(2));
          final reference = tester
              .widgetList<ReferenceHoverText>(find.byType(ReferenceHoverText))
              .first;
          expect(reference.language, 'english');
          expect(reference.version.toLowerCase(), 'kjv');
          expect(reference.topicLanguage, 'arabic');
          expect(reference.reference.book, 'Luke');
          expect(reference.reference.chapter, 1);
          expect(reference.reference.verses, '5');
          assertBible(tester);
          expect(
            requests.where((uri) => uri.path.endsWith('/topics')),
            hasLength(1),
          );
        });
      },
    );
  }

  testWidgets(
    'French table survives topic reading, Back and a refreshed grouped URL',
    (tester) async {
      await inReader(
        tester,
        route('miracles', 'french', grouped: true),
        () async {
          final topicLink = links(
            tester,
          ).firstWhere((link) => link.uri!.path == '/topic');
          final saved = topicLink.uri!.replace(
            path: '/',
            queryParameters: {...topicLink.uri!.queryParameters}
              ..remove('topicId')
              ..remove('topicNumber'),
          );
          await tap(tester, find.text(_name('miracles', '10', 'french')));
          final detail = tester.widget<AuthorComparisonScreen>(
            find.byType(AuthorComparisonScreen),
          );
          expect(detail.topic.datasetId, 'miracles');
          expect(detail.topic.name, _name('miracles', '10', 'french'));
          expect(detail.topicLanguage, 'french');
          expect(
            find.textContaining('English KJV fixture', findRichText: true),
            findsWidgets,
          );
          Navigator.of(tester.element(find.byType(TopicDetailScreen))).pop();
          await tester.pumpAndSettle();
          expect(table(tester).topicLanguage.code, 'french');
          expect(table(tester).groupedByType, isTrue);
          expect(
            table(tester).metadata.typeLabel('healing', 'french'),
            'Guérison',
          );
          assertBible(tester);
          await tester.pumpWidget(const SizedBox());
          notifyCatalogChanged();
          await tester.pumpWidget(app(saved.toString()));
          await tester.pumpAndSettle();
          expect(table(tester).topicLanguage.code, 'french');
          expect(table(tester).topicLanguage.gospelNames[2], 'Luc localisé');
          expect(table(tester).topics.map((topic) => topic.id), ['10', '11']);
          expect(table(tester).groupedByType, isTrue);
          assertBible(tester);
        },
      );
    },
  );
}
