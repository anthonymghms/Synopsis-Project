part of 'admin_portal.dart';

class _HistoryList extends StatefulWidget {
  const _HistoryList({
    required this.data,
    required this.labels,
    required this.onOpen,
    required this.client,
  });
  final List<Map<String, dynamic>> data;
  final _AdminLabels labels;
  final ValueChanged<Map<String, dynamic>> onOpen;
  final AdminClient client;
  @override
  State<_HistoryList> createState() => _HistoryListState();
}

class _HistoryListState extends State<_HistoryList> {
  late final Future<Map<String, dynamic>> _history = widget.client.getJson(
    '/admin/imports?limit=100',
  );
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Text(
        widget.labels.history,
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 16),
      FutureBuilder<Map<String, dynamic>>(
        future: _history,
        builder: (context, snapshot) => Column(
          children: [
            if (snapshot.connectionState != ConnectionState.done)
              const LinearProgressIndicator(),
            if (snapshot.hasError) _InlineError(snapshot.error.toString()),
            _HistoryCards(
              data: snapshot.hasData
                  ? _listOfMaps(snapshot.data!['imports'])
                  : widget.data,
              labels: widget.labels,
              onOpen: widget.onOpen,
            ),
          ],
        ),
      ),
    ],
  );
}

String _importStatus(Map<String, dynamic> item, _AdminLabels labels) {
  final status = item['status'];
  if (status == 'validated') {
    final stats = item['validation'] is Map
        ? Map<String, dynamic>.from(item['validation'] as Map)
        : <String, dynamic>{};
    final count = stats['verses'] ?? stats['topics'] ?? stats['labels'];
    return '${labels.t('Awaiting import — not published', 'بانتظار الاستيراد — غير منشور')}${count == null ? '' : ' · $count ${labels.t('validated', 'تم التحقق منها')}'}';
  }
  if (status == 'completed') {
    return '${labels.t('Completed', 'مكتمل')} · ${item['recordsProcessed'] ?? 0} ${labels.t('imported', 'تم استيرادها')}';
  }
  if (status == 'validation_failed') {
    return labels.t('Validation failed', 'فشل التحقق');
  }
  if (status == 'failed') return labels.t('Import failed', 'فشل الاستيراد');
  return item['stage']?.toString() ?? status?.toString() ?? '';
}

