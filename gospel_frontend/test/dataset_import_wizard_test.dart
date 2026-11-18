import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gospel_frontend/admin_api_client.dart';
import 'package:gospel_frontend/admin_file_picker.dart';
import 'package:gospel_frontend/admin_portal.dart';

Map<String, dynamic> _preview({
  String dataset = 'miracles',
  bool replaces = false,
  bool hasTypes = true,
  bool valid = true,
}) => {
  'datasetId': dataset,
  'importId': 'staged-$dataset',
  'filename': dataset == 'miracles' ? 'Miracles.csv' : 'Parables.csv',
  'valid': valid,
  'replacesExisting': replaces,
  'hasTypes': hasTypes,
  'languages': ['english', 'arabic'],
  'encoding': 'utf-8-sig',
  'header': [
    '#',
    'Subject',
    'الموضوع',
    'Type',
    'Matthew',
    'Mark',
    'Luke',
    'John',
  ],
  'sourceChecksum': 'test-fixture-checksum',
  'stats': {'items': 2, 'references': 3, 'missingTypes': hasTypes ? 1 : 2},
  'types': hasTypes
      ? [
          {
            'id': 'figure-of-speech',
            'labels': {'english': 'Figure of Speech', 'arabic': 'صورة بيانية'},
            'count': 1,
          },
        ]
      : [],
  'errors': valid
      ? []
      : [
          {'field': 'Luke', 'row': 2, 'message': 'Malformed reference'},
        ],
  'warnings': [
    {'row': 3, 'message': 'Missing Type classification'},
  ],
  'preview': [
    {
      'id': '10',
      'name': 'Fixture subject',
      'names': {'english': 'Fixture subject', 'arabic': 'موضوع تجريبي'},
      'typeId': hasTypes ? 'figure-of-speech' : null,
      'type': hasTypes ? 'Figure of Speech' : null,
      'references': {
        'Matthew': '5:13,14',
        'Mark': '',
        'Luke': '8:1-3;9:1',
        'John': '',
      },
    },
  ],
};

class _DatasetClient implements AdminClient {
  _DatasetClient({
    this.replaces = false,
    this.hasTypes = true,
    this.valid = true,
    this.sourceAvailable = true,
    this.publishError,
    this.catalogFailures = 0,
    this.concurrentCreation = false,
  });
  final bool replaces, hasTypes, valid, sourceAvailable;
  final AdminApiException? publishError;
  int catalogFailures;
  final bool concurrentCreation;
  bool createdElsewhere = false;
  final calls = <({String path, Map<String, dynamic> body})>[];
  final uploads =
      <
        ({
          String path,
          Map<String, String> fields,
          List<AdminUploadFile> files,
          String field,
        })
      >[];

  @override
  Future<Map<String, dynamic>> getJson(String path) async {
    if (path == '/admin/datasets') {
      if (catalogFailures > 0) {
        catalogFailures--;
        throw const AdminApiException('Catalog unavailable');
      }
      return {
        'datasets': [
          if (createdElsewhere)
            {
              'datasetId': 'sayings',
              'labels': {'english': 'Sayings'},
              'published': true,
            },
          for (final id in ['harmony', 'miracles', 'parables'])
            {'datasetId': id, 'published': true},
          {
            'datasetId': 'teachings',
            'labels': {'english': 'Teachings', 'arabic': 'التعاليم'},
            'published': true,
          },
        ],
      };
    }

    if (path == '/admin/datasets/template') {
      return {
        'filename': 'table-template.csv',
        'csv': '#,Subject,الموضوع,Type,Matthew,Mark,Luke,John\r\n',
      };
    }
    if (path == '/admin/datasets/sources') {
      return {
        'sources': [
          for (final id in ['miracles', 'parables'])
            {
              'datasetId': id,
              'filename': id == 'miracles' ? 'Miracles.csv' : 'Parables.csv',
              'available': sourceAvailable,
              'generation': 'fixture-v1',
              'size': 1024,
            },
        ],
      };
    }
    if (path == '/admin/overview') return {'counts': {}, 'recentImports': []};
    throw StateError('Unexpected GET $path');
  }

