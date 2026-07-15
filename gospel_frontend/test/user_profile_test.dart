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
      expect(preferences.menuLanguage, 'arabic');
      expect(preferences.preferredVersion, 'Van Dyke-');
      expect(preferences.zoomLevel, maximumProfileZoom);
      expect(preferences.showDiacritics, isTrue);
    });

    test('serializes the complete preference schema', () {
      final map = const UserPreferences(
        menuLanguage: 'arabic',
        contentLanguage: 'english',
        preferredVersion: 'ASV',
        zoomLevel: 1.2,
        interlinearEnabled: true,
        showTopicNamesInChapter: true,
      ).toMap();

      expect(map.keys, {
        'menuLanguage',
        'contentLanguage',
        'preferredVersion',
        'showDiacritics',
        'zoomLevel',
        'interlinearEnabled',
        'showTopicNamesInChapter',
      });
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
    expect(saved?.preferences.preferredVersion, 'Van Dyke-');
  });
}
