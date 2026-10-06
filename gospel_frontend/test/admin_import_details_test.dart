import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gospel_frontend/admin_api_client.dart';
import 'package:gospel_frontend/admin_portal.dart';

const _importId = '0123456789abcdef0123456789abcdef';

class _ImportClient implements AdminClient {
  _ImportClient({this.collision = false, this.status = 'validated'});
  final bool collision;
  final String status;
  final posts = <({String path, Map<String, dynamic> body})>[];

  @override
  Future<Map<String, dynamic>> getJson(String path) async => {
    'import': {
      'id': _importId,
      'type': 'bible',
      'language': 'ancientgreek',
      'version': 'TR',
      'status': posts.isEmpty ? status : 'completed',
      'collision': collision,
      'recordsProcessed': posts.isEmpty ? 0 : 3744,
      'validation': {'books': 4, 'chapters': 89, 'verses': 3744},
      'filenames': ['ancient_greek.usfm'],
      'errors': status == 'validation_failed'
          ? [
              {'message': 'No verses found.'},
            ]
          : [],
      'warnings': <dynamic>[],
    },
  };

  @override
  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    posts.add((path: path, body: body));
    return {'status': 'queued'};
  }

  @override
  Future<Map<String, dynamic>> upload(
    String path, {
    required Map<String, String> fields,
    required List<AdminUploadFile> files,
    required String fileField,
  }) => throw UnimplementedError();
}

Future<void> _pump(
  WidgetTester tester,
  _ImportClient client,
  VoidCallback onCompleted,
) async {
  tester.view.physicalSize = const Size(1200, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ImportDetailsDialog(
          client: client,
          arabic: false,
          importId: _importId,
          onCompleted: onCompleted,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'validated import shows validated counts and resumes only after confirmation',
    (tester) async {
      final client = _ImportClient();
      var completed = 0;
      await _pump(tester, client, () => completed++);
      expect(
        find.text('Awaiting import — not published · 3744 validated'),
        findsOneWidget,
      );
      expect(find.text('verses: 3744'), findsOneWidget);
      expect(find.text('Completed · 0 imported'), findsNothing);
      await _tap(tester, find.byKey(const ValueKey('resume-import')));
      expect(client.posts, isEmpty);
      expect(find.text('Confirm import'), findsOneWidget);
      await _tap(tester, find.text('Import'));
      expect(client.posts.single.path, '/admin/bibles/import');
      expect(client.posts.single.body, {
        'importId': _importId,
        'confirm': true,
        'replace': false,
      });
      expect(completed, 1);
      expect(find.text('Completed · 3744 imported'), findsOneWidget);
    },
  );

  testWidgets(
    'existing dataset requires replacement checkbox and confirmation',
    (tester) async {
      final client = _ImportClient(collision: true);
      await _pump(tester, client, () {});
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('resume-import')))
            .onPressed,
        isNull,
      );
      await _tap(tester, find.byType(CheckboxListTile));
      await _tap(tester, find.byKey(const ValueKey('resume-import')));
      expect(find.text('Confirm replacement'), findsOneWidget);
      expect(client.posts, isEmpty);
      await _tap(tester, find.text('Cancel'));
      expect(client.posts, isEmpty);
      await _tap(tester, find.byKey(const ValueKey('resume-import')));
      await _tap(tester, find.text('Replace'));
      expect(client.posts.single.body['replace'], true);
    },
  );

  testWidgets('validation failures cannot publish invalid files', (
    tester,
  ) async {
    final client = _ImportClient(status: 'validation_failed');
    await _pump(tester, client, () {});
    expect(find.byKey(const ValueKey('resume-import')), findsNothing);
    expect(
      find.text('Correct the reported errors and upload the files again.'),
      findsOneWidget,
    );
    expect(client.posts, isEmpty);
  });
}
