/// Dataset identity and presentation state, independent of Bible selection.
const topicDatasetIds = <String>['harmony', 'miracles', 'parables'];

/// A UI-only category for a missing classification, never a guessed Type.
const unclassifiedTypeId = '__unclassified__';

String normalizeDatasetId(String? value) {
  final id = value?.trim().toLowerCase();
  return topicDatasetIds.contains(id) ? id! : 'harmony';
}

String datasetItemKey(String datasetId, String itemId) =>
    '${normalizeDatasetId(datasetId)}:${Uri.encodeComponent(itemId)}';

bool _isArabic(String language) =>
    language.toLowerCase() == 'arabic' || language.toLowerCase() == 'ar';

String datasetDisplayName(String datasetId, String language) {
  final arabic = _isArabic(language);
  return switch (normalizeDatasetId(datasetId)) {
    'miracles' => arabic ? 'المعجزات' : 'Miracles',
    'parables' => arabic ? 'الأمثال' : 'Parables',
    _ => arabic ? 'التوافق / جميع المواضيع' : 'Harmony / All Topics',
  };
}

String datasetControlLabel(String key, String language) {
  final labels = _isArabic(language) ? _arabicLabels : _englishLabels;
  return labels[key] ?? _englishLabels[key] ?? key;
}

const _englishLabels = <String, String>{
  'dataset': 'Table',
  'selectDataset': 'Choose table',
  'type': 'Type',
  'table': 'Table',
  'groupByType': 'Group by Type',
  'allTypes': 'All types',
  'unclassified': 'Unclassified',
  'expandAll': 'Expand all',
  'collapseAll': 'Collapse all',
  'items': 'items',
  'noTypeInformation':
      'Type grouping is available after importing Type values.',
};

const _arabicLabels = <String, String>{
  'dataset': 'الجدول',
  'selectDataset': 'اختر الجدول',
  'type': 'النوع',
  'table': 'جدول',
  'groupByType': 'تجميع حسب النوع',
  'allTypes': 'جميع الأنواع',
  'unclassified': 'غير مصنف',
  'expandAll': 'توسيع الكل',
  'collapseAll': 'طي الكل',
  'items': 'موضوع',
  'noTypeInformation': 'يتاح التجميع حسب النوع بعد استيراد قيم النوع.',
};

String datasetTypeId(String? typeId) {
  final value = typeId?.trim() ?? '';
  return value.isEmpty ? unclassifiedTypeId : value;
}

class DatasetType {
  const DatasetType({
    required this.id,
    this.labels = const {},
    this.order,
    this.count = 0,
  });

  final String id;
  final Map<String, String> labels;
  final int? order;
  final int count;

  factory DatasetType.fromJson(Map<String, dynamic> json) => DatasetType(
    id: (json['id'] ?? '').toString().trim(),
    labels: Map<String, String>.unmodifiable(_stringMap(json['labels'])),
    order: _asInt(json['order']),
    count: _asInt(json['count']) ?? 0,
  );

  /// Missing translations fall back on the same Type's source label, then ID.
  /// The two bundled translations translate explicit labels; they never assign
  /// a classification to an item or change the ID used for matching.
  String label(String language) {
    if (id == unclassifiedTypeId) {
      return datasetControlLabel('unclassified', language);
    }
    final key = _isArabic(language) ? 'arabic' : language.toLowerCase();
    final localized = labels[key] ?? labels[_isArabic(language) ? 'ar' : key];
    if (localized?.trim().isNotEmpty == true) return localized!;
    final english = labels['english'] ?? labels['en'];
    if (_isArabic(language) && english != null) {
      switch (english.trim().toLowerCase()) {
        case 'parable':
          return 'مثل';
        case 'figure of speech':
          return 'تعبير مجازي';
      }
    }
    if (english?.trim().isNotEmpty == true) return english!;
    final languages = labels.keys.toList()..sort();
    for (final key in languages) {
      if (labels[key]?.trim().isNotEmpty == true) return labels[key]!;
    }
    return id;
  }
}

