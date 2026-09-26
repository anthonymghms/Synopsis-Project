part of 'admin_portal.dart';

class InterfaceImportWizard extends StatefulWidget {
  const InterfaceImportWizard({
    super.key,
    required this.client,
    required this.arabic,
    required this.language,
    required this.languageLabel,
    required this.onCompleted,
    this.filePicker = const PlatformAdminFilePicker(),
    this.csvDownloader = downloadCsv,
  });
  final AdminClient client;
  final bool arabic;
  final String language;
  final String languageLabel;
  final VoidCallback onCompleted;
  final AdminFilePicker filePicker;
  final Future<void> Function(String contents, String filename) csvDownloader;

  @override
  State<InterfaceImportWizard> createState() => _InterfaceImportWizardState();
}

class _InterfaceImportWizardState extends State<InterfaceImportWizard> {
  AdminUploadFile? _file;
  Map<String, dynamic>? _validation;
  Map<String, dynamic>? _progress;
  String? _error;
  bool _busy = false;
  bool _replace = false;
  bool get _completed => _progress?['status'] == 'completed';
  _AdminLabels get labels => _AdminLabels(widget.arabic);

  Future<void> _download() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.client.getJson(
        '/admin/interface-translations/template/${Uri.encodeComponent(widget.language)}',
      );
      await widget.csvDownloader(
        result['csv'] as String,
        result['filename'] as String,
      );
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
      if (file.size > 512 * 1024) {
        throw AdminApiException(labels.fileTooLarge('512 KB'));
      }
      setState(() {
        _file = file;
        _validation = null;
        _progress = null;
        _replace = false;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _validate() async {
    if (_file == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _validation = null;
      _replace = false;
    });
    try {
      final result = await widget.client.upload(
        '/admin/interface-translations/validate',
        fields: {'language': widget.language},
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

  Future<void> _import() async {
    final validation = _validation;
    if (validation == null ||
        validation['valid'] != true ||
        _completed ||
        (validation['collision'] == true && !_replace)) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final importId = validation['importId'].toString();
      await widget.client.postJson('/admin/interface-translations/import', {
        'importId': importId,
        'confirm': true,
        'replace': _replace,
      });
      while (mounted) {
        final response = await widget.client.getJson(
          '/admin/imports/$importId',
        );
        if (!mounted) return;
        final record = Map<String, dynamic>.from(response['import'] as Map);
        setState(() => _progress = record);
        if (record['status'] == 'completed') {
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
        await Future<void>.delayed(const Duration(milliseconds: 1200));
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _WizardDialog(
    title: '${labels.interfaceTranslations} · ${widget.languageLabel}',
    closeLabel: labels.close,
    busy: _busy,
    child: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(labels.interfaceCsvInstructions),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const ValueKey('download-interface-template'),
          onPressed: _busy ? null : _download,
          icon: const Icon(Icons.download),
          label: Text(labels.downloadInterfaceTemplate),
        ),
        const SizedBox(height: 20),
        if (_file == null)
          _UploadDropSurface(
            message: labels.selectCsv,
            buttonLabel: labels.selectCsv,
            buttonKey: const ValueKey('select-interface-file'),
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
                    _validation = null;
                    _progress = null;
                    _replace = false;
                    _error = null;
                  }),
          ),
        const SizedBox(height: 20),
        FilledButton.icon(
          key: const ValueKey('validate-interface-upload'),
          onPressed: _busy || _file == null || _completed ? null : _validate,
          icon: const Icon(Icons.fact_check_outlined),
          label: Text(labels.validate),
        ),
        if (_error != null) _InlineError(_error!),
        if (_validation case final validation?) ...[
          const SizedBox(height: 16),
          _ValidationSummary(data: validation, labels: labels),
          if (validation['missingKeys'] is List &&
              (validation['missingKeys'] as List).isNotEmpty)
            ExpansionTile(
              title: Text(labels.missingInterfaceLabels),
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(
                    (validation['missingKeys'] as List).join(', '),
                  ),
                ),
              ],
            ),
          ExpansionTile(
            title: Text(labels.preview),
            children: [
              for (final row in _listOfMaps(validation['preview']))
                ListTile(
                  title: Text(row['translation']?.toString() ?? ''),
                  subtitle: Text('${row['key']} · ${row['english']}'),
                ),
            ],
          ),
          if (validation['collision'] == true)
            CheckboxListTile(
              key: const ValueKey('replace-interface-translations'),
              value: _replace,
              onChanged: _busy || _completed
                  ? null
                  : (value) => setState(() => _replace = value == true),
              title: Text(labels.replaceInterfaceTranslations),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const ValueKey('import-interface-upload'),
            onPressed:
                _busy ||
                    _completed ||
                    validation['valid'] != true ||
                    (validation['collision'] == true && !_replace)
                ? null
                : _import,
            icon: const Icon(Icons.cloud_upload_outlined),
            label: Text(labels.importInterfaceTranslations),
          ),
        ],
        if (_progress != null) _ProgressCard(data: _progress!, labels: labels),
      ],
    ),
  );
}
