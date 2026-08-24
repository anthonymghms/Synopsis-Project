import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import 'admin_access.dart';
import 'admin_api_client.dart';
import 'catalog_events.dart';
import 'user_profile.dart';

class AdminPortal extends StatefulWidget {
  const AdminPortal({
    super.key,
    required this.apiBaseUrl,
    this.client,
    this.adminCheck,
    this.arabic,
  });

  final String apiBaseUrl;
  final AdminClient? client;
  final Future<bool>? adminCheck;
  final bool? arabic;

  @override
  State<AdminPortal> createState() => _AdminPortalState();
}

class _AdminPortalState extends State<AdminPortal> {
  late final AdminClient _client =
      widget.client ?? AdminApiClient(baseUrl: widget.apiBaseUrl);
  late Future<bool> _adminCheck =
      widget.adminCheck ?? adminAccess.currentUserIsAdmin(forceRefresh: true);
  late Future<Map<String, dynamic>> _overview = _client.getJson(
    '/admin/overview',
  );
  int _section = 0;

  bool get _arabic =>
      widget.arabic ??
      UserProfileController.instance.preferences.menuLanguage == 'arabic';
  _AdminLabels get _labels => _AdminLabels(_arabic);

  void _refresh() {
    setState(() {
      _overview = _client.getJson('/admin/overview');
    });
  }

  void _importCompleted() {
    notifyCatalogChanged();
    _refresh();
  }

  Future<void> _openTopics() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => TopicImportWizard(
        client: _client,
        arabic: _arabic,
        onCompleted: _importCompleted,
      ),
    );
  }

  Future<void> _openBible() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BibleImportWizard(
        client: _client,
        arabic: _arabic,
        onCompleted: _importCompleted,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final labels = _labels;
    return FutureBuilder<bool>(
      future: _adminCheck,
      builder: (context, access) {
        if (access.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (access.data != true) {
          return Scaffold(
            appBar: AppBar(
              leading: const BackButton(),
              title: Text(labels.admin),
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_outline, size: 54),
                    const SizedBox(height: 16),
                    Text(
                      labels.accessDenied,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => setState(() {
                        _adminCheck = adminAccess.currentUserIsAdmin(
                          forceRefresh: true,
                        );
                      }),
                      icon: const Icon(Icons.refresh),
                      label: Text(labels.retry),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return Directionality(
          textDirection: _arabic ? TextDirection.rtl : TextDirection.ltr,
          child: Scaffold(
            appBar: AppBar(
              leading: const BackButton(),
              title: Text(labels.admin),
              actions: [
                IconButton(
                  tooltip: labels.refresh,
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            body: FutureBuilder<Map<String, dynamic>>(
              future: _overview,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _AdminError(
                    message: snapshot.error.toString(),
                    retryLabel: labels.retry,
                    onRetry: _refresh,
                  );
                }
                return _responsivePortal(
                  context,
                  snapshot.data ?? const <String, dynamic>{},
                );
              },
            ),
            bottomNavigationBar: MediaQuery.sizeOf(context).width < 820
                ? NavigationBar(
                    selectedIndex: _section,
                    onDestinationSelected: (value) =>
                        setState(() => _section = value),
                    destinations: _destinations(labels)
                        .map(
                          (item) => NavigationDestination(
                            icon: Icon(item.icon),
                            label: item.label,
                          ),
                        )
                        .toList(),
                  )
                : null,
          ),
        );
      },
    );
  }

  Widget _responsivePortal(
    BuildContext context,
    Map<String, dynamic> overview,
  ) {
    final labels = _labels;
    final content = _sectionContent(overview, labels);
    if (MediaQuery.sizeOf(context).width < 820) return content;
    final destinations = _destinations(labels);
    return Row(
      children: [
        NavigationRail(
          selectedIndex: _section,
          labelType: NavigationRailLabelType.all,
          onDestinationSelected: (value) => setState(() => _section = value),
          destinations: destinations
              .map(
                (item) => NavigationRailDestination(
                  icon: Icon(item.icon),
                  label: Text(item.label),
                ),
              )
              .toList(),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: content),
      ],
    );
  }

  List<_Destination> _destinations(_AdminLabels labels) => [
    _Destination(Icons.dashboard_outlined, labels.dashboard),
    _Destination(Icons.menu_book_outlined, labels.bibles),
    _Destination(Icons.table_chart_outlined, labels.topics),
    _Destination(Icons.history, labels.history),
  ];

  Widget _sectionContent(Map<String, dynamic> overview, _AdminLabels labels) {
    switch (_section) {
      case 1:
        return _BibleList(
          data: _listOfMaps(overview['bibleLanguages']),
          labels: labels,
          onAdd: _openBible,
        );
      case 2:
        return _TopicList(
          data: _listOfMaps(overview['topicLanguages']),
          labels: labels,
          onAdd: _openTopics,
        );
      case 3:
        return _HistoryList(
          data: _listOfMaps(overview['recentImports']),
          labels: labels,
        );
      default:
        return _Dashboard(
          overview: overview,
          labels: labels,
          addBible: _openBible,
          addTopics: _openTopics,
        );
    }
  }
}

class _Destination {
  const _Destination(this.icon, this.label);
  final IconData icon;
  final String label;
}

List<Map<String, dynamic>> _listOfMaps(dynamic value) => value is Iterable
    ? value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList()
    : <Map<String, dynamic>>[];

class _Dashboard extends StatelessWidget {
  const _Dashboard({
    required this.overview,
    required this.labels,
    required this.addBible,
    required this.addTopics,
  });

  final Map<String, dynamic> overview;
  final _AdminLabels labels;
  final VoidCallback addBible;
  final VoidCallback addTopics;

  @override
  Widget build(BuildContext context) {
    final counts = overview['counts'] is Map
        ? Map<String, dynamic>.from(overview['counts'] as Map)
        : const <String, dynamic>{};
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          labels.dashboard,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _CountCard(labels.bibleLanguages, counts['bibleLanguages'] ?? 0),
            _CountCard(labels.bibleVersions, counts['bibleVersions'] ?? 0),
            _CountCard(labels.topicLanguages, counts['topicLanguages'] ?? 0),
            _CountCard(labels.failedImports, counts['failedImports'] ?? 0),
          ],
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              key: const ValueKey<String>('add-bible-translation'),
              onPressed: addBible,
              icon: const Icon(Icons.add),
              label: Text(labels.addBible),
            ),
            FilledButton.tonalIcon(
              key: const ValueKey<String>('add-topic-dataset'),
              onPressed: addTopics,
              icon: const Icon(Icons.add),
              label: Text(labels.addTopics),
            ),
          ],
        ),
        const SizedBox(height: 28),
        Text(
          labels.recentImports,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        _HistoryCards(
          data: _listOfMaps(overview['recentImports']),
          labels: labels,
        ),
      ],
    );
  }
}

