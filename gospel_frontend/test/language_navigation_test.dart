import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gospel_frontend/main.dart';
import 'package:gospel_frontend/reader_language_route.dart';
import 'package:gospel_frontend/topic_language_catalog.dart';

void main() {
  final english = kBaseLanguageOptions.first;
  final greek = english.copyWith(
    code: 'ancientgreek',
    label: 'Ἑλληνική',
    apiLanguage: 'ancientgreek',
    apiVersion: 'TR',
    versions: const [BibleVersion(id: 'TR', label: 'Textus Receptus')],
  );

  setUp(() async {
    await loadPrimaryLanguageCatalogs(
      bibleLoader: () async => [...kBaseLanguageOptions, greek],
      topicLoader: () async => [
        TopicLanguageOption.fromJson({
          'id': 'english',
          'interfaceTranslations': {'exportCsv': 'Download spreadsheet'},
        }),
        bundledTopicLanguages.last,
      ],
    );
    PrimaryLanguageController.instance.select('arabic');
  });

  tearDown(() async {
    await loadPrimaryLanguageCatalogs(
      bibleLoader: () async => kBaseLanguageOptions,
      topicLoader: () async => bundledTopicLanguages,
    );
    PrimaryLanguageController.instance.select('english');
  });

  Widget app({required GlobalKey<NavigatorState> navigatorKey}) {
    return MenuLanguageScope(
      notifier: MenuLanguageController.instance.notifier,
      child: MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [readerLanguageRouteObserver],
        initialRoute:
            '/?menuLanguage=arabic&topicLanguage=arabic&bibleLanguage=arabic',
        onGenerateRoute: (settings) {
          final uri = Uri.parse(settings.name!);
          final selection = resolveReaderLanguages(uri);
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (context) => ReaderLanguageRoute(
              onActivated: () => activateReaderLanguages(selection),
              child: Builder(
                builder: (context) {
                  final menu = MenuLanguageScope.of(context);
                  return Scaffold(
                    body: Column(
                      children: [
                        AppToolbar(
                          language: selection.bible,
                          version:
                              uri.queryParameters['version'] ??
                              selection.bible.apiVersion,
                          languages: readerLanguageOptions(),
                          onLanguageChanged: (_) {},
                          onVersionChanged: (_) {},
                          onTranslationChanged: (language, version) {
                            final next = readerLanguagesForSelection(language);
                            activateReaderLanguages(next);
                            Navigator.of(context).pushReplacementNamed(
                              Uri(
                                path: uri.path,
                                queryParameters: {
                                  ...readerLanguageQueryParameters(
                                    bible: language,
                                    menuLanguage: next.menu,
                                    topicLanguage: next.topic,
                                  ),
                                  'version': version,
                                },
                              ).toString(),
                            );
                          },
                        ),
                        Text(menu.ui.text('exportCsv')),
                        Text(menu.ui.filter),
                        Text(menu.ui.resetTable),
                        Text(menu.ui.settings),
                        if (uri.path == '/')
                          TextButton(
                            key: const Key('open-chapter'),
                            onPressed: () => Navigator.of(context).pushNamed(
                              Uri(
                                path: '/reference',
                                queryParameters: {
                                  ...readerLanguageQueryParameters(
                                    bible: selection.bible,
                                  ),
                                  'book': 'Matthew',
                                  'chapter': '1',
                                  'version':
                                      uri.queryParameters['version'] ??
                                      selection.bible.apiVersion,
                                },
                              ).toString(),
                            ),
                            child: Text(menu.ui.clickToReadInChapter),
                          )
                        else
                          ChapterNav(
                            bookTitle: menu.ui.formatGospelTitle(
                              menu.gospelHeaders.first,
                            ),
                            chapter: 1,
                            previousBookUri: null,
                            previousChapterUri: null,
                            nextChapterUri: null,
                            nextBookUri: null,
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  testWidgets(
    'Arabic to English updates menus, sheet labels and chapter links',
    (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(app(navigatorKey: navigatorKey));
      await tester.pumpAndSettle();
      expect(find.text('الإعدادات'), findsOneWidget);

      await tester.tap(find.byTooltip('اللغة: العربية'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('English').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('KJV').last);
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Download spreadsheet'), findsOneWidget);
      expect(find.text('Filter'), findsOneWidget);
      expect(find.byTooltip('Language: English'), findsOneWidget);
      expect(find.text('الإعدادات'), findsNothing);
      expect(MenuLanguageController.instance.languageCode, 'english');

      await tester.tap(find.byKey(const Key('open-chapter')));
      await tester.pumpAndSettle();
      final route = ModalRoute.of(tester.element(find.byType(ChapterNav)))!;
      expect(
        Uri.parse(route.settings.name!).queryParameters['menuLanguage'],
        'english',
      );
      expect(find.text('Gospel of Matthew — Chapter 1'), findsOneWidget);
      expect(find.byTooltip('Next chapter'), findsOneWidget);
      expect(find.text('إنجيل متى — الفصل ١'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Greek Bible keeps English interface and chapter navigation', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(app(navigatorKey: navigatorKey));
    await tester.pumpAndSettle();
    navigatorKey.currentState!.pushNamed(
      '/reference?menuLanguage=english&topicLanguage=english&bibleLanguage=english&version=kjv',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Language: English'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ἑλληνική').last);
    await tester.pumpAndSettle();

    expect(LanguageSelectionController.instance.languageCode, 'ancientgreek');
    expect(MenuLanguageController.instance.languageCode, 'english');
    expect(TopicLanguageSelectionController.instance.languageCode, 'english');
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Gospel of Matthew — Chapter 1'), findsOneWidget);
    expect(find.text('Download spreadsheet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
