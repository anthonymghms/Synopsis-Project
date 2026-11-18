import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gospel_frontend/admin_api_client.dart';
import 'package:gospel_frontend/admin_file_picker.dart';
import 'package:gospel_frontend/admin_portal.dart';

class _Client implements AdminClient {
  _Client({
    this.valid = true,
    this.replaces = false,
    this.failure,
    this.metadata,
  });
  final bool valid, replaces;
  final String? failure;
  final Map<String, dynamic>? metadata;
  final gets = <String>[];
  final posts = <({String path, Map<String, dynamic> body})>[];
  final uploads =
      <
        ({
          String path,
          Map<String, String> fields,
          List<AdminUploadFile> files,
          String fileField,
        })
      >[];
  @override
  Future<Map<String, dynamic>> getJson(String path) async {
    gets.add(path);
    if (path == '/admin/overview') return {'counts': {}, 'recentImports': []};
    final uri = Uri.parse(path);
    expect(uri.path, '/admin/table-languages/template');
    return {
      'filename':
          '${uri.queryParameters['datasetId']}-${uri.queryParameters['language']}.csv',
      'csv':
          '\ufeffItemId,SourceName,Translation,TypeId,TypeTranslation\r\n10,Fixture,,figure-of-speech,\r\n',
      'revision': 'fixture-r1',
      if (metadata != null) 'languageMetadata': metadata,
    };
  }