class _CountCard extends StatelessWidget {
  const _CountCard(this.label, this.value);
  final String label;
  final dynamic value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 190,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$value', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 4),
            Text(label),
          ],
        ),
      ),
    ),
  );
}

class _BibleList extends StatelessWidget {
  const _BibleList({
    required this.data,
    required this.labels,
    required this.onAdd,
  });
  final List<Map<String, dynamic>> data;
  final _AdminLabels labels;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      _SectionHeader(
        title: labels.bibles,
        action: labels.addBible,
        onAction: onAdd,
      ),
      for (final language in data)
        Card(
          child: ExpansionTile(
            initiallyExpanded: true,
            title: Text(
              language['name']?.toString() ?? language['id'].toString(),
            ),
            subtitle: Text(
              '${_listOfMaps(language['versions']).length} ${labels.versions.toLowerCase()}',
            ),
            children: [
              for (final version in _listOfMaps(language['versions']))
                ListTile(
                  leading: const Icon(Icons.menu_book_outlined),
                  title: Text(
                    version['name']?.toString() ?? version['id'].toString(),
                  ),
                  subtitle: Text(
                    [
                      if (version['books'] != null)
                        '${version['books']} ${labels.books.toLowerCase()}',
                      if (version['verses'] != null)
                        '${version['verses']} ${labels.verses.toLowerCase()}',
                    ].join(' · '),
                  ),
                  trailing: _StatusChip(
                    active: version['active'] != false,
                    labels: labels,
                  ),
                ),
            ],
          ),
        ),
    ],
  );
}

class _TopicList extends StatelessWidget {
  const _TopicList({
    required this.data,
    required this.labels,
    required this.onAdd,
  });
  final List<Map<String, dynamic>> data;
  final _AdminLabels labels;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      _SectionHeader(
        title: labels.topics,
        action: labels.addTopics,
        onAction: onAdd,
      ),
      for (final item in data)
        Card(
          child: ListTile(
            leading: const Icon(Icons.table_chart_outlined),
            title: Text(item['name']?.toString() ?? item['id'].toString()),
            subtitle: Text(
              '${item['topics'] ?? 0} ${labels.topicRecords.toLowerCase()}',
            ),
            trailing: _StatusChip(
              active: item['active'] != false,
              labels: labels,
            ),
          ),
        ),
    ],
  );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.active, required this.labels});
  final bool active;
  final _AdminLabels labels;

  @override
  Widget build(BuildContext context) => Chip(
    avatar: Icon(
      active ? Icons.check_circle_outline : Icons.pause_circle_outline,
      size: 17,
    ),
    label: Text(active ? labels.active : labels.inactive),
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.action,
    required this.onAction,
  });
  final String title;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineMedium),
        FilledButton.icon(
          onPressed: onAction,
          icon: const Icon(Icons.add),
          label: Text(action),
        ),
      ],
    ),
  );
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({required this.data, required this.labels});
  final List<Map<String, dynamic>> data;
  final _AdminLabels labels;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Text(labels.history, style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 16),
      _HistoryCards(data: data, labels: labels),
    ],
  );
}

