import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gospel_frontend/admin_api_client.dart';
import 'package:gospel_frontend/admin_file_picker.dart';
import 'package:gospel_frontend/admin_portal.dart';

class _FakeAdminClient implements AdminClient {
  _FakeAdminClient({this.uploadResponse, this.importResponse});

  final Map<String, dynamic>? uploadResponse;
  final Map<String, dynamic>? importResponse;
  int uploads = 0;
  String? uploadPath;
  Map<String, String>? uploadFields;
  List<AdminUploadFile>? uploadFiles;
  String? uploadFileField;

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
    return importResponse ??
        <String, dynamic>{
          'import': <String, dynamic>{
            'status': 'completed',
            'stage': 'Completed',
          },
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
    uploadPath = path;
    uploadFields = Map<String, String>.from(fields);
    uploadFiles = List<AdminUploadFile>.from(files);
    uploadFileField = fileField;
    return uploadResponse ??
        <String, dynamic>{
          'importId': '0123456789abcdef0123456789abcdef',
          'valid': true,
          'collision': false,
          'errors': <dynamic>[],
          'warnings': <dynamic>[],
          'stats': <String, dynamic>{'topics': 1, 'references': 4},
          'preview': <dynamic>[
            <String, dynamic>{
              'id': '1',
              'canonicalName': 'Prologue',
              'localizedName': 'Localized Prologue',
            },
          ],
        };
  }
}

class _FakeAdminFilePicker implements AdminFilePicker {
  _FakeAdminFilePicker({this.result, this.error});

  List<AdminUploadFile>? result;
  Object? error;
  int calls = 0;
  List<String>? allowedExtensions;
  bool? allowMultiple;

  @override
  Future<List<AdminUploadFile>?> pickFiles({
    required List<String> allowedExtensions,
    bool allowMultiple = false,
  }) async {
    calls += 1;
    this.allowedExtensions = List<String>.from(allowedExtensions);
    this.allowMultiple = allowMultiple;
    if (error case final pickerError?) throw pickerError;
    return result;
  }
}

Future<void> _pumpTopicWizard(
  WidgetTester tester, {
  required _FakeAdminClient client,
  AdminFilePicker? filePicker,
  AdminUploadFile? initialFile,
  bool arabic = false,
  bool canonicalReferences = false,
  int maxUploadBytes = defaultMaxAdminUploadBytes,
}) async {
  tester.view.physicalSize = const Size(1200, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: TopicImportWizard(
        client: client,
        arabic: arabic,
        onCompleted: () {},
        filePicker: filePicker ?? _FakeAdminFilePicker(),
        initialFile: initialFile,
        maxUploadBytes: maxUploadBytes,
        canonicalReferences: canonicalReferences,
      ),
    ),
  );
}

