import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:gospel_frontend/main.dart';
import 'package:gospel_frontend/profile_editor.dart';
import 'package:gospel_frontend/topic_language_catalog.dart';

void main() {
  tearDown(() async {
    registerInterfaceTranslations('french', {});
    await loadPrimaryLanguageCatalogs(
      bibleLoader: () async => kBaseLanguageOptions,
      topicLoader: () async => bundledTopicLanguages,
    );
    PrimaryLanguageController.instance.select('english');
  });

  test('French bundles reader menus, settings and Gospel names offline', () {
    final labels = LocalizedUiLabels.forLanguage('french');
    expect(labels.backToMainTable, 'Retour au tableau principal');
    expect(labels.addTranslation, 'Ajouter une traduction');
    expect(labels.previousChapter, 'Chapitre précédent');
    expect(labels.previousTopic, 'Sujet précédent');
    expect(labels.gospelHeaders, ['Matthieu', 'Marc', 'Luc', 'Jean']);
    expect(
      ProfileEditorLabels.forLanguage('french').saveChanges,
      'Enregistrer les modifications',
    );
    expect(LocalizedUiLabels.forLanguage('fr').nextChapter, 'Chapitre suivant');
    expect(LocalizedUiLabels.forLanguage('unknown').settings, 'Settings');
  });

  test('partial uploaded translations use language defaults then English', () {
    final labels = LocalizedUiLabels.forLanguage('french', {
      'nextTopic': 'Prochain sujet',
    });
    expect(labels.nextTopic, 'Prochain sujet');
    expect(labels.previousTopic, 'Sujet précédent');
    final italian = LocalizedUiLabels.forLanguage('italian', {
      'nextTopic': 'Successivo',
    });
    expect(italian.nextTopic, 'Successivo');
    expect(italian.previousTopic, 'Previous topic');
  });

  test('French metadata replaces unedited English Gospel defaults', () {
    final language = TopicLanguageOption.fromJson({
      'id': 'french',
      'gospels': {
        'Matthew': 'Matthew',
        'Mark': 'Mark',
        'Luke': 'Luc',
        'John': 'Jean',
      },
    });
    expect(language.gospelNames, ['Matthieu', 'Marc', 'Luc', 'Jean']);
    expect(language.subjectsLabel, 'Sujets');
    final custom = TopicLanguageOption.fromJson({
      'id': 'french',
      'gospels': {'Mark': 'Saint Marc'},
    });
    expect(custom.gospelNames[1], 'Saint Marc');
  });

  test(
    'catalog refresh replaces uploaded overrides, including settings labels',
    () async {
      var overrides = <String, String>{
        'nextTopic': 'Prochain sujet',
        'profile.profile': 'Mon profil',
      };
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'languages': [
              {'id': 'french', 'interfaceTranslations': overrides},
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      final catalog = TopicLanguageCatalog(client: client);
      await catalog.load();
      expect(
        LocalizedUiLabels.forLanguage('french').nextTopic,
        'Prochain sujet',
      );
      expect(ProfileEditorLabels.forLanguage('french').profile, 'Mon profil');
      overrides = {};
      await catalog.load();
      expect(
        LocalizedUiLabels.forLanguage('french').nextTopic,
        'Sujet suivant',
      );
      expect(ProfileEditorLabels.forLanguage('french').profile, 'Profil');
    },
  );

  testWidgets('French chapter title and tooltips switch back to English', (
    tester,
  ) async {
    final french = kBaseLanguageOptions.first.copyWith(
      code: 'french',
      label: 'Français',
      apiLanguage: 'french',
      versions: const [BibleVersion(id: 'lsg', label: 'LSG')],
    );
    await loadPrimaryLanguageCatalogs(
      bibleLoader: () async => [...kBaseLanguageOptions, french],
      topicLoader: () async => [
        ...bundledTopicLanguages,
        TopicLanguageOption.fromJson({
          'id': 'french',
          'topicCount': 1,
          'canonicalTopicCount': 1,
          'complete': true,
        }),
      ],
    );
    PrimaryLanguageController.instance.select('french');
    await tester.pumpWidget(
      MaterialApp(
        home: MenuLanguageScope(
          notifier: MenuLanguageController.instance.notifier,
          child: Builder(
            builder: (context) {
              final language = MenuLanguageScope.of(context);
              return Scaffold(
                body: ChapterNav(
                  bookTitle: language.ui.formatGospelTitle(
                    language.gospelHeaders[1],
                  ),
                  chapter: 1,
                  previousBookUri: Uri(
                    path: '/reference',
                    queryParameters: {'book': 'Matthew'},
                  ),
                  previousChapterUri: null,
                  nextChapterUri: Uri(
                    path: '/reference',
                    queryParameters: {'book': 'Mark', 'chapter': '2'},
                  ),
                  nextBookUri: Uri(
                    path: '/reference',
                    queryParameters: {'book': 'Luke'},
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    expect(find.text('Évangile selon Marc — Chapitre 1'), findsOneWidget);
    expect(find.byTooltip('Chapitre suivant'), findsOneWidget);
    expect(find.byTooltip('Évangile suivant'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is IconButton &&
                  widget.tooltip == 'Chapitre précédent',
            ),
          )
          .onPressed,
      isNull,
    );
    PrimaryLanguageController.instance.select('english');
    await tester.pump();
    expect(find.text('Gospel of Mark — Chapter 1'), findsOneWidget);
    expect(find.byTooltip('Next chapter'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('heading templates allow translated word order', () {
    final labels = LocalizedUiLabels.forLanguage('french', {
      'gospelTitle': 'Évangile selon {book}',
      'chapterTitle': 'Chapitre {number} de {gospel}',
    });
    expect(
      labels.formatChapterTitle(labels.formatGospelTitle('Marc'), '12'),
      'Chapitre 12 de Évangile selon Marc',
    );
  });
}