class _HistoryCards extends StatelessWidget {
  const _HistoryCards({required this.data, required this.labels});
  final List<Map<String, dynamic>> data;
  final _AdminLabels labels;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return Text(labels.noImports);
    return Column(
      children: [
        for (final item in data)
          Card(
            child: ListTile(
              leading: Icon(
                item['type'] == 'bible' ? Icons.menu_book : Icons.table_chart,
              ),
              title: Text(
                item['type'] == 'bible'
                    ? '${item['language']} · ${item['version'] ?? ''}'
                    : item['language']?.toString() ?? '',
              ),
              subtitle: Text(
                '${item['stage'] ?? item['status'] ?? ''}${item['recordsProcessed'] != null ? ' · ${item['recordsProcessed']}' : ''}',
              ),
              trailing: Chip(label: Text(item['status']?.toString() ?? '')),
            ),
          ),
      ],
    );
  }
}

class _AdminError extends StatelessWidget {
  const _AdminError({
    required this.message,
    required this.retryLabel,
    required this.onRetry,
  });
  final String message;
  final String retryLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: Text(retryLabel),
          ),
        ],
      ),
    ),
  );
}

class TopicImportWizard extends StatefulWidget {
  const TopicImportWizard({
    super.key,
    required this.client,
    required this.arabic,
    required this.onCompleted,
    this.initialFile,
  });
  final AdminClient client;
  final bool arabic;
  final VoidCallback onCompleted;
  final AdminUploadFile? initialFile;

  @override
  State<TopicImportWizard> createState() => _TopicImportWizardState();
}

class _TopicImportWizardState extends State<TopicImportWizard> {
  final _formKey = GlobalKey<FormState>();
  final _language = TextEditingController(text: 'english');
  final _displayName = TextEditingController(text: 'English');
  String _direction = 'ltr';
  AdminUploadFile? _file;
  Map<String, dynamic>? _validation;
  Map<String, dynamic>? _progress;
  bool _busy = false;
  bool _replace = false;
  String? _error;

  _AdminLabels get labels => _AdminLabels(widget.arabic);

  @override
  void initState() {
    super.initState();
    _file = widget.initialFile;
  }

  @override
  void dispose() {
    _language.dispose();
    _displayName.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv'],
      withData: true,
    );
    final file = result?.files.singleOrNull;
    if (file?.bytes == null) return;
    setState(() {
      _file = AdminUploadFile(name: file!.name, bytes: file.bytes!);
      _validation = null;
      _progress = null;
      _error = null;
    });
  }

  Future<void> _acceptDroppedFiles(DropDoneDetails details) async {
    final candidates = details.files
        .where((file) => file.name.toLowerCase().endsWith('.csv'))
        .toList();
    if (candidates.isEmpty) {
      setState(() => _error = labels.selectCsv);
      return;
    }
    final file = candidates.first;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() {
      _file = AdminUploadFile(name: file.name, bytes: bytes);
      _validation = null;
      _progress = null;
      _error = null;
    });
  }

  Future<void> _validate() async {
    if (!_formKey.currentState!.validate() || _file == null) {
      setState(() => _error = labels.selectCsv);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final response = await widget.client.upload(
        '/admin/topics/validate',
        fields: <String, String>{
          'language': _language.text.trim(),
          'displayName': _displayName.text.trim(),
          'direction': _direction,
          'canonicalDataset': 'english_kjv',
        },
        files: [_file!],
        fileField: 'file',
      );
      if (mounted) setState(() => _validation = response);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final validation = _validation;
    if (validation == null || validation['valid'] != true) return;
    if (validation['collision'] == true && !_replace) {
      setState(() => _error = labels.replaceRequired);
      return;
    }
    final confirmed = await _confirmImport(
      context,
      labels,
      validation['collision'] == true,
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.client.postJson('/admin/topics/import', <String, dynamic>{
        'importId': validation['importId'],
        'confirm': true,
        'replace': _replace,
      });
      await _poll(validation['importId'].toString());
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _poll(String importId) async {
    while (mounted) {
      final response = await widget.client.getJson('/admin/imports/$importId');
      final record = Map<String, dynamic>.from(response['import'] as Map);
      setState(() => _progress = record);
      final status = record['status']?.toString();
      if (status == 'completed') {
        widget.onCompleted();
        return;
      }
      if (status == 'failed') {
        final errors = _listOfMaps(record['errors']);
        throw AdminApiException(
          errors.isEmpty
              ? labels.importFailed
              : errors.first['message'].toString(),
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 1200));
    }
  }

  @override
  Widget build(BuildContext context) {
    return _WizardDialog(
      title: labels.addTopics,
      closeLabel: labels.close,
      busy: _busy,
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _StepTitle(number: 1, title: labels.language),
            _metadataFields(
              _language,
              _displayName,
              labels,
              (value) => setState(() => _direction = value),
              _direction,
            ),
            const SizedBox(height: 20),
            _StepTitle(number: 2, title: labels.uploadCsv),
            Text(labels.csvFormat),
            const SizedBox(height: 8),
            DropTarget(
              onDragDone: _busy ? null : _acceptDroppedFiles,
              child: _UploadDropSurface(
                message: _file?.name ?? labels.dropCsv,
                buttonLabel: labels.selectCsv,
                onPressed: _busy ? null : _pick,
              ),
            ),
            const SizedBox(height: 20),
            _StepTitle(number: 3, title: labels.validatePreview),
            FilledButton.icon(
              key: const ValueKey<String>('validate-topic-upload'),
              onPressed: _busy ? null : _validate,
              icon: const Icon(Icons.fact_check_outlined),
              label: Text(labels.validate),
            ),
            if (_error != null) _InlineError(_error!),
            if (_validation != null) ...[
              const SizedBox(height: 16),
              _ValidationSummary(data: _validation!, labels: labels),
              _TopicPreview(
                data: _listOfMaps(_validation!['preview']),
                labels: labels,
              ),
              if (_validation!['collision'] == true)
                CheckboxListTile(
                  value: _replace,
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _replace = value == true),
                  title: Text(labels.replaceExisting),
                  subtitle: Text(labels.replaceWarning),
                ),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const ValueKey<String>('import-topic-upload'),
                onPressed: _busy || _validation!['valid'] != true
                    ? null
                    : _import,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: Text(labels.importTopics),
              ),
            ],
            if (_progress != null)
              _ProgressCard(data: _progress!, labels: labels),
          ],
        ),
      ),
    );
  }
}

