import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gospel_frontend/preference_language_catalog.dart';
import 'package:gospel_frontend/profile_editor.dart';
import 'package:gospel_frontend/user_profile.dart';

void main() {
  group('UserPreferences', () {
    test('uses safe defaults for existing users with missing fields', () {
      final preferences = UserPreferences.fromMap(null);

      expect(preferences.menuLanguage, 'english');
      expect(preferences.topicLanguage, 'english');
      expect(preferences.contentLanguage, 'english');
      expect(preferences.preferredVersion, 'kjv');
      expect(preferences.zoomLevel, 1.0);
      expect(preferences.showDiacritics, isFalse);
      expect(preferences.interlinearEnabled, isFalse);
      expect(preferences.showTopicNamesInChapter, isFalse);
    });

    test('reads legacy preference aliases and clamps zoom', () {
      final preferences = UserPreferences.fromMap(
        null,
        legacy: {
          'language': 'arabic',
          'menuLanguage': 'arabic',
          'version': 'Van Dyke-',
          'zoomLevel': 9,
          'showDiacritics': true,
        },
      );

      expect(preferences.contentLanguage, 'arabic');
      expect(preferences.topicLanguage, 'arabic');
      expect(preferences.menuLanguage, 'arabic');
      expect(preferences.preferredVersion, 'Van Dyke-');
      expect(preferences.zoomLevel, maximumProfileZoom);
      expect(preferences.showDiacritics, isTrue);
    });

    test('normalizes legacy mixed language fields to Bible content', () {
      final preferences = UserPreferences.fromMap({
        'topicLanguage': 'english',
        'bibleLanguage': 'arabic',
        'bibleVersion': 'Van Dyke-',
        'contentLanguage': 'english',
        'preferredVersion': 'kjv',
      });

      expect(preferences.topicLanguage, 'arabic');
      expect(preferences.menuLanguage, 'arabic');
      expect(preferences.bibleLanguage, 'arabic');
      expect(preferences.bibleVersion, 'Van Dyke-');
    });

    test('normalizes a conflicting topic language to the primary language', () {
      final preferences = UserPreferences.fromMap({
        'topicLanguage': 'english',
        'menuLanguage': 'arabic',
        'bibleLanguage': 'arabic',
      });

      expect(preferences.topicLanguage, 'arabic');
      expect(preferences.menuLanguage, 'arabic');
      expect(preferences.bibleLanguage, 'arabic');
      expect(preferences.toMap()['menuLanguage'], 'arabic');
      expect(preferences.toMap()['topicLanguage'], 'arabic');
    });

    test('empty canonical fields fall through to legacy language aliases', () {
      final preferences = UserPreferences.fromMap(
        {'bibleLanguage': '   ', 'bibleVersion': ''},
        legacy: {'language': 'arabic', 'version': 'Van Dyke-'},
      );

      expect(preferences.contentLanguage, 'arabic');
      expect(preferences.topicLanguage, 'arabic');
      expect(preferences.menuLanguage, 'arabic');
      expect(preferences.preferredVersion, 'Van Dyke-');
    });

    test('copyWith keeps every primary language alias synchronized', () {
      final preferences = const UserPreferences(
        contentLanguage: 'english',
      ).copyWith(menuLanguage: 'arabic');

      expect(preferences.contentLanguage, 'arabic');
      expect(preferences.topicLanguage, 'arabic');
      expect(preferences.menuLanguage, 'arabic');
    });

    test('serializes the complete preference schema', () {
      final map = const UserPreferences(
        menuLanguage: 'arabic',
        topicLanguage: 'arabic',
        contentLanguage: 'english',
        preferredVersion: 'ASV',
        zoomLevel: 1.2,
        interlinearEnabled: true,
        showTopicNamesInChapter: true,
      ).toMap();

      expect(map.keys, {
        'menuLanguage',
        'topicLanguage',
        'bibleLanguage',
        'bibleVersion',
        'contentLanguage',
        'preferredVersion',
        'showDiacritics',
        'zoomLevel',
        'interlinearEnabled',
        'showTopicNamesInChapter',
      });
      expect(map['menuLanguage'], 'english');
      expect(map['topicLanguage'], 'english');
      expect(map['bibleLanguage'], 'english');
    });
  });

  group('Preference language catalog', () {
    test('rejects a translation from a different content language', () {
      final english = PreferenceLanguageCatalog.resolve(
        bundledPreferenceLanguages,
        'english',
      );
      final arabic = PreferenceLanguageCatalog.resolve(
        bundledPreferenceLanguages,
        'arabic',
      );

      expect(english.supportsVersion('kjv'), isTrue);
      expect(english.supportsVersion('Van Dyke-'), isFalse);
      expect(arabic.supportsVersion('Van Dyke-'), isTrue);
      expect(arabic.supportsVersion('kjv'), isFalse);
      expect(arabic.sanitizeVersion('kjv'), 'Van Dyke-');
    });

    test('primary preferences exclude comparison-only languages', () {
      const french = PreferenceLanguageOption(
        code: 'french',
        label: 'Français',
        direction: TextDirection.ltr,
        defaultVersion: 'lsg',
        versions: <PreferenceVersionOption>[
          PreferenceVersionOption(id: 'lsg', label: 'LSG'),
        ],
      );

      final primary = primaryPreferenceLanguageOptions(
        <PreferenceLanguageOption>[...bundledPreferenceLanguages, french],
      );

      expect(primary.map((option) => option.code), <String>[
        'english',
        'arabic',
      ]);
    });
  });

  testWidgets('Arabic profile editor is RTL and validates required names', (
    tester,
  ) async {
    UserProfile? saved;
    const profile = UserProfile(
      firstName: '',
      lastName: '',
      displayName: '',
      email: 'reader@example.com',
      preferences: UserPreferences(
        menuLanguage: 'arabic',
        topicLanguage: 'arabic',
        contentLanguage: 'arabic',
        preferredVersion: 'Van Dyke-',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProfileEditor(
              initialProfile: profile,
              setupMode: true,
              onSave: (value) async {
                saved = value;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('الملف الشخصي'), findsOneWidget);
    expect(find.text('اللغة'), findsOneWidget);
    expect(find.text('لغة القوائم'), findsNothing);
    final editorDirection = tester.widget<Directionality>(
      find
          .descendant(
            of: find.byType(ProfileEditor),
            matching: find.byType(Directionality),
          )
          .first,
    );
    expect(editorDirection.textDirection, TextDirection.rtl);

    await tester.ensureVisible(find.byKey(const Key('profile-save')));
    await tester.tap(find.byKey(const Key('profile-save')));
    await tester.pump();
    expect(find.text('هذا الحقل مطلوب.'), findsNWidgets(2));
    expect(find.text('اختر ترجمة متاحة.'), findsOneWidget);
    expect(saved, isNull);

    await tester.enterText(
      find.byKey(const Key('profile-first-name')),
      'جورجيو',
    );
    await tester.enterText(find.byKey(const Key('profile-last-name')), 'مراد');
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('profile-version-arabic-')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('profile-version-arabic-')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('البستاني فاندايك').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('profile-save')));
    await tester.tap(find.byKey(const Key('profile-save')));
    await tester.pumpAndSettle();

    expect(saved?.profileCompleted, isTrue);
    expect(saved?.preferences.contentLanguage, 'arabic');
    expect(saved?.preferences.topicLanguage, 'arabic');
    expect(saved?.preferences.menuLanguage, 'arabic');
    expect(saved?.preferences.preferredVersion, 'Van Dyke-');
  });

  testWidgets(
    'changing the profile language relocalizes and saves one locale',
    (tester) async {
      UserProfile? saved;
      final previews = <String>[];
      const profile = UserProfile(
        firstName: 'جورجيو',
        lastName: 'مراد',
        displayName: '',
        email: 'reader@example.com',
        profileCompleted: true,
        preferences: UserPreferences(
          contentLanguage: 'arabic',
          preferredVersion: 'Van Dyke-',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ProfileEditor(
                initialProfile: profile,
                onMenuLanguagePreview: previews.add,
                onSave: (value) async => saved = value,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final languageField = find.byKey(
        const ValueKey<String>('profile-content-language-arabic'),
      );
      await tester.ensureVisible(languageField);
      await tester.pumpAndSettle();
      await tester.tap(languageField);
      await tester.pumpAndSettle();
      await tester.tap(find.text('الإنجليزية').last);
      await tester.pumpAndSettle();

      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('Language'), findsOneWidget);
      final editorDirection = tester.widget<Directionality>(
        find
            .descendant(
              of: find.byType(ProfileEditor),
              matching: find.byType(Directionality),
            )
            .first,
      );
      expect(editorDirection.textDirection, TextDirection.ltr);
      expect(previews.last, 'english');

      await tester.ensureVisible(find.byKey(const Key('profile-save')));
      await tester.tap(find.byKey(const Key('profile-save')));
      await tester.pumpAndSettle();

      expect(saved?.preferences.contentLanguage, 'english');
      expect(saved?.preferences.topicLanguage, 'english');
      expect(saved?.preferences.menuLanguage, 'english');
      expect(saved?.preferences.preferredVersion, 'kjv');
    },
  );
}
