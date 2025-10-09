// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

Future<bool> openReferenceLinkImpl(Uri uri) async {
  final resolved = uri.hasScheme
      ? uri
      : Uri.parse(html.window.location.href).resolveUri(uri);
  html.window.open(resolved.toString(), '_blank');
  return true;
}