class BibleImportWizard extends StatefulWidget {
  const BibleImportWizard({
    super.key,
    required this.client,
    required this.arabic,
    required this.onCompleted,
  });
  final AdminClient client;
  final bool arabic;
  final VoidCallback onCompleted;

  @override
  State<BibleImportWizard> createState() => _BibleImportWizardState();
}

class _BibleImportWizardState extends State<BibleImportWizard> {
  final _formKey = GlobalKey<FormState>();
  final _language = TextEditingController(text: 'english');
  final _languageName = TextEditingController(text: 'English');
  final _translation = TextEditingController();
  final _versionId = TextEditingController();
  final _displayName = TextEditingController();
  final _description = TextEditingController();
  final _related = TextEditingController();
  String _direction = 'ltr';
  String _diacritics = 'auto';
  List<AdminUploadFile> _files = [];
  Map<String, dynamic>? _validation;
  Map<String, dynamic>? _progress;
  bool _busy = false;
  bool _replace = false;
  String? _error;

  _AdminLabels get labels => _AdminLabels(widget.arabic);

  @override
  void dispose() {
    for (final controller in [
      _language,
      _languageName,
      _translation,
      _versionId,
      _displayName,
      _description,
      _related,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pick() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['usfm'],
      allowMultiple: true,
      withData: true,
    );
    if (result == null) return;
    final files = result.files
        .where((file) => file.bytes != null)
        .map((file) => AdminUploadFile(name: file.name, bytes: file.bytes!))
        .toList();
    setState(() {
      _files = files;
      _validation = null;
      _progress = null;
      _error = null;
    });
  }

  Future<void> _acceptDroppedFiles(DropDoneDetails details) async {
    final candidates = details.files
        .where((file) => file.name.toLowerCase().endsWith('.usfm'))
        .toList();
    if (candidates.isEmpty) {
      setState(() => _error = labels.selectUsfm);
      return;
    }
    final files = <AdminUploadFile>[];
    for (final file in candidates.take(10)) {
      files.add(
        AdminUploadFile(name: file.name, bytes: await file.readAsBytes()),
      );
    }
    if (!mounted) return;
    setState(() {
      _files = files;
      _validation = null;
      _progress = null;
      _error = null;
    });
  }

  Future<void> _validate() async {
    if (!_formKey.currentState!.validate() || _files.isEmpty) {
      setState(() => _error = labels.selectUsfm);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final response = await widget.client.upload(
        '/admin/bibles/validate',
        fields: <String, String>{
          'language': _language.text.trim(),
          'languageDisplayName': _languageName.text.trim(),
          'direction': _direction,
          'translationName': _translation.text.trim(),
          'versionId': _versionId.text.trim(),
          'versionDisplayName': _displayName.text.trim(),
          'description': _description.text.trim(),
          'relatedTranslation': _related.text.trim(),
          'containsDiacritics': _diacritics,
        },
        files: _files,
        fileField: 'files',
      );
      if (mounted) setState(() => _validation = response);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final validation = _validation;
    if (validation == null || validation['valid'] != true) return;
    if (validation['collision'] == true && !_replace) {
      setState(() => _error = labels.replaceRequired);
      return;
    }
    final confirmed = await _confirmImport(
      context,
      labels,
      validation['collision'] == true,
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.client.postJson('/admin/bibles/import', <String, dynamic>{
        'importId': validation['importId'],
        'confirm': true,
        'replace': _replace,
      });
      await _poll(validation['importId'].toString());
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _poll(String importId) async {
    while (mounted) {
      final response = await widget.client.getJson('/admin/imports/$importId');
      final record = Map<String, dynamic>.from(response['import'] as Map);
      setState(() => _progress = record);
      final status = record['status']?.toString();
      if (status == 'completed') {
        widget.onCompleted();
        return;
      }
      if (status == 'failed') {
        final errors = _listOfMaps(record['errors']);
        throw AdminApiException(
          errors.isEmpty
              ? labels.importFailed
              : errors.first['message'].toString(),
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 1200));
    }
  }

  @override
  Widget build(BuildContext context) {
    return _WizardDialog(
      title: labels.addBible,
      closeLabel: labels.close,
      busy: _busy,
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _StepTitle(number: 1, title: labels.language),
            _metadataFields(
              _language,
              _languageName,
              labels,
              (value) => setState(() => _direction = value),
              _direction,
            ),
            const SizedBox(height: 20),
            _StepTitle(number: 2, title: labels.translationMetadata),
            TextFormField(
              key: const ValueKey<String>('translation-name'),
              controller: _translation,
              decoration: InputDecoration(labelText: labels.translationName),
              validator: (value) => value == null || value.trim().isEmpty
                  ? labels.required
                  : null,
              onChanged: (value) {
                if (_displayName.text.isEmpty) _displayName.text = value;
                if (_versionId.text.isEmpty) {
                  _versionId.text = value
                      .toLowerCase()
                      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
                      .replaceAll(RegExp(r'^_|_$'), '');
                }
              },
            ),
            TextFormField(
              controller: _versionId,
              decoration: InputDecoration(labelText: labels.internalKey),
            ),
            TextFormField(
              controller: _displayName,
              decoration: InputDecoration(labelText: labels.displayName),
            ),
            TextFormField(
              controller: _description,
              maxLines: 2,
              decoration: InputDecoration(labelText: labels.description),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _diacritics,
              decoration: InputDecoration(labelText: labels.diacritics),
              items: [
                DropdownMenuItem(
                  value: 'auto',
                  child: Text(labels.detectAutomatically),
                ),
                DropdownMenuItem(value: 'true', child: Text(labels.yes)),
                DropdownMenuItem(value: 'false', child: Text(labels.no)),
              ],
              onChanged: (value) =>
                  setState(() => _diacritics = value ?? 'auto'),
            ),
            TextFormField(
              controller: _related,
              decoration: InputDecoration(labelText: labels.relatedTranslation),
            ),
            const SizedBox(height: 20),
            _StepTitle(number: 3, title: labels.uploadUsfm),
            Text(labels.usfmFormat),
            const SizedBox(height: 8),
            DropTarget(
              onDragDone: _busy ? null : _acceptDroppedFiles,
              child: _UploadDropSurface(
                message: _files.isEmpty
                    ? labels.dropUsfm
                    : labels.filesSelected(_files.length),
                buttonLabel: labels.selectUsfm,
                onPressed: _busy ? null : _pick,
              ),
            ),
            if (_files.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_files.map((file) => file.name).join(', ')),
              ),
            const SizedBox(height: 20),
            _StepTitle(number: 4, title: labels.validatePreview),
            FilledButton.icon(
              key: const ValueKey<String>('validate-bible-upload'),
              onPressed: _busy ? null : _validate,
              icon: const Icon(Icons.fact_check_outlined),
              label: Text(labels.validate),
            ),
            if (_error != null) _InlineError(_error!),
            if (_validation != null) ...[
              const SizedBox(height: 16),
              _ValidationSummary(data: _validation!, labels: labels),
              _BiblePreview(
                data: _listOfMaps(_validation!['preview']),
                labels: labels,
              ),
              if (_validation!['collision'] == true)
                CheckboxListTile(
                  value: _replace,
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _replace = value == true),
                  title: Text(labels.replaceExisting),
                  subtitle: Text(labels.replaceWarning),
                ),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const ValueKey<String>('import-bible-upload'),
                onPressed: _busy || _validation!['valid'] != true
                    ? null
                    : _import,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: Text(labels.importBible),
              ),
            ],
            if (_progress != null)
              _ProgressCard(data: _progress!, labels: labels),
          ],
        ),
      ),
    );
  }
}

