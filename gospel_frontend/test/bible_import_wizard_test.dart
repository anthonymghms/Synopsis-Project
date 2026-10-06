import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gospel_frontend/admin_api_client.dart';
import 'package:gospel_frontend/admin_file_picker.dart';
import 'package:gospel_frontend/admin_portal.dart';

class _BibleClient implements AdminClient {
  _BibleClient({this.emptyCatalog = false, this.catalogFuture});
  final bool emptyCatalog;
  final Future<Map<String, dynamic>>? catalogFuture;
  final getPaths = <String>[];
  final posts = <({String path, Map<String, dynamic> body})>[];
  final uploads = <Map<String, String>>[];

  @override
  Future<Map<String, dynamic>> getJson(String path) async {
    getPaths.add(path);
    if (path == '/admin/languages') {
      if (catalogFuture != null) return catalogFuture!;
      return {
        'bibleLanguages': emptyCatalog
            ? []
            : [
                {'id': 'english', 'name': 'English', 'direction': 'ltr'},
                {'id': 'arabic', 'name': 'Arabic', 'direction': 'rtl'},
                {
                  'id': 'translation_abc',
                  'name': 'Standalone',
                  'standalone': true,
                },
              ],
        'topicLanguages': emptyCatalog
            ? []
            : [
                {'id': 'french', 'name': 'French', 'direction': 'ltr'},
              ],
      };
    }
    return {
      'import': {
        'status': 'completed',
        'stage': 'Completed',
        'recordsProcessed': 1,
      },
    };
  }

  @override
  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    posts.add((path: path, body: Map<String, dynamic>.from(body)));
    return {'status': 'queued'};
  }

  @override
  Future<Map<String, dynamic>> upload(
    String path, {
    required Map<String, String> fields,
    required List<AdminUploadFile> files,
    required String fileField,
  }) async {
    expect(path, '/admin/bibles/validate');
    expect(fileField, 'files');
    expect(files.single.name, 'MAT.usfm');
    uploads.add(Map<String, String>.from(fields));
    return {
      'importId': '0123456789abcdef0123456789abcdef',
      'valid': true,
      'collision': false,
      'stats': {'books': 1, 'chapters': 1, 'verses': 1},
      'preview': [
        {
          'book': 'Matthew',
          'chapter': '1',
          'verse': '1',
          'text': 'Example text',
        },
      ],
      'errors': <dynamic>[],
      'warnings': <dynamic>[],
    };
  }
}

class _BiblePicker implements AdminFilePicker {
  @override
  Future<List<AdminUploadFile>?> pickFiles({
    required List<String> allowedExtensions,
    bool allowMultiple = false,
  }) async {
    expect(allowedExtensions, ['usfm']);
    expect(allowMultiple, isTrue);
    return [
      AdminUploadFile(
        name: 'MAT.usfm',
        bytes: Uint8List.fromList(
          utf8.encode('\\id MAT\n\\c 1\n\\v 1 Example text\n'),
        ),
      ),
    ];
  }
}

