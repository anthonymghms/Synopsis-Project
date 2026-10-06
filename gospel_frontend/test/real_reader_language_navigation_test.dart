import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
// Firebase's own platform mock keeps these reader tests offline.
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gospel_frontend/account_access.dart';
import 'package:gospel_frontend/catalog_events.dart';
import 'package:gospel_frontend/main.dart';
import 'package:gospel_frontend/reader_language_route.dart';
import 'package:gospel_frontend/topic_language_catalog.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final greek = kBaseLanguageOptions.first.copyWith(
    code: 'ancientgreek',
    label: 'Ἑλληνική',
    apiLanguage: 'ancientgreek',
    apiVersion: 'TR',
    versions: const [BibleVersion(id: 'TR', label: 'Textus Receptus')],
  );
  late AccountAccessController originalAccess;
  late MockClient client;
  late List<Uri> requests;

  setUpAll(() async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // Exercise the reader's cached catalog fallback without a live Firebase
    // connection; the preloaded catalog below includes the imported Greek Bible.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
          'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi.queryGet',
          (_) async => const StandardMessageCodec().encodeMessage([
            'unavailable',
            'Offline reader test',
            null,
          ]),
        );
    originalAccess = accountAccess;
    accountAccess = AccountAccessController(
      tokenProvider: () async => 'reader-test-token',
    );
    accountAccess.beginSession('reader');
    requests = [];
    client = MockClient((request) async {
      requests.add(request.url);
      expect(request.headers['Authorization'], 'Bearer reader-test-token');
      final path = request.url.path;
      Object response;
      if (path == '/account/access') {
        response = {
          'uid': 'reader',
          'role': 'subscribed',
          'canRead': true,
          'accessStatus': 'active',
        };
      } else if (path == '/topic-languages') {
        response = {
          'languages': [
            {'id': 'english', 'direction': 'ltr'},
            {'id': 'arabic', 'direction': 'rtl'},
          ],
        };
      } else if (path == '/harmony/topics') {
        response = {
          'topics': [
            {
              'id': '3',
              'name': 'Birth of John the Baptist Foretold',
              'references': [
                {'book': 'Luke', 'chapter': 1, 'verses': '5-25'},
              ],
            },
          ],
        };
      } else if (path.startsWith('/topic-localizations/')) {
        response = {
          'topics': [
            {
              'id': '3',
              'name': path.endsWith('/arabic')
                  ? 'قصة ولادة يوحنا المعمدان'
                  : 'Birth of John the Baptist Foretold',
            },
          ],
        };
      } else if (path == '/get_chapter' || path == '/get_verse') {
        final language = request.url.queryParameters['language'];
        response = [
          {
            'verse': 5,
            'text': language == 'arabic'
                ? 'نص لوقا العربي'
                : language == 'ancientgreek'
                ? 'Λόγος δοκιμής'
                : 'English Luke passage',
          },
        ];
      } else {
        fail('Unexpected reader request: ${request.url}');
      }
      return http.Response(
        jsonEncode(response),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    notifyCatalogChanged();
    await loadPrimaryLanguageCatalogs(
      bibleLoader: () async => [...kBaseLanguageOptions, greek],
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

  // Only routing and external data are replaced. The toolbar, selection
  // handlers, persistence, chapter/topic loaders and readers are production UI.
  Widget app(String initialRoute) => MenuLanguageScope(
    notifier: MenuLanguageController.instance.notifier,
    child: MaterialApp(
      navigatorObservers: [readerLanguageRouteObserver],
      initialRoute: initialRoute,
      onGenerateRoute: (settings) {
        final uri = Uri.parse(settings.name!);
        final languages = resolveReaderLanguages(uri);
        final query = uri.queryParameters;
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => ReaderLanguageRoute(
            onActivated: () => activateReaderLanguages(languages),
            child: uri.path == '/topic'
                ? TopicDetailScreen(
                    languageOption: languages.bible,
                    topicLanguage: languages.topic,
                    apiVersion: query['version'] ?? languages.bible.apiVersion,
                    topicId: query['topicId'] ?? '3',
                    topicNumber: query['topicNumber'] ?? '3',
                    comparisonState: query['comparisons'] ?? '',
                  )
                : ReferenceViewerPage(
                    displayBook: query['bookDisplay'] ?? 'Luke',
                    bookId: query['book'] ?? 'Luke',
                    chapter: int.parse(query['chapter'] ?? '1'),
                    verses: query['verses'] ?? '5-25',
                    language: languages.bible.apiLanguage,
                    version: query['version'] ?? languages.bible.apiVersion,
                    topicLanguage: languages.topic,
                    topicName: query['topic'] ?? '',
                    source: 'harmony',
                    topicId: query['topicId'] ?? '3',
                    topicNumber: query['topicNumber'] ?? '3',
                    comparisonState: query['comparisons'] ?? '',
                    gospel: 'Luke',
                  ),
          ),
        );
      },
    ),
  );

  final comparisonState = base64Url.encode(
    utf8.encode(
      jsonEncode([
        {
          'language': 'ancientgreek',
          'version': 'TR',
          'withDiacritics': false,
          'scopeMode': 'chapter',
          'scopeStartVerse': 1,
          'scopeEndVerse': 25,
        },
      ]),
    ),
  );

  String route(
    String path, {
    String menu = 'english',
    bool comparison = false,
  }) => Uri(
    path: path,
    queryParameters: {
      'menuLanguage': menu,
      'topicLanguage': menu,
      'bibleLanguage': 'english',
      'language': 'english',
      'version': 'kjv',
      'book': 'Luke',
      'bookDisplay': 'Luke',
      'chapter': '1',
      'verses': '5-25',
      'topicId': '3',
      'topicNumber': '3',
      'source': 'harmony',
      if (comparison) 'comparisons': comparisonState,
    },
  ).toString();

  Future<void> chooseLanguage(WidgetTester tester, String nativeName) async {
    final toolbar = tester.widget<AppToolbar>(find.byType(AppToolbar));
    final ui = MenuLanguageController.instance.languageCode == 'arabic'
        ? 'اللغة'
        : 'Language';
    final label = toolbar.language.code == 'arabic' ? 'العربية' : 'English';
    await tester.tap(find.byTooltip('$ui: $label'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(nativeName).last);
    await tester.pumpAndSettle();
    if (nativeName == 'العربية' &&
        find.text('البستاني فاندايك').evaluate().isNotEmpty) {
      await tester.tap(find.text('البستاني فاندايك').last);
      await tester.pumpAndSettle();
    }
    if (nativeName == 'English' && find.text('KJV').evaluate().isNotEmpty) {
      await tester.tap(find.text('KJV').last);
      await tester.pumpAndSettle();
    }
  }

  void expectLanguages(
    WidgetTester tester,
    String path,
    String bible,
    String ui,
  ) {
    final reader = path == '/topic'
        ? find.byType(TopicDetailScreen)
        : find.byType(ReferenceViewerPage);
    final uri = Uri.parse(
      ModalRoute.of(tester.element(reader))!.settings.name!,
    );
    expect(uri.queryParameters['bibleLanguage'], bible);
    expect(uri.queryParameters['topicLanguage'], ui);
    expect(uri.queryParameters['menuLanguage'], ui);
    expect(uri.queryParameters['topicId'], '3');
    expect(uri.queryParameters['topicNumber'], '3');
    if (path == '/reference') {
      expect(uri.queryParameters['book'], 'Luke');
      expect(uri.queryParameters['chapter'], '1');
      expect(uri.queryParameters['verses'], '5-25');
    }
    expect(LanguageSelectionController.instance.languageCode, bible);
    expect(MenuLanguageController.instance.languageCode, ui);
    expect(TopicLanguageSelectionController.instance.languageCode, ui);
    expect(
      find.text(
        ui == 'arabic' ? 'العودة إلى الجدول الرئيسي' : 'Back to main table',
      ),
      findsOneWidget,
    );
    if (path == '/topic') {
      expect(
        find.textContaining(
          ui == 'arabic'
              ? 'قصة ولادة يوحنا المعمدان'
              : 'Birth of John the Baptist Foretold',
        ),
        findsOneWidget,
      );
    } else {
      expect(
        find.text(
          ui == 'arabic'
              ? 'إنجيل لوقا — الفصل ١'
              : 'Gospel of Luke — Chapter 1',
        ),
        findsWidgets,
      );
    }
    expect(tester.takeException(), isNull);
  }

  void expectComparison(WidgetTester tester, String path) {
    final reader = path == '/topic'
        ? find.byType(TopicDetailScreen)
        : find.byType(ReferenceViewerPage);
    final uri = Uri.parse(
      ModalRoute.of(tester.element(reader))!.settings.name!,
    );
    final raw =
        jsonDecode(
              utf8.decode(
                base64Url.decode(uri.queryParameters['comparisons']!),
              ),
            )
            as List;
    expect(raw.single['language'], 'ancientgreek');
    expect(raw.single['version'], 'TR');
    expect(
      find.textContaining('Λόγος δοκιμής', findRichText: true),
      findsWidgets,
    );
  }

  for (final path in ['/reference', '/topic']) {
    testWidgets(
      '$path version-only change preserves chosen interface, topics and comparison',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1600, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await http.runWithClient(() async {
          try {
            await accountAccess.refresh(force: true);
            await tester.pumpWidget(
              app(route(path, menu: 'arabic', comparison: true)),
            );
            await tester.pumpAndSettle();
            await tester.tap(find.byTooltip('الترجمة: Kjv'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('ASV').last);
            await tester.pumpAndSettle();
            expectLanguages(tester, path, 'english', 'arabic');
            expect(
              tester.widget<AppToolbar>(find.byType(AppToolbar)).version,
              'ASV',
            );
            expectComparison(tester, path);
          } finally {
            await tester.pumpWidget(const SizedBox());
            accountAccess.clear();
          }
        }, () => client);
      },
    );

    testWidgets(
      '$path real toolbar switches Arabic and English throughout the page',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1600, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await http.runWithClient(() async {
          try {
            await accountAccess.refresh(force: true);
            await tester.pumpWidget(app(route(path, comparison: true)));
            await tester.pumpAndSettle();
            await chooseLanguage(tester, 'العربية');
            expectLanguages(tester, path, 'arabic', 'arabic');
            expectComparison(tester, path);
            expect(
              find.textContaining('نص لوقا العربي', findRichText: true),
              findsWidgets,
            );
            await chooseLanguage(tester, 'English');
            expectLanguages(tester, path, 'english', 'english');
            expectComparison(tester, path);
            expect(
              find.textContaining('English Luke passage', findRichText: true),
              findsWidgets,
            );
          } finally {
            await tester.pumpWidget(const SizedBox());
            accountAccess.clear();
          }
        }, () => client);
      },
    );

    testWidgets(
      '$path selecting its current Bible language repairs a mixed-language link',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1600, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await http.runWithClient(() async {
          try {
            await accountAccess.refresh(force: true);
            await tester.pumpWidget(app(route(path, menu: 'arabic')));
            await tester.pumpAndSettle();
            await chooseLanguage(tester, 'English');
            expectLanguages(tester, path, 'english', 'english');
          } finally {
            await tester.pumpWidget(const SizedBox());
            accountAccess.clear();
          }
        }, () => client);
      },
    );

    testWidgets(
      '$path Bible-only Greek keeps Arabic interface and topic localization',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1600, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await http.runWithClient(() async {
          try {
            await accountAccess.refresh(force: true);
            await tester.pumpWidget(app(route(path, menu: 'arabic')));
            await tester.pumpAndSettle();
            await chooseLanguage(tester, 'Ἑλληνική');
            expectLanguages(tester, path, 'ancientgreek', 'arabic');
            expect(
              find.textContaining('Λόγος δοκιμής', findRichText: true),
              findsWidgets,
            );
            expect(
              requests.any(
                (uri) => uri.path == '/topic-localizations/ancientgreek',
              ),
              isFalse,
            );
          } finally {
            await tester.pumpWidget(const SizedBox());
            accountAccess.clear();
          }
        }, () => client);
      },
    );
  }
}