class DatasetMetadata {
  const DatasetMetadata({
    this.datasetId = 'harmony',
    this.revision = '',
    this.types = const [],
    this.hasTypes = false,
    this.languages = const [],
    this.itemCount = 0,
    this.source = const {},
  });

  final String datasetId;
  final String revision;
  final List<DatasetType> types;
  final bool hasTypes;
  final List<String> languages;
  final int itemCount;
  final Map<String, dynamic> source;

  /// Accepts either metadata directly or the public dataset topics envelope.
  factory DatasetMetadata.fromJson(Map<String, dynamic> json) {
    final rawMetadata = json['metadata'];
    final merged = <String, dynamic>{
      ...json,
      if (rawMetadata is Map) ...Map<String, dynamic>.from(rawMetadata),
    };
    final types = <DatasetType>[];
    final seen = <String>{};
    final rawTypes = merged['types'];
    if (rawTypes is List) {
      for (final raw in rawTypes) {
        if (raw is! Map) continue;
        final type = DatasetType.fromJson(Map<String, dynamic>.from(raw));
        if (type.id.isNotEmpty && seen.add(type.id)) types.add(type);
      }
    }
    final rawLanguages = merged['languages'];
    final languages = rawLanguages is List
        ? rawLanguages.map((value) => value.toString()).toList()
        : rawLanguages is Map
        ? rawLanguages.keys.map((value) => value.toString()).toList()
        : <String>[];
    final rawSource = json['source'] ?? merged['source'];
    return DatasetMetadata(
      datasetId: normalizeDatasetId(
        (json['datasetId'] ?? merged['datasetId'])?.toString(),
      ),
      revision: (json['revision'] ?? merged['revision'] ?? '').toString(),
      types: List<DatasetType>.unmodifiable(types),
      hasTypes: merged['hasTypes'] is bool
          ? merged['hasTypes'] as bool
          : types.any((type) => type.id != unclassifiedTypeId),
      languages: List<String>.unmodifiable(languages),
      itemCount: _asInt(merged['itemCount']) ?? 0,
      source: Map<String, dynamic>.unmodifiable(
        rawSource is Map ? Map<String, dynamic>.from(rawSource) : {},
      ),
    );
  }

  DatasetType? typeForId(String? typeId) {
    final id = datasetTypeId(typeId);
    for (final type in types) {
      if (type.id == id) return type;
    }
    return null;
  }

  String typeLabel(String? typeId, String language) =>
      (typeForId(typeId) ?? DatasetType(id: datasetTypeId(typeId))).label(
        language,
      );

  String cacheKeyForLanguage(String language) =>
      '$datasetId:${Uri.encodeComponent(revision)}:${language.toLowerCase()}';

  DatasetMetadata withTypeLabels(
    Map<String, dynamic> labels, {
    required String language,
  }) => DatasetMetadata(
    datasetId: datasetId,
    revision: revision,
    hasTypes: hasTypes,
    languages: languages,
    itemCount: itemCount,
    source: source,
    types: List<DatasetType>.unmodifiable([
      for (final type in types)
        DatasetType(
          id: type.id,
          order: type.order,
          count: type.count,
          labels: Map<String, String>.unmodifiable({
            ...type.labels,
            if (labels[type.id] is String &&
                (labels[type.id] as String).trim().isNotEmpty)
              language.toLowerCase(): (labels[type.id] as String).trim(),
            if (labels[type.id] is Map) ..._stringMap(labels[type.id]),
          }),
        ),
    ]),
  );
}

enum DatasetViewMode { table, grouped }

class DatasetViewState {
  const DatasetViewState({
    this.datasetId = 'harmony',
    this.mode = DatasetViewMode.table,
    this.selectedTypeIds = const {},
  });

  final String datasetId;
  final DatasetViewMode mode;
  final Set<String> selectedTypeIds;

