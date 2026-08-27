import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart';

import 'admin_api_client.dart';

Future<List<AdminUploadFile>?> pickAdminFiles({
  required List<String> allowedExtensions,
  required bool allowMultiple,
}) async {
  final input = HTMLInputElement()
    ..type = 'file'
    ..multiple = allowMultiple
    ..accept = allowedExtensions
        .map((extension) => '.${extension.replaceFirst(RegExp(r'^\.'), '')}')
        .join(',')
    ..style.display = 'none';
  final completer = Completer<List<AdminUploadFile>?>();
  var selectionChanged = false;
  Timer? cancelTimer;

  void completeOnce(List<AdminUploadFile>? files) {
    if (!completer.isCompleted) completer.complete(files);
  }

  Future<Uint8List> readBytes(File file) async {
    final reader = FileReader();
    final bytesCompleter = Completer<Uint8List>();
    late JSFunction loadListener;
    late JSFunction errorListener;

    void cleanup() {
      reader.removeEventListener('loadend', loadListener);
      reader.removeEventListener('error', errorListener);
    }

    loadListener = ((Event _) {
      final result = (reader.result as JSArrayBuffer?)?.toDart;
      cleanup();
      if (result == null) {
        bytesCompleter.completeError(
          StateError('The selected file bytes are unavailable.'),
        );
      } else {
        bytesCompleter.complete(result.asUint8List());
      }
    }).toJS;
    errorListener = ((Event _) {
      cleanup();
      bytesCompleter.completeError(
        StateError('The selected file could not be read.'),
      );
    }).toJS;
    reader.addEventListener('loadend', loadListener);
    reader.addEventListener('error', errorListener);
    reader.readAsArrayBuffer(file);
    return bytesCompleter.future;
  }

  Future<void> handleSelection() async {
    selectionChanged = true;
    try {
      final files = <AdminUploadFile>[];
      final selectedFiles = input.files;
      for (var index = 0; index < (selectedFiles?.length ?? 0); index++) {
        final file = selectedFiles?.item(index);
        if (file == null) continue;
        files.add(
          AdminUploadFile(name: file.name, bytes: await readBytes(file)),
        );
      }
      completeOnce(files);
    } catch (error, stackTrace) {
      if (!completer.isCompleted) completer.completeError(error, stackTrace);
    }
  }

  late JSFunction changeListener;
  late JSFunction cancelListener;
  late JSFunction focusListener;
  changeListener = ((Event _) {
    unawaited(handleSelection());
  }).toJS;
  cancelListener = ((Event _) => completeOnce(null)).toJS;
  focusListener = ((Event _) {
    cancelTimer?.cancel();
    cancelTimer = Timer(const Duration(milliseconds: 500), () {
      if (!selectionChanged) completeOnce(null);
    });
  }).toJS;
  input.addEventListener('change', changeListener);
  input.addEventListener('cancel', cancelListener);
  window.addEventListener('focus', focusListener);

  document.body?.children.add(input);
  try {
    // Browser security requires this click during the originating user gesture.
    input.click();
    return await completer.future;
  } finally {
    cancelTimer?.cancel();
    input.removeEventListener('change', changeListener);
    input.removeEventListener('cancel', cancelListener);
    window.removeEventListener('focus', focusListener);
    input.remove();
  }
}
