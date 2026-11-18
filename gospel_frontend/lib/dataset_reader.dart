part of 'main.dart';

const _datasetViewKeys = <String>{
  'dataset',
  'view',
  'types',
  'filter',
  'filterMode',
  'include',
  'exclude',
  'sort',
  'columns',
};

/// Carries the live table state into links before it is committed to history.
class DatasetNavigationScope extends InheritedWidget {
  const DatasetNavigationScope({
    super.key,
    required this.query,
    required super.child,
  });
  final Map<String, String> query;
  @override
  bool updateShouldNotify(DatasetNavigationScope oldWidget) =>
      !mapEquals(query, oldWidget.query);
}

Map<String, String> _datasetRouteParameters(
  BuildContext? context, {
  String? datasetId,
}) {
  final scope = context
      ?.dependOnInheritedWidgetOfExactType<DatasetNavigationScope>();
  final route = context == null ? null : ModalRoute.of(context)?.settings.name;
  final routeName = (route ?? '/').replaceFirst(RegExp(r'^/?#'), '');
  final uri = Uri.tryParse(routeName);
  final source =
      scope?.query ?? uri?.queryParameters ?? const <String, String>{};
  final result = <String, String>{
    for (final entry in source.entries)
      if (_datasetViewKeys.contains(entry.key)) entry.key: entry.value,
  };
  final id = normalizeDatasetId(datasetId ?? source['dataset']);
  if (id == 'harmony') {
    result.remove('dataset');
  } else {
    result['dataset'] = id;
  }
  return result;
}

class DatasetSelector extends StatelessWidget {
  const DatasetSelector({
    super.key,
    required this.datasetId,
    required this.language,
    required this.onChanged,
    this.catalog = builtinDatasetCatalog,
  });
  final List<DatasetCatalogEntry> catalog;
  final String datasetId;
  final String language;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final entries = <String, DatasetCatalogEntry>{
        for (final entry in catalog) entry.datasetId: entry,
      };
      // A bookmarked table may load before its catalog request completes.
      entries.putIfAbsent(
        datasetId,
        () => DatasetCatalogEntry(datasetId: datasetId),
      );
      if (constraints.maxWidth < 560 || entries.length > 3) {
        return Align(
          alignment: AlignmentDirectional.centerStart,
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: DropdownButtonFormField<String>(
              key: const ValueKey('dataset-selector-dropdown'),
              initialValue: datasetId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: datasetControlLabel('dataset', language),
                isDense: true,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              items: [
                for (final entry in entries.values)
                  DropdownMenuItem(
                    value: entry.datasetId,
                    child: Text(
                      entry.label(language),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (id) {
                if (id != null) onChanged(id);
              },
            ),
          ),
        );
      }
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: SegmentedButton<String>(
          key: const ValueKey('dataset-selector-tabs'),
          showSelectedIcon: false,
          segments: [
            for (final entry in entries.values)
              ButtonSegment(
                value: entry.datasetId,
                label: Text(entry.label(language)),
              ),
          ],
          selected: {datasetId},
          onSelectionChanged: (ids) => onChanged(ids.single),
        ),
      );
    },
  );
}
