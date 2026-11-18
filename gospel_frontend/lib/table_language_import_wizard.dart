part of 'admin_portal.dart';

/// Imports only localized table labels; canonical item IDs/references are never
/// accepted from this workflow. All authorization and coverage checks are server-side.
class TableLanguageImportWizard extends StatefulWidget {
  const TableLanguageImportWizard({
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
  State<TableLanguageImportWizard> createState() =>
      _TableLanguageImportWizardState();
}

class _TableLanguageImportWizardState extends State<TableLanguageImportWizard> {
  final _form = GlobalKey<FormState>();
  final _language = TextEditingController(text: 'english');
  final _displayName = TextEditingController(text: 'English');
  final _subjectsLabel = TextEditingController(text: 'Subjects');
  final _gospels = {
    for (final name in ['Matthew', 'Mark', 'Luke', 'John'])
      name: TextEditingController(text: name),
  };
  String _dataset = 'harmony', _preset = 'english', _direction = 'ltr';
  AdminUploadFile? _file;
  Map<String, dynamic>? _validation;
  bool _busy = false, _replace = false, _completed = false;
  String? _error, _downloaded;

  _AdminLabels get labels => _AdminLabels(widget.arabic);
  String _datasetName(String id) => switch (id) {
    'miracles' => labels.t('Miracles', 'المعجزات'),
    'parables' => labels.t('Parables', 'الأمثال'),
    _ => labels.t('Harmony / All Topics', 'التناغم / جميع المواضيع'),
  };
  String get _languageId => _language.text.trim();
  bool get _canPublish =>
      !_busy &&
      !_completed &&
      _validation?['valid'] == true &&
      (_validation?['replacesExisting'] != true || _replace);

  @override
  void dispose() {
    for (final controller in [
      _language,
      _displayName,
      _subjectsLabel,
      ..._gospels.values,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _clearPreview() {
    _validation = null;
    _replace = false;
    _completed = false;
    _error = null;
  }

  void _choosePreset(String value) {
    setState(() {
      _preset = value;
      _direction = value == 'arabic' ? 'rtl' : 'ltr';
      _language.text = value == 'custom' ? '' : value;
      _displayName.text = switch (value) {
        'arabic' => 'العربية',
        'french' => 'Français',
        'english' => 'English',
        _ => '',
      };
      _subjectsLabel.text = switch (value) {
        'arabic' => 'المواضيع',
        'french' => 'Sujets',
        'english' => 'Subjects',
        _ => '',
      };
      final names = switch (value) {
        'arabic' => ['متى', 'مرقس', 'لوقا', 'يوحنا'],
        'french' => ['Matthieu', 'Marc', 'Luc', 'Jean'],
        'english' => ['Matthew', 'Mark', 'Luke', 'John'],
        _ => ['', '', '', ''],
      };
      var index = 0;
      for (final controller in _gospels.values) {
        controller.text = names[index++];
      }
      _file = null;
      _downloaded = null;
      _clearPreview();
    });
  }

  bool _validForm() => _form.currentState?.validate() == true;

  Future<void> _downloadTemplate() async {
    if (_busy) return;
    if (!RegExp(r'^[a-z][a-z0-9_-]*$').hasMatch(_languageId)) {
      setState(() => _error = labels.invalidLanguageCode);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final uri = Uri(
        path: '/admin/table-languages/template',
        queryParameters: {'datasetId': _dataset, 'language': _languageId},
      );
      final result = await widget.client.getJson(uri.toString());
      final csv = result['csv'];
      if (csv is! String) {
        throw AdminApiException(
          labels.t(
            'The template response contained no CSV.',
            'لم تتضمن استجابة القالب ملف CSV.',
          ),
        );
      }
      final filename =
          result['filename']?.toString() ?? '$_dataset-$_languageId.csv';
      await widget.csvDownloader(csv, filename);
      if (!mounted) return;
      setState(() {
        _clearPreview();
        _downloaded = filename;
        // Existing metadata accompanies an update template, so downloading it
        // preserves that language's labels instead of replacing them by defaults.
        if (result['languageMetadata'] case final Map metadata) {
          if (metadata['label'] is String) {
            _displayName.text = metadata['label'] as String;
          }
          if (metadata['subjectsLabel'] is String) {
            _subjectsLabel.text = metadata['subjectsLabel'] as String;
          }
          if (metadata['direction'] == 'rtl' ||
              metadata['direction'] == 'ltr') {
            _direction = metadata['direction'] as String;
          }
          if (metadata['gospels'] case final Map names) {
            for (final entry in _gospels.entries) {
              if (names[entry.key] is String) {
                entry.value.text = names[entry.key] as String;
              }
            }
          }
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
    if (_busy || _file == null || !_validForm()) return;
    setState(() {
      _clearPreview();
      _busy = true;
    });
    try {
      final result = await widget.client.upload(
        '/admin/table-languages/validate',
        fields: {
          'datasetId': _dataset,
          'language': _languageId,
          'displayName': _displayName.text.trim(),
          'direction': _direction,
          'subjectsLabel': _subjectsLabel.text.trim(),
          'gospels': jsonEncode({
            for (final entry in _gospels.entries)
              entry.key: entry.value.text.trim(),
          }),
        },
        files: [_file!],
        fileField: 'file',
      );
      if (mounted) setState(() => _validation = result);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _publish() async {
    if (!_canPublish) return;
    final validation = _validation!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: widget.arabic ? TextDirection.rtl : TextDirection.ltr,
        child: AlertDialog(
          title: Text(labels.t('Publish table language?', 'نشر لغة الجدول؟')),
          content: Text(
            labels.t(
              'Publish ${_displayName.text} ($_languageId) for ${_datasetName(_dataset)} using ${validation['filename'] ?? _file!.name}? Only this table language is updated. Canonical references and other languages are preserved.',
              'نشر ${_displayName.text} ($_languageId) لجدول ${_datasetName(_dataset)} باستخدام ${validation['filename'] ?? _file!.name}؟ سيتم تحديث لغة هذا الجدول فقط مع الحفاظ على المراجع الأساسية واللغات الأخرى.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(labels.cancel),
            ),
            FilledButton(
              key: const ValueKey('confirm-publish-table-language'),
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
      final result = await widget.client
          .postJson('/admin/table-languages/publish', {
            'datasetId': _dataset,
            'language': _languageId,
            'importId': validation['importId'],
            'confirm': true,
            'replace': validation['replacesExisting'] == true && _replace,
          });
      if (result['status'] != 'completed') {
        throw AdminApiException(
          labels.t(
            'Publication could not be verified. Validate again before retrying.',
            'تعذر التحقق من النشر. أعد التحقق قبل المحاولة.',
          ),
        );
      }
      if (!mounted) return;
      setState(() => _completed = true);
      widget.onCompleted();
    } catch (error) {
      if (mounted) {
        setState(() {
          _validation = null;
          _replace = false;
          _error =
              '${error.toString()}\n${labels.t('Validate the current template again before publishing.', 'أعد التحقق من القالب الحالي قبل النشر.')}';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(
    String key,
    String title,
    TextEditingController controller, {
    bool languageCode = false,
  }) => SizedBox(
    width: 240,
    child: TextFormField(
      key: ValueKey(key),
      controller: controller,
      enabled: !_busy,
      decoration: InputDecoration(
        labelText: title,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) return labels.required;
        if (languageCode &&
            !RegExp(r'^[a-z][a-z0-9_-]*$').hasMatch(value.trim())) {
          return labels.invalidLanguageCode;
        }
        return null;
      },
      onChanged: (_) => setState(() {
        _clearPreview();
        if (languageCode) {
          _file = null;
          _downloaded = null;
        }
      }),
    ),
  );

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: widget.arabic ? TextDirection.rtl : TextDirection.ltr,
    child: _WizardDialog(
      title: labels.addTopics,
      closeLabel: labels.close,
      busy: _busy,
      child: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              labels.t(
                'Translate this table’s subjects, Type labels, and headings. Readers see these translations when they choose an available Bible translation in the same language. This import does not add Bible text or change another table.',
                'ترجم مواضيع هذا الجدول وتسميات النوع وعناوين الأعمدة. تظهر هذه الترجمات عند اختيار ترجمة متاحة للكتاب المقدس باللغة نفسها. لا يضيف هذا الاستيراد نصوص الكتاب المقدس ولا يغيّر جدولًا آخر.',
              ),
            ),
            const SizedBox(height: 16),
            _StepTitle(
              number: 1,
              title: labels.t('Table and language', 'الجدول واللغة'),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 240,
                  child: DropdownButtonFormField<String>(
                    key: const ValueKey('table-language-dataset'),
                    initialValue: _dataset,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: labels.t('Table', 'الجدول'),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      for (final id in ['harmony', 'miracles', 'parables'])
                        DropdownMenuItem(
                          value: id,
                          child: Text(_datasetName(id)),
                        ),
                    ],
                    onChanged: _busy
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() {
                                _dataset = value;
                                _file = null;
                                _downloaded = null;
                                _clearPreview();
                              });
                            }
                          },
                  ),
                ),
                SizedBox(
                  width: 240,
                  child: DropdownButtonFormField<String>(
                    key: const ValueKey('table-language-preset'),
                    initialValue: _preset,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: labels.language,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: 'english',
                        child: Text('English'),
                      ),
                      const DropdownMenuItem(
                        value: 'arabic',
                        child: Text('العربية'),
                      ),
                      const DropdownMenuItem(
                        value: 'french',
                        child: Text('Français'),
                      ),
                      DropdownMenuItem(
                        value: 'custom',
                        child: Text(labels.t('Other language', 'لغة أخرى')),
                      ),
                    ],
                    onChanged: _busy
                        ? null
                        : (value) {
                            if (value != null) _choosePreset(value);
                          },
                  ),
                ),
                _field(
                  'table-language-code',
                  labels.languageCode,
                  _language,
                  languageCode: true,
                ),
                _field(
                  'table-language-name',
                  labels.t('Native language name', 'اسم اللغة بلغتها'),
                  _displayName,
                ),
                SizedBox(
                  width: 240,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('table-language-direction-$_direction'),
                    initialValue: _direction,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: labels.direction,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      DropdownMenuItem(value: 'ltr', child: Text(labels.ltr)),
                      DropdownMenuItem(value: 'rtl', child: Text(labels.rtl)),
                    ],
                    onChanged: _busy
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() {
                                _direction = value;
                                _clearPreview();
                              });
                            }
                          },
                  ),
                ),
              ],
            ),
            ExpansionTile(
              maintainState: true,
              initiallyExpanded: true,
              title: Text(
                labels.t(
                  'Translated column headings',
                  'عناوين الأعمدة المترجمة',
                ),
              ),
              childrenPadding: const EdgeInsets.only(bottom: 16),
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _field(
                      'table-language-subjects',
                      labels.t('Subject column heading', 'عنوان عمود الموضوع'),
                      _subjectsLabel,
                    ),
                    for (final entry in _gospels.entries)
                      _field(
                        'table-language-${entry.key}',
                        entry.key,
                        entry.value,
                      ),
                  ],
                ),
              ],
            ),
            _StepTitle(
              number: 2,
              title: labels.t('Download and translate', 'تنزيل وترجمة'),
            ),
            const SizedBox(height: 8),
            Text(
              labels.t(
                'Download the template for this table and language. Fill Translation for every item, and optionally TypeTranslation for classified Types. A blank TypeTranslation preserves the existing label or source fallback. Keep ItemId and TypeId unchanged. SourceName helps identify each row. Save as CSV UTF-8, preserving quoted cells. Existing translations and labels are loaded when downloading an update template.',
                'نزّل قالب هذا الجدول واللغة. املأ Translation لكل موضوع واختياريًا TypeTranslation للأنواع المصنّفة. تُبقي القيمة الفارغة تسمية النوع الحالية أو تسمية المصدر البديلة. أبقِ ItemId وTypeId دون تغيير. يساعد SourceName في تحديد الصف. احفظ بصيغة CSV UTF-8 مع الحفاظ على الخلايا المقتبسة. تُحمّل الترجمات والتسميات الحالية عند تنزيل قالب تحديث.',
              ),
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                key: const ValueKey('download-table-language-template'),
                onPressed: _busy ? null : _downloadTemplate,
                icon: const Icon(Icons.download_outlined),
                label: Text(
                  labels.t('Download CSV template', 'تنزيل قالب CSV'),
                ),
              ),
            ),
            if (_downloaded != null)
              Text(
                '${labels.t('Template downloaded', 'تم تنزيل القالب')}: $_downloaded',
              ),
            const SizedBox(height: 16),
            _StepTitle(
              number: 3,
              title: labels.t('Upload and validate', 'رفع وتحقق'),
            ),
            const SizedBox(height: 8),
            if (_file == null)
              _UploadDropSurface(
                message: labels.t(
                  'Select the completed translation CSV.',
                  'اختر ملف CSV بعد إكمال الترجمة.',
                ),
                buttonLabel: labels.selectCsv,
                buttonKey: const ValueKey('select-table-language-file'),
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
              child: FilledButton.icon(
                key: const ValueKey('validate-table-language'),
                onPressed: _busy || _file == null || _completed
                    ? null
                    : _validate,
                icon: const Icon(Icons.fact_check_outlined),
                label: Text(labels.validatePreview),
              ),
            ),
            if (_error != null) _InlineError(_error!),
            if (_validation case final data?) ...[
              const SizedBox(height: 16),
              _StepTitle(
                number: 4,
                title: labels.t('Preview and publish', 'معاينة ونشر'),
              ),
              _preview(data),
              if (data['replacesExisting'] == true)
                CheckboxListTile(
                  key: const ValueKey('replace-table-language'),
                  contentPadding: EdgeInsets.zero,
                  value: _replace,
                  onChanged: _busy || _completed
                      ? null
                      : (value) => setState(() => _replace = value == true),
                  title: Text(
                    labels.t(
                      'Replace only this table’s $_languageId translations',
                      'استبدال ترجمات $_languageId لهذا الجدول فقط',
                    ),
                  ),
                  subtitle: Text(
                    labels.t(
                      'Other languages and canonical references remain available.',
                      'تبقى اللغات الأخرى والمراجع الأساسية متاحة.',
                    ),
                  ),
                ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: FilledButton.icon(
                  key: const ValueKey('publish-table-language'),
                  onPressed: _canPublish ? _publish : null,
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: Text(
                    labels.t('Publish table language', 'نشر لغة الجدول'),
                  ),
                ),
              ),
            ],
            if (_completed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  labels.t(
                    'Table language published successfully.',
                    'تم نشر لغة الجدول بنجاح.',
                  ),
                  key: const ValueKey('table-language-completed'),
                ),
              ),
          ],
        ),
      ),
    ),
  );

  Widget _preview(Map<String, dynamic> data) {
    final stats = data['stats'] is Map ? data['stats'] as Map : const {};
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
              '${_datasetName(_dataset)} · ${_displayName.text} ($_languageId)\n${data['filename'] ?? _file!.name}',
            ),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            Chip(
              label: Text(
                '${stats['items'] ?? stats['topics'] ?? 0} ${labels.t('items', 'مواضيع')}',
              ),
            ),
            Chip(
              label: Text(
                '${stats['translations'] ?? stats['items'] ?? 0} ${labels.t('translations', 'ترجمات')}',
              ),
            ),
            Chip(
              label: Text(
                '${stats['types'] ?? 0} ${labels.t('Types', 'أنواع')}',
              ),
            ),
          ],
        ),
        Text(
          data['replacesExisting'] == true
              ? labels.t(
                  'Updates the existing language for this table.',
                  'يحدّث اللغة الحالية لهذا الجدول.',
                )
              : labels.t(
                  'Adds a new language to this table.',
                  'يضيف لغة جديدة لهذا الجدول.',
                ),
        ),
        if (data['revision'] != null || data['currentRevision'] != null)
          Text(
            '${labels.t('Table revision', 'إصدار الجدول')}: ${data['revision'] ?? data['currentRevision']}',
          ),
        if (data['encoding'] != null)
          Text('${labels.t('Encoding', 'الترميز')}: ${data['encoding']}'),
        if (data['sourceChecksum'] != null)
          SelectableText(
            '${labels.t('Source checksum', 'بصمة المصدر')}: ${data['sourceChecksum']}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        for (final kind in ['errors', 'warnings'])
          if (_listOfMaps(data[kind]).isNotEmpty)
            _IssueList(
              title: kind == 'errors' ? labels.errors : labels.warnings,
              issues: _listOfMaps(data[kind]),
              color: kind == 'errors'
                  ? Theme.of(context).colorScheme.error
                  : Colors.orange.shade800,
            ),
        ExpansionTile(
          initiallyExpanded: true,
          title: Text(labels.t('Sample translations', 'عينة من الترجمات')),
          children: [
            for (final row in _listOfMaps(data['preview']))
              ListTile(
                isThreeLine: row['typeId'] != null && row['typeId'] != '',
                title: Text('${row['id']} · ${row['translation'] ?? ''}'),
                subtitle: Text(
                  '${row['sourceName'] ?? ''}${row['typeId'] != null && row['typeId'] != '' ? '\n${row['typeId']}: ${row['typeTranslation'] ?? ''}' : ''}',
                ),
              ),
          ],
        ),
      ],
    );
  }
}