Future<void> _pump(
  WidgetTester tester,
  _BibleClient client, {
  bool arabic = false,
  Size size = const Size(1200, 1100),
  VoidCallback? onCompleted,
  bool waitForCatalog = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: BibleImportWizard(
          client: client,
          arabic: arabic,
          filePicker: _BiblePicker(),
          onCompleted: onCompleted ?? () {},
        ),
      ),
    ),
  );
  if (waitForCatalog) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.pumpAndSettle();
  if (finder.evaluate().isEmpty) {
    await tester.drag(find.byType(ListView).first, const Offset(0, 2200));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 20,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _reveal(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, Finder finder, String text) async {
  await _reveal(tester, finder);
  await tester.enterText(finder, text);
  await tester.pumpAndSettle();
}

Future<void> _mode(WidgetTester tester, String current, String label) async {
  await _tap(tester, find.byKey(ValueKey('bible-language-mode-$current')));
  await _tap(tester, find.text(label).last);
}

Future<void> _validate(WidgetTester tester, {bool arabic = false}) async {
  await _tap(
    tester,
    find.text(arabic ? 'اختر ملفات USFM' : 'Select USFM files'),
  );
  await _tap(tester, find.byKey(const ValueKey('validate-bible-upload')));
}

void main() {
  testWidgets(
    'a late empty language catalog does not override standalone choice',
    (tester) async {
      final catalog = Completer<Map<String, dynamic>>();
      final client = _BibleClient(catalogFuture: catalog.future);
      await _pump(tester, client, waitForCatalog: false);
      await tester.tap(
        find.byKey(const ValueKey('bible-language-mode-existing')),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Standalone translation').last);
      await tester.pumpAndSettle();
      catalog.complete({'bibleLanguages': [], 'topicLanguages': []});
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('bible-language-mode-standalone')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('language-code')), findsNothing);
    },
  );

  testWidgets(
    'existing language chooses its native name and imports without topic upload',
    (tester) async {
      final client = _BibleClient();
      var completed = 0;
      await _pump(tester, client, onCompleted: () => completed++);
      await _tap(
        tester,
        find.byKey(const ValueKey('existing-bible-language-english')),
      );
      expect(find.text('Français'), findsOneWidget);
      expect(find.text('Standalone'), findsNothing);
      await _tap(tester, find.text('العربية').last);
      await _enter(
        tester,
        find.byKey(const ValueKey('translation-name')),
        'Van Dyke',
      );
      await _validate(tester);
      expect(client.uploads.single['languageMode'], 'existing');
      expect(client.uploads.single['language'], 'arabic');
      expect(client.uploads.single['languageDisplayName'], 'العربية');
      expect(client.uploads.single['direction'], 'rtl');
      await _tap(tester, find.byKey(const ValueKey('import-bible-upload')));
      await _tap(tester, find.text('Import'));
      expect(client.posts.single.path, '/admin/bibles/import');
      expect(completed, 1);
      expect(client.getPaths.where((path) => path.contains('topics')), isEmpty);
    },
  );

  testWidgets(
    'new language submits native language metadata independently of topics',
    (tester) async {
      final client = _BibleClient();
      await _pump(tester, client);
      await _mode(tester, 'existing', 'New language');
      await _enter(
        tester,
        find.byKey(const ValueKey('language-code')),
        'ancientgreek',
      );
      await _enter(
        tester,
        find.byKey(const ValueKey('language-display-name')),
        'Ἑλληνική',
      );
      await _enter(
        tester,
        find.byKey(const ValueKey('translation-name')),
        'Textus Receptus',
      );
      await _validate(tester);
      expect(client.uploads.single['languageMode'], 'new');
      expect(client.uploads.single['language'], 'ancientgreek');
      expect(client.uploads.single['languageDisplayName'], 'Ἑλληνική');
      expect(client.uploads.single['versionId'], 'textus_receptus');
      expect(client.uploads.single['versionDisplayName'], 'Textus Receptus');
    },
  );

  testWidgets('standalone uploads require no language or topic catalog', (
    tester,
  ) async {
    final client = _BibleClient(emptyCatalog: true);
    await _pump(tester, client);
    await _mode(tester, 'new', 'Standalone translation');
    expect(find.byKey(const ValueKey('language-code')), findsNothing);
    expect(find.byKey(const ValueKey('language-display-name')), findsNothing);
    await _enter(
      tester,
      find.byKey(const ValueKey('translation-name')),
      'Ancient Source',
    );
    await _validate(tester);
    expect(client.uploads.single['languageMode'], 'standalone');
    expect(client.uploads.single['language'], isEmpty);
    expect(client.uploads.single['languageDisplayName'], isEmpty);
    expect(client.uploads.single['relatedTranslation'], isEmpty);
    expect(client.uploads.single['translationName'], 'Ancient Source');
  });

  testWidgets('suggested metadata follows typing until explicitly customized', (
    tester,
  ) async {
    final client = _BibleClient();
    await _pump(tester, client);
    final translation = find.byKey(const ValueKey('translation-name'));
    await _enter(tester, translation, 'Text');
    await _enter(tester, translation, 'Textus Receptus');
    await _reveal(tester, _field('Short name / identifier'));
    expect(
      tester
          .widget<TextField>(_field('Short name / identifier'))
          .controller!
          .text,
      'textus_receptus',
    );
    expect(
      tester.widget<TextField>(_field('Display name')).controller!.text,
      'Textus Receptus',
    );
    await _enter(tester, _field('Short name / identifier'), 'TR');
    await _enter(tester, _field('Display name'), 'My Greek Bible');
    await _enter(tester, translation, 'Textus Receptus 1894');
    await _validate(tester);
    expect(client.uploads.single['versionId'], 'TR');
    expect(client.uploads.single['versionDisplayName'], 'My Greek Bible');
    expect(client.uploads.single['translationName'], 'Textus Receptus 1894');
  });

  testWidgets(
    'editing metadata or language mode invalidates the validated upload',
    (tester) async {
      final client = _BibleClient();
      await _pump(tester, client);
      await _enter(
        tester,
        find.byKey(const ValueKey('translation-name')),
        'KJV Revised',
      );
      await _validate(tester);
      await _reveal(tester, find.byKey(const ValueKey('import-bible-upload')));
      expect(find.byKey(const ValueKey('import-bible-upload')), findsOneWidget);
      await _enter(
        tester,
        _field('Description (optional)'),
        'Changed after validation',
      );
      expect(find.byKey(const ValueKey('import-bible-upload')), findsNothing);
      await _tap(tester, find.byKey(const ValueKey('validate-bible-upload')));
      expect(client.uploads.last['description'], 'Changed after validation');
      await _mode(tester, 'existing', 'Standalone translation');
      expect(find.byKey(const ValueKey('import-bible-upload')), findsNothing);
      expect(client.posts, isEmpty);
    },
  );

  testWidgets('Arabic new-language workflow fits phone width and uses RTL', (
    tester,
  ) async {
    final client = _BibleClient();
    await _pump(tester, client, arabic: true, size: const Size(390, 844));
    await _mode(tester, 'existing', 'لغة جديدة');
    expect(tester.takeException(), isNull);
    expect(
      Directionality.of(
        tester.element(find.byKey(const ValueKey('bible-language-mode-new'))),
      ),
      TextDirection.rtl,
    );
    await _enter(
      tester,
      find.byKey(const ValueKey('language-code')),
      'ancientgreek',
    );
    await _enter(
      tester,
      find.byKey(const ValueKey('language-display-name')),
      'Ἑλληνική',
    );
    await _enter(
      tester,
      find.byKey(const ValueKey('translation-name')),
      'Textus Receptus',
    );
    await _validate(tester, arabic: true);
    expect(client.uploads.single['languageMode'], 'new');
    expect(tester.takeException(), isNull);
  });
}
