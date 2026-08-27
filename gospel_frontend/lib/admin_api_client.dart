import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class AdminUploadFile {
  const AdminUploadFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;

  int get size => bytes.lengthInBytes;
}

class AdminApiException implements Exception {
  const AdminApiException(this.message, {this.code, this.status});

  final String message;
  final String? code;
  final int? status;

  @override
  String toString() => message;
}

abstract class AdminClient {
  Future<Map<String, dynamic>> getJson(String path);
  Future<Map<String, dynamic>> postJson(String path, Map<String, dynamic> body);
  Future<Map<String, dynamic>> upload(
    String path, {
    required Map<String, String> fields,
    required List<AdminUploadFile> files,
    required String fileField,
  });
}

class AdminApiClient implements AdminClient {
  AdminApiClient({
    required this.baseUrl,
    FirebaseAuth? auth,
    http.Client? client,
    Future<String> Function()? tokenProvider,
  }) : _auth = auth ?? (tokenProvider == null ? FirebaseAuth.instance : null),
       _client = client ?? http.Client(),
       _tokenProvider = tokenProvider;

  final String baseUrl;
  final FirebaseAuth? _auth;
  final http.Client _client;
  final Future<String> Function()? _tokenProvider;

  Uri _uri(String path, [Map<String, String>? query]) => Uri.parse(
    '${baseUrl.replaceFirst(RegExp(r'/$'), '')}$path',
  ).replace(queryParameters: query);

  Future<String> _token() async {
    final tokenProvider = _tokenProvider;
    if (tokenProvider != null) {
      final token = await tokenProvider();
      if (token.isNotEmpty) return token;
    }
    final user = _auth?.currentUser;
    if (user == null) {
      throw const AdminApiException(
        'Sign in with an administrator account to continue.',
        code: 'authentication_required',
        status: 401,
      );
    }
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw const AdminApiException(
        'Your session could not be verified. Sign in again.',
        code: 'invalid_token',
        status: 401,
      );
    }
    return token;
  }

  @override
  Future<Map<String, dynamic>> getJson(String path) async {
    final response = await _client.get(
      _uri(path),
      headers: <String, String>{'Authorization': 'Bearer ${await _token()}'},
    );
    return _decode(response.statusCode, response.bodyBytes);
  }

  @override
  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await _client.post(
      _uri(path),
      headers: <String, String>{
        'Authorization': 'Bearer ${await _token()}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
    return _decode(response.statusCode, response.bodyBytes);
  }

  @override
  Future<Map<String, dynamic>> upload(
    String path, {
    required Map<String, String> fields,
    required List<AdminUploadFile> files,
    required String fileField,
  }) async {
    final request = http.MultipartRequest('POST', _uri(path));
    request.headers['Authorization'] = 'Bearer ${await _token()}';
    request.fields.addAll(fields);
    for (final file in files) {
      request.files.add(
        http.MultipartFile.fromBytes(
          fileField,
          file.bytes,
          filename: file.name,
        ),
      );
    }
    final streamed = await _client.send(request);
    final bytes = await streamed.stream.toBytes();
    return _decode(streamed.statusCode, bytes);
  }

  Map<String, dynamic> _decode(int status, List<int> bytes) {
    Map<String, dynamic> payload;
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      payload = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
    } catch (_) {
      payload = <String, dynamic>{};
    }
    if (status < 200 || status >= 300) {
      final error = payload['error'];
      final details = error is Map
          ? Map<String, dynamic>.from(error)
          : const <String, dynamic>{};
      throw AdminApiException(
        details['message']?.toString() ?? 'The admin request failed.',
        code: details['code']?.toString(),
        status: status,
      );
    }
    return payload;
  }
}
