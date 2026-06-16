// ignore_for_file: deprecated_member_use

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

Future<bool> openReferenceLinkImpl(Uri uri) async {
  if (uri.hasScheme || uri.hasAuthority) {
    html.window.location.assign(uri.toString());
    return true;
  }

  final pathWithQuery = uri.toString().startsWith('/')
      ? uri.toString()
      : '/${uri.toString()}';
  final target =
      ui_web.urlStrategy?.prepareExternalUrl(pathWithQuery) ?? pathWithQuery;

  html.window.location.assign(target);
  return true;
}
