// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

Future<bool> openReferenceLinkImpl(Uri uri) async {
  if (uri.hasScheme || uri.hasAuthority) {
    html.window.open(uri.toString(), '_blank');
    return true;
  }

  final location = html.window.location;
  final base = StringBuffer()
    ..write(location.origin)
    ..write(location.pathname)
    ..write(location.search);

  final pathWithQuery = uri.toString().startsWith('/')
      ? uri.toString()
      : '/${uri.toString()}';

  final target = '$base#${pathWithQuery.startsWith('/') ? '' : '/'}$pathWithQuery';
  html.window.open(target, '_blank');
  return true;
}
