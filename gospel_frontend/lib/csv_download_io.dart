import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

Future<void> downloadCsv(String contents, String filename) async {
  final bytes = Uint8List.fromList(utf8.encode(contents));
  final path = await FilePicker.platform.saveFile(
    fileName: filename,
    type: FileType.custom,
    allowedExtensions: const ['csv'],
    bytes: bytes,
  );
  if (path != null &&
      (Platform.isLinux || Platform.isMacOS || Platform.isWindows)) {
    await File(path).writeAsBytes(bytes);
  }
}
