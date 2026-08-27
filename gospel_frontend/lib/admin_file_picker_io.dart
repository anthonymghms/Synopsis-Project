import 'package:file_picker/file_picker.dart';

import 'admin_api_client.dart';

Future<List<AdminUploadFile>?> pickAdminFiles({
  required List<String> allowedExtensions,
  required bool allowMultiple,
}) async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: allowedExtensions,
    allowMultiple: allowMultiple,
    withData: true,
  );
  if (result == null) return null;

  final files = <AdminUploadFile>[];
  for (final file in result.files) {
    final bytes = file.bytes;
    if (bytes == null) {
      throw StateError('The selected file bytes are unavailable.');
    }
    files.add(AdminUploadFile(name: file.name, bytes: bytes));
  }
  return files;
}
