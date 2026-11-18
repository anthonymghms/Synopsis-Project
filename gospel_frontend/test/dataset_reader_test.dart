import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gospel_frontend/account_access.dart';
import 'package:gospel_frontend/browser_route_link.dart';
import 'package:gospel_frontend/catalog_events.dart';
import 'package:gospel_frontend/gospel_filter.dart';
import 'package:gospel_frontend/main.dart';
import 'package:gospel_frontend/reference_model.dart';
import 'package:gospel_frontend/topic_dataset.dart';
import 'package:gospel_frontend/topic_language_catalog.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// Synthetic fixtures deliberately include duplicate names and colliding IDs
// between datasets. They make no claim about the production CSV contents.
const _metadata = DatasetMetadata(
  datasetId: 'parables',
  revision: 'synthetic-1',
  hasTypes: true,
  types: [
    DatasetType(
      id: 'figure-of-speech',
      labels: {'english': 'Figure of Speech'},
      order: 1,
    ),
    DatasetType(id: 'parable', labels: {'english': 'Parable'}, order: 2),
    DatasetType(
      id: 'custom-type',
      labels: {'english': 'Custom source Type'},
      order: 3,
    ),
  ],
);

Topic _topic(
  String id,
  String type,
  int order,
  Map<String, String> references, {
  String datasetId = 'parables',
  String? name,
}) => Topic.fromJson({
  'id': id,
  'datasetId': datasetId,
  'name': name ?? 'Synthetic $id',
  'typeId': type,
  'sourceNumber': '${40 + int.parse(id)}',
  'canonicalOrder': order,
  'referenceCells': [
    for (final entry in references.entries)
      HarmonyReferenceCell.parse(entry.value, book: entry.key).toJson(),
  ],
});

List<Topic> _topics() => [
  _topic('1', 'parable', 3, {
    'Mark': '5:1',
    'Luke': '8:1 + 9:1, 3; 10:4',
  }, name: 'Duplicate subject'),
  _topic('2', 'parable', 1, {
    'Mark': '1:1',
    'Luke': '2:1',
  }, name: 'Duplicate subject'),
  _topic('3', 'figure-of-speech', 2, {'Luke': '3:1'}),
  _topic('4', 'parable', 4, {'Luke': '4:1', 'John': '1:1'}),
  _topic('5', '', 5, {'Matthew': '1:1'}),
  _topic('6', 'custom-type', 6, {'Luke': '6:1'}),
];

HarmonyTopicProcessingResult _process(
  List<Topic> topics, {
  Set<String> types = const {},
  GospelFilterState filter = const GospelFilterState(),
  GospelSortState sort = const GospelSortState(),
  ColumnVisibilityState columns = const ColumnVisibilityState(),
}) =>
    processHarmonyTopics(topics, filter, sort, columns, selectedTypeIds: types);

List<BrowserRouteLink> _links(WidgetTester tester, String path) => tester
    .widgetList<BrowserRouteLink>(find.byType(BrowserRouteLink))
    .where((link) => link.uri?.path == path)
    .toList();

Widget _tableHost(
  List<Topic> topics, {
  bool grouped = false,
  TopicLanguageOption? topicLanguage,
  DatasetMetadata metadata = _metadata,
  Map<String, String> query = const {},
}) => MaterialApp(
  home: Scaffold(
    body: DatasetNavigationScope(
      query: query,
      child: HarmonyTable(
        topics: topics,
        metadata: metadata,
        groupedByType: grouped,
        languageOption: kBaseLanguageOptions.first,
        topicLanguage: topicLanguage ?? bundledTopicLanguages.first,
        apiVersion: 'kjv',
      ),
    ),
  ),
);