  @override
  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    calls.add((path: path, body: Map.of(body)));
    if (path == '/admin/datasets/validate') {
      return _preview(
        dataset: body['datasetId'] as String,
        replaces: replaces,
        hasTypes: hasTypes,
        valid: valid,
      );
    }
    if (path == '/admin/datasets/publish') {
      if (publishError != null) throw publishError!;
      return {'status': 'completed', 'revisionId': 'fixture-revision'};
    }
    throw StateError('Unexpected POST $path');
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
      field: fileField,
    ));
    if (concurrentCreation) {
      createdElsewhere = true;
      throw const AdminApiException('Table already exists');
    }
    return _preview(
      dataset: fields['datasetId']!,
      replaces: replaces,
      hasTypes: hasTypes,
      valid: valid,
    );
  }
}

class _Picker implements AdminFilePicker {
  @override
  Future<List<AdminUploadFile>?> pickFiles({
    required List<String> allowedExtensions,
    bool allowMultiple = false,
  }) async {
    expect(allowedExtensions, ['csv']);
    expect(allowMultiple, isFalse);
    return [
      AdminUploadFile(
        name: 'Updated-parables.csv',
        bytes: Uint8List.fromList([1, 2, 3]),
      ),
    ];
  }
}

Future<void> _pump(
  WidgetTester tester,
  _DatasetClient client, {
  bool arabic = false,
  VoidCallback? onCompleted,
  Future<void> Function(String contents, String filename)? download,
  Size size = const Size(1200, 1100),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: DatasetImportWizard(
          client: client,
          arabic: arabic,
          onCompleted: onCompleted ?? () {},
          filePicker: _Picker(),
          csvDownloader: download ?? (_, _) async {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.drag(find.byType(ListView).first, const Offset(0, 3000));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      finder,
      250,
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

Future<void> _choose(WidgetTester tester, String key, String label) async {
  await _tap(tester, find.byKey(ValueKey(key)));
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'concurrent creation refreshes existing targets and preserves new-table inputs',
    (tester) async {
      final client = _DatasetClient(concurrentCreation: true);
      await _pump(tester, client);
      await _choose(
        tester,
        'dataset-import-target-miracles',
        'Create new table',
      );
      await tester.enterText(
        find.byKey(const ValueKey('new-table-id')),
        'sayings',
      );
      await tester.enterText(
        find.byKey(const ValueKey('new-table-name-english')),
        'Sayings',
      );
      await _tap(tester, find.byKey(const ValueKey('select-dataset-file')));
      await _tap(tester, find.byKey(const ValueKey('validate-dataset-source')));
      expect(find.text('Table already exists'), findsOneWidget);
      await _reveal(tester, find.byKey(const ValueKey('new-table-id')));
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('new-table-id')))
            .controller!
            .text,
        'sayings',
      );
      await _choose(tester, 'dataset-import-target-__new__', 'Sayings');
      expect(
        find.byKey(const ValueKey('dataset-import-target-sayings')),
        findsOneWidget,
      );
      expect(client.calls, isEmpty);
    },
  );

  testWidgets('new table validates labels then requires explicit publication', (
    tester,
  ) async {
    final client = _DatasetClient();
    var completions = 0;
    await _pump(tester, client, onCompleted: () => completions++);
    await _choose(tester, 'dataset-import-target-miracles', 'Create new table');
    expect(
      find.byKey(const ValueKey('dataset-import-source-upload')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('new-table-id')),
      'sayings',
    );
    await tester.enterText(
      find.byKey(const ValueKey('new-table-name-english')),
      'Sayings',
    );
    await tester.enterText(
      find.byKey(const ValueKey('new-table-name-arabic')),
      'الأقوال',
    );
    await _tap(tester, find.byKey(const ValueKey('select-dataset-file')));
    await _tap(tester, find.byKey(const ValueKey('validate-dataset-source')));
    expect(client.uploads.single.fields['datasetId'], 'sayings');
    expect(client.uploads.single.fields['createNew'], 'true');
    expect(jsonDecode(client.uploads.single.fields['labels']!), {
      'english': 'Sayings',
      'arabic': 'الأقوال',
    });
    expect(client.calls, isEmpty);
    await _tap(tester, find.byKey(const ValueKey('publish-dataset')));
    expect(find.text('Publish Sayings?'), findsOneWidget);
    expect(client.calls, isEmpty);
    await _tap(tester, find.byKey(const ValueKey('confirm-publish-dataset')));
    expect(client.calls.single.body, {
      'datasetId': 'sayings',
      'importId': 'staged-sayings',
      'confirm': true,
      'replace': false,
    });
    expect(completions, 1);
  });

  testWidgets('changing new table identity or labels invalidates its preview', (
    tester,
  ) async {
    final client = _DatasetClient();
    await _pump(tester, client);
    await _choose(tester, 'dataset-import-target-miracles', 'Create new table');
    await tester.enterText(
      find.byKey(const ValueKey('new-table-id')),
      'sayings',
    );
    await tester.enterText(
      find.byKey(const ValueKey('new-table-name-english')),
      'Sayings',
    );
    await _tap(tester, find.byKey(const ValueKey('select-dataset-file')));
    for (final field in [
      'new-table-name-english',
      'new-table-name-arabic',
      'new-table-id',
    ]) {
      await _tap(tester, find.byKey(const ValueKey('validate-dataset-source')));
      await _reveal(tester, find.byKey(const ValueKey('publish-dataset')));
      expect(find.byKey(const ValueKey('publish-dataset')), findsOneWidget);
      await _reveal(tester, find.byKey(ValueKey(field)));
      await tester.enterText(
        find.byKey(ValueKey(field)),
        field == 'new-table-id' ? 'sayings-revised' : 'Revised name',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('publish-dataset')), findsNothing);
    }
    expect(client.calls, isEmpty);
  });

  testWidgets('reserved and malformed IDs cannot validate a new table', (
    tester,
  ) async {
    final client = _DatasetClient();
    await _pump(tester, client);
    await _choose(tester, 'dataset-import-target-miracles', 'Create new table');
    await tester.enterText(
      find.byKey(const ValueKey('new-table-name-english')),
      'Sayings',
    );
    await _tap(tester, find.byKey(const ValueKey('select-dataset-file')));
    for (final id in [
      'harmony',
      'miracles',
      'teachings',
      'x',
      'Sayings',
      'bad--id',
      'bad-',
      'bad/id',
    ]) {
      await _reveal(tester, find.byKey(const ValueKey('new-table-id')));
      await tester.enterText(find.byKey(const ValueKey('new-table-id')), id);
      await tester.pumpAndSettle();
      await _reveal(
        tester,
        find.byKey(const ValueKey('validate-dataset-source')),
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('validate-dataset-source')),
            )
            .onPressed,
        isNull,
        reason: id,
      );
    }
    expect(client.uploads, isEmpty);
  });

  testWidgets('existing custom table uploads without creation metadata', (
    tester,
  ) async {
    final client = _DatasetClient(replaces: true);
    await _pump(tester, client);
    await _choose(tester, 'dataset-import-target-miracles', 'Teachings');
    expect(find.byKey(const ValueKey('new-table-id')), findsNothing);
    await _tap(tester, find.byKey(const ValueKey('select-dataset-file')));
    await _tap(tester, find.byKey(const ValueKey('validate-dataset-source')));
    expect(client.uploads.single.fields, {
      'datasetId': 'teachings',
      'source': 'upload',
    });
    await _reveal(tester, find.byKey(const ValueKey('publish-dataset')));
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('publish-dataset')))
          .onPressed,
      isNull,
    );
    expect(find.text('Replace the current Teachings revision'), findsOneWidget);
  });

  testWidgets('catalog failure blocks import until successful retry', (
    tester,
  ) async {
    final client = _DatasetClient(catalogFailures: 1);
    await _pump(tester, client);
    expect(find.text('Catalog unavailable'), findsOneWidget);
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byKey(const ValueKey('dataset-import-target-miracles')),
          )
          .onChanged,
      isNull,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('validate-dataset-source')),
          )
          .onPressed,
      isNull,
    );
    await _tap(tester, find.byKey(const ValueKey('retry-dataset-catalog')));
    await _choose(tester, 'dataset-import-target-miracles', 'Teachings');
    expect(
      find.byKey(const ValueKey('dataset-import-target-teachings')),
      findsOneWidget,
    );
  });

  testWidgets('generic CSV template downloads without creating a dataset', (
    tester,
  ) async {
    final client = _DatasetClient();
    String? csv, filename;
    await _pump(
      tester,
      client,
      download: (contents, name) async {
        csv = contents;
        filename = name;
      },
    );
    await _tap(tester, find.byKey(const ValueKey('download-dataset-template')));
    expect(filename, 'table-template.csv');
    expect(csv, '#,Subject,الموضوع,Type,Matthew,Mark,Luke,John\r\n');
    expect(client.calls, isEmpty);
    expect(client.uploads, isEmpty);
  });

  testWidgets(
    'Storage preview is dataset scoped and requires explicit publication confirmation',
    (tester) async {
      final client = _DatasetClient();
      var completions = 0;
      await _pump(tester, client, onCompleted: () => completions++);
      expect(find.text('Miracles.csv'), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('validate-dataset-source')));
      expect(client.calls.single.path, '/admin/datasets/validate');
      expect(client.calls.single.body, {
        'datasetId': 'miracles',
        'source': 'storage',
        'filename': 'Miracles.csv',
      });
      expect(completions, 0);
      await _tap(tester, find.byKey(const ValueKey('publish-dataset')));
      expect(find.text('Publish Miracles?'), findsOneWidget);
      expect(client.calls.length, 1);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(client.calls.length, 1);
      await _tap(tester, find.byKey(const ValueKey('publish-dataset')));
      await _tap(tester, find.byKey(const ValueKey('confirm-publish-dataset')));
      expect(client.calls.last.body, {
        'datasetId': 'miracles',
        'importId': 'staged-miracles',
        'confirm': true,
        'replace': false,
      });
      expect(completions, 1);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('publish-dataset')))
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets(
    'upload shares validation endpoint and preserves bilingual Type and reference preview',
    (tester) async {
      final client = _DatasetClient();
      await _pump(tester, client);
      await _choose(tester, 'dataset-import-target-miracles', 'Parables');
      await _choose(tester, 'dataset-import-source-storage', 'Upload CSV');
      await _tap(tester, find.byKey(const ValueKey('select-dataset-file')));
      await _tap(tester, find.byKey(const ValueKey('validate-dataset-source')));
      expect(client.uploads.single.path, '/admin/datasets/validate');
      expect(client.uploads.single.fields, {
        'datasetId': 'parables',
        'source': 'upload',
      });
      expect(client.uploads.single.field, 'file');
      expect(client.uploads.single.files.single.name, 'Updated-parables.csv');
      await _reveal(
        tester,
        find.byKey(const ValueKey('dataset-import-preview')),
      );
      expect(find.text('العربية: موضوع تجريبي'), findsOneWidget);
      expect(find.text('Matthew: 5:13,14'), findsOneWidget);
      expect(find.text('Luke: 8:1-3;9:1'), findsOneWidget);
      expect(find.text('Type: Figure of Speech'), findsOneWidget);
      expect(client.calls, isEmpty);
    },
  );

  testWidgets(
    'replacement is gated and changed source requires fresh validation',
    (tester) async {
      final client = _DatasetClient(
        replaces: true,
        publishError: const AdminApiException(
          'Source changed',
          code: 'source_changed',
          status: 409,
        ),
      );
      await _pump(tester, client);
      await _tap(tester, find.byKey(const ValueKey('validate-dataset-source')));
      final publish = find.byKey(const ValueKey('publish-dataset'));
      await _reveal(tester, publish);
      expect(tester.widget<FilledButton>(publish).onPressed, isNull);
      await _tap(
        tester,
        find.byKey(const ValueKey('replace-dataset-revision')),
      );
      await _tap(tester, publish);
      await _tap(tester, find.byKey(const ValueKey('confirm-publish-dataset')));
      expect(client.calls.last.body['replace'], isTrue);
      expect(find.byKey(const ValueKey('publish-dataset')), findsNothing);
      expect(
        find.text('Source changed Validate again before publishing.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('validate-dataset-source')),
            )
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets(
    'missing Type allows publication and explains need for updated CSV',
    (tester) async {
      final client = _DatasetClient(hasTypes: false);
      await _pump(tester, client);
      await _tap(tester, find.byKey(const ValueKey('validate-dataset-source')));
      await _reveal(tester, find.byKey(const ValueKey('publish-dataset')));
      expect(
        find.textContaining('No Type classifications were found.'),
        findsOneWidget,
      );
      expect(find.text('Missing Type (Unclassified): 2'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('publish-dataset')))
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets(
    'invalid references block publication and dataset changes clear staged preview',
    (tester) async {
      final client = _DatasetClient(valid: false, hasTypes: false);
      await _pump(tester, client);
      await _tap(tester, find.byKey(const ValueKey('validate-dataset-source')));
      await _reveal(tester, find.byKey(const ValueKey('publish-dataset')));
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('publish-dataset')))
            .onPressed,
        isNull,
      );
      expect(find.text('Malformed reference'), findsOneWidget);
      expect(find.textContaining('The table can be published'), findsNothing);
      expect(
        find.textContaining('Resolve any blocking errors before publishing.'),
        findsOneWidget,
      );
      await _choose(tester, 'dataset-import-target-miracles', 'Parables');
      expect(find.byKey(const ValueKey('publish-dataset')), findsNothing);
      expect(find.text('Parables.csv'), findsOneWidget);
      expect(client.calls.length, 1);
    },
  );

  testWidgets('unavailable Storage allows picker without arbitrary paths', (
    tester,
  ) async {
    final client = _DatasetClient(sourceAvailable: false);
    await _pump(tester, client);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('validate-dataset-source')),
          )
          .onPressed,
      isNull,
    );
    expect(find.byType(TextField), findsNothing);
    await _choose(tester, 'dataset-import-source-storage', 'Upload CSV');
    await _tap(tester, find.byKey(const ValueKey('select-dataset-file')));
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('validate-dataset-source')),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets(
    'Arabic wizard fits narrow viewport and displays localized Type labels',
    (tester) async {
      final client = _DatasetClient();
      await _pump(tester, client, arabic: true, size: const Size(390, 844));
      await _tap(tester, find.byKey(const ValueKey('validate-dataset-source')));
      await _tap(tester, find.byKey(const ValueKey('publish-dataset')));
      expect(find.text('نشر المعجزات؟'), findsOneWidget);
      expect(find.text('صورة بيانية: 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'portal offers additional table importer separately from Harmony',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AdminPortal(
            apiBaseUrl: 'http://localhost',
            client: _DatasetClient(),
            adminCheck: Future.value(true),
            arabic: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('update-harmony-references')),
        findsOneWidget,
      );
      await _tap(
        tester,
        find.byKey(const ValueKey('import-additional-dataset')),
      );
      expect(find.byType(DatasetImportWizard), findsOneWidget);
      expect(find.byType(TopicImportWizard), findsNothing);
    },
  );
}
