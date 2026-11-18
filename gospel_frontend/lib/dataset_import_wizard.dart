part of 'admin_portal.dart';

/// Additional tables have their own revisions and never use the Harmony importer.
class DatasetImportWizard extends StatefulWidget {
  const DatasetImportWizard({
    super.key,
    required this.client,
    required this.arabic,
    required this.onCompleted,
    this.filePicker = const PlatformAdminFilePicker(),
    this.maxUploadBytes = defaultMaxAdminUploadBytes,
    this.csvDownloader = downloadCsv,
  });

  final AdminClient client;
  final bool arabic;
  final VoidCallback onCompleted;
  final AdminFilePicker filePicker;
  final int maxUploadBytes;
  final Future<void> Function(String contents, String filename) csvDownloader;

  @override
  State<DatasetImportWizard> createState() => _DatasetImportWizardState();
}

class _DatasetImportWizardState extends State<DatasetImportWizard> {
  static const _newTarget = '__new__';
  final _newId = TextEditingController();
  final _englishName = TextEditingController();
  final _arabicName = TextEditingController();
  List<Map<String, dynamic>> _datasets = [];
  bool _loadingCatalog = true;
  String? _catalogError;
  String _dataset = 'miracles';
  String _source = 'storage';
  List<Map<String, dynamic>> _sources = [];
  AdminUploadFile? _file;
  Map<String, dynamic>? _validation;
  Map<String, dynamic>? _published;
  bool _loadingSources = true;
  bool _busy = false;
  bool _replace = false;
  String? _sourceError;
  String? _error;

  _AdminLabels get labels => _AdminLabels(widget.arabic);
  bool get _creating => _dataset == _newTarget;
  bool get _catalogReady => !_loadingCatalog && _catalogError == null;
  String get _datasetId => _creating ? _newId.text.trim() : _dataset;
  String get _datasetName => _creating
      ? ((widget.arabic && _arabicName.text.trim().isNotEmpty)
            ? _arabicName.text.trim()
            : _englishName.text.trim().isNotEmpty
            ? _englishName.text.trim()
            : labels.t('New table', 'جدول جديد'))
      : _name(_dataset);
  String _name(String id) => _adminDatasetName(id, _datasets, labels);
  bool get _supportsStorage =>
      const {'miracles', 'parables'}.contains(_dataset);
  String get _filename => switch (_dataset) {
    'miracles' => 'Miracles.csv',
    'parables' => 'Parables.csv',
    _ => _file?.name ?? 'table.csv',
  };
  String? get _idError {
    final id = _newId.text.trim();
    if (id.isEmpty) return null;
    if (id.length < 2 ||
        id.length > 48 ||
        !RegExp(r'^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$').hasMatch(id)) {
      return labels.t(
        'Use 2–48 lowercase letters, digits, and single hyphens; start with a letter.',
        'استخدم 2–48 حرفًا لاتينيًا صغيرًا أو رقمًا أو شرطة مفردة؛ ابدأ بحرف.',
      );
    }
    if (const {'harmony', 'miracles', 'parables'}.contains(id) ||
        _datasets.any((entry) => entry['datasetId'] == id)) {
      return labels.t(
        'This ID already belongs to a table. Choose that table to update it.',
        'هذا المعرّف مستخدم لجدول. اختر الجدول الموجود لتحديثه.',
      );
    }
    return null;
  }

  Map<String, dynamic>? get _storageSource {
    for (final source in _sources) {
      // The UI never accepts free-form Storage paths or arbitrary URLs.
      if (source['datasetId'] == _dataset && source['filename'] == _filename) {
        return source;
      }
    }
    return null;
  }

  bool get _completed => _published != null;
  bool get _canValidate =>
      !_busy &&
      !_completed &&
      _catalogReady &&
      (!_creating ||
          (_newId.text.trim().isNotEmpty &&
              _idError == null &&
              _englishName.text.trim().isNotEmpty)) &&
      (_source == 'upload'
          ? _file != null
          : _storageSource?['available'] == true);
  bool get _canPublish =>
      !_busy &&
      !_completed &&
      _validation?['valid'] == true &&
      (_validation?['replacesExisting'] != true || _replace);

  @override
  void initState() {
    super.initState();
    _loadSources();
    _loadCatalog();
  }

  @override
  void dispose() {
    _newId.dispose();
    _englishName.dispose();
    _arabicName.dispose();
    super.dispose();
  }

