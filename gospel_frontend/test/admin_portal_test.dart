import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gospel_frontend/admin_api_client.dart';
import 'package:gospel_frontend/admin_portal.dart';

class _FakeAdminClient implements AdminClient {
  int uploads = 0;

  @override
  Future<Map<String, dynamic>> getJson(String path) async {
    if (path == '/admin/overview') {
      return <String, dynamic>{
        'counts': <String, dynamic>{
          'bibleLanguages': 2,
          'bibleVersions': 6,
          'topicLanguages': 2,
          'failedImports': 0,
        },
        'bibleLanguages': <dynamic>[],
        'topicLanguages': <dynamic>[],
        'recentImports': <dynamic>[],
      };
    }
    return <String, dynamic>{
      'import': <String, dynamic>{'status': 'completed', 'stage': 'Completed'},
    };
  }

  @override
  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body,
  ) async => <String, dynamic>{'status': 'queued'};

  @override
  Future<Map<String, dynamic>> upload(
    String path, {
    required Map<String, String> fields,
    required List<AdminUploadFile> files,
    required String fileField,
  }) async {
    uploads += 1;
    return <String, dynamic>{
      'importId': '0123456789abcdef0123456789abcdef',
      'valid': true,
      'collision': false,
      'errors': <dynamic>[],
      'warnings': <dynamic>[],
      'stats': <String, dynamic>{'topics': 1, 'references': 4},
      'preview': <dynamic>[
        <String, dynamic>{
          'id': '1',
          'name': 'Prologue',
          'references': <String, dynamic>{
            'Matthew': '1:1',
            'Mark': '1:1',
            'Luke': '1:1-4',
            'John': '1:1',
          },
        },
      ],
    };
  }
}

void main() {
  testWidgets('non-admin cannot open the portal', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AdminPortal(
          apiBaseUrl: 'http://localhost',
          client: _FakeAdminClient(),
          adminCheck: Future<bool>.value(false),
          arabic: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Administrator access is required.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('add-bible-translation')),
      findsNothing,
    );
  });

  testWidgets('admin dashboard exposes both primary import actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AdminPortal(
          apiBaseUrl: 'http://localhost',
          client: _FakeAdminClient(),
          adminCheck: Future<bool>.value(true),
          arabic: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('add-bible-translation')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('add-topic-dataset')),
      findsOneWidget,
    );
    expect(find.text('2'), findsNWidgets(2));
    expect(find.text('6'), findsOneWidget);
  });

  testWidgets('topic upload validates and renders a preview before import', (
    tester,
  ) async {
    final client = _FakeAdminClient();
    await tester.pumpWidget(
      MaterialApp(
        home: TopicImportWizard(
          client: client,
          arabic: false,
          onCompleted: () {},
          initialFile: AdminUploadFile(
            name: 'topics.csv',
            bytes: Uint8List.fromList(<int>[1, 2, 3]),
          ),
        ),
      ),
    );

    await tester.drag(find.byType(ListView), const Offset(0, -650));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('validate-topic-upload')),
    );
    await tester.pumpAndSettle();

    expect(client.uploads, 1);
    expect(find.text('Validation successful'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(find.text('Prologue'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('import-topic-upload')),
      findsOneWidget,
    );
  });

  testWidgets('Arabic portal uses RTL and localized navigation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AdminPortal(
          apiBaseUrl: 'http://localhost',
          client: _FakeAdminClient(),
          adminCheck: Future<bool>.value(true),
          arabic: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('الإدارة'), findsOneWidget);
    final directionality = tester.widgetList<Directionality>(
      find.byType(Directionality),
    );
    expect(
      directionality.any((widget) => widget.textDirection == TextDirection.rtl),
      isTrue,
    );
  });
}
