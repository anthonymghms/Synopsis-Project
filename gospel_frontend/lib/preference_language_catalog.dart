import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class PreferenceVersionOption {
  const PreferenceVersionOption({required this.id, required this.label});

  final String id;
  final String label;
}

class PreferenceLanguageOption {
  const PreferenceLanguageOption({
    required this.code,
    required this.label,
    required this.direction,
    required this.defaultVersion,
    required this.versions,
  });

  final String code;
  final String label;
  final TextDirection direction;
  final String defaultVersion;
  final List<PreferenceVersionOption> versions;

  bool get isRtl => direction == TextDirection.rtl;

  String sanitizeVersion(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isNotEmpty) {
      for (final version in versions) {
        if (version.id.toLowerCase() == normalized ||
            version.label.toLowerCase() == normalized) {
          return version.id;
        }
      }
    }
    return versions.any((version) => version.id == defaultVersion)
        ? defaultVersion
        : (versions.isNotEmpty ? versions.first.id : defaultVersion);
  }

  bool supportsVersion(String value) {
    final normalized = value.trim().toLowerCase();
    return versions.any((version) => version.id.toLowerCase() == normalized);
  }
}

const List<PreferenceLanguageOption> bundledPreferenceLanguages =
    <PreferenceLanguageOption>[
      PreferenceLanguageOption(
        code: 'english',
        label: 'English',
        direction: TextDirection.ltr,
        defaultVersion: 'kjv',
        versions: <PreferenceVersionOption>[
          PreferenceVersionOption(id: 'kjv', label: 'KJV'),
          PreferenceVersionOption(id: 'ASV', label: 'ASV'),
        ],
      ),
      PreferenceLanguageOption(
        code: 'arabic',
        label: 'العربية',
        direction: TextDirection.rtl,
        defaultVersion: 'Van Dyke-',
        versions: <PreferenceVersionOption>[
          PreferenceVersionOption(id: 'Van Dyke-', label: 'البستاني فاندايك'),
          PreferenceVersionOption(
            id: 'New Arabic Version-',
            label: 'كتاب الحياة',
          ),
        ],
      ),
    ];