class _HistoryCards extends StatelessWidget {
  const _HistoryCards({
    required this.data,
    required this.labels,
    required this.onOpen,
  });
  final List<Map<String, dynamic>> data;
  final _AdminLabels labels;
  final ValueChanged<Map<String, dynamic>> onOpen;
  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return Text(labels.noImports);
    return Column(
      children: [
        for (final item in data)
          Card(
            child: ListTile(
              onTap: () => onOpen(item),
              leading: Icon(
                item['type'] == 'bible' ? Icons.menu_book : Icons.table_chart,
              ),
              title: Text(
                item['type'] == 'bible'
                    ? '${item['language']} · ${item['version'] ?? ''}'
                    : item['language']?.toString() ?? '',
              ),
              subtitle: Text(_importStatus(item, labels)),
              trailing: IconButton(
                key: ValueKey('open-import-${item['id']}'),
                tooltip: item['status'] == 'validated'
                    ? labels.t(
                        'Review & finish import',
                        'مراجعة وإكمال الاستيراد',
                      )
                    : labels.t('View import details', 'عرض تفاصيل الاستيراد'),
                onPressed: () => onOpen(item),
                icon: Icon(
                  item['status'] == 'validated'
                      ? Icons.upload_outlined
                      : Icons.chevron_right,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class ImportDetailsDialog extends StatefulWidget {
  const ImportDetailsDialog({
    super.key,
    required this.client,
    required this.arabic,
    required this.importId,
    required this.onCompleted,
  });
  final AdminClient client;
  final bool arabic;
  final String importId;
  final VoidCallback onCompleted;
  @override
  State<ImportDetailsDialog> createState() => _ImportDetailsDialogState();
}

class _ImportDetailsDialogState extends State<ImportDetailsDialog> {
  Map<String, dynamic>? _record;
  String? _error;
  bool _busy = true, _replace = false;
  _AdminLabels get labels => _AdminLabels(widget.arabic);
  static const _endpoints = {
    'bible': 'bibles',
    'topics': 'topics',
    'harmony': 'harmony',
    'topic_localization': 'localizations',
    'interface_translation': 'interface-translations',
  };
  bool get _running => const {
    'queued',
    'writing',
    'importing',
    'activating',
  }.contains(_record?['status']);
  bool get _canImport =>
      const {'validated', 'failed'}.contains(_record?['status']) &&
      _endpoints.containsKey(_record?['type']);
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.client.getJson(
        '/admin/imports/${widget.importId}',
      );
      if (mounted) {
        setState(
          () => _record = Map<String, dynamic>.from(result['import'] as Map),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    final record = _record!;
    if (record['collision'] == true && !_replace) return;
    final confirmed = await _confirmImport(
      context,
      labels,
      record['collision'] == true,
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.client.postJson(
        '/admin/${_endpoints[record['type']]}/import',
        {'importId': widget.importId, 'confirm': true, 'replace': _replace},
      );
      while (mounted) {
        final response = await widget.client.getJson(
          '/admin/imports/${widget.importId}',
        );
        if (!mounted) return;
        final next = Map<String, dynamic>.from(response['import'] as Map);
        setState(() => _record = next);
        if (next['status'] == 'completed') {
          widget.onCompleted();
          return;
        }
        if (const {'failed', 'validation_failed'}.contains(next['status'])) {
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 1200));
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final record = _record;
    final stats = record?['validation'] is Map
        ? Map<String, dynamic>.from(record!['validation'] as Map)
        : <String, dynamic>{};
    return Directionality(
      textDirection: widget.arabic ? TextDirection.rtl : TextDirection.ltr,
      child: _WizardDialog(
        title: labels.t('Import details', 'تفاصيل الاستيراد'),
        closeLabel: labels.close,
        busy: false,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_busy) const LinearProgressIndicator(),
            if (_error != null) _InlineError(_error!),
            if (record != null) ...[
              Text(
                '${record['language']} ${record['version'] ?? ''}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                _importStatus(record, labels),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (record['status'] == 'validated')
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    labels.t(
                      'Your files passed validation. No records have been published yet. Finish the import below to make this content available.',
                      'اجتازت ملفاتك التحقق. لم يتم نشر أي سجلات بعد. أكمل الاستيراد أدناه لإتاحة هذا المحتوى.',
                    ),
                  ),
                ),
              if (record['metadata'] case final Map metadata) ...[
                for (final key in [
                  'languageDisplayName',
                  'displayName',
                  'translationName',
                  'versionDisplayName',
                  'description',
                ])
                  if (metadata[key] != null &&
                      metadata[key].toString().isNotEmpty)
                    Text(metadata[key].toString()),
              ],
              const SizedBox(height: 12),
              for (final filename in record['filenames'] as List? ?? [])
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.description_outlined),
                  title: Text(filename.toString()),
                ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in stats.entries)
                    Chip(label: Text('${entry.key}: ${entry.value}')),
                ],
              ),
              if (_listOfMaps(record['warnings']).isNotEmpty)
                _IssueList(
                  title: labels.warnings,
                  issues: _listOfMaps(record['warnings']),
                  color: Colors.orange.shade800,
                ),
              if (_listOfMaps(record['errors']).isNotEmpty)
                _IssueList(
                  title: labels.errors,
                  issues: _listOfMaps(record['errors']),
                  color: Theme.of(context).colorScheme.error,
                ),
              if (_canImport) ...[
                if (record['collision'] == true)
                  CheckboxListTile(
                    value: _replace,
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _replace = value == true),
                    title: Text(labels.replaceExisting),
                    subtitle: Text(labels.replaceWarning),
                  ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  key: const ValueKey('resume-import'),
                  onPressed: _busy || (record['collision'] == true && !_replace)
                      ? null
                      : _start,
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: Text(labels.t('Finish import', 'إكمال الاستيراد')),
                ),
              ],
              if (_running || _busy)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    labels.t(
                      'You may close this window. The import continues on the server; check Import History for progress.',
                      'يمكنك إغلاق هذه النافذة. يستمر الاستيراد على الخادم؛ تحقق من سجل الاستيراد لمتابعته.',
                    ),
                  ),
                ),
              if (record['status'] == 'validation_failed')
                Text(
                  labels.t(
                    'Correct the reported errors and upload the files again.',
                    'صحّح الأخطاء المذكورة ثم ارفع الملفات مجددًا.',
                  ),
                ),
            ],
            TextButton.icon(
              onPressed: _busy ? null : _load,
              icon: const Icon(Icons.refresh),
              label: Text(labels.refresh),
            ),
          ],
        ),
      ),
    );
  }
}
