// Browser-only regression for native history and refreshable dataset URLs.
// ignore_for_file: deprecated_member_use
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'package:flutter_test/flutter_test.dart';
import 'package:gospel_frontend/browser_route_link.dart';
import 'package:gospel_frontend/gospel_filter.dart';
import 'package:gospel_frontend/topic_dataset.dart';

void main() {
  testWidgets(
    'browser Back and Forward restore dataset and filter view state',
    (tester) async {
      final original = html.window.location.href;
      final harmony = Uri(
        path: '/',
        queryParameters: {'language': 'english', 'version': 'kjv'},
      );
      final parables = Uri(
        path: '/',
        queryParameters: {
          ...const DatasetViewState(
            datasetId: 'parables',
            mode: DatasetViewMode.grouped,
            selectedTypeIds: {'parable'},
          ).toQueryParameters(),
          ...harmonyViewQueryParameters(
            filter: GospelFilterState(
              mode: GospelFilterMode.union,
              includeMask: Gospel.mark.bit | Gospel.luke.bit,
              excludeMask: Gospel.john.bit,
            ),
            sort: const GospelSortState(),
            columns: const ColumnVisibilityState(),
          ),
          'topicLanguage': 'arabic',
          'menuLanguage': 'arabic',
          'bibleLanguage': 'arabic',
          'language': 'arabic',
          'version': 'Van Dyke-',
        },
      );
      final miracles = Uri(
        path: '/',
        queryParameters: {
          'dataset': 'miracles',
          'language': 'english',
          'version': 'kjv',
        },
      );
      addTearDown(() => html.window.history.replaceState(null, '', original));
      await tester.runAsync(() async {
        BrowserRouteHistory.update(harmony, replace: true);
        BrowserRouteHistory.update(parables);
        BrowserRouteHistory.update(miracles);
        final backward = BrowserRouteHistory.changes.first;
        html.window.history.back();
        final restored = await backward.timeout(const Duration(seconds: 10));
        final state = DatasetViewState.fromQueryParameters(
          restored.queryParameters,
        );
        expect(state.datasetId, 'parables');
        expect(state.mode, DatasetViewMode.grouped);
        expect(state.selectedTypeIds, {'parable'});
        expect(restored.queryParameters['topicLanguage'], 'arabic');
        expect(restored.queryParameters['bibleLanguage'], 'arabic');
        expect(restored.queryParameters['version'], 'Van Dyke-');
        final gospel = GospelFilterState.fromQueryParameters(
          restored.queryParameters,
        );
        expect(gospel.mode, GospelFilterMode.union);
        expect(gospel.excludeMask, Gospel.john.bit);
        // The actual address is a complete refresh/new-tab entry point.
        final address = Uri.parse(html.window.location.href);
        final reloaded = address.fragment.startsWith('/')
            ? Uri.parse(address.fragment)
            : address;
        expect(
          DatasetViewState.fromQueryParameters(reloaded.queryParameters),
          state,
        );
        final forward = BrowserRouteHistory.changes.first;
        html.window.history.forward();
        expect(
          DatasetViewState.fromQueryParameters(
            (await forward.timeout(
              const Duration(seconds: 10),
            )).queryParameters,
          ).datasetId,
          'miracles',
        );
      });
    },
  );

  testWidgets(
    'custom fourth table survives native Back Forward and a refreshed URL',
    (tester) async {
      final original = html.window.location.href;
      final tableState = DatasetViewState(
        datasetId: 'journeys',
        mode: DatasetViewMode.grouped,
        selectedTypeIds: const {'teaching', 'journey'},
      );
      final table = Uri(
        path: '/topics',
        queryParameters: {
          ...tableState.toQueryParameters(),
          ...harmonyViewQueryParameters(
            filter: GospelFilterState(
              mode: GospelFilterMode.union,
              includeMask: Gospel.mark.bit | Gospel.luke.bit,
              excludeMask: Gospel.john.bit,
            ),
            sort: const GospelSortState(),
            columns: const ColumnVisibilityState(),
          ),
          'tableLocale': 'arabic',
          'bibleLanguage': 'french',
          'language': 'french',
          'version': 'fixture-french',
        },
      );
      final topic = Uri(
        path: '/topic',
        queryParameters: {...table.queryParameters, 'topicId': '1'},
      );
      addTearDown(() => html.window.history.replaceState(null, '', original));
      await tester.runAsync(() async {
        BrowserRouteHistory.update(Uri(path: '/'), replace: true);
        BrowserRouteHistory.update(table);
        BrowserRouteHistory.update(topic);
        final backward = BrowserRouteHistory.changes.first;
        html.window.history.back();
        final restored = await backward.timeout(const Duration(seconds: 10));
        expect(restored.path, '/topics');
        expect(restored.queryParameters['tableLocale'], 'arabic');
        expect(
          DatasetViewState.fromQueryParameters(restored.queryParameters),
          tableState,
        );
        expect(restored.queryParameters['bibleLanguage'], 'french');
        expect(restored.queryParameters['version'], 'fixture-french');
        final filter = GospelFilterState.fromQueryParameters(
          restored.queryParameters,
        );
        expect(filter.includeMask, Gospel.mark.bit | Gospel.luke.bit);
        expect(filter.excludeMask, Gospel.john.bit);
        final address = Uri.parse(html.window.location.href);
        final refreshed = address.fragment.startsWith('/')
            ? Uri.parse(address.fragment)
            : address;
        expect(
          DatasetViewState.fromQueryParameters(refreshed.queryParameters),
          tableState,
        );
        expect(refreshed.queryParameters['dataset'], 'journeys');
        final forward = BrowserRouteHistory.changes.first;
        html.window.history.forward();
        final restoredTopic = await forward.timeout(
          const Duration(seconds: 10),
        );
        expect(restoredTopic.path, '/topic');
        expect(restoredTopic.queryParameters['dataset'], 'journeys');
        expect(restoredTopic.queryParameters['topicId'], '1');
        expect(
          datasetItemKey(restoredTopic.queryParameters['dataset']!, '1'),
          'journeys:1',
        );
        expect(restoredTopic.queryParameters['version'], 'fixture-french');
        expect(
          DatasetViewState.fromQueryParameters(restoredTopic.queryParameters),
          tableState,
        );
      });
    },
  );
}
