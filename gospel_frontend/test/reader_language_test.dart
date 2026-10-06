import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gospel_frontend/main.dart';
import 'package:gospel_frontend/account_access.dart';
import 'package:gospel_frontend/catalog_events.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:gospel_frontend/topic_language_catalog.dart';

void main() {
  final english = kBaseLanguageOptions.first;
  final greek = english.copyWith(
    code: 'ancientgreek',
    label: 'Ancient Greek',
    apiLanguage: 'ancientgreek',
    apiVersion: 'TR',
    versions: const [BibleVersion(id: 'TR', label: 'Textus Receptus')],
  );

  setUp(() async {
    await loadPrimaryLanguageCatalogs(
      bibleLoader: () async => [...kBaseLanguageOptions, greek],
      topicLoader: () async => bundledTopicLanguages,
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

  test(
    'Bible-only languages are selectable in readers but not topic tables',
    () {
      expect(
        readerLanguageOptions().map((option) => option.code),
        contains('ancientgreek'),
      );
      expect(
        primaryLanguageOptionsFor(
          bibleLanguages: readerLanguageOptions(),
          topicLanguages: bundledTopicLanguages,
        ).map((option) => option.code),
        isNot(contains('ancientgreek')),
      );
    },
  );

  test('passage and topic URLs preserve independent language choices', () {
    for (final path in ['/reference', '/topic']) {
      final uri = Uri(
        path: path,
        queryParameters: {
          ...readerLanguageQueryParameters(bible: greek),
          'version': 'TR',
          'book': 'John',
          'chapter': '1',
        },
      );
      expect(uri.queryParameters['bibleLanguage'], 'ancientgreek');
      expect(uri.queryParameters['topicLanguage'], 'arabic');
      expect(uri.queryParameters['menuLanguage'], 'arabic');
      final resolved = resolveReaderLanguages(uri);
      expect(resolved.bible.code, 'ancientgreek');
      expect(resolved.bible.apiVersion, 'TR');
      expect(resolved.topic, 'arabic');
      expect(resolved.menu, 'arabic');
    }
  });

  test('Bible-only legacy deep links retain the current topic language', () {
    final resolved = resolveReaderLanguages(
      Uri.parse('/reference?language=ancientgreek&version=TR'),
    );
    expect(resolved.bible.code, 'ancientgreek');
    expect(resolved.topic, 'arabic');
    expect(resolved.menu, 'arabic');
  });

  testWidgets('reader toolbar can select an imported Bible-only translation', (
    tester,
  ) async {
    PrimaryLanguageController.instance.select('english');
    String? selectedLanguage;
    String? selectedVersion;
    await tester.pumpWidget(
      MaterialApp(
        home: MenuLanguageScope(
          notifier: MenuLanguageController.instance.notifier,
          child: Scaffold(
            body: AppToolbar(
              language: english,
              version: 'kjv',
              languages: readerLanguageOptions(),
              onLanguageChanged: (_) {},
              onVersionChanged: (_) {},
              onTranslationChanged: (language, version) {
                selectedLanguage = language.code;
                selectedVersion = version;
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Language: English'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ἑλληνική').last);
    await tester.pumpAndSettle();
    expect(selectedLanguage, 'ancientgreek');
    expect(selectedVersion, 'TR');
    expect(MenuLanguageController.instance.languageCode, 'english');
    expect(TopicLanguageSelectionController.instance.languageCode, 'english');
    expect(tester.takeException(), isNull);
  });
  testWidgets('admin edits invalidate loaded verse previews and API cache', (
    tester,
  ) async {
    final previousAccess = accountAccess;
    accountAccess = AccountAccessController(
      tokenProvider: () async => 'test-token',
    );
    accountAccess.beginSession('reader');
    addTearDown(() {
      accountAccess.dispose();
      accountAccess = previousAccess;
    });
    var verseText = 'Original verse text';
    var requests = 0;
    final client = MockClient((request) async {
      expect(request.headers['Authorization'], 'Bearer test-token');
      if (request.url.path == '/account/access') {
        return http.Response(
          jsonEncode({
            'uid': 'reader',
            'role': 'subscribed',
            'canRead': true,
            'accessStatus': 'active',
          }),
          200,
        );
      }
      requests++;
      return http.Response(
        jsonEncode([
          {'verse': 1, 'text': verseText},
        ]),
        200,
      );
    });
    await http.runWithClient(() async {
      await accountAccess.refresh(force: true);
      await tester.pumpWidget(
        MaterialApp(
          home: MenuLanguageScope(
            notifier: ValueNotifier<String>('english'),
            child: const Scaffold(
              body: Center(
                child: ReferenceHoverText(
                  reference: GospelReference(
                    book: 'John',
                    chapter: 1,
                    verses: '1',
                  ),
                  displayBook: 'John',
                  language: 'english',
                  version: 'kjv',
                ),
              ),
            ),
          ),
        ),
      );
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: const Offset(0, 0));
      await gesture.moveTo(tester.getCenter(find.byType(ReferenceHoverText)));
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pump();
      expect(
        find.textContaining('Original verse text', findRichText: true),
        findsOneWidget,
      );
      expect(requests, 1);
      await gesture.moveTo(const Offset(0, 0));
      await tester.pump(const Duration(milliseconds: 200));
      verseText = 'Corrected verse text';
      notifyCatalogChanged();
      await tester.pump();
      await gesture.moveTo(tester.getCenter(find.byType(ReferenceHoverText)));
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pump();
      expect(
        find.textContaining('Corrected verse text', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('Original verse text', findRichText: true),
        findsNothing,
      );
      expect(requests, 2);
      await gesture.moveTo(const Offset(0, 0));
      await tester.pump(const Duration(milliseconds: 200));
      accountAccess.handleDeniedResponse(
        http.Response(
          jsonEncode({
            'error': {'code': 'guest_access_expired', 'message': 'Expired'},
          }),
          403,
        ),
      );
      await gesture.moveTo(tester.getCenter(find.byType(ReferenceHoverText)));
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pump();
      expect(
        find.textContaining('Corrected verse text', findRichText: true),
        findsNothing,
      );
      expect(
        requests,
        2,
        reason:
            'Expired access must not use cached text or issue a content request.',
      );
      await gesture.moveTo(const Offset(0, 0));
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.removePointer();
      await tester.pumpWidget(const SizedBox());
      accountAccess.clear();
    }, () => client);
  });
}
