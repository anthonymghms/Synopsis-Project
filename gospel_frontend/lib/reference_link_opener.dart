import 'reference_link_opener_stub.dart'
    if (dart.library.html) 'reference_link_opener_web.dart';

Future<bool> openReferenceLink(Uri uri) => openReferenceLinkImpl(uri);
