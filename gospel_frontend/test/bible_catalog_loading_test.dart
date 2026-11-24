// These test-only Firestore fakes hold reads pending to verify request overlap.
// ignore_for_file: subtype_of_sealed_class

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gospel_frontend/main.dart';
import 'package:gospel_frontend/preference_language_catalog.dart';
import 'package:gospel_frontend/user_profile.dart';

class _CatalogStore extends Fake implements FirebaseFirestore {
  final releaseReads = Completer<void>();
  bool denyVersionListing = false;
  final requests = <String>[];
  final languages = <String, Map<String, dynamic>>{
    'english': {
      'versions': ['kjv'],
    },
    'ancientgreek': {'label': 'Greek'},
    'french': {
      'versions': ['LSG'],
    },
    'arabic': {
      'versions': ['Van Dyke-'],
      'direction': 'rtl',
    },
  };

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Collection(this, path);

  Future<Map<String, dynamic>?> readDocument(String path) async {
    requests.add(path);
    await releaseReads.future;
    if (path == 'bibles/english/versions/manifest') {
      return {
        'available_versions': {'legacy': true},
      };
    }
    if (path.endsWith('/metadata/versions')) {
      throw StateError('Legacy metadata source unavailable');
    }
    if (path == 'bibles/ancientgreek/version_manifest/all') {
      return {
        'versions': ['TR'],
      };
    }
    return null;
  }

  Future<QuerySnapshot<Map<String, dynamic>>> readCollection(
    String path,
  ) async {
    requests.add(path);
    if (path == 'bibles') {
      return _QuerySnapshot([
        for (final entry in languages.entries)
          _QueryDocument(this, 'bibles/${entry.key}', entry.value),
      ]);
    }
    await releaseReads.future;
    if (path == 'bibles/english/versions') {
      if (denyVersionListing) throw StateError('Cannot list versions');
      return _QuerySnapshot([
        _QueryDocument(this, '$path/ASV', {'label': 'American Standard'}),
        _QueryDocument(this, '$path/kjv', {
          'versions': ['kjv'],
        }),
      ]);
    }
    return _QuerySnapshot([]);
  }
}

class _Collection extends Fake
    implements CollectionReference<Map<String, dynamic>> {
  _Collection(this.store, this.path);
  final _CatalogStore store;
  @override
  final String path;

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      _Document(store, '${this.path}/$path');

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) =>
      store.readCollection(path);
}

class _Document extends Fake
    implements DocumentReference<Map<String, dynamic>> {
  _Document(this.store, this.path);
  final _CatalogStore store;
  @override
  final String path;
  @override
  String get id => path.split('/').last;

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Collection(store, '${this.path}/$path');

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async => _DocumentSnapshot(await store.readDocument(path));
}

class _DocumentSnapshot extends Fake
    implements DocumentSnapshot<Map<String, dynamic>> {
  _DocumentSnapshot(this.value);
  final Map<String, dynamic>? value;
  @override
  bool get exists => value != null;
  @override
  Map<String, dynamic>? data() => value;
}

class _QueryDocument extends Fake
    implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _QueryDocument(this.store, this.path, this.value);
  final _CatalogStore store;
  final String path;
  final Map<String, dynamic> value;
  @override
  String get id => path.split('/').last;
  @override
  Map<String, dynamic> data() => value;
  @override
  DocumentReference<Map<String, dynamic>> get reference =>
      _Document(store, path);
}

class _QuerySnapshot extends Fake
    implements QuerySnapshot<Map<String, dynamic>> {
  _QuerySnapshot(this.docs);
  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
}

void main() {
  test(
    'catalog overlaps bounded language reads and preserves legacy versions',
    () async {
      final store = _CatalogStore();
      addTearDown(() {
        if (!store.releaseReads.isCompleted) store.releaseReads.complete();
      });
      final loading = loadBibleLanguageCatalog(firestore: store);
      await Future<void>.delayed(Duration.zero);

      // Three independent languages start together, rather than waiting for
      // each missing manifest before even asking for the next language.
      expect(store.requests.length, 1 + 3 * 5);
      for (final language in ['english', 'ancientgreek', 'french']) {
        expect(store.requests, contains('bibles/$language/versions'));
        expect(
          store.requests,
          contains('bibles/$language/version_manifest/all'),
        );
        expect(store.requests, isNot(contains('bibles/$language')));
      }
      expect(
        store.requests.any((path) => path.startsWith('bibles/arabic/')),
        isFalse,
      );

      store.releaseReads.complete();
      final languages = await loading;
      expect(store.requests.length, 1 + 4 * 5);
      final english = languages.firstWhere((item) => item.code == 'english');
      expect(english.versions.map((item) => item.id), ['ASV', 'kjv']);
      expect(english.versions.first.label, 'American Standard');
      expect(
        languages
            .firstWhere((item) => item.code == 'ancientgreek')
            .versions
            .single
            .id,
        'TR',
      );
      expect(
        languages.firstWhere((item) => item.code == 'arabic').direction,
        TextDirection.rtl,
      );
    },
  );
  test(
    'settings preserves legacy versions when collection listings are denied',
    () async {
      final store = _CatalogStore()..denyVersionListing = true;
      store.releaseReads.complete();
      final catalog = await PreferenceLanguageCatalog(firestore: store).load();
      final english = catalog.firstWhere((option) => option.code == 'english');
      expect(
        english.versions.map((item) => item.id),
        containsAll(['legacy', 'kjv']),
      );
      expect(store.requests, contains('bibles/english/versions/_index'));
      expect(store.requests, isNot(contains('bibles/french/versions/_index')));
    },
  );

  test('only bundled table choices can open before language discovery', () {
    final uri = Uri.parse('/topics');
    expect(
      canOpenTableWithBundledCatalog(uri, const UserPreferences()),
      isTrue,
    );
    for (final query in [
      'language=french',
      'version=imported',
      'tableLocale=hebrew',
    ]) {
      expect(
        canOpenTableWithBundledCatalog(
          Uri.parse('/topics?$query'),
          const UserPreferences(),
        ),
        isFalse,
      );
    }
    expect(
      canOpenTableWithBundledCatalog(
        uri,
        const UserPreferences(
          contentLanguage: 'english',
          tableLanguageOverride: 'arabic',
        ),
      ),
      isTrue,
    );
    expect(
      canOpenTableWithBundledCatalog(
        uri,
        const UserPreferences(contentLanguage: 'greek'),
      ),
      isFalse,
    );
  });
  test(
    'reader deep links preserve imported comparison choices during discovery',
    () {
      final uri = Uri.parse('/reference?language=english&version=kjv');
      expect(
        canOpenReaderWithBundledCatalog(uri, const UserPreferences()),
        isTrue,
      );
      expect(
        canOpenReaderWithBundledCatalog(
          Uri.parse('/topic?language=arabic&version=Van%20Dyke-'),
          const UserPreferences(),
        ),
        isTrue,
      );
      expect(
        canOpenReaderWithBundledCatalog(
          Uri.parse('/topic?language=english&comparisons=restored'),
          const UserPreferences(),
        ),
        isFalse,
      );
      expect(
        canOpenReaderWithBundledCatalog(
          Uri.parse('/reference?version=custom'),
          const UserPreferences(),
        ),
        isFalse,
      );
    },
  );
}
