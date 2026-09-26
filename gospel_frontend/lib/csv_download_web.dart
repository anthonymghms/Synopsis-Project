// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;

Future<void> downloadCsv(String contents, String filename) async {
  final url = html.Url.createObjectUrlFromBlob(
    html.Blob([contents], 'text/csv;charset=utf-8'),
  );
  final anchor = html.AnchorElement(href: url)
    ..download = filename
    ..style.display = 'none';
  html.document.body!.append(anchor);
  anchor.click();
  anchor.remove();
  Timer(const Duration(seconds: 1), () => html.Url.revokeObjectUrl(url));
}
