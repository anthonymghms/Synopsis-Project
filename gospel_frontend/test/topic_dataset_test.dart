import 'package:flutter_test/flutter_test.dart';
import 'package:gospel_frontend/gospel_filter.dart';
import 'package:gospel_frontend/topic_dataset.dart';

// Explicit synthetic fixtures: these are not copies of production CSV rows.
const metadata = DatasetMetadata(
  datasetId: 'parables',
  revision: 'fixture-v1',
  hasTypes: true,
  languages: ['english', 'arabic'],
  types: [
    DatasetType(id: 'parable', labels: {'english': 'Parable'}, order: 2),
    DatasetType(
      id: 'figure-of-speech',
      labels: {'english': 'Figure of Speech'},
      order: 1,
    ),
  ],
);

typedef FixtureItem = ({String id, String name, String? typeId, int mask});
const fixtureItems = <FixtureItem>[
  (id: '8', name: 'Same name', typeId: 'parable', mask: 6),
  (id: '3', name: 'Same name', typeId: 'parable', mask: 2),
  (id: '4', name: 'Fixture C', typeId: 'figure-of-speech', mask: 4),
  (id: '6', name: 'Fixture D', typeId: 'parable', mask: 12),
  (id: '2', name: 'Fixture E', typeId: null, mask: 1),
  (id: '7', name: 'Fixture F', typeId: 'new-source-type', mask: 4),
];