Widget _metadataFields(
  TextEditingController language,
  TextEditingController displayName,
  _AdminLabels labels,
  ValueChanged<String> onDirection,
  String direction,
) => Column(
  children: [
    TextFormField(
      key: const ValueKey<String>('language-code'),
      controller: language,
      decoration: InputDecoration(labelText: labels.languageCode),
      validator: (value) =>
          value == null ||
              !RegExp(r'^[a-z][a-z0-9_-]{1,39}$').hasMatch(value.trim())
          ? labels.invalidLanguageCode
          : null,
    ),
    TextFormField(
      controller: displayName,
      decoration: InputDecoration(labelText: labels.displayName),
      validator: (value) =>
          value == null || value.trim().isEmpty ? labels.required : null,
    ),
    DropdownButtonFormField<String>(
      initialValue: direction,
      decoration: InputDecoration(labelText: labels.direction),
      items: [
        DropdownMenuItem(value: 'ltr', child: Text(labels.ltr)),
        DropdownMenuItem(value: 'rtl', child: Text(labels.rtl)),
      ],
      onChanged: (value) {
        if (value != null) onDirection(value);
      },
    ),
  ],
);

class _WizardDialog extends StatelessWidget {
  const _WizardDialog({
    required this.title,
    required this.closeLabel,
    required this.busy,
    required this.child,
  });
  final String title;
  final String closeLabel;
  final bool busy;
  final Widget child;

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(16),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 920, maxHeight: 820),
      child: Column(
        children: [
          ListTile(
            title: Text(title, style: Theme.of(context).textTheme.titleLarge),
            trailing: IconButton(
              tooltip: closeLabel,
              onPressed: busy ? null : () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close),
            ),
          ),
          const Divider(height: 1),
          Expanded(child: child),
          if (busy) const LinearProgressIndicator(),
        ],
      ),
    ),
  );
}

