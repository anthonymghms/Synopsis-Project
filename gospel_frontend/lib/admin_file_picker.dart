import 'admin_api_client.dart';
import 'admin_file_picker_io.dart'
    if (dart.library.html) 'admin_file_picker_web.dart'
    as implementation;

const int defaultMaxAdminUploadBytes = 32 * 1024 * 1024;

abstract interface class AdminFilePicker {
  Future<List<AdminUploadFile>?> pickFiles({
    required List<String> allowedExtensions,
    bool allowMultiple = false,
  });
}

class PlatformAdminFilePicker implements AdminFilePicker {
  const PlatformAdminFilePicker();

  @override
  Future<List<AdminUploadFile>?> pickFiles({
    required List<String> allowedExtensions,
    bool allowMultiple = false,
  }) => implementation.pickAdminFiles(
    allowedExtensions: allowedExtensions,
    allowMultiple: allowMultiple,
  );
}