void main() {
  test(
    'canonical metadata and localized names retain dataset-specific references',
    () {
      final parable = _topics().first;
      final localized = parable.copyWithName('اسم تجريبي');
      final harmony = _topic('1', '', 1, {'John': '7:1'}, datasetId: 'harmony');
      final miracle = _topic('1', 'healing', 1, {
        'Matthew': '9:1',
      }, datasetId: 'miracles');
      expect({
        for (final topic in [harmony, miracle, localized])
          datasetItemKey(topic.datasetId, topic.id),
      }, hasLength(3));
      expect(localized.id, '1');
      expect(localized.typeId, 'parable');
      expect(localized.sourceNumber, '41');
      expect(localized.canonicalOrder, 3);
      expect(identical(localized.references, parable.references), isTrue);
      expect(harmony.references.single.book, 'John');
      expect(miracle.references.single.book, 'Matthew');
      expect(localized.references.first.book, 'Mark');
    },
  );

  test('Type OR combines with Gospel Union, Intersection and Exclusion', () {
    final filter = GospelFilterState(
      mode: GospelFilterMode.union,
      includeMask: Gospel.mark.bit | Gospel.luke.bit,
      excludeMask: Gospel.john.bit,
    );
    final union = _process(
      _topics(),
      types: {'parable', 'figure-of-speech'},
      filter: filter,
    );
    expect(union.topics.map((topic) => topic.id), ['2', '3', '1']);
    expect(union.sourceIndexes, [1, 2, 0]);
    expect(union.visibleTopicCount, 3);
    expect(union.visibleReferenceCount, 7);
    final intersection = _process(
      _topics(),
      types: {'parable', 'figure-of-speech'},
      filter: filter.copyWith(mode: GospelFilterMode.intersection),
    );
    expect(intersection.topics.map((topic) => topic.id), ['2', '1']);
    expect(intersection.visibleReferenceCount, 6);
    final typesOnly = _process(
      _topics(),
      types: {'figure-of-speech', 'custom-type'},
    );
    expect(typesOnly.topics.map((topic) => topic.id), ['3', '6']);
  });

  test(
    'clearing Types restores all classifications without clearing Gospel filters',
    () {
      final filter = GospelFilterState(
        includeMask: Gospel.luke.bit,
        excludeMask: Gospel.john.bit,
      );
      final selected = _process(_topics(), types: {'parable'}, filter: filter);
      final cleared = _process(_topics(), filter: filter);
      expect(selected.topics.map((topic) => topic.id), ['2', '1']);
      expect(cleared.topics.map((topic) => topic.id), ['2', '3', '1', '6']);
      expect(
        _process(_topics(), types: {unclassifiedTypeId}).topics.single.id,
        '5',
      );
      expect(_process(_topics(), types: {'custom-type'}).topics.single.id, '6');
    },
  );

  test(
    'visible columns prune empty rows and count logical selections using shared grammar',
    () {
      final all = _process(_topics());
      expect(all.visibleTopicCount, 6);
      expect(all.visibleReferenceCount, 11);
      final mark = _process(
        _topics(),
        columns: ColumnVisibilityState(visibleMask: Gospel.mark.bit),
      );
      expect(mark.topics.map((topic) => topic.id), ['2', '1']);
      expect(mark.visibleReferenceCount, 2);
      final luke = _process([
        _topics().first,
      ], columns: ColumnVisibilityState(visibleMask: Gospel.luke.bit));
      expect(
        luke.visibleReferenceCount,
        3,
        reason:
            '+ is continuous; comma and semicolon retain separate selections.',
      );
      expect(
        luke.topics.single.references.where(
          (reference) => reference.book == 'Luke',
        ),
        hasLength(4),
      );
    },
  );

  test(
    'flat and grouped exports have identical matching items and Type counts',
    () {
      final result = _process(_topics());
      final flat = buildTopicsTableDocument(
        topics: result.topics,
        sourceIndexes: result.sourceIndexes,
        topicLanguage: bundledTopicLanguages.first,
        visibleGospels: Gospel.values,
        title: 'Synthetic Parables',
        metadata: _metadata,
      );
      final grouped = buildTopicsTableDocument(
        topics: result.topics,
        sourceIndexes: result.sourceIndexes,
        topicLanguage: bundledTopicLanguages.first,
        visibleGospels: Gospel.values,
        title: 'Synthetic Parables',
        metadata: _metadata,
        grouped: true,
      );
      expect(flat.headers, [
        '#',
        'Subjects',
        'Type',
        'Matthew',
        'Mark',
        'Luke',
        'John',
      ]);
      expect(
        grouped.rows.map(jsonEncode).toSet(),
        flat.rows.map(jsonEncode).toSet(),
      );
      expect(grouped.rows, hasLength(6));
      expect(grouped.groups.map((group) => group.count), [1, 3, 1, 1]);
      expect(
        grouped.groups.map((group) => group.count).reduce((a, b) => a + b),
        result.visibleTopicCount,
      );
      expect(grouped.groups[1].rows.map((row) => row.take(2).toList()), [
        ['42', 'Duplicate subject'],
        ['41', 'Duplicate subject'],
        ['44', 'Synthetic 4'],
      ]);
      expect(grouped.groups.last.label, 'Unclassified');
      expect(grouped.toPrintHtml(), contains('Parable — 3'));
      expect(grouped.toCsv().split('\r\n'), hasLength(8));
    },
  );

  test(
    'Gospel sorting is preserved within Type groups and differs from source order',
    () {
      final result = _process(
        _topics(),
        sort: const GospelSortState(mode: TopicSortMode.luke),
      );
      final groups = groupDatasetItems(
        result.topics,
        typeIdOf: (topic) => topic.typeId,
        metadata: _metadata,
      );
      expect(
        groups
            .firstWhere((group) => group.typeId == 'parable')
            .items
            .map((topic) => topic.id),
        ['2', '4', '1'],
      );
      expect(
        groups.expand((group) => group.items),
        hasLength(result.visibleTopicCount),
      );
      expect(
        countVisibleReferences(
          groups.expand((group) => group.items),
          const ColumnVisibilityState(),
        ),
        result.visibleReferenceCount,
      );
    },
  );

  test(
    'Harmony remains an ordinary table with its original IDs and no Type column',
    () {
      final harmony = _topic('1', '', 1, {'John': '7:1'}, datasetId: 'harmony');
      final result = _process([harmony]);
      final document = buildTopicsTableDocument(
        topics: result.topics,
        topicLanguage: bundledTopicLanguages.first,
        visibleGospels: [Gospel.john],
        title: 'Harmony',
      );
      expect(document.headers, ['#', 'Subjects', 'John']);
      expect(document.rows.single.take(2), ['41', 'Synthetic 1']);
      expect(document.groups, isEmpty);
      expect(result.visibleTopicCount, 1);
      expect(result.visibleReferenceCount, 1);
    },
  );

  testWidgets(
    'dataset selector reuses table without colliding item IDs or changing Bible choice',
    (tester) async {
      var dataset = 'harmony';
      const bibleVersion = 'kjv';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => Column(
                children: [
                  DatasetSelector(
                    datasetId: dataset,
                    language: 'english',
                    onChanged: (value) => setState(() => dataset = value),
                  ),
                  Expanded(
                    child: HarmonyTable(
                      metadata: DatasetMetadata(datasetId: dataset),
                      topics: [
                        _topic(
                          '1',
                          '',
                          1,
                          {'Luke': '1:1'},
                          datasetId: dataset,
                          name: 'Subject from $dataset',
                        ),
                      ],
                      languageOption: kBaseLanguageOptions.first,
                      topicLanguage: bundledTopicLanguages.first,
                      apiVersion: bibleVersion,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey('dataset-selector-tabs')),
        findsOneWidget,
      );
      for (final id in ['parables', 'miracles', 'harmony']) {
        await tester.tap(find.text(datasetDisplayName(id, 'english')));
        await tester.pumpAndSettle();
        expect(find.text('Subject from $id'), findsOneWidget);
        final link = _links(tester, '/topic').single;
        expect(
          link.uri!.queryParameters['dataset'],
          id == 'harmony' ? isNull : id,
        );
        expect(link.uri!.queryParameters['topicId'], '1');
        expect(link.uri!.queryParameters['version'], bibleVersion);
        expect(link.openInNewTab, isFalse);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'narrow dataset control exposes an Arabic dropdown with active selection',
    (tester) async {
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              child: DatasetSelector(
                datasetId: 'parables',
                language: 'arabic',
                onChanged: (value) => selected = value,
              ),
            ),
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey('dataset-selector-dropdown')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('dataset-selector-tabs')), findsNothing);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('المعجزات').last);
      await tester.pumpAndSettle();
      expect(selected, 'miracles');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'group collapse hides presentation only and preserves export and group totals',
    (tester) async {
      final result = _process(_topics());
      await tester.pumpWidget(_tableHost(result.topics, grouped: true));
      await tester.pumpAndSettle();
      expect(_links(tester, '/topic'), hasLength(6));
      expect(find.text('Parable — 3 items'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('type-group-parable')));
      await tester.pumpAndSettle();
      expect(_links(tester, '/topic'), hasLength(3));
      expect(find.text('Parable — 3 items'), findsOneWidget);
      final exported = buildTopicsTableDocument(
        topics: result.topics,
        topicLanguage: bundledTopicLanguages.first,
        visibleGospels: Gospel.values,
        title: 'Parables',
        metadata: _metadata,
        grouped: true,
      );
      expect(exported.rows, hasLength(6));
      expect(exported.toCsv(), contains('"41","Duplicate subject"'));
      expect(exported.toCsv(), contains('"42","Duplicate subject"'));
      await tester.tap(find.byKey(const ValueKey('collapse-all-types')));
      await tester.pumpAndSettle();
      expect(_links(tester, '/topic'), isEmpty);
      expect(find.text('Parable — 3 items'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('expand-all-types')));
      await tester.pumpAndSettle();
      expect(_links(tester, '/topic'), hasLength(6));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Arabic names and Type labels retain English Bible in topic/reference URLs',
    (tester) async {
      final topics = [_topics().first.copyWithName('موضوع تجريبي')];
      const query = {
        'dataset': 'parables',
        'view': 'grouped',
        'types': 'parable',
        'include': 'mark,luke',
        'filterMode': 'union',
        'exclude': 'john',
        'sort': 'luke',
      };
      await tester.pumpWidget(
        _tableHost(
          topics,
          topicLanguage: bundledTopicLanguages.last,
          query: query,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('موضوع تجريبي'), findsOneWidget);
      expect(find.text('#'), findsOneWidget);
      expect(find.text('٤١'), findsOneWidget);
      expect(find.text('النوع'), findsOneWidget);
      expect(find.text('مثل'), findsOneWidget);
      expect(find.text('لوقا'), findsOneWidget);
      final topicLink = _links(tester, '/topic').single;
      expect(topicLink.openInNewTab, isFalse);
      final referenceLinks = _links(tester, '/reference');
      expect(referenceLinks, hasLength(5));
      for (final link in [topicLink, ...referenceLinks]) {
        final parameters = link.uri!.queryParameters;
        expect(parameters['dataset'], 'parables');
        expect(parameters['topicId'], '1');
        expect(parameters['topicLanguage'], 'arabic');
        expect(parameters['bibleLanguage'], 'english');
        expect(parameters['version'], 'kjv');
        expect(parameters['view'], 'grouped');
        expect(parameters['types'], 'parable');
        expect(parameters['include'], 'mark,luke');
        expect(parameters['exclude'], 'john');
        expect(parameters['sort'], 'luke');
        final reopened = Uri.parse(link.uri.toString());
        expect(
          DatasetViewState.fromQueryParameters(
            reopened.queryParameters,
          ).datasetId,
          'parables',
        );
        expect(resolveReaderLanguages(reopened).bible.code, 'english');
        expect(resolveReaderLanguages(reopened).topic, 'arabic');
      }
      expect(referenceLinks.every((link) => link.openInNewTab), isTrue);
      final combined = tester.widget<ReferenceCellHoverPreview>(
        find.byType(ReferenceCellHoverPreview),
      );
      expect(combined.datasetId, 'parables');
      expect(combined.language, 'english');
      expect(combined.topicLanguage, 'arabic');
      expect(
        combined.references.map((reference) => reference.separatorBefore),
        ['', '+', ',', ';'],
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Type chips update shared matches live and All types keeps Gospel exclusions',
    (tester) async {
      var types = <String>{};
      var filter = GospelFilterState(
        mode: GospelFilterMode.union,
        includeMask: Gospel.mark.bit | Gospel.luke.bit,
        excludeMask: Gospel.john.bit,
      );
      var commits = 0;
      var changes = 0;
      final topics = _topics();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => HarmonyFilterButton(
                filterState: filter,
                uiLanguage: kBaseLanguageOptions.first,
                topics: topics,
                metadata: _metadata,
                selectedTypeIds: types,
                columns: const ColumnVisibilityState(),
                onChanged: (value) => setState(() => filter = value),
                onTypesChanged: (value) => setState(() {
                  types = value;
                  changes++;
                }),
                onInteractionEnd: () => commits++,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text(kBaseLanguageOptions.first.ui.filter));
      await tester.pumpAndSettle();
      final count = find.byKey(const ValueKey('filter-header-count'));
      expect(tester.widget<Text>(count).data, contains('4'));
      await tester.tap(find.byKey(const ValueKey('type-filter-parable')));
      await tester.pumpAndSettle();
      expect(types, {'parable'});
      expect(tester.widget<Text>(count).data, contains('2'));
      expect(
        _process(topics, types: types, filter: filter).visibleTopicCount,
        2,
      );
      await tester.tap(
        find.byKey(const ValueKey('type-filter-figure-of-speech')),
      );
      await tester.pumpAndSettle();
      expect(types, {'parable', 'figure-of-speech'});
      expect(tester.widget<Text>(count).data, contains('3'));
      await tester.tap(find.byKey(const ValueKey('type-filter-all')));
      await tester.pumpAndSettle();
      expect(types, isEmpty);
      expect(filter.excludeMask, Gospel.john.bit);
      expect(filter.includeMask, Gospel.mark.bit | Gospel.luke.bit);
      expect(tester.widget<Text>(count).data, contains('4'));
      final beforeApply = changes;
      await tester.tap(find.byKey(const ValueKey('apply-filter')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('type-filter-all')), findsNothing);
      expect(commits, 1);
      expect(
        changes,
        beforeApply,
        reason: 'Apply commits the live state without processing it again.',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'combined hover reads English verses while preserving dataset in preview links',
    (tester) async {
      final previousAccess = accountAccess;
      final requests = <Uri>[];
      final client = MockClient((request) async {
        if (request.url.path == '/account/access') {
          return http.Response(
            jsonEncode({
              'uid': 'reader',
              'role': 'subscribed',
              'canRead': true,
              'accessStatus': 'active',
            }),
            200,
          );
        }
        expect(request.url.path, '/get_verse');
        requests.add(request.url);
        return http.Response(
          jsonEncode([
            {'verse': 1, 'text': 'Synthetic English verse'},
          ]),
          200,
        );
      });
      accountAccess = AccountAccessController(
        tokenProvider: () async => 'test-token',
        client: client,
      )..beginSession('reader');
      addTearDown(() {
        accountAccess.dispose();
        accountAccess = previousAccess;
        client.close();
      });
      await http.runWithClient(() async {
        await accountAccess.refresh(force: true);
        notifyCatalogChanged();
        await tester.pumpWidget(
          _tableHost(
            [_topics().first],
            topicLanguage: bundledTopicLanguages.last,
            query: {
              'dataset': 'parables',
              'view': 'grouped',
              'types': 'parable',
            },
          ),
        );
        await tester.pumpAndSettle();
        final tableLinks = _links(tester, '/reference').toSet();
        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        await gesture.addPointer(location: Offset.zero);
        await gesture.moveTo(
          tester.getCenter(find.byType(ReferenceCellHoverPreview)),
        );
        await tester.pump(const Duration(milliseconds: 249));
        expect(requests, isEmpty);
        await tester.pump(const Duration(milliseconds: 1));
        await tester.pumpAndSettle();
        expect(requests, hasLength(4));
        expect(
          requests.every((uri) => uri.queryParameters['language'] == 'english'),
          isTrue,
        );
        expect(
          requests.every((uri) => uri.queryParameters['version'] == 'kjv'),
          isTrue,
        );
        expect(
          find.textContaining('Synthetic English verse', findRichText: true),
          findsWidgets,
        );
        final previewLinks = _links(
          tester,
          '/reference',
        ).where((link) => !tableLinks.contains(link)).toList();
        expect(
          previewLinks,
          hasLength(2),
          reason:
              'Semicolon begins a second preview section; plus and comma share the first.',
        );
        for (final link in previewLinks) {
          expect(link.uri!.queryParameters['dataset'], 'parables');
          expect(link.uri!.queryParameters['types'], 'parable');
          expect(link.uri!.queryParameters['topicLanguage'], 'arabic');
          expect(link.uri!.queryParameters['bibleLanguage'], 'english');
        }
        await gesture.moveTo(Offset.zero);
        await tester.pump(const Duration(milliseconds: 200));
        await gesture.removePointer();
        await tester.pumpWidget(const SizedBox());
        accountAccess.clear();
      }, () => client);
    },
  );
}