class _UploadDropSurface extends StatelessWidget {
  const _UploadDropSurface({
    required this.message,
    required this.buttonLabel,
    required this.onPressed,
  });

  final String message;
  final String buttonLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      borderRadius: BorderRadius.circular(12),
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
    ),
    child: Column(
      children: [
        const Icon(Icons.file_upload_outlined, size: 34),
        const SizedBox(height: 8),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: onPressed, child: Text(buttonLabel)),
      ],
    ),
  );
}

class _StepTitle extends StatelessWidget {
  const _StepTitle({required this.number, required this.title});
  final int number;
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        CircleAvatar(radius: 15, child: Text('$number')),
        const SizedBox(width: 10),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
      ],
    ),
  );
}

class _InlineError extends StatelessWidget {
  const _InlineError(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.errorContainer,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const Icon(Icons.error_outline),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
        ],
      ),
    ),
  );
}

class _ValidationSummary extends StatelessWidget {
  const _ValidationSummary({required this.data, required this.labels});
  final Map<String, dynamic> data;
  final _AdminLabels labels;

  @override
  Widget build(BuildContext context) {
    final errors = _listOfMaps(data['errors']);
    final warnings = _listOfMaps(data['warnings']);
    final stats = data['stats'] is Map
        ? Map<String, dynamic>.from(data['stats'] as Map)
        : const <String, dynamic>{};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          color: data['valid'] == true
              ? Colors.green.withValues(alpha: .12)
              : Theme.of(context).colorScheme.errorContainer,
          child: ListTile(
            leading: Icon(
              data['valid'] == true
                  ? Icons.check_circle_outline
                  : Icons.error_outline,
            ),
            title: Text(
              data['valid'] == true
                  ? labels.validationSuccessful
                  : labels.validationFailed,
            ),
            subtitle: Text(
              stats.entries
                  .map((entry) => '${entry.key}: ${entry.value}')
                  .join(' · '),
            ),
          ),
        ),
        if (errors.isNotEmpty)
          _IssueList(
            title: labels.errors,
            issues: errors,
            color: Theme.of(context).colorScheme.error,
          ),
        if (warnings.isNotEmpty)
          _IssueList(
            title: labels.warnings,
            issues: warnings,
            color: Colors.orange.shade800,
          ),
      ],
    );
  }
}

