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
          'bibleLanguage': 'english',
          'language': 'english',
          'version': 'kjv',
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
        expect(restored.queryParameters['bibleLanguage'], 'english');
        expect(restored.queryParameters['version'], 'kjv');
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
}
