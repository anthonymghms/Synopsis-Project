import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gospel_frontend/admin_api_client.dart';
import 'package:gospel_frontend/admin_portal.dart';

class _ContentClient implements AdminClient {
  final posts = <({String path, Map<String, dynamic> body})>[];
  AdminApiException? saveError;
  bool emptySecondVerse = false;
  bool standaloneBible = false;
  int loads = 0;

  @override
  Future<Map<String, dynamic>> getJson(String path) async {
    loads++;
    if (path.startsWith('/admin/content/topics/')) {
      return {
        'revision': 'topics-v1',
        'metadata': {
          'displayName': 'Français',
          'direction': 'ltr',
          'gospels': {
            'Matthew': 'Matthieu',
            'Mark': 'Marc',
            'Luke': 'Luc',
            'John': 'Jean',
          },
        },
        'topics': [
          {
            'id': '1',
            'name': 'Prologue',
            'references': {'John': '1:1-18'},
          },
          {
            'id': '2',
            'name': 'Genealogy',
            'references': {'Matthew': '1:1-17'},
          },
        ],
      };
    }
    if (path.endsWith('/Matthew/1')) {
      return {
        'revision': 'verses-v1',
        'verses': [
          {
            'id': '1',
            'text': 'Original first verse',
            'title': 'Original heading',
          },
          {
            'id': '2',
            'text': emptySecondVerse ? '' : 'Original second verse',
            'title': '',
          },
        ],
      };
    }
    return {
      'revision': 'bible-v1',
      'metadata': {
        'languageDisplayName': 'Ancient Greek',
        'displayName': 'Textus Receptus',
        'description': 'Existing description',
        'direction': 'ltr',
        'containsDiacritics': false,
        'relatedTranslation': '',
        'standalone': standaloneBible,
      },
      'books': [
        {
          'id': 'Matthew',
          'chapters': ['1', '2'],
        },
        {
          'id': 'John',
          'chapters': ['1'],
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    posts.add((
      path: path,
      body: Map<String, dynamic>.from(jsonDecode(jsonEncode(body)) as Map),
    ));
    if (saveError case final error?) throw error;
    return {'saved': true};
  }

  @override
  Future<Map<String, dynamic>> upload(
    String path, {
    required Map<String, String> fields,
    required List<AdminUploadFile> files,
    required String fileField,
  }) => throw UnimplementedError();
}

Future<void> _pumpEditor(
  WidgetTester tester,
  WidgetBuilder editor, {
  Size size = const Size(1200, 1100),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: editor,
            ),
            child: const Text('Open editor'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open editor'));
  await tester.pumpAndSettle();
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Bible metadata editor saves diacritics and its related translation',
    (tester) async {
      final client = _ContentClient();
      await _pumpEditor(
        tester,
        (_) => BibleContentEditor(
          client: client,
          arabic: false,
          language: 'ancientgreek',
          version: 'TR',
          onSaved: () {},
        ),
      );
      await _tap(tester, find.byType(SwitchListTile));
      await tester.ensureVisible(_field('Related translation (optional)'));
      await tester.pumpAndSettle();
      await tester.enterText(
        _field('Related translation (optional)'),
        'TR-without-marks',
      );
      await _tap(tester, find.byKey(const ValueKey('save-content')));
      expect(client.posts.single.body['metadata'], {
        'languageDisplayName': 'Ancient Greek',
        'direction': 'ltr',
        'displayName': 'Textus Receptus',
        'description': 'Existing description',
        'containsDiacritics': true,
        'relatedTranslation': 'TR-without-marks',
      });
    },
  );

  testWidgets(
    'standalone Bible metadata hides language and related-translation fields',
    (tester) async {
      final client = _ContentClient()..standaloneBible = true;
      await _pumpEditor(
        tester,
        (_) => BibleContentEditor(
          client: client,
          arabic: false,
          language: 'translation_abcd',
          version: 'TR',
          onSaved: () {},
        ),
      );
      expect(_field('Language name (native spelling)'), findsNothing);
      expect(_field('Related translation (optional)'), findsNothing);
      expect(
        find.text(
          'Standalone translation — no topics or language association required.',
        ),
        findsOneWidget,
      );
      await tester.enterText(_field('Translation name'), 'Standalone revised');
      await _tap(tester, find.byKey(const ValueKey('save-content')));
      expect(
        (client.posts.single.body['metadata'] as Map)['displayName'],
        'Standalone revised',
      );
    },
  );

  testWidgets(
    'renaming a topic under its original-name filter retains the editor focus',
    (tester) async {
      final client = _ContentClient();
      await _pumpEditor(
        tester,
        (_) => TopicContentEditor(
          client: client,
          arabic: false,
          language: 'french',
          onSaved: () {},
        ),
      );
      await tester.enterText(
        _field('Search by topic number or name'),
        'Prologue',
      );
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('topic-name-1'));
      await tester.enterText(field, 'An entirely different topic name');
      await tester.pumpAndSettle();
      expect(field, findsOneWidget);
      final editable = tester.widget<EditableText>(
        find.descendant(of: field, matching: find.byType(EditableText)),
      );
      expect(editable.focusNode.hasFocus, isTrue);
      expect(editable.controller.text, 'An entirely different topic name');
      expect(find.byKey(const ValueKey('topic-name-2')), findsNothing);
    },
  );

  testWidgets('Arabic topic language settings fit a narrow phone screen', (
    tester,
  ) async {
    final client = _ContentClient();
    await _pumpEditor(
      tester,
      (_) => TopicContentEditor(
        client: client,
        arabic: true,
        language: 'french',
        onSaved: () {},
      ),
      size: const Size(390, 844),
    );
    await _tap(tester, find.text('إعدادات اللغة'));
    expect(
      Directionality.of(
        tester.element(find.byKey(const ValueKey('save-content'))),
      ),
      TextDirection.rtl,
    );
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(_field('John'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await _tap(tester, find.text('إعدادات اللغة'));
    await tester.enterText(
      find.byKey(const ValueKey('topic-name-1')),
      'عنوان منقّح',
    );
    await _tap(tester, find.byKey(const ValueKey('save-content')));
    expect(client.posts.single.body['topics'], [
      {'id': '1', 'name': 'عنوان منقّح'},
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Arabic chapter editing fits a narrow phone screen', (
    tester,
  ) async {
    final client = _ContentClient();
    await _pumpEditor(
      tester,
      (_) => BibleChapterEditor(
        client: client,
        arabic: true,
        language: 'arabic',
        version: 'Van Dyke',
        book: 'Matthew',
        chapter: '1',
        direction: 'rtl',
        onSaved: () {},
      ),
      size: const Size(390, 844),
    );
    expect(tester.takeException(), isNull);
    final verse = find.byKey(const ValueKey('verse-text-1'));
    expect(
      Directionality.of(
        tester.element(find.byKey(const ValueKey('save-content'))),
      ),
      TextDirection.rtl,
    );
    await tester.ensureVisible(verse);
    await tester.enterText(verse, 'نص الآية المنقّح للاختبار');
    await _tap(tester, find.byKey(const ValueKey('save-content')));
    expect(client.posts.single.body['verses'], [
      {
        'id': '1',
        'text': 'نص الآية المنقّح للاختبار',
        'title': 'Original heading',
      },
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'topic search retains edits in hidden rows and saves names with revision',
    (tester) async {
      final client = _ContentClient();
      var saved = 0;
      await _pumpEditor(
        tester,
        (_) => TopicContentEditor(
          client: client,
          arabic: false,
          language: 'french',
          onSaved: () => saved++,
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('topic-name-1')),
        'Revised prologue',
      );
      await tester.enterText(
        _field('Search by topic number or name'),
        'Genealogy',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('topic-name-1')), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('topic-name-2')),
        'Revised genealogy',
      );
      await _tap(tester, find.byKey(const ValueKey('save-content')));
      expect(saved, 1);
      expect(client.posts.single.path, '/admin/content/topics/french');
      expect(client.posts.single.body, {
        'revision': 'topics-v1',
        'metadata': {
          'displayName': 'Français',
          'direction': 'ltr',
          'gospels': {
            'Matthew': 'Matthieu',
            'Mark': 'Marc',
            'Luke': 'Luc',
            'John': 'Jean',
          },
        },
        'topics': [
          {'id': '1', 'name': 'Revised prologue'},
          {'id': '2', 'name': 'Revised genealogy'},
        ],
      });
    },
  );

  testWidgets('conflict retains edited verse and heading for review', (
    tester,
  ) async {
    final client = _ContentClient()
      ..saveError = const AdminApiException(
        'Another administrator changed this content. Reload before saving.',
        code: 'content_conflict',
        status: 409,
      );
    var saved = 0;
    await _pumpEditor(
      tester,
      (_) => BibleChapterEditor(
        client: client,
        arabic: false,
        language: 'ancientgreek',
        version: 'TR',
        book: 'Matthew',
        chapter: '1',
        direction: 'ltr',
        onSaved: () => saved++,
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('verse-text-1')),
      'Ἐν ἀρχῇ',
    );
    await tester.enterText(
      find.byKey(const ValueKey('verse-title-1')),
      'Revised heading',
    );
    await _tap(tester, find.byKey(const ValueKey('save-content')));
    expect(saved, 0);
    expect(
      find.text(
        'Another administrator changed this content. Reload before saving.',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('verse-text-1')))
          .controller!
          .text,
      'Ἐν ἀρχῇ',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('verse-title-1')))
          .controller!
          .text,
      'Revised heading',
    );
    expect(client.loads, 1);
    expect(
      client.posts.single.path,
      '/admin/content/bibles/ancientgreek/TR/Matthew/1',
    );
    expect(client.posts.single.body, {
      'revision': 'verses-v1',
      'verses': [
        {'id': '1', 'text': 'Ἐν ἀρχῇ', 'title': 'Revised heading'},
      ],
    });
  });

  testWidgets('unsaved close can keep editing or discard without saving', (
    tester,
  ) async {
    final client = _ContentClient();
    await _pumpEditor(
      tester,
      (_) => TopicContentEditor(
        client: client,
        arabic: false,
        language: 'french',
        onSaved: () {},
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('topic-name-1')),
      'Unsaved name',
    );
    await _tap(tester, find.byTooltip('Close'));
    expect(find.text('Discard unsaved changes?'), findsOneWidget);
    await _tap(tester, find.text('Keep editing'));
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('topic-name-1')))
          .controller!
          .text,
      'Unsaved name',
    );
    await _tap(tester, find.byTooltip('Close'));
    await _tap(tester, find.text('Discard'));
    expect(find.byType(TopicContentEditor), findsNothing);
    expect(client.posts, isEmpty);
  });

  testWidgets(
    'Bible metadata saves without changing identity or verse content',
    (tester) async {
      final client = _ContentClient();
      await _pumpEditor(
        tester,
        (_) => BibleContentEditor(
          client: client,
          arabic: false,
          language: 'ancientgreek',
          version: 'TR',
          onSaved: () {},
        ),
      );
      await tester.enterText(
        _field('Language name (native spelling)'),
        'Ἑλληνική',
      );
      await tester.enterText(
        _field('Translation name'),
        'Revised Textus Receptus',
      );
      await _tap(tester, find.byKey(const ValueKey('save-content')));
      expect(client.posts.single.path, '/admin/content/bibles/ancientgreek/TR');
      expect(client.posts.single.body, {
        'revision': 'bible-v1',
        'metadata': {
          'languageDisplayName': 'Ἑλληνική',
          'direction': 'ltr',
          'displayName': 'Revised Textus Receptus',
          'description': 'Existing description',
          'containsDiacritics': false,
          'relatedTranslation': '',
        },
      });
    },
  );

  testWidgets(
    'existing empty imported verses do not block editing another verse',
    (tester) async {
      final client = _ContentClient()..emptySecondVerse = true;
      await _pumpEditor(
        tester,
        (_) => BibleChapterEditor(
          client: client,
          arabic: false,
          language: 'ancientgreek',
          version: 'TR',
          book: 'Matthew',
          chapter: '1',
          direction: 'ltr',
          onSaved: () {},
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('verse-text-1')),
        'Corrected first verse',
      );
      await _tap(tester, find.byKey(const ValueKey('save-content')));
      expect(client.posts, hasLength(1));
    },
  );

  testWidgets('topic language settings remain usable on short screens', (
    tester,
  ) async {
    final client = _ContentClient();
    await _pumpEditor(
      tester,
      (_) => TopicContentEditor(
        client: client,
        arabic: false,
        language: 'french',
        onSaved: () {},
      ),
      size: const Size(500, 700),
    );
    await _tap(tester, find.text('Language settings'));
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(_field('John'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('discard and reload restores the displayed text direction', (
    tester,
  ) async {
    final client = _ContentClient();
    await _pumpEditor(
      tester,
      (_) => TopicContentEditor(
        client: client,
        arabic: false,
        language: 'french',
        onSaved: () {},
      ),
    );
    await _tap(tester, find.text('Language settings'));
    await _tap(tester, find.byKey(const ValueKey('topic-direction-ltr')));
    await _tap(tester, find.text('Right to left').last);
    expect(find.byKey(const ValueKey('topic-direction-rtl')), findsOneWidget);
    await _tap(tester, find.text('Reload'));
    await _tap(tester, find.text('Discard'));
    expect(find.byKey(const ValueKey('topic-direction-ltr')), findsOneWidget);
    expect(find.byKey(const ValueKey('topic-direction-rtl')), findsNothing);
    expect(client.posts, isEmpty);
  });

  testWidgets(
    'reverting chapter edits does not submit an invalid empty change set',
    (tester) async {
      final client = _ContentClient();
      await _pumpEditor(
        tester,
        (_) => BibleChapterEditor(
          client: client,
          arabic: false,
          language: 'ancientgreek',
          version: 'TR',
          book: 'Matthew',
          chapter: '1',
          direction: 'ltr',
          onSaved: () {},
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('verse-text-1')),
        'Temporary edit',
      );
      await tester.enterText(
        find.byKey(const ValueKey('verse-text-1')),
        'Original first verse',
      );
      await _tap(tester, find.byKey(const ValueKey('save-content')));
      expect(client.posts, isEmpty);
      expect(find.text('Unsaved changes'), findsNothing);
    },
  );
}
