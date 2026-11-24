import 'package:cloud_firestore/cloud_firestore.dart';

import 'account_access.dart';
import 'catalog_events.dart';

typedef BibleCatalogDocument = ({
  String id,
  Map<String, dynamic> data,
  Map<String, String> versions,
});

Future<List<BibleCatalogDocument>>? _catalog;
(int, int)? _scope;

/// Readers and settings use different default-version rules, but discover the
/// same Firestore documents. Share just the source data for the current session.
Future<List<BibleCatalogDocument>> readBibleCatalog({
  FirebaseFirestore? firestore,
}) {
  if (firestore != null || !accountAccess.canRead) {
    return _readCatalog(firestore ?? FirebaseFirestore.instance);
  }
  final scope = (accountAccess.revision, catalogRevision.value);
  if (_scope != scope) {
    _scope = scope;
    _catalog = null;
  }
  final cached = _catalog;
  if (cached != null) return cached;
  final future = _readCatalog(FirebaseFirestore.instance);
  _catalog = future;
  return future.catchError((Object error, StackTrace stack) {
    if (identical(_catalog, future)) _catalog = null;
    Error.throwWithStackTrace(error, stack);
  });
}

Future<List<BibleCatalogDocument>> _readCatalog(FirebaseFirestore db) async {
  final languages = await db.collection('bibles').get();
  final docs = languages.docs.where((doc) => doc.id.trim().isNotEmpty).toList();
  final result = <BibleCatalogDocument>[];
  // Bound concurrency when a deployment has many imported languages.
  for (var start = 0; start < docs.length; start += 3) {
    result.addAll(
      await Future.wait(docs.skip(start).take(3).map(_readLanguage)),
    );
  }
  return result;
}

Future<BibleCatalogDocument> _readLanguage(
  QueryDocumentSnapshot<Map<String, dynamic>> language,
) async {
  final versions = <String, String>{};
  void collect(Map<String, dynamic> document) {
    for (final key in const [
      'versions',
      'availableVersions',
      'available_versions',
      'versionList',
      'version_list',
      'supportedVersions',
      'supported_versions',
    ]) {
      final field = document[key];
      final items = field is Map ? field.keys : field;
      if (items is! Iterable) continue;
      for (final item in items) {
        final id = item?.toString().trim() ?? '';
        if (id.isNotEmpty) versions.putIfAbsent(id, () => '');
      }
    }
  }

  Future<void> manifest(String collection, String id) async {
    try {
      final doc = await language.reference.collection(collection).doc(id).get();
      final data = doc.data();
      if (data != null) collect(data);
    } catch (_) {
      // Optional legacy layouts may be absent or inaccessible.
    }
  }

  Future<void> readVersions() async {
    try {
      final snapshot = await language.reference.collection('versions').get();
      for (final doc in snapshot.docs) {
        final id = doc.id.trim();
        final data = doc.data();
        if (id.isNotEmpty && id != 'manifest' && id != '_index') {
          versions[id] =
              (data['label'] ?? data['name'])?.toString().trim() ?? '';
        }
        collect(data);
      }
    } catch (_) {
      // Older rules may permit document reads but deny listing the collection.
      await Future.wait([
        manifest('versions', 'manifest'),
        manifest('versions', '_index'),
      ]);
    }
  }

  final data = language.data();
  collect(data);
  await Future.wait([
    readVersions(),
    manifest('metadata', 'versions'),
    manifest('meta', 'versions'),
    manifest('version_manifest', 'index'),
    manifest('version_manifest', 'all'),
  ]);
  return (id: language.id.trim(), data: data, versions: versions);
}