  Future<void> _loadCatalog() async {
    setState(() {
      _loadingCatalog = true;
      _catalogError = null;
    });
    try {
      final entries = await _loadAdminDatasetCatalog(widget.client);
      if (mounted) setState(() => _datasets = entries);
    } catch (error) {
      if (mounted) setState(() => _catalogError = error.toString());
    } finally {
      if (mounted) setState(() => _loadingCatalog = false);
    }
  }

  Future<void> _downloadTemplate() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.client.getJson('/admin/datasets/template');
      if (result['csv'] is! String) {
        throw const AdminApiException(
          'The template response contained no CSV.',
        );
      }
      await widget.csvDownloader(
        result['csv'] as String,
        result['filename']?.toString() ?? 'table-template.csv',
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadSources() async {
    setState(() {
      _loadingSources = true;
      _sourceError = null;
    });
    try {
      final result = await widget.client.getJson('/admin/datasets/sources');
      if (mounted) setState(() => _sources = _listOfMaps(result['sources']));
    } catch (error) {
      if (mounted) setState(() => _sourceError = error.toString());
    } finally {
      if (mounted) setState(() => _loadingSources = false);
    }
  }

  void _clearPreview() {
    _validation = null;
    _published = null;
    _replace = false;
    _error = null;
  }

  Future<void> _pick() async {
    try {
      final files = await widget.filePicker.pickFiles(
        allowedExtensions: const ['csv'],
      );
      if (!mounted || files == null) return;
      if (files.length != 1 ||
          !files.single.name.toLowerCase().endsWith('.csv')) {
        throw AdminApiException(labels.pleaseSelectCsv);
      }
      final file = files.single;
      if (file.size == 0) throw AdminApiException(labels.emptyCsv);
      if (file.size > widget.maxUploadBytes) {
        throw AdminApiException(
          labels.fileTooLarge(_formatFileSize(widget.maxUploadBytes)),
        );
      }
      setState(() {
        _file = file;
        _clearPreview();
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _validate() async {
    if (!_canValidate) return;
    setState(() {
      _busy = true;
      _clearPreview();
    });
    try {
      final result = _source == 'storage'
          ? await widget.client.postJson('/admin/datasets/validate', {
              'datasetId': _datasetId,
              'source': 'storage',
              'filename': _filename,
            })
          : await widget.client.upload(
              '/admin/datasets/validate',
              fields: {
                'datasetId': _datasetId,
                'source': 'upload',
                if (_creating) 'createNew': 'true',
                if (_creating)
                  'labels': jsonEncode({
                    'english': _englishName.text.trim(),
                    if (_arabicName.text.trim().isNotEmpty)
                      'arabic': _arabicName.text.trim(),
                  }),
              },
              files: [_file!],
              fileField: 'file',
            );
      if (mounted) setState(() => _validation = result);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
        if (_creating) await _loadCatalog();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _publish() async {
    if (!_canPublish) return;
    final validation = _validation!;
    final replacing = validation['replacesExisting'] == true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: widget.arabic ? TextDirection.rtl : TextDirection.ltr,
        child: AlertDialog(
          title: Text(labels.t('Publish $_datasetName?', 'نشر $_datasetName؟')),
          content: Text(
            labels.t(
              'Publish the validated ${validation['filename'] ?? _filename} to $_datasetName. '
                  '${replacing ? 'This replaces its active revision after all records are verified.' : 'This creates its first published revision.'}',
              'نشر الملف المتحقق منه ${validation['filename'] ?? _filename} في $_datasetName. '
                  '${replacing ? 'سيحل محل الإصدار النشط بعد التحقق من جميع السجلات.' : 'سينشئ أول إصدار منشور لهذا الجدول.'}',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(labels.cancel),
            ),
            FilledButton(
              key: const ValueKey('confirm-publish-dataset'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(labels.t('Publish', 'نشر')),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var result = await widget.client.postJson('/admin/datasets/publish', {
        'datasetId': _datasetId,
        'importId': validation['importId'],
        'confirm': true,
        'replace': replacing && _replace,
      });
      while (mounted) {
        final record = result['import'] is Map
            ? Map<String, dynamic>.from(result['import'] as Map)
            : result;
        if (record['status'] == 'completed') {
          setState(() => _published = record);
          widget.onCompleted();
          return;
        }
        if (record['status'] == 'failed') {
          final errors = _listOfMaps(record['errors']);
          throw AdminApiException(
            errors.isEmpty
                ? labels.importFailed
                : errors.first['message'].toString(),
          );
        }
        if (record['status'] != 'queued' &&
            record['status'] != 'running' &&
            record['status'] != 'processing') {
          throw AdminApiException(
            labels.t(
              'Publication could not be verified. Validate again before retrying.',
              'تعذر التحقق من النشر. أعد التحقق قبل المحاولة.',
            ),
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        if (!mounted) return;
        result = await widget.client.getJson(
          '/admin/imports/${validation['importId']}',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          // A changed source/revision can never reuse an old preview.
          _validation = null;
          _replace = false;
          _error =
              '${error.toString()} ${labels.t('Validate again before publishing.', 'أعد التحقق قبل النشر.')}';
        });
        if (_creating) await _loadCatalog();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: widget.arabic ? TextDirection.rtl : TextDirection.ltr,
    child: _WizardDialog(
      title: labels.importAdditionalDataset,
      closeLabel: labels.close,
      busy: _busy,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _StepTitle(number: 1, title: labels.t('Choose table', 'اختر الجدول')),
          if (_loadingCatalog) const LinearProgressIndicator(),
          if (_catalogError != null) ...[
            _InlineError(_catalogError!),
            TextButton.icon(
              key: const ValueKey('retry-dataset-catalog'),
              onPressed: _busy ? null : _loadCatalog,
              icon: const Icon(Icons.refresh),
              label: Text(labels.retry),
            ),
          ],
          DropdownButtonFormField<String>(
            key: ValueKey('dataset-import-target-$_dataset'),
            initialValue: _dataset,
            decoration: InputDecoration(
              labelText: labels.t('Target table', 'الجدول المستهدف'),
              border: const OutlineInputBorder(),
            ),
            isExpanded: true,
            items: [
              for (final id in <String>{
                'miracles',
                'parables',
                ..._datasets
                    .where((entry) => entry['datasetId'] != 'harmony')
                    .map((entry) => entry['datasetId'] as String),
              })
                DropdownMenuItem(value: id, child: Text(_name(id))),
              DropdownMenuItem(
                value: _newTarget,
                child: Text(labels.t('Create new table', 'إنشاء جدول جديد')),
              ),
            ],
            onChanged: _busy || !_catalogReady
                ? null
                : (value) {
                    if (value == null || value == _dataset) return;
                    setState(() {
                      _dataset = value;
                      if (!_supportsStorage) _source = 'upload';
                      _file = null;
                      _clearPreview();
                    });
                  },
          ),
          if (_creating) ...[
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('new-table-id'),
              controller: _newId,
              enabled: !_busy,
              decoration: InputDecoration(
                labelText: labels.t('Stable table ID', 'معرّف الجدول الثابت'),
                helperMaxLines: 2,
                errorMaxLines: 3,
                helperText: labels.t(
                  'For example: teachings. Used in links; choose it once.',
                  'مثال: teachings. يُستخدم في الروابط؛ اختره مرة واحدة.',
                ),
                errorText: _idError,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(_clearPreview),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('new-table-name-english'),
              controller: _englishName,
              enabled: !_busy,
              maxLength: 80,
              decoration: InputDecoration(
                labelText: labels.t(
                  'Table name in English (required)',
                  'اسم الجدول بالإنجليزية (مطلوب)',
                ),
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(_clearPreview),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('new-table-name-arabic'),
              controller: _arabicName,
              enabled: !_busy,
              maxLength: 80,
              textDirection: TextDirection.rtl,
              decoration: InputDecoration(
                labelText: labels.t(
                  'Table name in Arabic (optional)',
                  'اسم الجدول بالعربية (اختياري)',
                ),
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(_clearPreview),
            ),
          ],
          const SizedBox(height: 20),
          _StepTitle(
            number: 2,
            title: labels.t('Choose source', 'اختر المصدر'),
          ),
          DropdownButtonFormField<String>(
            key: ValueKey('dataset-import-source-$_source'),
            initialValue: _source,
            decoration: InputDecoration(
              labelText: labels.t('Source', 'المصدر'),
              border: const OutlineInputBorder(),
            ),
            items: [
              if (_supportsStorage)
                DropdownMenuItem(
                  value: 'storage',
                  child: Text(
                    labels.t(
                      'Existing Firebase Storage file',
                      'ملف موجود في Firebase Storage',
                    ),
                  ),
                ),
              DropdownMenuItem(value: 'upload', child: Text(labels.uploadCsv)),
            ],
            isExpanded: true,
            onChanged: _busy
                ? null
                : (value) {
                    if (value == null || value == _source) return;
                    setState(() {
                      _source = value;
                      _clearPreview();
                    });
                  },
          ),
          const SizedBox(height: 12),
          if (_source == 'storage')
            _storageCard()
          else if (_file == null)
            _UploadDropSurface(
              message: labels.t(
                'Select the CSV for $_datasetName.',
                'اختر ملف CSV لجدول $_datasetName.',
              ),
              buttonLabel: labels.selectCsv,
              buttonKey: const ValueKey('select-dataset-file'),
              onPressed: _busy ? null : _pick,
            )
          else
            _SelectedUploadSurface(
              file: _file!,
              selectedLabel: labels.selectedFile,
              changeLabel: labels.changeFile,
              removeLabel: labels.removeFile,
              onChange: _busy ? null : _pick,
              onRemove: _busy
                  ? null
                  : () => setState(() {
                      _file = null;
                      _clearPreview();
                    }),
            ),
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              key: const ValueKey('download-dataset-template'),
              onPressed: _busy || !_catalogReady ? null : _downloadTemplate,
              icon: const Icon(Icons.download_outlined),
              label: Text(labels.t('Download CSV template', 'تنزيل قالب CSV')),
            ),
          ),
          Text(
            labels.t(
              'Columns are matched by header. Include #, Subject and/or الموضوع, optional Type, and Matthew, Mark, Luke, John. Quote reference cells containing commas. Use + for a continuous passage, ; for separate passages, and , for selections in the same chapter.',
              'تُطابق الأعمدة حسب العنوان. أدرج # وSubject و/أو الموضوع، وType اختياريًا، ومتى ومرقس ولوقا ويوحنا. ضع المراجع التي تحتوي على فاصلة بين علامتي اقتباس. استخدم + للمقطع المستمر و; للمقاطع المنفصلة و, لاختيارات الفصل نفسه.',
            ),
          ),
          const SizedBox(height: 20),
          _StepTitle(number: 3, title: labels.validatePreview),
          FilledButton.icon(
            key: const ValueKey('validate-dataset-source'),
            onPressed: _canValidate ? _validate : null,
            icon: const Icon(Icons.fact_check_outlined),
            label: Text(labels.validatePreview),
          ),
          if (_error != null) _InlineError(_error!),
          if (_validation case final validation?) ...[
            const SizedBox(height: 16),
            _DatasetValidationPreview(
              data: validation,
              datasetName: _datasetName,
              labels: labels,
            ),
            const SizedBox(height: 20),
            _StepTitle(number: 4, title: labels.t('Publish', 'نشر')),
            if (validation['replacesExisting'] == true)
              CheckboxListTile(
                key: const ValueKey('replace-dataset-revision'),
                value: _replace,
                onChanged: _busy || _completed
                    ? null
                    : (value) => setState(() => _replace = value == true),
                title: Text(
                  labels.t(
                    'Replace the current $_datasetName revision',
                    'استبدال الإصدار الحالي لجدول $_datasetName',
                  ),
                ),
                subtitle: Text(labels.replaceWarning),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
            FilledButton.icon(
              key: const ValueKey('publish-dataset'),
              onPressed: _canPublish ? _publish : null,
              icon: const Icon(Icons.publish),
              label: Text(
                labels.t('Publish $_datasetName', 'نشر $_datasetName'),
              ),
            ),
          ],
          if (_published case final published?)
            Card(
              color: Colors.green.withValues(alpha: .12),
              child: ListTile(
                leading: const Icon(Icons.check_circle_outline),
                title: Text(labels.importCompleted),
                subtitle: Text(
                  '$_datasetName${published['revisionId'] == null ? '' : ' · ${published['revisionId']}'}',
                ),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _storageCard() {
    final source = _storageSource;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_filename, style: Theme.of(context).textTheme.titleSmall),
            if (_loadingSources)
              const LinearProgressIndicator()
            else if (_sourceError != null || source?['available'] != true) ...[
              Text(
                _sourceError ??
                    source?['error']?.toString() ??
                    labels.t(
                      'This file is unavailable through the configured backend Storage connection. You can upload a CSV instead.',
                      'هذا الملف غير متاح عبر اتصال التخزين الخلفي. يمكنك رفع ملف CSV.',
                    ),
              ),
              TextButton.icon(
                onPressed: _busy ? null : _loadSources,
                icon: const Icon(Icons.refresh),
                label: Text(labels.retry),
              ),
            ] else ...[
              Text(
                labels.t(
                  'Available through the authorized backend connection',
                  'متاح عبر اتصال الخلفية المصرّح به',
                ),
              ),
              if (source?['size'] is num)
                Text(_formatFileSize((source!['size'] as num).toInt())),
              if (source?['generation'] != null)
                Text(
                  '${labels.t('Source revision', 'إصدار المصدر')}: ${source!['generation']}',
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DatasetValidationPreview extends StatelessWidget {
  const _DatasetValidationPreview({
    required this.data,
    required this.datasetName,
    required this.labels,
  });
  final Map<String, dynamic> data;
  final String datasetName;
  final _AdminLabels labels;

  Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : {};
  String _typeName(Map<String, dynamic> type) {
    final names = _map(type['labels']);
    return (names[labels.arabic ? 'arabic' : 'english'] ??
            names['english'] ??
            type['id'] ??
            '')
        .toString();
  }

  @override
  Widget build(BuildContext context) {
    final stats = _map(data['stats']);
    final types = _listOfMaps(data['types']);
    final errors = _listOfMaps(data['errors']);
    final warnings = _listOfMaps(data['warnings']);
    final languages = data['languages'] is List
        ? data['languages'] as List
        : [];
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
              '$datasetName · ${data['filename'] ?? ''}\n${stats['items'] ?? stats['topics'] ?? 0} ${labels.t('items', 'مواضيع')} · ${stats['references'] ?? 0} ${labels.t('references', 'مراجع')}',
            ),
          ),
        ),
        Text(
          data['replacesExisting'] == true
              ? labels.t(
                  'Replaces the existing published revision',
                  'يستبدل الإصدار المنشور الحالي',
                )
              : labels.t('Creates a new table', 'ينشئ جدولًا جديدًا'),
        ),
        const SizedBox(height: 8),
        Text(
          '${labels.t('Detected languages', 'اللغات المكتشفة')}: ${languages.map((language) => nativeLanguageName(language.toString(), language.toString())).join(', ')}',
        ),
        if (data['encoding'] != null)
          Text('${labels.t('Encoding', 'الترميز')}: ${data['encoding']}'),
        if (data['header'] is List)
          Text(
            '${labels.t('Headers', 'عناوين الأعمدة')}: ${(data['header'] as List).join(' | ')}',
          ),
        if (data['sourceChecksum'] != null)
          SelectableText(
            '${labels.t('Source checksum', 'بصمة المصدر')}: ${data['sourceChecksum']}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        const SizedBox(height: 12),
        Text(
          labels.t('Type values and item counts', 'قيم النوع وعدد المواضيع'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        if (data['hasTypes'] != true)
          Text(
            labels.t(
              'No Type classifications were found. Upload an updated CSV with populated Type values to enable Type filters and grouping. Resolve any blocking errors before publishing.',
              'لم يُعثر على تصنيفات للنوع. ارفع ملف CSV محدثًا بقيم Type لتفعيل التصفية والتجميع حسب النوع. صحّح الأخطاء المانعة قبل النشر.',
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final type in types)
                Chip(label: Text('${_typeName(type)}: ${type['count'] ?? 0}')),
            ],
          ),
        Text(
          '${labels.t('Missing Type (Unclassified)', 'نوع غير محدد (غير مصنف)')}: ${stats['missingTypes'] ?? 0}',
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
        ExpansionTile(
          key: const ValueKey('dataset-import-preview'),
          title: Text(labels.t('Sample rows', 'عينة من الصفوف')),
          initiallyExpanded: true,
          children: [
            for (final row in _listOfMaps(data['preview']))
              _sampleRow(context, row),
          ],
        ),
      ],
    );
  }

  Widget _sampleRow(BuildContext context, Map<String, dynamic> row) {
    final names = _map(row['names']);
    final references = _map(row['references']);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '#${row['id']} · ${row['name'] ?? names['english'] ?? names['arabic'] ?? ''}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          for (final entry in names.entries)
            Directionality(
              textDirection: entry.key == 'arabic'
                  ? TextDirection.rtl
                  : TextDirection.ltr,
              child: Text(
                '${nativeLanguageName(entry.key, entry.key)}: ${entry.value}',
              ),
            ),
          Text(
            '${labels.t('Type', 'النوع')}: ${row['type']?.toString().isNotEmpty == true ? row['type'] : labels.t('Unclassified', 'غير مصنف')}',
          ),
          for (final gospel in ['Matthew', 'Mark', 'Luke', 'John'])
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text('$gospel: ${references[gospel] ?? ''}'),
            ),
        ],
      ),
    );
  }
}
