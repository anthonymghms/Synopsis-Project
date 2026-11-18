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
  });
  final bool replaces, hasTypes, valid, sourceAvailable;
  final AdminApiException? publishError;
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