void main() {
  test('legacy dataset defaults and identity never collide across tables', () {
    expect(normalizeDatasetId(null), 'harmony');
    expect(normalizeDatasetId(''), 'harmony');
    expect(normalizeDatasetId('new-table'), 'new-table');
    expect(normalizeDatasetId(' Parables '), 'parables');
    expect(
      topicDatasetIds.map((id) => datasetItemKey(id, '1')).toSet(),
      hasLength(3),
    );
    expect(const DatasetViewState().toQueryParameters(), isEmpty);
  });

  test(
    'custom dataset IDs remain isolated and invalid path IDs are rejected',
    () {
      for (final invalid in [
        '',
        'a',
        '../miracles',
        'a/b',
        'a_b',
        '-abc',
        'abc-',
        'a--b',
        'a' * 49,
      ]) {
        expect(normalizeDatasetId(invalid), 'harmony', reason: invalid);
      }
      expect(normalizeDatasetId(' FOURTH-Table '), 'fourth-table');
      expect(datasetItemKey('fourth-table', '1'), 'fourth-table:1');
      expect(
        datasetItemKey('harmony', '1'),
        isNot(datasetItemKey('fourth-table', '1')),
      );
      final state = DatasetViewState.fromQueryParameters({
        'dataset': 'fourth-table',
        'view': 'grouped',
        'types': 'first-type,other-type',
      });
      expect(state.datasetId, 'fourth-table');
      expect(state.toQueryParameters()['dataset'], 'fourth-table');
      expect(
        DatasetViewState.fromQueryParameters(state.toQueryParameters()),
        state,
      );
      final metadata = DatasetMetadata.fromJson({
        'datasetId': 'fourth-table',
        'revision': 'fourth-v1',
      });
      expect(
        metadata.cacheKeyForLanguage('french'),
        'fourth-table:fourth-v1:french',
      );
    },
  );

  test(
    'catalog adds only published custom tables and preserves builtin labels',
    () {
      final catalog = parseDatasetCatalog({
        'datasets': [
          {
            'datasetId': 'harmony',
            'labels': {'english': 'Harmony / All Topics'},
            'published': true,
          },
          {
            'datasetId': 'parables',
            'labels': {'english': 'Parables'},
            'published': true,
          },
          {
            'datasetId': 'new-table',
            'labels': {
              'english': 'New table',
              'arabic': 'جدول جديد',
              'fr': 'Nouveau tableau',
            },
            'published': true,
            'revision': 'new-v1',
          },
          {
            'datasetId': 'draft-table',
            'labels': {'english': 'Draft'},
            'published': false,
          },
          {
            'datasetId': '../unsafe',
            'labels': {'english': 'Invalid'},
            'published': true,
          },
        ],
      });
      expect(catalog.map((entry) => entry.datasetId), [
        ...topicDatasetIds,
        'new-table',
      ]);
      expect(catalog[2].label('french'), 'Paraboles');
      expect(catalog.last.label('ar'), 'جدول جديد');
      expect(catalog.last.label('french'), 'Nouveau tableau');
      expect(catalog.last.label('german'), 'New table');
      expect(catalog.last.revision, 'new-v1');
      expect(parseDatasetCatalog(null), hasLength(3));
      expect(parseDatasetCatalog({'datasets': 'malformed'}), hasLength(3));
      expect(
        const DatasetCatalogEntry(datasetId: 'new-table').label('english'),
        'new-table',
      );
      expect(
        const DatasetCatalogEntry(
          datasetId: 'new-table',
          labels: {'arabic': 'جدول جديد'},
        ).label('french'),
        'جدول جديد',
      );
      replaceDatasetCatalog(catalog);
      addTearDown(() => replaceDatasetCatalog(builtinDatasetCatalog));
      expect(datasetDisplayName('new-table', 'french'), 'Nouveau tableau');
      expect(datasetDisplayName('unknown-table', 'english'), 'unknown-table');
    },
  );

  test(
    'metadata accepts public envelope and localizes labels independently',
    () {
      final parsed = DatasetMetadata.fromJson({
        'datasetId': 'parables',
        'revision': 'revision-2',
        'source': {'filename': 'Synthetic fixture.csv'},
        'metadata': {
          'languages': ['english', 'arabic'],
          'hasTypes': true,
          'itemCount': 7,
          'types': [
            {
              'id': 'parable',
              'labels': {'english': 'Parable', 'arabic': 'الأمثال'},
              'order': 2,
              'count': 4,
            },
            {
              'id': 'other',
              'labels': {'english': 'Preserved source classification'},
              'count': 3,
            },
          ],
        },
      });
      expect(parsed.datasetId, 'parables');
      expect(parsed.revision, 'revision-2');
      expect(parsed.languages, ['english', 'arabic']);
      expect(parsed.hasTypes, isTrue);
      expect(parsed.itemCount, 7);
      expect(parsed.typeForId('parable')!.count, 4);
      expect(parsed.typeLabel('parable', 'arabic'), 'الأمثال');
      expect(
        parsed.typeLabel('other', 'arabic'),
        'Preserved source classification',
      );
      expect(
        parsed.typeLabel('missing-metadata', 'arabic'),
        'missing-metadata',
      );
      expect(parsed.typeLabel(null, 'arabic'), 'غير مصنف');
      expect(parsed.source['filename'], 'Synthetic fixture.csv');
      expect(
        parsed.cacheKeyForLanguage('arabic'),
        'parables:revision-2:arabic',
      );
      expect(
        parsed
            .withTypeLabels({'other': 'نوع موثق'}, language: 'arabic')
            .typeLabel('other', 'arabic'),
        'نوع موثق',
      );
      expect(
        parsed.typeLabel('other', 'arabic'),
        'Preserved source classification',
      );
    },
  );

  test(
    'known source labels have bundled Arabic translations without ID changes',
    () {
      expect(metadata.typeLabel('parable', 'arabic'), 'مثل');
      expect(metadata.typeLabel('figure-of-speech', 'arabic'), 'تعبير مجازي');
      expect(metadata.typeForId('parable')!.id, 'parable');
      expect(
        const DatasetType(id: 'parable').label('arabic'),
        'parable',
        reason: 'An ID alone does not invent a source display classification.',
      );
    },
  );

  test('missing Type metadata keeps ordinary table view and every item', () {
    final parsed = DatasetMetadata.fromJson({
      'datasetId': 'miracles',
      'metadata': {
        'itemCount': 4,
        'languages': ['english'],
      },
    });
    expect(parsed.hasTypes, isFalse);
    expect(parsed.types, isEmpty);
    const view = DatasetViewState(datasetId: 'miracles');
    expect(view.mode, DatasetViewMode.table);
    expect(
      fixtureItems.where((item) => view.matchesType(item.typeId)),
      hasLength(fixtureItems.length),
    );
  });

  test(
    'Type selection uses source IDs, OR within Types and AND with Gospels',
    () {
      const view = DatasetViewState(
        datasetId: 'parables',
        selectedTypeIds: {'parable', 'figure-of-speech'},
      );
      final gospelFilter = GospelFilterState(
        mode: GospelFilterMode.union,
        includeMask: Gospel.mark.bit | Gospel.luke.bit,
        excludeMask: Gospel.john.bit,
      );
      final matches = fixtureItems
          .where(
            (item) =>
                view.matchesType(item.typeId) &&
                gospelFilter.matchesPresenceMask(item.mask),
          )
          .toList();
      expect(matches.map((item) => item.id), ['8', '3', '4']);
      final intersection = gospelFilter.copyWith(
        mode: GospelFilterMode.intersection,
      );
      expect(
        matches
            .where((item) => intersection.matchesPresenceMask(item.mask))
            .map((item) => item.id),
        ['8'],
      );
      expect(view.matchesType('Parable'), isFalse);
      expect(view.matchesType('مثل'), isFalse);
      final cleared = view.copyWith(selectedTypeIds: {});
      expect(cleared.matchesType('new-source-type'), isTrue);
      expect(gospelFilter.excludeMask, Gospel.john.bit);
      expect(
        const DatasetViewState(
          selectedTypeIds: {unclassifiedTypeId},
        ).matchesType(null),
        isTrue,
      );
    },
  );

  test(
    'view query round trips without changing Bible or Gospel preferences',
    () {
      const view = DatasetViewState(
        datasetId: 'parables',
        mode: DatasetViewMode.grouped,
        selectedTypeIds: {'parable', 'figure-of-speech', unclassifiedTypeId},
      );
      final uri = Uri(
        path: '/topics',
        queryParameters: {
          'bibleLanguage': 'english',
          'version': 'KJV',
          'topicLanguage': 'arabic',
          'include': 'mark,luke',
          ...view.toQueryParameters(),
        },
      );
      final restored = DatasetViewState.fromQueryParameters(
        uri.queryParameters,
      );
      expect(restored, view);
      expect(restored.hashCode, view.hashCode);
      expect(uri.queryParameters['bibleLanguage'], 'english');
      expect(uri.queryParameters['version'], 'KJV');
      expect(uri.queryParameters['topicLanguage'], 'arabic');
      expect(uri.queryParameters['include'], 'mark,luke');
      expect(
        restored.toQueryParameters()['types'],
        '__unclassified__,figure-of-speech,parable',
      );
      final states = {
        'parables': restored,
        'miracles': const DatasetViewState(datasetId: 'miracles'),
      };
      expect(states['miracles']!.selectedTypeIds, isEmpty);
      expect(states['parables'], view);
    },
  );

  test(
    'grouping uses metadata order, preserves sorted items and counts duplicates',
    () {
      final groups = groupDatasetItems(
        fixtureItems,
        typeIdOf: (item) => item.typeId,
        metadata: metadata,
      );
      expect(groups.map((group) => group.typeId), [
        'figure-of-speech',
        'parable',
        'new-source-type',
        unclassifiedTypeId,
      ]);
      expect(groups[1].items.map((item) => item.id), ['8', '3', '6']);
      expect(
        groups.map((group) => group.count).reduce((a, b) => a + b),
        fixtureItems.length,
      );
      expect(
        groups.expand((group) => group.items).map((item) => item.id).toSet(),
        fixtureItems.map((item) => item.id).toSet(),
      );
      // Collapse state belongs to the renderer and cannot alter group membership.
      final collapsed = {groups.first.typeId};
      expect(collapsed, isNotEmpty);
      expect(
        groups.expand((group) => group.items),
        hasLength(fixtureItems.length),
      );
    },
  );

  test(
    'group ordering without metadata is deterministic and unclassified last',
    () {
      final groups = groupDatasetItems(
        fixtureItems.reversed,
        typeIdOf: (item) => item.typeId,
        metadata: const DatasetMetadata(datasetId: 'parables'),
      );
      expect(groups.map((group) => group.typeId), [
        'figure-of-speech',
        'new-source-type',
        'parable',
        unclassifiedTypeId,
      ]);
      expect(groups[2].items.map((item) => item.id), ['6', '3', '8']);
    },
  );

  test(
    'visible-column removal happens before grouping and preserves matching totals',
    () {
      const view = DatasetViewState(
        selectedTypeIds: {'parable', 'figure-of-speech'},
      );
      final visible = ColumnVisibilityState(visibleMask: Gospel.mark.bit);
      final matching = fixtureItems
          .where(
            (item) =>
                view.matchesType(item.typeId) &&
                item.mask & visible.visibleMask != 0,
          )
          .toList();
      final groups = groupDatasetItems(
        matching,
        typeIdOf: (item) => item.typeId,
        metadata: metadata,
      );
      expect(matching.map((item) => item.id), ['8', '3']);
      expect(groups.single.count, 2);
      expect(groups.single.items.map((item) => item.id), ['8', '3']);
    },
  );

  test('dataset controls localize separately from stable identifiers', () {
    expect(datasetDisplayName('parables', 'arabic'), 'الأمثال');
    expect(datasetDisplayName('miracles', 'english'), 'Miracles');
    expect(datasetControlLabel('type', 'arabic'), 'النوع');
    expect(datasetControlLabel('groupByType', 'arabic'), 'تجميع حسب النوع');
    expect(datasetControlLabel('unclassified', 'english'), 'Unclassified');
  });
}
