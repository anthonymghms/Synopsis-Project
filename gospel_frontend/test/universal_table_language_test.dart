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

// Synthetic data: French names exist only for Miracles; a French Bible is
// available independently. IDs/references deliberately overlap across tables.
const _languages = ['english', 'arabic'];
final _frenchBible = kBaseLanguageOptions.first.copyWith(
  code: 'french',
  label: 'Français',
  apiLanguage: 'french',
  apiVersion: 'LSG',
  versions: const [BibleVersion(id: 'LSG', label: 'Louis Segond')],
);
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
  late Map<String, List<String>> availableLanguages;

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
    availableLanguages = {
      for (final dataset in topicDatasetIds)
        dataset: [..._languages, if (dataset == 'miracles') 'french'],
    };
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
        final languages = availableLanguages[dataset]!;
        body = {
          'datasetId': dataset,
          'revision': '$dataset-fixture-1',
          'metadata': {
            'languages': languages,
            'itemCount': 2,
            'hasTypes': dataset != 'harmony',
            'languageMetadata': {
              // French headers are supplied only by its localization payload.
              for (final code in languages.where((code) => code != 'french'))
                code: _language(code),
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
        if (!availableLanguages[dataset]!.contains(language)) {
          return http.Response(
            jsonEncode({'error': '$language is unavailable for $dataset.'}),
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
        final language = request.url.queryParameters['language'];
        expect(language, isIn(['english', 'arabic', 'french']));
        if (language == 'french') {
          expect(request.url.queryParameters['version']?.toUpperCase(), 'LSG');
        }
        body = [
          for (var verse = 1; verse <= 6; verse++)
            {'verse': verse, 'text': '$language Bible fixture $verse'},
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
      bibleLoader: () async => [...kBaseLanguageOptions, _frenchBible],
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
    if (uri.path == '/reference') {
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => DatasetReaderLanguageRoute(
          uri: uri,
          builder: (selection) => ReferenceViewerPage(
            datasetId: normalizeDatasetId(query['dataset']),
            displayBook: query['bookDisplay']!,
            bookId: query['book']!,
            chapter: int.parse(query['chapter']!),
            verses: query['verses'] ?? '',
            language: selection.bible.apiLanguage,
            version: query['version']!,
            topicLanguage: selection.topic,
            topicId: query['topicId'] ?? '',
            topicNumber: query['topicNumber'] ?? '',
            topicName: query['topic'] ?? '',
            source: query['source'] ?? '',
            gospel: query['gospel'] ?? '',
          ),
        ),
      );
    }
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
                topicId: query['topicId']!,
                topicNumber: query['topicNumber'] ?? '',
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
                initialTableLocale: query['tableLocale'],
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
      'bibleLanguage': language,
      'language': language,
      'version': language == 'french'
          ? 'LSG'
          : language == 'arabic'
          ? 'Van Dyke-'
          : 'kjv',
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
  void assertBible(WidgetTester tester, [String language = 'english']) {
    final toolbar = tester.widget<AppToolbar>(find.byType(AppToolbar));
    expect(toolbar.language.code, language);
    if (language == 'english') expect(toolbar.version.toLowerCase(), 'kjv');
    if (language == 'french') expect(toolbar.version.toUpperCase(), 'LSG');
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> chooseBible(WidgetTester tester, String nativeName) async {
    await tap(
      tester,
      find.byWidgetPredicate(
        (widget) =>
            widget is Tooltip && widget.message?.endsWith(': English') == true,
      ),
    );
    await tap(tester, find.text(nativeName).last);
    if (find.text('البستاني فاندايك').evaluate().isNotEmpty) {
      await tap(tester, find.text('البستاني فاندايك').last);
    }
    expect(BrowserRouteLinkNavigation.isBlocked, isFalse);
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
    'applying old mixed preferences follows the selected Bible language',
    () {
      expect(
        readerLanguageOptions().map((option) => option.code),
        contains('french'),
      );
      applyUserPreferencesToLegacyControllers(
        const UserPreferences(
          topicLanguage: 'french',
          menuLanguage: 'french',
          contentLanguage: 'arabic',
        ),
      );
      expect(TopicLanguageSelectionController.instance.languageCode, 'arabic');
      expect(MenuLanguageController.instance.languageCode, 'arabic');
      expect(LanguageSelectionController.instance.languageCode, 'arabic');

      // A later Bible preference update also determines the requested locale.
      applyUserPreferencesToLegacyControllers(
        const UserPreferences(
          topicLanguage: 'french',
          menuLanguage: 'french',
          contentLanguage: 'english',
        ),
      );
      expect(TopicLanguageSelectionController.instance.languageCode, 'english');
      expect(MenuLanguageController.instance.languageCode, 'english');
      expect(LanguageSelectionController.instance.languageCode, 'english');
    },
  );

  testWidgets(
    'French Bible selection uses Miracles French metadata without a Harmony locale',
    (tester) async {
      await inReader(tester, route('miracles', 'english'), () async {
        await chooseBible(tester, 'Français');
        expect(
          readerLanguageOptions().map((option) => option.code),
          contains('french'),
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
        applyUserPreferencesToLegacyControllers(
          const UserPreferences(
            contentLanguage: 'french',
            topicLanguage: 'french',
            menuLanguage: 'french',
          ),
        );
        expect(
          TopicLanguageSelectionController.instance.languageCode,
          'french',
        );
        expect(MenuLanguageController.instance.languageCode, 'french');
        expect(LanguageSelectionController.instance.languageCode, 'french');
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
          expect(link.uri!.queryParameters['bibleLanguage'], 'french');
        }
        assertBible(tester, 'french');
        expect(
          find.byKey(const ValueKey('table-language-selector')),
          findsOneWidget,
        );
        expect(
          requests.any((uri) => uri.path == '/topic-localizations/french'),
          isFalse,
        );
      });
    },
  );

  testWidgets(
    'switching tables keeps French Bible and matches available table locales with a fallback notice',
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
        expect(
          find.textContaining('is not available for this table'),
          findsOneWidget,
        );
        expect(current.topics.map((topic) => topic.name), [
          _name('harmony', '10', 'english'),
          _name('harmony', '11', 'english'),
        ]);
        for (final link in links(tester)) {
          expect(link.uri!.queryParameters['dataset'], isNull);
          expect(link.uri!.queryParameters['topicLanguage'], 'english');
          expect(link.uri!.queryParameters['bibleLanguage'], 'french');
          expect(link.uri!.queryParameters['version']?.toUpperCase(), 'LSG');
        }
        assertBible(tester, 'french');
        await tap(tester, find.text(datasetDisplayName('parables', 'english')));
        expect(table(tester).topicLanguage.code, 'english');
        expect(
          table(tester).topics.first.name,
          _name('parables', '10', 'english'),
        );
        assertBible(tester, 'french');
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
          expect(link.uri!.queryParameters['bibleLanguage'], 'french');
        }
        assertBible(tester, 'french');
      });
    },
  );

  for (final dataset in topicDatasetIds) {
    testWidgets(
      '$dataset Bible control changes Arabic subjects, Gospel headers, Types and reference notation together',
      (tester) async {
        await inReader(tester, route(dataset, 'english'), () async {
          expect(find.text('#'), findsOneWidget);
          expect(find.text('10'), findsOneWidget);
          expect(find.text('Table language: '), findsNothing);
          expect(
            find.byKey(const ValueKey('table-language-selector')),
            findsOneWidget,
          );
          expect(find.textContaining('Bible language:'), findsOneWidget);
          await chooseBible(tester, 'العربية');
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
          expect(reference.language, 'arabic');
          expect(reference.version, isNotEmpty);
          expect(reference.topicLanguage, 'arabic');
          expect(reference.reference.book, 'Luke');
          expect(reference.reference.chapter, 1);
          expect(reference.reference.verses, '5');
          assertBible(tester, 'arabic');
          expect(
            requests.where((uri) => uri.path.endsWith('/topics')),
            hasLength(1),
          );
        });
      },
    );
  }

  testWidgets(
    'a missing matching locale uses the first available locale when English is absent',
    (tester) async {
      availableLanguages['miracles'] = ['arabic'];
      await inReader(tester, route('miracles', 'english'), () async {
        expect(table(tester).topicLanguage.code, 'arabic');
        expect(
          table(tester).topics.first.name,
          _name('miracles', '10', 'arabic'),
        );
        expect(find.byType(SnackBar), findsOneWidget);
        expect(
          find.byKey(const ValueKey('table-language-selector')),
          findsOneWidget,
        );
        assertBible(tester);
        final reference = tester
            .widgetList<ReferenceHoverText>(find.byType(ReferenceHoverText))
            .first;
        expect(reference.language, 'english');
        expect(reference.topicLanguage, 'arabic');
      });
    },
  );

  testWidgets(
    'explicit table language keeps KJV, reaches readers and can follow the Bible again',
    (tester) async {
      await inReader(tester, route('parables', 'english'), () async {
        final selector = find.byKey(const ValueKey('table-language-selector'));
        await tap(tester, selector);
        await tap(tester, find.text('العربية').last);
        expect(table(tester).topicLanguage.code, 'arabic');
        expect(
          table(tester).topics.first.name,
          _name('parables', '10', 'arabic'),
        );
        assertBible(tester);
        final readerLinks = links(tester);
        expect(readerLinks, isNotEmpty);
        for (final link in readerLinks) {
          expect(link.uri!.queryParameters['tableLocale'], 'arabic');
          expect(link.uri!.queryParameters['topicLanguage'], 'arabic');
          expect(link.uri!.queryParameters['bibleLanguage'], 'english');
        }
        await tap(tester, find.text(_name('parables', '10', 'arabic')));
        final reading = tester.widget<AuthorComparisonScreen>(
          find.byType(AuthorComparisonScreen),
        );
        expect(reading.topicLanguage, 'arabic');
        expect(reading.languageOption.code, 'english');
        final chapterLink = find.descendant(
          of: find.byType(ReferenceHoverText).first,
          matching: find.byType(BrowserRouteLink),
        );
        await tap(tester, chapterLink);
        final chapterFinder = find.byType(ReferenceViewerPage);
        final chapter = tester.widget<ReferenceViewerPage>(chapterFinder);
        final chapterUri = Uri.parse(
          ModalRoute.of(tester.element(chapterFinder))!.settings.name!,
        );
        expect(chapterUri.queryParameters['tableLocale'], 'arabic');
        expect(chapter.datasetId, 'parables');
        expect(chapter.topicId, '10');
        expect(chapter.topicLanguage, 'arabic');
        expect(chapter.language, 'english');
        expect(chapter.version.toLowerCase(), 'kjv');
        expect(chapter.verses, isNotEmpty);
        expect(
          find.textContaining('english Bible fixture', findRichText: true),
          findsWidgets,
        );
        Navigator.of(tester.element(chapterFinder)).pop();
        await tester.pumpAndSettle();
        expect(find.byType(AuthorComparisonScreen), findsOneWidget);
        expect(
          TopicLanguageSelectionController.instance.languageCode,
          'arabic',
        );
        Navigator.of(tester.element(find.byType(AuthorComparisonScreen))).pop();
        await tester.pumpAndSettle();
        await tap(tester, selector);
        await tap(
          tester,
          find.text(datasetControlLabel('followBible', 'arabic')),
        );
        expect(table(tester).topicLanguage.code, 'english');
        assertBible(tester);
        expect(
          links(tester).every(
            (link) => !link.uri!.queryParameters.containsKey('tableLocale'),
          ),
          isTrue,
        );
        expect(
          requests.where((uri) => uri.path.endsWith('/topics')),
          hasLength(1),
        );
      });
    },
  );

  testWidgets(
    'a mixed English table and Arabic Bible survives a cold table URL',
    (tester) async {
      final initial = Uri.parse(route('parables', 'arabic', grouped: true));
      final mixed = initial.replace(
        path: '/topics',
        queryParameters: {...initial.queryParameters, 'tableLocale': 'english'},
      );
      await inReader(tester, mixed.toString(), () async {
        expect(table(tester).topicLanguage.code, 'english');
        expect(table(tester).groupedByType, isTrue);
        assertBible(tester, 'arabic');
        for (final link in links(tester)) {
          expect(link.uri!.queryParameters['tableLocale'], 'english');
          expect(link.uri!.queryParameters['topicLanguage'], 'english');
          expect(link.uri!.queryParameters['bibleLanguage'], 'arabic');
        }
      });
    },
  );

  testWidgets(
    'refresh repairs an old mixed route using the Bible language and retains grouped filters',
    (tester) async {
      final mixed = Uri.parse(route('parables', 'english', grouped: true))
          .replace(
            queryParameters: {
              ...Uri.parse(
                route('parables', 'english', grouped: true),
              ).queryParameters,
              'topicLanguage': 'arabic',
              'menuLanguage': 'arabic',
            },
          );
      await inReader(tester, mixed.toString(), () async {
        void expectRepaired() {
          expect(table(tester).topicLanguage.code, 'english');
          expect(
            table(tester).topics.first.name,
            _name('parables', '10', 'english'),
          );
          expect(table(tester).groupedByType, isTrue);
          assertBible(tester);
          for (final link in links(tester)) {
            expect(link.uri!.queryParameters['topicLanguage'], 'english');
            expect(link.uri!.queryParameters['bibleLanguage'], 'english');
            expect(link.uri!.queryParameters['view'], 'grouped');
            expect(link.uri!.queryParameters['types'], 'healing');
          }
        }

        expectRepaired();
        await tester.pumpWidget(const SizedBox());
        notifyCatalogChanged();
        await tester.pumpWidget(app(mixed.toString()));
        await tester.pumpAndSettle();
        expectRepaired();
        expect(
          requests.any((uri) => uri.path.endsWith('/localizations/arabic')),
          isFalse,
        );
      });
    },
  );

  testWidgets(
    'a cold French Parables reader link resolves English names before requesting the locale',
    (tester) async {
      final cold = Uri.parse(route('parables', 'french')).replace(
        path: '/topic',
        queryParameters: {
          ...Uri.parse(route('parables', 'french')).queryParameters,
          'topicId': '10',
          'topicNumber': '10',
        },
      );
      await inReader(tester, cold.toString(), () async {
        final detail = tester.widget<AuthorComparisonScreen>(
          find.byType(AuthorComparisonScreen),
        );
        expect(detail.topic.datasetId, 'parables');
        expect(detail.topic.name, _name('parables', '10', 'english'));
        expect(detail.topicLanguage, 'english');
        expect(
          find.textContaining('french Bible fixture', findRichText: true),
          findsWidgets,
        );
        expect(
          requests.any(
            (uri) => uri.path == '/datasets/parables/localizations/french',
          ),
          isFalse,
        );
        expect(
          requests.any(
            (uri) => uri.path == '/datasets/parables/localizations/english',
          ),
          isTrue,
        );
        assertBible(tester, 'french');
      });
    },
  );

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
            find.textContaining('french Bible fixture', findRichText: true),
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
          assertBible(tester, 'french');
          await tester.pumpWidget(const SizedBox());
          notifyCatalogChanged();
          await tester.pumpWidget(app(saved.toString()));
          await tester.pumpAndSettle();
          expect(table(tester).topicLanguage.code, 'french');
          expect(table(tester).topicLanguage.gospelNames[2], 'Luc localisé');
          expect(table(tester).topics.map((topic) => topic.id), ['10', '11']);
          expect(table(tester).groupedByType, isTrue);
          assertBible(tester, 'french');
        },
      );
    },
  );
}
