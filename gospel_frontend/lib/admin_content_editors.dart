part of 'admin_portal.dart';

String _contentPath(String kind, List<String> ids) =>
    '/admin/content/$kind/${ids.map(Uri.encodeComponent).join('/')}';

Future<bool> _discardEdits(BuildContext context, _AdminLabels labels) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: labels.arabic ? TextDirection.rtl : TextDirection.ltr,
        child: AlertDialog(
          title: Text(
            labels.t(
              'Discard unsaved changes?',
              'تجاهل التعديلات غير المحفوظة؟',
            ),
          ),
          content: Text(
            labels.t(
              'Your saved content will remain unchanged.',
              'سيبقى المحتوى المحفوظ كما هو.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(labels.t('Keep editing', 'متابعة التعديل')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(labels.t('Discard', 'تجاهل')),
            ),
          ],
        ),
      ),
    ) ==
    true;

class _EditorFrame extends StatelessWidget {
  const _EditorFrame({
    required this.title,
    required this.labels,
    required this.busy,
    required this.dirty,
    required this.child,
    required this.onSave,
    required this.onReload,
    this.error,
  });
  final String title;
  final _AdminLabels labels;
  final bool busy, dirty;
  final Widget child;
  final VoidCallback? onSave;
  final VoidCallback onReload;
  final String? error;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy && !dirty,
    onPopInvokedWithResult: (didPop, result) async {
      if (!didPop &&
          !busy &&
          await _discardEdits(context, labels) &&
          context.mounted) {
        Navigator.of(context).pop();
      }
    },
    child: Directionality(
      textDirection: labels.arabic ? TextDirection.rtl : TextDirection.ltr,
      child: Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 880),
          child: Column(
            children: [
              ListTile(
                title: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                subtitle: dirty
                    ? Text(labels.t('Unsaved changes', 'تعديلات غير محفوظة'))
                    : null,
                trailing: IconButton(
                  tooltip: labels.close,
                  onPressed: busy
                      ? null
                      : () async {
                          if ((!dirty ||
                                  await _discardEdits(context, labels)) &&
                              context.mounted) {
                            Navigator.of(context).pop();
                          }
                        },
                  icon: const Icon(Icons.close),
                ),
              ),
              const Divider(height: 1),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _InlineError(error!),
                ),
              Expanded(
                child: AbsorbPointer(absorbing: busy, child: child),
              ),
              if (busy) const LinearProgressIndicator(),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: busy
                          ? null
                          : () async {
                              if (!dirty ||
                                  await _discardEdits(context, labels)) {
                                onReload();
                              }
                            },
                      icon: const Icon(Icons.refresh),
                      label: Text(labels.t('Reload', 'إعادة التحميل')),
                    ),
                    FilledButton.icon(
                      key: const ValueKey('save-content'),
                      onPressed: busy || !dirty ? null : onSave,
                      icon: const Icon(Icons.save_outlined),
                      label: Text(labels.t('Save changes', 'حفظ التعديلات')),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class TopicContentEditor extends StatefulWidget {
  const TopicContentEditor({
    super.key,
    required this.client,
    required this.arabic,
    required this.language,
    required this.onSaved,
  });
  final AdminClient client;
  final bool arabic;
  final String language;
  final VoidCallback onSaved;
  @override
  State<TopicContentEditor> createState() => _TopicContentEditorState();
}

class _TopicContentEditorState extends State<TopicContentEditor> {
  final _name = TextEditingController();
  final Map<String, TextEditingController> _gospels = {};
  final Map<String, TextEditingController> _names = {};
  Map<String, dynamic>? _data;
  String _direction = 'ltr', _query = '';
  bool _busy = true, _dirty = false;
  String? _error;
  _AdminLabels get labels => _AdminLabels(widget.arabic);
  String get _path => _contentPath('topics', [widget.language]);
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _changed() => setState(() => _dirty = true);
  @override
  void dispose() {
    _name.dispose();
    for (final c in [..._gospels.values, ..._names.values]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await widget.client.getJson(_path);
      if (!mounted) return;
      final metadata = Map<String, dynamic>.from(data['metadata'] as Map);
      for (final c in [..._gospels.values, ..._names.values]) {
        c.dispose();
      }
      _gospels.clear();
      _names.clear();
      _name.text = metadata['displayName']?.toString() ?? widget.language;
      _direction = metadata['direction']?.toString() ?? 'ltr';
      for (final book in ['Matthew', 'Mark', 'Luke', 'John']) {
        _gospels[book] = TextEditingController(
          text: (metadata['gospels'] as Map?)?[book]?.toString() ?? book,
        );
      }
      for (final row in _listOfMaps(data['topics'])) {
        _names[row['id'].toString()] = TextEditingController(
          text: row['name']?.toString() ?? '',
        );
      }
      setState(() {
        _data = data;
        _dirty = false;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty ||
        _gospels.values.any((c) => c.text.trim().isEmpty) ||
        _listOfMaps(_data?['topics']).any(
          (row) =>
              _names[row['id'].toString()]!.text.trim().isEmpty &&
              _names[row['id'].toString()]!.text != row['name'],
        )) {
      setState(
        () => _error = labels.t(
          'Display names and topic names cannot be empty.',
          'لا يمكن ترك أسماء العرض والمواضيع فارغة.',
        ),
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.client.postJson(_path, {
        'revision': _data!['revision'],
        'metadata': {
          'displayName': _name.text.trim(),
          'direction': _direction,
          'gospels': _gospels.map(
            (key, value) => MapEntry(key, value.text.trim()),
          ),
        },
        'topics': [
          for (final row in _listOfMaps(_data!['topics']))
            if (_names[row['id'].toString()]!.text != row['name'])
              {
                'id': row['id'],
                'name': _names[row['id'].toString()]!.text.trim(),
              },
        ],
      });
      if (!mounted) return;
      widget.onSaved();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              labels.t('Topic changes saved.', 'تم حفظ تعديلات المواضيع.'),
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _listOfMaps(_data?['topics']).where((row) {
      final id = row['id'].toString();
      return '$id ${row['name']} ${_names[id]?.text}'.toLowerCase().contains(
        _query.toLowerCase(),
      );
    }).toList();
    return _EditorFrame(
      title:
          '${labels.t('Edit topics', 'تعديل المواضيع')} · ${widget.language}',
      labels: labels,
      busy: _busy,
      dirty: _dirty,
      error: _error,
      onSave: _data == null ? null : _save,
      onReload: _load,
      child: _data == null
          ? Center(
              child: _busy
                  ? const CircularProgressIndicator()
                  : Text(
                      labels.t(
                        'Content could not be loaded.',
                        'تعذر تحميل المحتوى.',
                      ),
                    ),
            )
          : Column(
              children: [
                ExpansionTile(
                  title: Text(labels.t('Language settings', 'إعدادات اللغة')),
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              TextField(
                                controller: _name,
                                maxLength: 120,
                                decoration: InputDecoration(
                                  labelText: labels.displayName,
                                ),
                                onChanged: (_) => _changed(),
                              ),
                              DropdownButtonFormField<String>(
                                isExpanded: true,
                                key: ValueKey('topic-direction-$_direction'),
                                initialValue: _direction,
                                decoration: InputDecoration(
                                  labelText: labels.direction,
                                ),
                                items: [
                                  DropdownMenuItem(
                                    value: 'ltr',
                                    child: Text(labels.ltr),
                                  ),
                                  DropdownMenuItem(
                                    value: 'rtl',
                                    child: Text(labels.rtl),
                                  ),
                                ],
                                onChanged: (value) {
                                  if (value != null) {
                                    setState(() {
                                      _direction = value;
                                      _dirty = true;
                                    });
                                  }
                                },
                              ),
                              for (final entry in _gospels.entries)
                                TextField(
                                  controller: entry.value,
                                  maxLength: 120,
                                  decoration: InputDecoration(
                                    labelText: entry.key,
                                  ),
                                  onChanged: (_) => _changed(),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        labels.t(
                          'Edit names directly. Gospel references are shared by all languages and come from Master Harmony.',
                          'عدّل الأسماء مباشرة. مراجع الأناجيل مشتركة بين جميع اللغات وتأتي من جدول التناغم الرئيسي.',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          labelText: labels.t(
                            'Search by topic number or name',
                            'البحث برقم الموضوع أو اسمه',
                          ),
                        ),
                        onChanged: (value) => setState(() => _query = value),
                      ),
                      Text(
                        '${rows.length} / ${_names.length} ${labels.topicRecords}',
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Directionality(
                    textDirection: _direction == 'rtl'
                        ? TextDirection.rtl
                        : TextDirection.ltr,
                    child: ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final row = rows[index];
                        final id = row['id'].toString();
                        final refs = row['references'] is Map
                            ? Map<String, dynamic>.from(
                                row['references'] as Map,
                              )
                            : <String, dynamic>{};
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 48,
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 16),
                                  child: Text('#$id'),
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    TextField(
                                      key: ValueKey('topic-name-$id'),
                                      controller: _names[id],
                                      minLines: 1,
                                      maxLines: 3,
                                      maxLength: 1000,
                                      decoration: InputDecoration(
                                        border: const OutlineInputBorder(),
                                        labelText: labels.topic,
                                      ),
                                      onChanged: (_) => _changed(),
                                    ),
                                    Text(
                                      refs.entries
                                          .where((e) => '${e.value}'.isNotEmpty)
                                          .map((e) => '${e.key} ${e.value}')
                                          .join(' · '),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class BibleContentEditor extends StatefulWidget {
  const BibleContentEditor({
    super.key,
    required this.client,
    required this.arabic,
    required this.language,
    required this.version,
    required this.onSaved,
  });
  final AdminClient client;
  final bool arabic;
  final String language, version;
  final VoidCallback onSaved;
  @override
  State<BibleContentEditor> createState() => _BibleContentEditorState();
}

class _BibleContentEditorState extends State<BibleContentEditor> {
  final _languageName = TextEditingController(),
      _name = TextEditingController(),
      _description = TextEditingController(),
      _related = TextEditingController();
  Map<String, dynamic>? _data;
  String _direction = 'ltr';
  bool _containsDiacritics = false, _standalone = false;
  String? _book, _chapter, _error;
  bool _busy = true, _dirty = false;
  _AdminLabels get labels => _AdminLabels(widget.arabic);
  String get _path => _contentPath('bibles', [widget.language, widget.version]);
  List<Map<String, dynamic>> get _books => _listOfMaps(_data?['books']);
  List<String> get _chapters => _books
      .where((b) => b['id'] == _book)
      .expand((b) => (b['chapters'] as List? ?? []).map((c) => c.toString()))
      .toList();
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _languageName.dispose();
    _name.dispose();
    _description.dispose();
    _related.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await widget.client.getJson(_path);
      if (!mounted) return;
      final metadata = Map<String, dynamic>.from(data['metadata'] as Map);
      _languageName.text =
          metadata['languageDisplayName']?.toString() ?? widget.language;
      _name.text = metadata['displayName']?.toString() ?? widget.version;
      _description.text = metadata['description']?.toString() ?? '';
      _related.text = metadata['relatedTranslation']?.toString() ?? '';
      _containsDiacritics = metadata['containsDiacritics'] == true;
      _standalone = metadata['standalone'] == true;
      _direction = metadata['direction']?.toString() ?? 'ltr';
      setState(() {
        _data = data;
        _dirty = false;
        if (!_books.any((b) => b['id'] == _book)) {
          _book = _books.firstOrNull?['id'].toString();
        }
        if (!_chapters.contains(_chapter)) _chapter = _chapters.firstOrNull;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _languageName.text.trim().isEmpty) {
      setState(() => _error = labels.required);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.client.postJson(_path, {
        'revision': _data!['revision'],
        'metadata': {
          'languageDisplayName': _languageName.text.trim(),
          'direction': _direction,
          'displayName': _name.text.trim(),
          'description': _description.text.trim(),
          'containsDiacritics': _containsDiacritics,
          'relatedTranslation': _related.text.trim(),
        },
      });
      if (!mounted) return;
      widget.onSaved();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              labels.t('Translation details saved.', 'تم حفظ تفاصيل الترجمة.'),
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openChapter() async {
    if (_dirty && !await _discardEdits(context, labels)) return;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BibleChapterEditor(
        client: widget.client,
        arabic: widget.arabic,
        language: widget.language,
        version: widget.version,
        book: _book!,
        chapter: _chapter!,
        direction: _direction,
        onSaved: widget.onSaved,
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) => _EditorFrame(
    title:
        '${labels.t('Edit translation', 'تعديل الترجمة')} · ${widget.language} / ${widget.version}',
    labels: labels,
    busy: _busy,
    dirty: _dirty,
    error: _error,
    onSave: _data == null ? null : _save,
    onReload: _load,
    child: _data == null
        ? Center(
            child: _busy
                ? const CircularProgressIndicator()
                : Text(
                    labels.t(
                      'Content could not be loaded.',
                      'تعذر تحميل المحتوى.',
                    ),
                  ),
          )
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                labels.t(
                  'Edit Bible text by chapter',
                  'تعديل نص الكتاب المقدس حسب الفصل',
                ),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                isExpanded: true,
                key: ValueKey('book-$_book'),
                initialValue: _book,
                decoration: InputDecoration(
                  labelText: labels.t('Book', 'السفر'),
                ),
                items: _books
                    .map(
                      (b) => DropdownMenuItem(
                        value: b['id'].toString(),
                        child: Text(b['id'].toString()),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() {
                  _book = value;
                  _chapter = _chapters.firstOrNull;
                }),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                isExpanded: true,
                key: ValueKey('chapter-$_book-$_chapter'),
                initialValue: _chapter,
                decoration: InputDecoration(
                  labelText: labels.t('Chapter', 'الفصل'),
                ),
                items: _chapters
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (value) => setState(() => _chapter = value),
              ),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                key: const ValueKey('edit-bible-chapter'),
                onPressed: _book == null || _chapter == null
                    ? null
                    : _openChapter,
                icon: const Icon(Icons.edit_note),
                label: Text(
                  labels.t('Edit verses & headings', 'تعديل الآيات والعناوين'),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                labels.t('Translation details', 'تفاصيل الترجمة'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (!_standalone)
                TextField(
                  controller: _languageName,
                  maxLength: 120,
                  decoration: InputDecoration(
                    labelText: labels.t(
                      'Language name (native spelling)',
                      'اسم اللغة بلغتها الأصلية',
                    ),
                  ),
                  onChanged: (_) => setState(() => _dirty = true),
                ),
              DropdownButtonFormField<String>(
                isExpanded: true,
                key: ValueKey('bible-direction-$_direction'),
                initialValue: _direction,
                decoration: InputDecoration(labelText: labels.direction),
                items: [
                  DropdownMenuItem(value: 'ltr', child: Text(labels.ltr)),
                  DropdownMenuItem(value: 'rtl', child: Text(labels.rtl)),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _direction = value;
                      _dirty = true;
                    });
                  }
                },
              ),
              TextField(
                controller: _name,
                maxLength: 120,
                decoration: InputDecoration(labelText: labels.translationName),
                onChanged: (_) => setState(() => _dirty = true),
              ),
              SwitchListTile(
                title: Text(labels.diacritics),
                value: _containsDiacritics,
                onChanged: (value) => setState(() {
                  _containsDiacritics = value;
                  _dirty = true;
                }),
              ),
              if (!_standalone)
                TextField(
                  controller: _related,
                  decoration: InputDecoration(
                    labelText: labels.relatedTranslation,
                  ),
                  maxLength: 80,
                  onChanged: (_) => setState(() => _dirty = true),
                ),
              if (_standalone)
                Text(
                  labels.t(
                    'Standalone translation — no topics or language association required.',
                    'ترجمة مستقلة — لا تتطلب مواضيع أو ربطًا بلغة.',
                  ),
                ),
              TextField(
                controller: _description,
                maxLength: 1000,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(labelText: labels.description),
                onChanged: (_) => setState(() => _dirty = true),
              ),
            ],
          ),
  );
}

class BibleChapterEditor extends StatefulWidget {
  const BibleChapterEditor({
    super.key,
    required this.client,
    required this.arabic,
    required this.language,
    required this.version,
    required this.book,
    required this.chapter,
    required this.direction,
    required this.onSaved,
  });
  final AdminClient client;
  final bool arabic;
  final String language, version, book, chapter, direction;
  final VoidCallback onSaved;
  @override
  State<BibleChapterEditor> createState() => _BibleChapterEditorState();
}

class _BibleChapterEditorState extends State<BibleChapterEditor> {
  final Map<String, TextEditingController> _texts = {}, _titles = {};
  Map<String, dynamic>? _data;
  bool _busy = true, _dirty = false;
  String? _error;
  _AdminLabels get labels => _AdminLabels(widget.arabic);
  String get _path => _contentPath('bibles', [
    widget.language,
    widget.version,
    widget.book,
    widget.chapter,
  ]);
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [..._texts.values, ..._titles.values]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await widget.client.getJson(_path);
      if (!mounted) return;
      for (final c in [..._texts.values, ..._titles.values]) {
        c.dispose();
      }
      _texts.clear();
      _titles.clear();
      for (final row in _listOfMaps(data['verses'])) {
        final id = row['id'].toString();
        _texts[id] = TextEditingController(text: row['text']?.toString() ?? '');
        _titles[id] = TextEditingController(
          text: row['title']?.toString() ?? '',
        );
      }
      setState(() {
        _data = data;
        _dirty = false;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final changes = [
      for (final row in _listOfMaps(_data!['verses']))
        if (_texts[row['id'].toString()]!.text != row['text'] ||
            _titles[row['id'].toString()]!.text != row['title'])
          {
            'id': row['id'],
            'text': _texts[row['id'].toString()]!.text.trim(),
            'title': _titles[row['id'].toString()]!.text.trim(),
          },
    ];
    if (changes.isEmpty) {
      setState(() {
        _dirty = false;
        _error = null;
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.client.postJson(_path, {
        'revision': _data!['revision'],
        'verses': changes,
      });
      if (!mounted) return;
      widget.onSaved();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              labels.t('Chapter changes saved.', 'تم حفظ تعديلات الفصل.'),
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _EditorFrame(
    title: '${widget.version} · ${widget.book} ${widget.chapter}',
    labels: labels,
    busy: _busy,
    dirty: _dirty,
    error: _error,
    onSave: _data == null ? null : _save,
    onReload: _load,
    child: _data == null
        ? Center(
            child: _busy
                ? const CircularProgressIndicator()
                : Text(
                    labels.t(
                      'Content could not be loaded.',
                      'تعذر تحميل المحتوى.',
                    ),
                  ),
          )
        : Directionality(
            textDirection: widget.direction == 'rtl'
                ? TextDirection.rtl
                : TextDirection.ltr,
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _texts.length,
              itemBuilder: (context, index) {
                final id = _texts.keys.elementAt(index);
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${widget.book} ${widget.chapter}:$id',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        TextField(
                          key: ValueKey('verse-title-$id'),
                          controller: _titles[id],
                          minLines: 1,
                          maxLines: 4,
                          maxLength: 2000,
                          decoration: InputDecoration(
                            labelText: labels.t(
                              'Heading before verse (optional)',
                              'عنوان قبل الآية (اختياري)',
                            ),
                          ),
                          onChanged: (_) => setState(() => _dirty = true),
                        ),
                        TextField(
                          key: ValueKey('verse-text-$id'),
                          controller: _texts[id],
                          minLines: 2,
                          maxLines: 10,
                          maxLength: 20000,
                          decoration: InputDecoration(
                            labelText: labels.t('Verse text', 'نص الآية'),
                            border: const OutlineInputBorder(),
                          ),
                          onChanged: (_) => setState(() => _dirty = true),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
  );
}
