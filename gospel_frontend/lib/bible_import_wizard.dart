part of 'admin_portal.dart';

class BibleImportWizard extends StatefulWidget {
  const BibleImportWizard({
    super.key,
    required this.client,
    required this.arabic,
    required this.onCompleted,
    this.filePicker = const PlatformAdminFilePicker(),
    this.maxUploadBytes = defaultMaxAdminUploadBytes,
  });
  final AdminClient client;
  final bool arabic;
  final VoidCallback onCompleted;
  final AdminFilePicker filePicker;
  final int maxUploadBytes;

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
  String _languageMode = 'existing';
  String? _existingLanguage;
  List<Map<String, dynamic>> _languages = [];
  bool _catalogLoading = true;
  String? _catalogError;
  String _suggestedDisplay = '', _suggestedVersion = '';
  bool get _completed => _progress?['status'] == 'completed';

  @override
  void initState() {
    super.initState();
    for (final c in [
      _language,
      _languageName,
      _translation,
      _versionId,
      _displayName,
      _description,
      _related,
    ]) {
      c.addListener(_invalidateValidation);
    }
    _loadLanguages();
  }

  void _invalidateValidation() {
    if (!mounted) return;
    setState(() {
      _validation = null;
      _progress = null;
      _replace = false;
      _error = null;
    });
  }

  Future<void> _loadLanguages() async {
    setState(() {
      _catalogLoading = true;
      _catalogError = null;
    });
    try {
      final catalog = await widget.client.getJson('/admin/languages');
      if (!mounted) return;
      final byId = <String, Map<String, dynamic>>{};
      for (final row in [
        ..._listOfMaps(catalog['topicLanguages']),
        ..._listOfMaps(catalog['bibleLanguages']),
      ]) {
        if (row['standalone'] == true) continue;
        final id = row['id']?.toString() ?? '';
        if (id.isNotEmpty) byId[id] = row;
      }
      setState(() {
        _languages = byId.values.toList()
          ..sort(
            (a, b) =>
                nativeLanguageName(
                  a['id'].toString(),
                  a['name']?.toString() ?? '',
                ).compareTo(
                  nativeLanguageName(
                    b['id'].toString(),
                    b['name']?.toString() ?? '',
                  ),
                ),
          );
        if (_languages.isEmpty && _languageMode == 'existing') {
          _languageMode = 'new';
        }
      });
      if (_languages.isNotEmpty && _existingLanguage == null) {
        final selected = _languages.any((l) => l['id'] == 'english')
            ? 'english'
            : _languages.first['id'].toString();
        if (_languageMode == 'existing') {
          _selectExisting(selected);
        } else {
          setState(() => _existingLanguage = selected);
        }
      }
    } catch (error) {
      if (mounted) setState(() => _catalogError = error.toString());
    } finally {
      if (mounted) setState(() => _catalogLoading = false);
    }
  }

  void _selectExisting(String id) {
    final row = _languages.firstWhere((l) => l['id'] == id);
    _language.text = id;
    _languageName.text = nativeLanguageName(id, row['name']?.toString() ?? id);
    _related.clear();
    setState(() {
      _existingLanguage = id;
      _direction = row['direction']?.toString() ?? 'ltr';
    });
  }

  void _setMode(String mode) {
    _invalidateValidation();
    _related.clear();
    setState(() => _languageMode = mode);
    if (mode == 'existing' && _existingLanguage != null) {
      _selectExisting(_existingLanguage!);
    } else {
      _language.clear();
      _languageName.clear();
      setState(() => _direction = 'ltr');
    }
  }

  void _suggestMetadata(String value) {
    if (_displayName.text == _suggestedDisplay) _displayName.text = value;
    _suggestedDisplay = value;
    final suggestion = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    if (_versionId.text == _suggestedVersion) _versionId.text = suggestion;
    _suggestedVersion = suggestion;
  }

