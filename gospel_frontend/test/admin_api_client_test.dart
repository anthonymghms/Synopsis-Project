import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gospel_frontend/admin_api_client.dart';
import 'package:http/http.dart' as http;

class _RecordingHttpClient extends http.BaseClient {
  http.BaseRequest? request;
  Uint8List? bodyBytes;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    this.request = request;
    bodyBytes = Uint8List.fromList(await request.finalize().toBytes());
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode('{"valid":true}')),
      200,
      headers: <String, String>{'content-type': 'application/json'},
    );
  }
}

void main() {
  test(
    'topic validation upload sends fields and selected bytes as multipart',
    () async {
      final httpClient = _RecordingHttpClient();
      final client = AdminApiClient(
        baseUrl: 'https://example.test',
        client: httpClient,
        tokenProvider: () async => 'admin-token',
      );
      final csvBytes = Uint8List.fromList(
        utf8.encode(
          'Topic,Matthew,Mark,Luke,John\nPrologue,1:1,1:1,1:1-4,1:1\n',
        ),
      );

      final response = await client.upload(
        '/admin/topics/validate',
        fields: const <String, String>{
          'language': 'arabic',
          'displayName': 'Arabic',
          'direction': 'rtl',
          'canonicalDataset': 'english_kjv',
        },
        files: <AdminUploadFile>[
          AdminUploadFile(name: 'arabic_topics.csv', bytes: csvBytes),
        ],
        fileField: 'file',
      );

      expect(response['valid'], isTrue);
      expect(
        httpClient.request?.url,
        Uri.parse('https://example.test/admin/topics/validate'),
      );
      expect(
        httpClient.request?.headers['Authorization'],
        'Bearer admin-token',
      );
      expect(
        httpClient.request?.headers['Content-Type'],
        startsWith('multipart/form-data; boundary='),
      );
      final body = latin1.decode(httpClient.bodyBytes!);
      expect(body, contains('name="language"\r\n\r\narabic'));
      expect(body, contains('name="displayName"\r\n\r\nArabic'));
      expect(body, contains('name="direction"\r\n\r\nrtl'));
      expect(body, contains('name="file"; filename="arabic_topics.csv"'));
      expect(body, contains(latin1.decode(csvBytes)));
    },
  );
}