class _IssueList extends StatelessWidget {
  const _IssueList({
    required this.title,
    required this.issues,
    required this.color,
  });
  final String title;
  final List<Map<String, dynamic>> issues;
  final Color color;
  @override
  Widget build(BuildContext context) => ExpansionTile(
    initiallyExpanded: true,
    leading: Icon(Icons.report_outlined, color: color),
    title: Text('$title (${issues.length})'),
    children: [
      for (final issue in issues.take(50))
        ListTile(
          dense: true,
          title: Text(issue['message']?.toString() ?? ''),
          subtitle: Text(
            [
              if (issue['row'] != null) 'Row ${issue['row']}',
              if (issue['topic'] != null) issue['topic'].toString(),
              if (issue['field'] != null) issue['field'].toString(),
            ].join(' · '),
          ),
        ),
    ],
  );
}

class _TopicPreview extends StatelessWidget {
  const _TopicPreview({required this.data, required this.labels});
  final List<Map<String, dynamic>> data;
  final _AdminLabels labels;
  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(labels.preview, style: Theme.of(context).textTheme.titleMedium),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: [
              DataColumn(label: Text(labels.topic)),
              const DataColumn(label: Text('Matthew')),
              const DataColumn(label: Text('Mark')),
              const DataColumn(label: Text('Luke')),
              const DataColumn(label: Text('John')),
            ],
            rows: [
              for (final row in data)
                DataRow(
                  cells: [
                    DataCell(Text(row['name']?.toString() ?? '')),
                    for (final book in ['Matthew', 'Mark', 'Luke', 'John'])
                      DataCell(
                        Text(
                          (row['references'] as Map?)?[book]?.toString() ?? '—',
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BiblePreview extends StatelessWidget {
  const _BiblePreview({required this.data, required this.labels});
  final List<Map<String, dynamic>> data;
  final _AdminLabels labels;
  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(labels.preview, style: Theme.of(context).textTheme.titleMedium),
        for (final sample in data)
          ListTile(
            dense: true,
            title: Text(
              '${sample['book']} ${sample['chapter']}:${sample['verse']}',
            ),
            subtitle: SelectableText(sample['text']?.toString() ?? ''),
          ),
      ],
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.data, required this.labels});
  final Map<String, dynamic> data;
  final _AdminLabels labels;
  @override
  Widget build(BuildContext context) {
    final completed = data['status'] == 'completed';
    return Card(
      margin: const EdgeInsets.only(top: 16),
      child: ListTile(
        leading: completed
            ? const Icon(Icons.check_circle, color: Colors.green)
            : const CircularProgressIndicator(),
        title: Text(data['stage']?.toString() ?? labels.preparing),
        subtitle: completed ? Text(labels.importCompleted) : null,
      ),
    );
  }
}

Future<bool?> _confirmImport(
  BuildContext context,
  _AdminLabels labels,
  bool replacement,
) => showDialog<bool>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(replacement ? labels.confirmReplacement : labels.confirmImport),
    content: Text(
      replacement ? labels.replaceWarning : labels.confirmImportMessage,
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(false),
        child: Text(labels.cancel),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(true),
        child: Text(replacement ? labels.replace : labels.importAction),
      ),
    ],
  ),
);