  @override
  Future<Map<String, dynamic>> upload(
    String path, {
    required Map<String, String> fields,
    required List<AdminUploadFile> files,
    required String fileField,
  }) async {
    uploads.add((
      path: path,
      fields: Map.of(fields),
      files: files,
      fileField: fileField,
    ));
    return {
      'importId': 'staged-language',
      'datasetId': fields['datasetId'],
      'language': fields['language'],
      'filename': files.single.name,
      'valid': valid,
      'replacesExisting': replaces,
      'revision': 'fixture-r1',
      'sourceChecksum': 'fixture-checksum',
      'encoding': 'utf-8-sig',
      'stats': {'items': 1, 'translations': 1, 'types': 1},
      'errors': valid
          ? []
          : [
              {'message': 'Missing translation for ItemId 10', 'row': 2},
            ],
      'warnings': [],
      'preview': [
        {
          'id': '10',
          'sourceName': 'Fixture subject',
          'translation': 'Sujet traduit',
          'typeId': 'figure-of-speech',
          'typeTranslation': 'Figure de style',
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    posts.add((path: path, body: Map.of(body)));
    if (failure != null) throw AdminApiException(failure!);
    return {'status': 'completed', 'revisionId': 'fixture-r2'};
  }
}

class _Picker implements AdminFilePicker {
  _Picker({this.empty = false});
  final bool empty;
  @override
  Future<List<AdminUploadFile>?> pickFiles({
    required List<String> allowedExtensions,
    bool allowMultiple = false,
  }) async {
    expect(allowedExtensions, ['csv']);
    expect(allowMultiple, isFalse);
    return [
      AdminUploadFile(
        name: 'translations.csv',
        bytes: Uint8List.fromList(
          empty
              ? []
              : utf8.encode(
                  'ItemId,SourceName,Translation\n10,Fixture,Sujet traduit\n',
                ),
        ),
      ),
    ];
  }
}

Future<void> _pump(
  WidgetTester t,
  _Client c, {
  bool arabic = false,
  Size size = const Size(1100, 1000),
  VoidCallback? completed,
  Future<void> Function(String, String)? download,
  AdminFilePicker? picker,
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: TableLanguageImportWizard(
          client: c,
          arabic: arabic,
          onCompleted: completed ?? () {},
          filePicker: picker ?? _Picker(),
          csvDownloader: download ?? (_, _) async {},
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Finder _key(String k) => find.byKey(ValueKey(k));
Future<void> _visible(WidgetTester t, Finder f, {bool up = false}) async {
  if (f.evaluate().isEmpty) {
    await t.scrollUntilVisible(
      f,
      up ? -300 : 300,
      scrollable: find
          .descendant(
            of: find.byType(TableLanguageImportWizard),
            matching: find.byType(Scrollable),
          )
          .first,
    );
  }
  await t.ensureVisible(f);
  await t.pumpAndSettle();
}

Future<void> _tap(WidgetTester t, String k, {bool up = false}) async {
  await _visible(t, _key(k), up: up);
  await t.tap(_key(k));
  await t.pumpAndSettle();
}

Future<void> _choose(
  WidgetTester t,
  String k,
  String text, {
  bool up = false,
}) async {
  await _tap(t, k, up: up);
  await t.tap(find.text(text).last);
  await t.pumpAndSettle();
}

Future<void> _validate(WidgetTester t) async {
  await _tap(t, 'select-table-language-file');
  await _tap(t, 'validate-table-language');
}

void main() {
  for (final e in {
    'harmony': 'Harmony / All Topics',
    'miracles': 'Miracles',
    'parables': 'Parables',
  }.entries) {
    testWidgets(
      '${e.key} imports independent French headings and stable-ID translations',
      (t) async {
        final c = _Client();
        await _pump(t, c);
        await _choose(t, 'table-language-dataset', e.value);
        await _choose(t, 'table-language-preset', 'Français');
        await _validate(t);
        final u = c.uploads.single;
        expect(u.path, '/admin/table-languages/validate');
        expect(u.fileField, 'file');
        expect(u.fields['datasetId'], e.key);
        expect(u.fields['language'], 'french');
        expect(u.fields['displayName'], 'Français');
        expect(u.fields['direction'], 'ltr');
        expect(u.fields['subjectsLabel'], 'Sujets');
        expect(jsonDecode(u.fields['gospels']!), {
          'Matthew': 'Matthieu',
          'Mark': 'Marc',
          'Luke': 'Luc',
          'John': 'Jean',
        });
        expect(
          utf8.decode(u.files.single.bytes),
          contains('10,Fixture,Sujet traduit'),
        );
        await _visible(t, _key('publish-table-language'));
        expect(find.text('10 · Sujet traduit'), findsOneWidget);
        expect(
          find.textContaining('figure-of-speech: Figure de style'),
          findsOneWidget,
        );
        expect(
          c.gets,
          isEmpty,
          reason: 'No Harmony/Bible language prerequisite',
        );
        expect(c.posts, isEmpty);
      },
    );
  }
  testWidgets('template selects target and loads existing metadata', (t) async {
    final c = _Client(
      metadata: {
        'label': 'Français personnalisé',
        'subjectsLabel': 'Thèmes',
        'direction': 'ltr',
        'gospels': {
          'Matthew': 'Évangile de Matthieu',
          'Mark': 'Marc',
          'Luke': 'Luc',
          'John': 'Jean',
        },
      },
    );
    final downloads = <(String, String)>[];
    await _pump(
      t,
      c,
      download: (csv, name) async {
        downloads.add((csv, name));
      },
    );
    await _choose(t, 'table-language-dataset', 'Parables');
    await _choose(t, 'table-language-preset', 'Français');
    await _tap(t, 'download-table-language-template');
    expect(
      c.gets.single,
      '/admin/table-languages/template?datasetId=parables&language=french',
    );
    expect(
      downloads.single.$1,
      startsWith('\ufeffItemId,SourceName,Translation,TypeId,TypeTranslation'),
    );
    expect(downloads.single.$2, 'parables-french.csv');
    await _validate(t);
    expect(c.uploads.single.fields['displayName'], 'Français personnalisé');
    expect(c.uploads.single.fields['subjectsLabel'], 'Thèmes');
    expect(
      jsonDecode(c.uploads.single.fields['gospels']!)['Matthew'],
      'Évangile de Matthieu',
    );
  });
  testWidgets('replacement needs checkbox and explicit target confirmation', (
    t,
  ) async {
    final c = _Client(replaces: true);
    var completed = 0;
    await _pump(t, c, completed: () => completed++);
    await _choose(t, 'table-language-dataset', 'Parables');
    await _choose(t, 'table-language-preset', 'Français');
    await _validate(t);
    await _visible(t, _key('publish-table-language'));
    expect(
      t.widget<FilledButton>(_key('publish-table-language')).onPressed,
      isNull,
    );
    await _tap(t, 'replace-table-language');
    await _tap(t, 'publish-table-language');
    expect(c.posts, isEmpty);
    expect(
      find.textContaining('Français (french) for Parables'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Canonical references and other languages are preserved.',
      ),
      findsOneWidget,
    );
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(c.posts, isEmpty);
    await _tap(t, 'publish-table-language');
    await _tap(t, 'confirm-publish-table-language');
    expect(c.posts.single.path, '/admin/table-languages/publish');
    expect(c.posts.single.body, {
      'datasetId': 'parables',
      'language': 'french',
      'importId': 'staged-language',
      'confirm': true,
      'replace': true,
    });
    expect(completed, 1);
    expect(
      t.widget<FilledButton>(_key('publish-table-language')).onPressed,
      isNull,
    );
  });
  testWidgets('blocking validation prevents publishing', (t) async {
    final c = _Client(valid: false);
    await _pump(t, c);
    await _validate(t);
    await _visible(t, _key('publish-table-language'));
    expect(find.text('Validation failed'), findsOneWidget);
    expect(
      find.textContaining('Missing translation for ItemId 10'),
      findsOneWidget,
    );
    expect(
      t.widget<FilledButton>(_key('publish-table-language')).onPressed,
      isNull,
    );
    expect(c.posts, isEmpty);
  });
  testWidgets('metadata and target changes invalidate preview', (t) async {
    final c = _Client();
    await _pump(t, c);
    await _validate(t);
    await _visible(t, _key('table-language-subjects'), up: true);
    await t.enterText(_key('table-language-subjects'), 'Titles');
    await t.pumpAndSettle();
    expect(_key('publish-table-language'), findsNothing);
    await _tap(t, 'validate-table-language');
    expect(c.uploads.last.fields['subjectsLabel'], 'Titles');
    await _choose(t, 'table-language-dataset', 'Miracles', up: true);
    await _visible(t, _key('select-table-language-file'));
    expect(_key('publish-table-language'), findsNothing);
    expect(
      t.widget<FilledButton>(_key('validate-table-language')).onPressed,
      isNull,
    );
    expect(c.posts, isEmpty);
  });
  testWidgets('stale revision failure discards preview', (t) async {
    final c = _Client(failure: 'Table revision changed');
    await _pump(t, c);
    await _validate(t);
    await _tap(t, 'publish-table-language');
    await _tap(t, 'confirm-publish-table-language');
    expect(_key('publish-table-language'), findsNothing);
    expect(find.textContaining('Table revision changed'), findsOneWidget);
    expect(
      find.textContaining('Validate the current template again'),
      findsOneWidget,
    );
  });
  testWidgets('custom language supports native headings independently', (
    t,
  ) async {
    final c = _Client();
    await _pump(t, c);
    await _choose(t, 'table-language-preset', 'Other language');
    for (final e in {
      'code': 'swahili',
      'name': 'Kiswahili',
      'subjects': 'Mada',
      'Matthew': 'Mathayo',
      'Mark': 'Marko',
      'Luke': 'Luka',
      'John': 'Yohana',
    }.entries) {
      final f = _key('table-language-${e.key}');
      await _visible(t, f);
      await t.enterText(f, e.value);
    }
    await _validate(t);
    expect(c.uploads.single.fields['language'], 'swahili');
    expect(c.uploads.single.fields['displayName'], 'Kiswahili');
    expect(jsonDecode(c.uploads.single.fields['gospels']!)['John'], 'Yohana');
  });
  testWidgets('Arabic phone controls remain usable without overflow', (
    t,
  ) async {
    final c = _Client();
    await _pump(t, c, arabic: true, size: const Size(390, 844));
    await _choose(t, 'table-language-dataset', 'الأمثال');
    await _choose(t, 'table-language-preset', 'العربية');
    await _validate(t);
    await _visible(t, _key('publish-table-language'));
    expect(c.uploads.single.fields['direction'], 'rtl');
    expect(c.uploads.single.fields['language'], 'arabic');
    expect(jsonDecode(c.uploads.single.fields['gospels']!)['Matthew'], 'متى');
    expect(t.takeException(), isNull);
  });
  testWidgets('empty upload is rejected before validation', (t) async {
    final c = _Client();
    await _pump(t, c, picker: _Picker(empty: true));
    await _tap(t, 'select-table-language-file');
    expect(find.text('The selected CSV file is empty.'), findsOneWidget);
    expect(c.uploads, isEmpty);
    expect(
      t.widget<FilledButton>(_key('validate-table-language')).onPressed,
      isNull,
    );
  });
  testWidgets('dashboard action opens universal language wizard', (t) async {
    final c = _Client();
    await t.pumpWidget(
      MaterialApp(
        home: AdminPortal(
          apiBaseUrl: 'http://localhost',
          client: c,
          adminCheck: Future.value(true),
          arabic: false,
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.ensureVisible(_key('add-topic-dataset'));
    await t.tap(_key('add-topic-dataset'));
    await t.pumpAndSettle();
    expect(find.byType(TableLanguageImportWizard), findsOneWidget);
    expect(find.text('Add / update table language'), findsWidgets);
    expect(find.byType(TopicImportWizard), findsNothing);
  });
}
