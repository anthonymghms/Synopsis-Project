// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

Future<bool> openReferenceLinkImpl(Uri uri) async {
  html.window.open(uri.toString(), '_blank');
  return true;
}