class PreferenceLanguageCatalog {
  PreferenceLanguageCatalog({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  Future<List<PreferenceLanguageOption>>? _cachedLoad;

  Future<List<PreferenceLanguageOption>> load() async {
    final cached = _cachedLoad;
    if (cached != null) {
      return cached;
    }
    final future = _loadUncached();
    _cachedLoad = future;
    try {
      return await future;
    } catch (_) {
      if (identical(_cachedLoad, future)) {
        _cachedLoad = null;
      }
      rethrow;
    }
  }

  Future<List<PreferenceLanguageOption>> _loadUncached() async {
    final snapshot = await _firestore.collection('bibles').get();
    if (snapshot.docs.isEmpty) {
      return bundledPreferenceLanguages;
    }

    final options = <PreferenceLanguageOption>[];
    for (final document in snapshot.docs) {
      final languageId = document.id.trim();
      if (languageId.isEmpty) {
        continue;
      }
      final code = languageId.toLowerCase();
      final bundled = _bundledFor(code);
      final data = document.data();
      final versionIds = <String>{};
      _collectVersions(data, versionIds);
      const manifestPaths = <List<String>>[
        <String>['versions', 'manifest'],
        <String>['versions', '_index'],
        <String>['metadata', 'versions'],
        <String>['meta', 'versions'],
        <String>['version_manifest', 'index'],
        <String>['version_manifest', 'all'],
      ];
      for (final path in manifestPaths) {
        try {
          final manifest = await document.reference
              .collection(path.first)
              .doc(path.last)
              .get();
          if (manifest.exists) {
            _collectVersions(
              manifest.data() ?? const <String, dynamic>{},
              versionIds,
            );
          }
        } catch (_) {
          // Keep checking the other supported Firestore layouts.
        }
      }
      try {
        final versionsSnapshot = await document.reference
            .collection('versions')
            .get();
        for (final versionDocument in versionsSnapshot.docs) {
          final versionId = versionDocument.id.trim();
          if (versionId.isNotEmpty &&
              versionId != 'manifest' &&
              versionId != '_index') {
            versionIds.add(versionId);
          }
          _collectVersions(versionDocument.data(), versionIds);
        }
      } catch (_) {
        // Some deployments expose versions on the language document only.
      }

      final discovered = versionIds
          .map(
            (id) =>
                PreferenceVersionOption(id: id, label: _versionLabel(code, id)),
          )
          .toList();
      final versions = _selectableVersions(
        code,
        discovered.isNotEmpty
            ? discovered
            : (bundled?.versions ?? const <PreferenceVersionOption>[]),
      );
      if (versions.isEmpty) {
        continue;
      }

      final directionValue = data['direction']?.toString().toLowerCase();
      final direction = directionValue == 'rtl'
          ? TextDirection.rtl
          : directionValue == 'ltr'
          ? TextDirection.ltr
          : (bundled?.direction ?? TextDirection.ltr);
      final requestedDefault =
          data['defaultVersion']?.toString().trim() ??
          bundled?.defaultVersion ??
          versions.first.id;
      final defaultVersion = _sanitizeFrom(versions, requestedDefault);

      options.add(
        PreferenceLanguageOption(
          code: code,
          label: data['label']?.toString().trim().isNotEmpty == true
              ? data['label'].toString().trim()
              : (bundled?.label ?? _titleCase(languageId)),
          direction: direction,
          defaultVersion: defaultVersion,
          versions: versions,
        ),
      );
    }

    options.sort((a, b) {
      final aIndex = _bundledIndex(a.code);
      final bIndex = _bundledIndex(b.code);
      if (aIndex != bIndex) {
        return aIndex.compareTo(bIndex);
      }
      return a.label.toLowerCase().compareTo(b.label.toLowerCase());
    });
    return options.isEmpty ? bundledPreferenceLanguages : options;
  }

  static PreferenceLanguageOption resolve(
    List<PreferenceLanguageOption> options,
    String code,
  ) {
    final normalized = code.trim().toLowerCase();
    return options.firstWhere(
      (option) => option.code.toLowerCase() == normalized,
      orElse: () => options.firstWhere(
        (option) => option.code == 'english',
        orElse: () => options.first,
      ),
    );
  }
}

const List<String> _versionFields = <String>[
  'versions',
  'availableVersions',
  'available_versions',
  'versionList',
  'version_list',
  'supportedVersions',
  'supported_versions',
];

void _collectVersions(Map<String, dynamic> data, Set<String> target) {
  for (final fieldName in _versionFields) {
    final field = data[fieldName];
    if (field is Iterable) {
      for (final value in field) {
        final id = value?.toString().trim() ?? '';
        if (id.isNotEmpty) {
          target.add(id);
        }
      }
    } else if (field is Map) {
      for (final key in field.keys) {
        final id = key.toString().trim();
        if (id.isNotEmpty) {
          target.add(id);
        }
      }
    }
  }
}

List<PreferenceVersionOption> _selectableVersions(
  String language,
  List<PreferenceVersionOption> versions,
) {
  if (language != 'arabic') {
    final copy = List<PreferenceVersionOption>.from(versions);
    copy.sort((a, b) => a.label.compareTo(b.label));
    return copy;
  }

  final byBase = <String, PreferenceVersionOption>{};
  for (final version in versions) {
    final base = version.id.endsWith('-')
        ? version.id.substring(0, version.id.length - 1).trim()
        : version.id.trim();
    final key = base.toLowerCase().replaceAll('dyck', 'dyke');
    final current = byBase[key];
    if (current == null || version.id.endsWith('-')) {
      byBase[key] = PreferenceVersionOption(
        id: version.id,
        label: _versionLabel(language, base),
      );
    }
  }
  final result = byBase.values.toList();
  result.sort((a, b) => a.label.compareTo(b.label));
  return result;
}

String _sanitizeFrom(List<PreferenceVersionOption> versions, String value) {
  final normalized = value.toLowerCase();
  for (final version in versions) {
    if (version.id.toLowerCase() == normalized ||
        version.label.toLowerCase() == normalized) {
      return version.id;
    }
  }
  if (normalized.endsWith('-')) {
    final base = normalized.substring(0, normalized.length - 1);
    for (final version in versions) {
      if (version.id.toLowerCase().replaceFirst(RegExp(r'-$'), '') == base) {
        return version.id;
      }
    }
  }
  return versions.first.id;
}

PreferenceLanguageOption? _bundledFor(String code) {
  for (final option in bundledPreferenceLanguages) {
    if (option.code == code) {
      return option;
    }
  }
  return null;
}

int _bundledIndex(String code) {
  final index = bundledPreferenceLanguages.indexWhere(
    (option) => option.code == code,
  );
  return index < 0 ? bundledPreferenceLanguages.length : index;
}

String _versionLabel(String language, String versionId) {
  final trimmed = versionId.endsWith('-')
      ? versionId.substring(0, versionId.length - 1).trim()
      : versionId.trim();
  if (language == 'arabic') {
    final normalized = trimmed.toLowerCase().replaceAll('dyck', 'dyke');
    if (normalized == 'van dyke') {
      return 'البستاني فاندايك';
    }
    if (normalized == 'new arabic version' || normalized == 'nav') {
      return 'كتاب الحياة';
    }
  }
  return _titleCase(trimmed);
}

String _titleCase(String value) {
  if (value.isEmpty) {
    return value;
  }
  return value.length == 1
      ? value.toUpperCase()
      : '${value[0].toUpperCase()}${value.substring(1)}';
}
