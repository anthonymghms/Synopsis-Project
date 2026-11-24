import 'dart:async';
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
  Completer<void>? canonicalRelease;
  Completer<void>? firstRangeRelease;
  var passageDelay = Duration.zero;
  var sameGospelRangeCount = 1;

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
    canonicalRelease = null;
    firstRangeRelease = null;
    passageDelay = Duration.zero;
    sameGospelRangeCount = 1;
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
        await canonicalRelease?.future;
        response = {
          'topics': [
            {
              'id': '3',
              'name': 'Birth of John the Baptist Foretold',
              'references': [
                for (
                  var chapter = 1;
                  chapter <= sameGospelRangeCount;
                  chapter++
                )
                  {'book': 'Luke', 'chapter': chapter, 'verses': '5-25'},
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
        if (path == '/get_verse' &&
            request.url.queryParameters['chapter'] == '1') {
          await firstRangeRelease?.future;
        }
        if (passageDelay != Duration.zero) {
          await Future<void>.delayed(passageDelay);
        }
        final language = request.url.queryParameters['language'];
        final chapter = request.url.queryParameters['chapter'];
        final suffix = sameGospelRangeCount > 1 ? ' (chapter $chapter)' : '';
        response = [
          {
            'verse': 5,
            'text': language == 'arabic'
                ? 'نص لوقا العربي'
                : language == 'ancientgreek'
                ? 'Λόγος δοκιμής$suffix'
                : 'English Luke passage$suffix',
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
    if (canonicalRelease != null && !canonicalRelease!.isCompleted) {
      canonicalRelease!.complete();
    }
    if (firstRangeRelease != null && !firstRangeRelease!.isCompleted) {
      firstRangeRelease!.complete();
    }
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
        final query = uri.queryParameters;
        if (uri.path == '/') {
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => const SizedBox(),
          );
        }
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => DatasetReaderLanguageRoute(
            uri: uri,
            builder: (languages) => uri.path == '/topic'
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
    String bible = 'english',
    bool comparison = false,
  }) => Uri(
    path: path,
    queryParameters: {
      'menuLanguage': menu,
      'topicLanguage': menu,
      'bibleLanguage': bible,
      'language': bible,
      'version': bible == 'arabic' ? arabicVersionWithoutDiacritics : 'kjv',
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

  for (final path in ['/topic', '/reference']) {
    testWidgets(
      '$path loads the main text and bookmarked comparison concurrently',
      (tester) async {
        final isTopic = path == '/topic';
        sameGospelRangeCount = 4;
        passageDelay = const Duration(milliseconds: 120);
        final endpoint = isTopic ? '/get_verse' : '/get_chapter';
        int requested(String language) => requests
            .where(
              (uri) =>
                  uri.path == endpoint &&
                  uri.queryParameters['language'] == language,
            )
            .length;
        await http.runWithClient(() async {
          try {
            await accountAccess.refresh(force: true);
            await tester.pumpWidget(app(route(path, comparison: true)));
            await tester.pump();
            await tester.pump();
            expect(requested('english'), isTopic ? 4 : 1);
            expect(requested('ancientgreek'), isTopic ? 2 : 1);

            await tester.pump(passageDelay);
            await tester.pump();
            final mainChapter = isTopic ? 4 : 1;
            expect(
              find.textContaining(
                'English Luke passage (chapter $mainChapter)',
                findRichText: true,
              ),
              findsWidgets,
            );
            expect(
              find.textContaining(
                'Λόγος δοκιμής (chapter 1)',
                findRichText: true,
              ),
              findsWidgets,
            );
            if (isTopic) {
              // At most two secondary ranges run alongside four main ranges.
              expect(requested('ancientgreek'), 4);
              await tester.pump(passageDelay);
              await tester.pump();
              expect(
                find.textContaining(
                  'Λόγος δοκιμής (chapter 4)',
                  findRichText: true,
                ),
                findsWidgets,
              );
            } else {
              expect(
                requests.where((uri) => uri.path == '/harmony/topics'),
                isEmpty,
              );
              expect(
                requests.where(
                  (uri) => uri.path.startsWith('/topic-localizations/'),
                ),
                isEmpty,
              );
              await tester.tap(find.text('Show topic names'));
              await tester.pumpAndSettle();
              expect(
                requests.where((uri) => uri.path == '/harmony/topics'),
                hasLength(1),
              );
              expect(find.byType(ChapterTopicHeading), findsWidgets);
            }
            final requestsBeforeInterlinear = requests.length;
            await tester.tap(find.text('Interlinear View'));
            await tester.pumpAndSettle();
            expect(find.byType(InterlinearVerseGroup), findsWidgets);
            expect(requests.length, requestsBeforeInterlinear);
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox());
            accountAccess.clear();
          }
        }, () => client);
      },
    );
  }

  testWidgets(
    'topic ranges keep source order when later chapters finish first',
    (tester) async {
      sameGospelRangeCount = 4;
      firstRangeRelease = Completer<void>();
      await http.runWithClient(() async {
        try {
          await accountAccess.refresh(force: true);
          await tester.pumpWidget(app(route('/topic')));
          await tester.pump();
          await tester.pump();
          expect(
            requests.where((uri) => uri.path == '/get_verse'),
            hasLength(4),
          );
          firstRangeRelease!.complete();
          await tester.pumpAndSettle();
          final positions = [
            for (var chapter = 1; chapter <= 4; chapter++)
              tester
                  .getTopLeft(
                    find
                        .textContaining(
                          'English Luke passage (chapter $chapter)',
                          findRichText: true,
                        )
                        .first,
                  )
                  .dy,
          ];
          expect(positions, orderedEquals(positions.toList()..sort()));
          expect(positions.toSet(), hasLength(4));
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
          accountAccess.clear();
        }
      }, () => client);
    },
  );

  testWidgets('topic localization starts while canonical topics are pending', (
    tester,
  ) async {
    canonicalRelease = Completer<void>();
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await http.runWithClient(() async {
      try {
        await accountAccess.refresh(force: true);
        await tester.pumpWidget(app(route('/topic', bible: 'arabic')));
        await tester.pump();
        expect(
          requests.map((uri) => uri.path),
          containsAll(['/harmony/topics', '/topic-localizations/arabic']),
        );
        expect(canonicalRelease!.isCompleted, isFalse);
        canonicalRelease!.complete();
        await tester.pumpAndSettle();
        expect(
          find.textContaining('قصة ولادة يوحنا المعمدان', findRichText: true),
          findsWidgets,
        );
        expect(tester.takeException(), isNull);
      } finally {
        if (!canonicalRelease!.isCompleted) canonicalRelease!.complete();
        await tester.pumpWidget(const SizedBox());
        accountAccess.clear();
      }
    }, () => client);
  });

  for (final path in ['/reference', '/topic']) {
    testWidgets(
      '$path phone reader keeps passage and comparison controls accessible',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(360, 640);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await http.runWithClient(() async {
          try {
            await accountAccess.refresh(force: true);
            await tester.pumpWidget(app(route(path, comparison: true)));
            await tester.pumpAndSettle();
            expect(
              find.textContaining('English Luke passage', findRichText: true),
              findsWidgets,
            );
            expect(find.byType(AppToolbar), findsNothing);
            await tester.tap(find.text('Reading tools'));
            await tester.pumpAndSettle();
            final toggle = find.text('Interlinear View');
            await tester.ensureVisible(toggle);
            await tester.tap(toggle);
            await tester.pumpAndSettle();
            await tester.tap(find.text('Reading tools'));
            await tester.pumpAndSettle();
            expect(find.byType(InterlinearVerseGroup), findsWidgets);
            expectComparison(tester, path);
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox());
            accountAccess.clear();
          }
        }, () => client);
      },
    );

    testWidgets(
      '$path old mixed link follows Bible language through version change and keeps comparison',
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
            expect(MenuLanguageController.instance.languageCode, 'english');
            expect(
              TopicLanguageSelectionController.instance.languageCode,
              'english',
            );
            await tester.tap(find.byTooltip('Translation: Kjv'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('ASV').last);
            await tester.pumpAndSettle();
            expectLanguages(tester, path, 'english', 'english');
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
      '$path real toolbar switches Bible, subjects and menus together while keeping comparison',
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
      '$path selecting its current Bible language normalizes old mixed table and menu parameters',
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
      '$path Bible-only Greek falls back from Arabic to English subjects and menus',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1600, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await http.runWithClient(() async {
          try {
            await accountAccess.refresh(force: true);
            await tester.pumpWidget(
              app(route(path, menu: 'arabic', bible: 'arabic')),
            );
            await tester.pumpAndSettle();
            await chooseLanguage(tester, 'Ἑλληνική');
            expectLanguages(tester, path, 'ancientgreek', 'english');
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