class _AdminLabels {
  const _AdminLabels(this.arabic);
  final bool arabic;
  String t(String en, String ar) => arabic ? ar : en;
  String get admin => t('Admin', 'الإدارة');
  String get dashboard => t('Dashboard', 'لوحة المعلومات');
  String get bibles => t('Bible Translations', 'ترجمات الكتاب المقدس');
  String get topics => t('Topic Datasets', 'بيانات المواضيع');
  String get history => t('Import History', 'سجل الاستيراد');
  String get addBible =>
      t('Add Bible Translation', 'إضافة ترجمة للكتاب المقدس');
  String get addTopics => t('Add Topic Dataset', 'إضافة بيانات مواضيع');
  String get bibleLanguages => t('Bible languages', 'لغات الكتاب المقدس');
  String get bibleVersions => t('Bible versions', 'ترجمات الكتاب المقدس');
  String get topicLanguages => t('Topic languages', 'لغات المواضيع');
  String get failedImports => t('Failed imports', 'عمليات الاستيراد الفاشلة');
  String get recentImports => t('Recent imports', 'عمليات الاستيراد الأخيرة');
  String get accessDenied =>
      t('Administrator access is required.', 'يلزم إذن مسؤول للوصول.');
  String get retry => t('Try again', 'إعادة المحاولة');
  String get refresh => t('Refresh', 'تحديث');
  String get versions => t('Versions', 'الترجمات');
  String get books => t('Books', 'الأسفار');
  String get verses => t('Verses', 'الآيات');
  String get topicRecords => t('Topics', 'المواضيع');
  String get active => t('Active', 'نشط');
  String get inactive => t('Inactive', 'غير نشط');
  String get noImports => t('No imports yet.', 'لا توجد عمليات استيراد بعد.');
  String get close => t('Close', 'إغلاق');
  String get language => t('Language', 'اللغة');
  String get languageCode => t('Language code', 'رمز اللغة');
  String get displayName => t('Display name', 'اسم العرض');
  String get direction => t('Text direction', 'اتجاه النص');
  String get ltr => t('Left to right', 'من اليسار إلى اليمين');
  String get rtl => t('Right to left', 'من اليمين إلى اليسار');
  String get required => t('This field is required.', 'هذا الحقل مطلوب.');
  String get invalidLanguageCode => t(
    'Use lowercase letters, numbers, underscores, or hyphens.',
    'استخدم أحرفًا لاتينية صغيرة وأرقامًا وشرطة سفلية أو واصلة.',
  );
  String get uploadCsv => t('Upload CSV', 'رفع ملف CSV');
  String get csvFormat => t(
    'Expected columns: Topic, Matthew, Mark, Luke, John. Multiple references may use commas or semicolons.',
    'الأعمدة المطلوبة: الموضوع، متى، مرقس، لوقا، يوحنا. يمكن فصل المراجع المتعددة بفاصلة أو فاصلة منقوطة.',
  );
  String get selectCsv => t('Select CSV file', 'اختر ملف CSV');
  String get dropCsv => t(
    'Drag and drop a CSV here, or choose a file.',
    'اسحب ملف CSV وأفلته هنا، أو اختر ملفًا.',
  );
  String get validatePreview => t('Validate and preview', 'التحقق والمعاينة');
  String get validate => t('Validate upload', 'التحقق من الملف');
  String get preview => t('Preview', 'معاينة');
  String get topic => t('Topic', 'الموضوع');
  String get errors => t('Errors', 'الأخطاء');
  String get warnings => t('Warnings', 'التحذيرات');
  String get validationSuccessful =>
      t('Validation successful', 'تم التحقق بنجاح');
  String get validationFailed => t('Validation failed', 'فشل التحقق');
  String get replaceExisting => t(
    'Replace the existing active dataset',
    'استبدال البيانات النشطة الحالية',
  );
  String get replaceWarning => t(
    'The current production dataset stays active until the complete replacement has been written and verified.',
    'ستبقى البيانات الحالية نشطة حتى تكتمل كتابة النسخة البديلة والتحقق منها.',
  );
  String get replaceRequired => t(
    'Confirm replacement before importing.',
    'أكد الاستبدال قبل الاستيراد.',
  );
  String get importTopics =>
      t('Import Topic Dataset', 'استيراد بيانات المواضيع');
  String get importBible =>
      t('Import Bible Translation', 'استيراد ترجمة الكتاب المقدس');
  String get translationMetadata =>
      t('Translation and diacritics', 'الترجمة والحركات');
  String get translationName => t('Translation name', 'اسم الترجمة');
  String get internalKey =>
      t('Short name / identifier', 'الاسم المختصر / المعرّف');
  String get description => t('Description (optional)', 'الوصف (اختياري)');
  String get diacritics =>
      t('Contains Arabic diacritics', 'يحتوي على حركات عربية');
  String get detectAutomatically => t('Detect automatically', 'اكتشاف تلقائي');
  String get yes => t('Yes', 'نعم');
  String get no => t('No', 'لا');
  String get relatedTranslation =>
      t('Related translation (optional)', 'الترجمة المرتبطة (اختياري)');
  String get uploadUsfm => t('Upload USFM files', 'رفع ملفات USFM');
  String get usfmFormat => t(
    'Supported book codes: MAT, MRK, LUK, JHN. Select one or more UTF-8 .usfm files.',
    'رموز الأسفار المدعومة: MAT وMRK وLUK وJHN. اختر ملفًا أو أكثر بترميز UTF-8 وامتداد .usfm.',
  );
  String get selectUsfm => t('Select USFM files', 'اختر ملفات USFM');
  String get dropUsfm => t(
    'Drag and drop USFM files here, or choose files.',
    'اسحب ملفات USFM وأفلتها هنا، أو اختر الملفات.',
  );
  String filesSelected(int count) =>
      t('$count files selected', 'تم اختيار $count ملفات');
  String get confirmImport => t('Confirm import', 'تأكيد الاستيراد');
  String get confirmReplacement => t('Confirm replacement', 'تأكيد الاستبدال');
  String get confirmImportMessage => t(
    'The validated upload will become active after all records are written.',
    'سيصبح الملف الذي تم التحقق منه نشطًا بعد كتابة جميع السجلات.',
  );
  String get cancel => t('Cancel', 'إلغاء');
  String get replace => t('Replace', 'استبدال');
  String get importAction => t('Import', 'استيراد');
  String get importCompleted => t('Import completed', 'اكتمل الاستيراد');
  String get importFailed => t('Import failed.', 'فشل الاستيراد.');
  String get preparing => t('Preparing import', 'جارٍ تحضير الاستيراد');
}