  void _acceptFiles(List<AdminUploadFile> files) {
    if (files.isEmpty ||
        files.length > 10 ||
        files.any(
          (f) => !f.name.toLowerCase().endsWith('.usfm') || f.size == 0,
        )) {
      throw AdminApiException(
        labels.t(
          'Select 1–10 non-empty .usfm files.',
          'اختر من ملف واحد إلى ١٠ ملفات USFM غير فارغة.',
        ),
      );
    }
    if (files.map((f) => f.name.toLowerCase()).toSet().length != files.length) {
      throw AdminApiException(
        labels.t(
          'Each file must have a different name.',
          'يجب أن يكون لكل ملف اسم مختلف.',
        ),
      );
    }
    if (files.fold<int>(0, (total, file) => total + file.size) >
        widget.maxUploadBytes) {
      throw AdminApiException(
        labels.fileTooLarge(_formatFileSize(widget.maxUploadBytes)),
      );
    }
    setState(() {
      _files = files;
      _validation = null;
      _progress = null;
      _replace = false;
      _error = null;
    });
  }

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
    try {
      final files = await widget.filePicker.pickFiles(
        allowedExtensions: const ['usfm'],
        allowMultiple: true,
      );
      if (!mounted || files == null) return;
      _acceptFiles(files);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _acceptDroppedFiles(DropDoneDetails details) async {
    if (details.files.length > 10 ||
        details.files.any((f) => !f.name.toLowerCase().endsWith('.usfm'))) {
      setState(
        () => _error = labels.t(
          'Select 1–10 .usfm files only.',
          'اختر من ملف واحد إلى ١٠ ملفات USFM فقط.',
        ),
      );
      return;
    }
    try {
      final files = <AdminUploadFile>[];
      for (final file in details.files) {
        files.add(
          AdminUploadFile(name: file.name, bytes: await file.readAsBytes()),
        );
      }
      if (mounted) _acceptFiles(files);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _validate() async {
    if (!_formKey.currentState!.validate()) return;
    if (_languageMode == 'existing' &&
        (_existingLanguage == null ||
            _catalogLoading ||
            _catalogError != null)) {
      setState(
        () => _error = labels.t(
          'Choose an existing language or use a new language/standalone translation.',
          'اختر لغة موجودة أو استخدم لغة جديدة أو ترجمة مستقلة.',
        ),
      );
      return;
    }
    if (_files.isEmpty) {
      setState(() => _error = labels.selectUsfm);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _validation = null;
      _progress = null;
      _replace = false;
    });
    try {
      final response = await widget.client.upload(
        '/admin/bibles/validate',
        fields: <String, String>{
          'languageMode': _languageMode,
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
    if (validation == null || validation['valid'] != true || _completed) return;
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
      if (!mounted) return;
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
    return Directionality(
      textDirection: widget.arabic ? TextDirection.rtl : TextDirection.ltr,
      child: _WizardDialog(
        title: labels.addBible,
        closeLabel: labels.close,
        busy: _busy,
        child: AbsorbPointer(
          absorbing: _busy,
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _StepTitle(number: 1, title: labels.language),
                DropdownButtonFormField<String>(
                  key: ValueKey('bible-language-mode-$_languageMode'),
                  initialValue: _languageMode,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: labels.t(
                      'Translation belongs to',
                      'نوع الترجمة',
                    ),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'existing',
                      child: Text(labels.t('Existing language', 'لغة موجودة')),
                    ),
                    DropdownMenuItem(
                      value: 'new',
                      child: Text(labels.t('New language', 'لغة جديدة')),
                    ),
                    DropdownMenuItem(
                      value: 'standalone',
                      child: Text(
                        labels.t('Standalone translation', 'ترجمة مستقلة'),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) _setMode(value);
                  },
                ),
                const SizedBox(height: 12),
                if (_languageMode == 'existing') ...[
                  if (_catalogLoading) const LinearProgressIndicator(),
                  if (_catalogError != null) ...[
                    _InlineError(_catalogError!),
                    TextButton(
                      onPressed: _loadLanguages,
                      child: Text(labels.retry),
                    ),
                  ],
                  DropdownButtonFormField<String>(
                    key: ValueKey('existing-bible-language-$_existingLanguage'),
                    initialValue: _existingLanguage,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: labels.language),
                    items: _languages
                        .map(
                          (row) => DropdownMenuItem(
                            value: row['id'].toString(),
                            child: Text(
                              nativeLanguageName(
                                row['id'].toString(),
                                row['name']?.toString() ?? '',
                              ),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: _catalogLoading
                        ? null
                        : (value) {
                            if (value != null) _selectExisting(value);
                          },
                    validator: (value) =>
                        value == null ? labels.required : null,
                  ),
                ] else if (_languageMode == 'new')
                  _metadataFields(_language, _languageName, labels, (value) {
                    _invalidateValidation();
                    setState(() => _direction = value);
                  }, _direction)
                else ...[
                  Text(
                    labels.t(
                      'This translation is available directly in the reader. No language or topics need to be created.',
                      'تتوفر هذه الترجمة مباشرة في القارئ دون إنشاء لغة أو مواضيع.',
                    ),
                  ),
                  DropdownButtonFormField<String>(
                    key: ValueKey('standalone-direction-$_direction'),
                    initialValue: _direction,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: labels.direction),
                    items: [
                      DropdownMenuItem(value: 'ltr', child: Text(labels.ltr)),
                      DropdownMenuItem(value: 'rtl', child: Text(labels.rtl)),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        _invalidateValidation();
                        setState(() => _direction = value);
                      }
                    },
                  ),
                ],
                if (_languageMode != 'standalone')
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      labels.t(
                        'Topic translations are optional. This Bible will be available in the reader independently.',
                        'ترجمة المواضيع اختيارية. سيتوفر هذا الكتاب المقدس في القارئ بصورة مستقلة.',
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                _StepTitle(number: 2, title: labels.translationMetadata),
                TextFormField(
                  key: const ValueKey<String>('translation-name'),
                  controller: _translation,
                  decoration: InputDecoration(
                    labelText: labels.translationName,
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? labels.required
                      : null,
                  onChanged: _suggestMetadata,
                ),
                TextFormField(
                  controller: _versionId,
                  validator: (value) =>
                      value == null ||
                          value.trim().isEmpty ||
                          !RegExp(
                            r'^[A-Za-z0-9][A-Za-z0-9 _-]{0,79}$',
                          ).hasMatch(value.trim())
                      ? labels.t(
                          'Enter a short identifier using Latin letters or numbers.',
                          'أدخل معرفًا مختصرًا بأحرف لاتينية أو أرقام.',
                        )
                      : null,
                  decoration: InputDecoration(labelText: labels.internalKey),
                ),
                TextFormField(
                  controller: _displayName,
                  validator: (value) => value == null || value.trim().isEmpty
                      ? labels.required
                      : null,
                  decoration: InputDecoration(labelText: labels.displayName),
                ),
                TextFormField(
                  controller: _description,
                  maxLines: 2,
                  decoration: InputDecoration(labelText: labels.description),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  isExpanded: true,
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
                  onChanged: (value) {
                    _invalidateValidation();
                    setState(() => _diacritics = value ?? 'auto');
                  },
                ),
                if (_languageMode == 'existing')
                  TextFormField(
                    controller: _related,
                    decoration: InputDecoration(
                      labelText: labels.relatedTranslation,
                    ),
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
                  if (_validation!['valid'] == true)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.info_outline),
                        title: Text(
                          labels.t(
                            'Validation complete — import still required',
                            'اكتمل التحقق — لا يزال الاستيراد مطلوبًا',
                          ),
                        ),
                        subtitle: Text(
                          labels.t(
                            'Review the preview, then select Import Bible Translation below. You can also finish later from Import History.',
                            'راجع المعاينة ثم اختر استيراد ترجمة الكتاب المقدس أدناه. يمكنك أيضًا الإكمال لاحقًا من سجل الاستيراد.',
                          ),
                        ),
                      ),
                    ),
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
                    onPressed:
                        _busy || _completed || _validation!['valid'] != true
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
        ),
      ),
    );
  }
}