FilledButton _validateTopicButton(WidgetTester tester) =>
    tester.widget(find.byKey(const ValueKey<String>('validate-topic-upload')));

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
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
    expect(
      find.byKey(const ValueKey<String>('update-harmony-references')),
      findsOneWidget,
    );
    expect(find.text('2'), findsNWidgets(2));
    expect(find.text('6'), findsOneWidget);
  });

  testWidgets('topic upload validates and renders a preview before import', (
    tester,
  ) async {
    final client = _FakeAdminClient();
    final bytes = Uint8List.fromList(<int>[1, 2, 3]);
    await _pumpTopicWizard(
      tester,
      client: client,
      initialFile: AdminUploadFile(name: 'topics.csv', bytes: bytes),
    );

    await tester.drag(find.byType(ListView), const Offset(0, -650));
    await tester.pumpAndSettle();
    await _tapVisible(
      tester,
      find.byKey(const ValueKey<String>('validate-topic-upload')),
    );
    await tester.pumpAndSettle();

    expect(client.uploads, 1);
    expect(client.uploadPath, '/admin/localizations/validate');
    expect(client.uploadFileField, 'file');
    expect(client.uploadFields, <String, String>{
      'language': 'english',
      'displayName': 'English',
      'direction': 'ltr',
      'canonicalDataset': 'english_kjv',
      'gospelMatthew': 'Matthew',
      'gospelMark': 'Mark',
      'gospelLuke': 'Luke',
      'gospelJohn': 'John',
    });
    expect(client.uploadFiles?.single.name, 'topics.csv');
    expect(client.uploadFiles?.single.bytes, orderedEquals(bytes));
    expect(find.text('Validation successful'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(find.text('Prologue'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('import-topic-upload')),
      findsOneWidget,
    );
  });

  testWidgets('canonical Harmony validation uses the restricted endpoint', (
    tester,
  ) async {
    final client = _FakeAdminClient();
    await _pumpTopicWizard(
      tester,
      client: client,
      canonicalReferences: true,
      initialFile: AdminUploadFile(
        name: 'harmony.csv',
        bytes: Uint8List.fromList(<int>[1, 2, 3]),
      ),
    );

    await _tapVisible(
      tester,
      find.byKey(const ValueKey<String>('validate-topic-upload')),
    );
    await tester.pumpAndSettle();

    expect(client.uploadPath, '/admin/harmony/validate');
    expect(client.uploadFields, {
      'localizationLanguage': 'arabic',
      'localizationDisplayName': 'العربية',
      'localizationDirection': 'rtl',
      'gospelMatthew': 'متى',
      'gospelMark': 'مرقس',
      'gospelLuke': 'لوقا',
      'gospelJohn': 'يوحنا',
    });
    expect(client.uploadFiles?.single.name, 'harmony.csv');
  });

  testWidgets('first full language table shows atomic bootstrap notice', (
    tester,
  ) async {
    final client = _FakeAdminClient(
      uploadResponse: <String, dynamic>{
        'importId': '0123456789abcdef0123456789abcdef',
        'valid': true,
        'collision': false,
        'bootstrapCanonical': true,
        'errors': <dynamic>[],
        'warnings': <dynamic>[],
        'stats': <String, dynamic>{
          'topics': 289,
          'canonicalTopics': 289,
          'references': 591,
          'physicalSegments': 596,
        },
        'preview': <dynamic>[
          <String, dynamic>{
            'id': '1',
            'canonicalName': 'المقدمة',
            'localizedName': 'المقدمة',
          },
        ],
      },
    );
    await _pumpTopicWizard(
      tester,
      client: client,
      initialFile: AdminUploadFile(
        name: 'Topics.csv',
        bytes: Uint8List.fromList(<int>[1, 2, 3]),
      ),
    );

    await tester.drag(find.byType(ListView), const Offset(0, -650));
    await tester.pumpAndSettle();
    await _tapVisible(
      tester,
      find.byKey(const ValueKey<String>('validate-topic-upload')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Main Harmony table detected'), findsOneWidget);
    expect(find.text('Import Main Table & Language'), findsOneWidget);
    expect(find.text('المقدمة'), findsOneWidget);
  });

  testWidgets('failed imports stop loading and display their reason', (
    tester,
  ) async {
    const reason = 'The active pointers could not be updated.';
    final client = _FakeAdminClient(
      uploadResponse: <String, dynamic>{
        'importId': '0123456789abcdef0123456789abcdef',
        'valid': true,
        'collision': false,
        'errors': <dynamic>[],
        'warnings': <dynamic>[],
        'stats': <String, dynamic>{'topics': 1},
        'preview': <dynamic>[],
      },
      importResponse: <String, dynamic>{
        'import': <String, dynamic>{
          'status': 'failed',
          'stage': 'Failed',
          'errors': <dynamic>[
            <String, dynamic>{'message': reason},
          ],
        },
      },
    );
    await _pumpTopicWizard(
      tester,
      client: client,
      initialFile: AdminUploadFile(
        name: 'Topics.csv',
        bytes: Uint8List.fromList(<int>[1, 2, 3]),
      ),
    );

    await _tapVisible(
      tester,
      find.byKey(const ValueKey<String>('validate-topic-upload')),
    );
    await tester.pumpAndSettle();
    await _tapVisible(
      tester,
      find.byKey(const ValueKey<String>('import-topic-upload')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text(reason), findsWidgets);
  });

  testWidgets('Select CSV invokes picker and populates selected-file state', (
    tester,
  ) async {
    final picker = _FakeAdminFilePicker(
      result: <AdminUploadFile>[
        AdminUploadFile(
          name: 'arabic_topics.csv',
          bytes: Uint8List.fromList(<int>[1, 2, 3]),
        ),
      ],
    );
    await _pumpTopicWizard(
      tester,
      client: _FakeAdminClient(),
      filePicker: picker,
    );

    expect(_validateTopicButton(tester).onPressed, isNull);
    await _tapVisible(
      tester,
      find.byKey(const ValueKey<String>('select-topic-file')),
    );
    await tester.pumpAndSettle();

    expect(picker.calls, 1);
    expect(picker.allowedExtensions, <String>['csv']);
    expect(picker.allowMultiple, isFalse);
    expect(find.text('arabic_topics.csv'), findsOneWidget);
    expect(find.text('3 B'), findsOneWidget);
    expect(find.text('Change file'), findsOneWidget);
    expect(find.text('Remove file'), findsOneWidget);
    expect(_validateTopicButton(tester).onPressed, isNotNull);
  });

  testWidgets('canceling replacement keeps the existing file and state', (
    tester,
  ) async {
    final picker = _FakeAdminFilePicker(result: null);
    await _pumpTopicWizard(
      tester,
      client: _FakeAdminClient(),
      filePicker: picker,
      initialFile: AdminUploadFile(
        name: 'topics.csv',
        bytes: Uint8List.fromList(<int>[1]),
      ),
    );

    await _tapVisible(
      tester,
      find.byKey(const ValueKey<String>('change-topic-file')),
    );
    await tester.pumpAndSettle();

    expect(picker.calls, 1);
    expect(find.text('topics.csv'), findsOneWidget);
    expect(
      find.text('Unable to open the file. Please try again.'),
      findsNothing,
    );
    expect(_validateTopicButton(tester).onPressed, isNotNull);
  });

  testWidgets('Change file replaces the selected filename and bytes', (
    tester,
  ) async {
    final replacementBytes = Uint8List.fromList(<int>[7, 8, 9]);
    final picker = _FakeAdminFilePicker(
      result: <AdminUploadFile>[
        AdminUploadFile(name: 'replacement.csv', bytes: replacementBytes),
      ],
    );
    final client = _FakeAdminClient();
    await _pumpTopicWizard(
      tester,
      client: client,
      filePicker: picker,
      initialFile: AdminUploadFile(
        name: 'original.csv',
        bytes: Uint8List.fromList(<int>[1]),
      ),
    );

    await _tapVisible(
      tester,
      find.byKey(const ValueKey<String>('change-topic-file')),
    );
    await tester.pumpAndSettle();
    expect(find.text('replacement.csv'), findsOneWidget);
    expect(find.text('original.csv'), findsNothing);

    await tester.drag(find.byType(ListView), const Offset(0, -650));
    await tester.pumpAndSettle();
    await _tapVisible(
      tester,
      find.byKey(const ValueKey<String>('validate-topic-upload')),
    );
    await tester.pumpAndSettle();
    expect(client.uploadFiles?.single.bytes, orderedEquals(replacementBytes));
  });

  testWidgets('wrong extension is rejected with a localized message', (
    tester,
  ) async {
    final picker = _FakeAdminFilePicker(
      result: <AdminUploadFile>[
        AdminUploadFile(
          name: 'topics.txt',
          bytes: Uint8List.fromList(<int>[1]),
        ),
      ],
    );
    await _pumpTopicWizard(
      tester,
      client: _FakeAdminClient(),
      filePicker: picker,
      arabic: true,
    );

    await _tapVisible(
      tester,
      find.byKey(const ValueKey<String>('select-topic-file')),
    );
    await tester.pumpAndSettle();

    expect(find.text('يرجى اختيار ملف CSV.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('selected-topic-filename')),
      findsNothing,
    );
    expect(_validateTopicButton(tester).onPressed, isNull);
  });

  testWidgets('empty and oversized CSV files are rejected', (tester) async {
    final picker = _FakeAdminFilePicker(
      result: <AdminUploadFile>[
        AdminUploadFile(name: 'topics.csv', bytes: Uint8List(0)),
      ],
    );
    await _pumpTopicWizard(
      tester,
      client: _FakeAdminClient(),
      filePicker: picker,
      maxUploadBytes: 2,
    );

    await _tapVisible(
      tester,
      find.byKey(const ValueKey<String>('select-topic-file')),
    );
    await tester.pumpAndSettle();
    expect(find.text('The selected CSV file is empty.'), findsOneWidget);

    picker.result = <AdminUploadFile>[
      AdminUploadFile(
        name: 'topics.csv',
        bytes: Uint8List.fromList(<int>[1, 2, 3]),
      ),
    ];
    await _tapVisible(
      tester,
      find.byKey(const ValueKey<String>('select-topic-file')),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('The selected file is too large. The upload limit is 2 B.'),
      findsOneWidget,
    );
    expect(_validateTopicButton(tester).onPressed, isNull);
  });

  testWidgets('picker errors are friendly and do not expose exceptions', (
    tester,
  ) async {
    final picker = _FakeAdminFilePicker(error: StateError('browser internals'));
    await _pumpTopicWizard(
      tester,
      client: _FakeAdminClient(),
      filePicker: picker,
    );

    await _tapVisible(
      tester,
      find.byKey(const ValueKey<String>('select-topic-file')),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Unable to open the file. Please try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('browser internals'), findsNothing);
  });

  testWidgets('remove file resets selection and disables validation', (
    tester,
  ) async {
    await _pumpTopicWizard(
      tester,
      client: _FakeAdminClient(),
      initialFile: AdminUploadFile(
        name: 'topics.csv',
        bytes: Uint8List.fromList(<int>[1, 2, 3]),
      ),
    );
    expect(_validateTopicButton(tester).onPressed, isNotNull);

    await _tapVisible(
      tester,
      find.byKey(const ValueKey<String>('remove-topic-file')),
    );
    await tester.pumpAndSettle();

    expect(find.text('topics.csv'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('select-topic-file')),
      findsOneWidget,
    );
    expect(_validateTopicButton(tester).onPressed, isNull);
  });

  testWidgets('required metadata controls validation button state', (
    tester,
  ) async {
    await _pumpTopicWizard(
      tester,
      client: _FakeAdminClient(),
      initialFile: AdminUploadFile(
        name: 'topics.csv',
        bytes: Uint8List.fromList(<int>[1]),
      ),
    );
    expect(_validateTopicButton(tester).onPressed, isNotNull);

    await tester.enterText(
      find.byKey(const ValueKey<String>('language-display-name')),
      '',
    );
    await tester.pump();
    expect(_validateTopicButton(tester).onPressed, isNull);

    await tester.enterText(
      find.byKey(const ValueKey<String>('language-display-name')),
      'Arabic',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('language-code')),
      'Arabic',
    );
    await tester.pump();
    expect(_validateTopicButton(tester).onPressed, isNull);

    await tester.enterText(
      find.byKey(const ValueKey<String>('language-code')),
      'arabic',
    );
    await tester.pump();
    expect(_validateTopicButton(tester).onPressed, isNotNull);
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
