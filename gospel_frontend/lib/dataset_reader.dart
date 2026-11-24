part of 'main.dart';

const _datasetViewKeys = <String>{
  'dataset',
  'tableLocale',
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

/// Keeps the table and its scrollable controls usable even in phone landscape.
class _DatasetWorkspace extends StatelessWidget {
  const _DatasetWorkspace({
    required this.header,
    required this.selector,
    required this.toolbar,
    required this.body,
    this.catalogRetry,
  });

  final Widget header;
  final Widget selector;
  final Widget toolbar;
  final Widget body;
  final Widget? catalogRetry;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final short = constraints.maxHeight < 420;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: constraints.maxHeight * .55),
            child: SingleChildScrollView(
              primary: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!short) header,
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: ResponsiveContentShell(
                      maxWidth: _maxHarmonyTableWidth,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          selector,
                          if (catalogRetry != null) catalogRetry!,
                        ],
                      ),
                    ),
                  ),
                  toolbar,
                ],
              ),
            ),
          ),
          Expanded(child: body),
        ],
      );
    },
  );
}

class _DatasetBanner extends StatelessWidget {
  const _DatasetBanner({required this.title, required this.description});
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < StudyTheme.compact;
      final theme = Theme.of(context);
      return ColoredBox(
        color: StudyTheme.ivory,
        child: Stack(
          children: [
            PositionedDirectional(
              top: 0,
              bottom: 0,
              end: 0,
              width: (constraints.maxWidth * (compact ? .43 : .54))
                  .ceilToDouble(),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  StudyPhoto(
                    compact: compact,
                    alignment: const Alignment(.3, -.22),
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: AlignmentDirectional.centerStart,
                        end: AlignmentDirectional.centerEnd,
                        colors: [StudyTheme.ivory, Color(0x00FFFAF3)],
                        stops: [0, .49],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ResponsiveContentShell(
              maxWidth: _maxHarmonyTableWidth,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: FractionallySizedBox(
                  widthFactor: compact ? .64 : .52,
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: compact ? 16 : 22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            title,
                            style:
                                (compact
                                        ? theme.textTheme.headlineSmall
                                        : theme.textTheme.displaySmall)
                                    ?.copyWith(
                                      color: StudyTheme.plum,
                                      fontFamily: StudyTheme.serif,
                                    ),
                          ),
                        ),
                        if (!compact) ...[
                          const SizedBox(height: 6),
                          Text(
                            description,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: StudyTheme.muted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _TableStatus extends StatelessWidget {
  const _TableStatus({required this.icon, required this.message, this.action});

  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      primary: false,
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: StudyTheme.plum, size: 30),
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          if (action != null) action!,
        ],
      ),
    ),
  );
}
