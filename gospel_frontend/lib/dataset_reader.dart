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
  });
  final String datasetId;
  final String language;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 560) {
        return DropdownButtonFormField<String>(
          key: const ValueKey('dataset-selector-dropdown'),
          initialValue: datasetId,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: language == 'arabic' ? 'الجدول' : 'Table',
            isDense: true,
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
          ),
          items: [
            for (final id in topicDatasetIds)
              DropdownMenuItem(
                value: id,
                child: Text(datasetDisplayName(id, language)),
              ),
          ],
          onChanged: (id) {
            if (id != null) onChanged(id);
          },
        );
      }
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: SegmentedButton<String>(
          key: const ValueKey('dataset-selector-tabs'),
          showSelectedIcon: false,
          segments: [
            for (final id in topicDatasetIds)
              ButtonSegment(
                value: id,
                label: Text(datasetDisplayName(id, language)),
              ),
          ],
          selected: {datasetId},
          onSelectionChanged: (ids) => onChanged(ids.single),
        ),
      );
    },
  );
}