  bool get isGrouped => mode == DatasetViewMode.grouped;
  bool get hasTypeFilter => selectedTypeIds.isNotEmpty;

  bool matchesType(String? typeId) =>
      selectedTypeIds.isEmpty ||
      selectedTypeIds.contains(datasetTypeId(typeId));

  factory DatasetViewState.fromQueryParameters(
    Map<String, String> parameters,
  ) => DatasetViewState(
    datasetId: normalizeDatasetId(parameters['dataset']),
    mode: parameters['view'] == 'grouped'
        ? DatasetViewMode.grouped
        : DatasetViewMode.table,
    selectedTypeIds: Set<String>.unmodifiable(
      (parameters['types'] ?? '')
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty),
    ),
  );

  Map<String, String> toQueryParameters() {
    final orderedTypes = selectedTypeIds.toList()..sort();
    return {
      if (normalizeDatasetId(datasetId) != 'harmony')
        'dataset': normalizeDatasetId(datasetId),
      if (isGrouped) 'view': 'grouped',
      if (orderedTypes.isNotEmpty) 'types': orderedTypes.join(','),
    };
  }

  DatasetViewState copyWith({
    String? datasetId,
    DatasetViewMode? mode,
    Set<String>? selectedTypeIds,
  }) => DatasetViewState(
    datasetId: normalizeDatasetId(datasetId ?? this.datasetId),
    mode: mode ?? this.mode,
    selectedTypeIds: Set<String>.unmodifiable(
      selectedTypeIds ?? this.selectedTypeIds,
    ),
  );

  @override
  bool operator ==(Object other) =>
      other is DatasetViewState &&
      datasetId == other.datasetId &&
      mode == other.mode &&
      selectedTypeIds.length == other.selectedTypeIds.length &&
      selectedTypeIds.containsAll(other.selectedTypeIds);

  @override
  int get hashCode => Object.hash(
    datasetId,
    mode,
    Object.hashAll(selectedTypeIds.toList()..sort()),
  );
}

class DatasetItemGroup<T> {
  const DatasetItemGroup({required this.typeId, required this.items});

  final String typeId;
  final List<T> items;
  int get count => items.length;
}

/// Group after the shared filtering/sorting pipeline. No matching, sorting of
/// items, deduplication, or collapse state is applied here, so totals and source
/// IDs cannot change when the display changes.
List<DatasetItemGroup<T>> groupDatasetItems<T>(
  Iterable<T> items, {
  required String? Function(T item) typeIdOf,
  required DatasetMetadata metadata,
}) {
  final groups = <String, List<T>>{};
  for (final item in items) {
    (groups[datasetTypeId(typeIdOf(item))] ??= []).add(item);
  }
  final typeIds = groups.keys.toList()
    ..sort((first, second) {
      if (first == second) return 0;
      if (first == unclassifiedTypeId) return 1;
      if (second == unclassifiedTypeId) return -1;
      final firstOrder = metadata.typeForId(first)?.order;
      final secondOrder = metadata.typeForId(second)?.order;
      if (firstOrder != null || secondOrder != null) {
        if (firstOrder == null) return 1;
        if (secondOrder == null) return -1;
        final comparison = firstOrder.compareTo(secondOrder);
        if (comparison != 0) return comparison;
      }
      return first.compareTo(second);
    });
  return List<DatasetItemGroup<T>>.unmodifiable([
    for (final typeId in typeIds)
      DatasetItemGroup(
        typeId: typeId,
        items: List<T>.unmodifiable(groups[typeId]!),
      ),
  ]);
}

Map<String, String> _stringMap(dynamic value) => {
  if (value is Map)
    for (final entry in value.entries)
      if (entry.value is String && (entry.value as String).trim().isNotEmpty)
        entry.key.toString().toLowerCase(): (entry.value as String).trim(),
};

int? _asInt(dynamic value) =>
    value is int ? value : int.tryParse(value?.toString() ?? '');
