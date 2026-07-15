import 'package:flutter/material.dart';

import 'preference_language_catalog.dart';
import 'user_profile.dart';

typedef ProfileSaveCallback = Future<void> Function(UserProfile profile);

class ProfileEditorLabels {
  const ProfileEditorLabels._({required this.arabic});

  factory ProfileEditorLabels.forLanguage(String language) =>
      ProfileEditorLabels._(arabic: language.toLowerCase() == 'arabic');

  final bool arabic;

  String get completeProfile =>
      arabic ? 'إكمال الملف الشخصي' : 'Complete profile';
  String get setupDescription => arabic
      ? 'أضف معلومات أساسية واختر لغة القراءة والترجمة المفضلة.'
      : 'Add a few basics and choose your preferred reading language and translation.';
  String get profile => arabic ? 'الملف الشخصي' : 'Profile';
  String get languageTranslation =>
      arabic ? 'اللغة والترجمة' : 'Language and translation';
  String get readingPreferences =>
      arabic ? 'تفضيلات القراءة' : 'Reading preferences';
  String get accountInformation =>
      arabic ? 'معلومات الحساب' : 'Account information';
  String get firstName => arabic ? 'الاسم الأول' : 'First name';
  String get lastName => arabic ? 'اسم العائلة' : 'Last name';
  String get displayName => arabic ? 'اسم العرض' : 'Display name';
  String get country => arabic ? 'البلد' : 'Country';
  String get timezone => arabic ? 'المنطقة الزمنية' : 'Time zone';
  String get yearOfBirth => arabic ? 'سنة الميلاد' : 'Year of birth';
  String get organization =>
      arabic ? 'الكنيسة أو المؤسسة' : 'Church or organization';
  String get bio => arabic ? 'نبذة قصيرة' : 'Short profile description';
  String get email => arabic ? 'البريد الإلكتروني' : 'Email';
  String get menuLanguage => arabic ? 'لغة القوائم' : 'Menu language';
  String get contentLanguage => arabic ? 'لغة المحتوى' : 'Content language';
  String get preferredVersion =>
      arabic ? 'الترجمة المفضلة' : 'Preferred translation';
  String get defaultZoom => arabic ? 'التكبير الافتراضي' : 'Default zoom';
  String get showDiacritics => arabic
      ? 'إظهار الحركات العربية افتراضيًا'
      : 'Show Arabic diacritics by default';
  String get showTopicNames => arabic
      ? 'إظهار أسماء المواضيع داخل الفصول'
      : 'Show topic names inside chapters';
  String get interlinear => arabic
      ? 'تفعيل العرض المتوازي افتراضيًا'
      : 'Enable interlinear view by default';
  String get saveChanges => arabic ? 'حفظ التغييرات' : 'Save changes';
  String get completeSetup => arabic ? 'حفظ ومتابعة' : 'Save and continue';
  String get reset => arabic ? 'إلغاء التغييرات' : 'Reset unsaved changes';
  String get requiredField =>
      arabic ? 'هذا الحقل مطلوب.' : 'This field is required.';
  String get invalidYear => arabic
      ? 'أدخل سنة بين 1900 والسنة الحالية.'
      : 'Enter a year between 1900 and the current year.';
  String get tooLong => arabic ? 'النص طويل جدًا.' : 'This value is too long.';
  String get selectLanguage => arabic ? 'اختر اللغة.' : 'Choose a language.';
  String get selectVersion =>
      arabic ? 'اختر ترجمة متاحة.' : 'Choose an available translation.';
  String get loadError => arabic
      ? 'تعذر تحميل اللغات. تم استخدام الخيارات الأساسية.'
      : 'Languages could not be loaded. Bundled options are being used.';
  String get unavailableVersion => arabic
      ? 'الترجمة المحفوظة لم تعد متاحة. اختر ترجمة بديلة ثم احفظ.'
      : 'The saved translation is no longer available. Choose a replacement and save.';
  String get saveError => arabic
      ? 'تعذر حفظ التغييرات. حاول مرة أخرى.'
      : 'Changes could not be saved. Please try again.';
  String get optional => arabic ? 'اختياري' : 'Optional';
}

class ProfileEditor extends StatefulWidget {
  const ProfileEditor({
    super.key,
    required this.initialProfile,
    required this.onSave,
    this.setupMode = false,
    this.onDirtyChanged,
    this.onMenuLanguagePreview,
  });

  final UserProfile initialProfile;
  final ProfileSaveCallback onSave;
  final bool setupMode;
  final ValueChanged<bool>? onDirtyChanged;
  final ValueChanged<String>? onMenuLanguagePreview;

  @override
  State<ProfileEditor> createState() => ProfileEditorState();
}

class ProfileEditorState extends State<ProfileEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  late final TextEditingController _displayName;
  late final TextEditingController _country;
  late final TextEditingController _yearOfBirth;
  late final TextEditingController _organization;
  late final TextEditingController _bio;

  List<PreferenceLanguageOption> _languages = bundledPreferenceLanguages;
  bool _catalogLoading = true;
  bool _catalogFallback = false;
  bool _saving = false;
  bool _dirty = false;
  bool _menuManuallyChanged = false;
  late bool _requiresExplicitInitialVersion;
  String? _saveError;
  String? _versionWarning;
  late String _menuLanguage;
  late String _contentLanguage;
  late String _preferredVersion;
  late String _timezone;
  late bool _showDiacritics;
  late bool _interlinearEnabled;
  late bool _showTopicNames;
  late double _zoom;

  ProfileEditorLabels get _labels =>
      ProfileEditorLabels.forLanguage(_menuLanguage);

  PreferenceLanguageOption get _contentOption =>
      PreferenceLanguageCatalog.resolve(_languages, _contentLanguage);

  @override
  void initState() {
    super.initState();
    _initializeFrom(widget.initialProfile);
    for (final controller in <TextEditingController>[
      _firstName,
      _lastName,
      _displayName,
      _country,
      _yearOfBirth,
      _organization,
      _bio,
    ]) {
      controller.addListener(_markDirty);
    }
    _loadCatalog();
  }

  void _initializeFrom(UserProfile profile) {
    _firstName = TextEditingController(text: profile.firstName);
    _lastName = TextEditingController(text: profile.lastName);
    _displayName = TextEditingController(text: profile.displayName);
    _country = TextEditingController(text: profile.country);
    _yearOfBirth = TextEditingController(
      text: profile.yearOfBirth?.toString() ?? '',
    );
    _organization = TextEditingController(text: profile.organization);
    _bio = TextEditingController(text: profile.bio);
    _menuLanguage = profile.preferences.menuLanguage;
    _contentLanguage = profile.preferences.contentLanguage;
    _preferredVersion = profile.preferences.preferredVersion;
    _requiresExplicitInitialVersion =
        widget.setupMode &&
        !profile.profileCompleted &&
        profile.firstName.trim().isEmpty &&
        profile.lastName.trim().isEmpty;
    if (_requiresExplicitInitialVersion) {
      final initialOption = PreferenceLanguageCatalog.resolve(
        _languages,
        _contentLanguage,
      );
      if (initialOption.versions.length > 1) {
        _preferredVersion = '';
      }
    }
    _timezone = profile.timezone.isEmpty ? 'UTC' : profile.timezone;
    _showDiacritics = profile.preferences.showDiacritics;
    _interlinearEnabled = profile.preferences.interlinearEnabled;
    _showTopicNames = profile.preferences.showTopicNamesInChapter;
    _zoom = profile.preferences.zoomLevel;
  }

  Future<void> _loadCatalog() async {
    try {
      final languages = await PreferenceLanguageCatalog().load();
      if (!mounted) {
        return;
      }
      final selectedLanguage = PreferenceLanguageCatalog.resolve(
        languages,
        _contentLanguage,
      );
      final supportsSaved = selectedLanguage.supportsVersion(_preferredVersion);
      setState(() {
        _languages = languages;
        _contentLanguage = selectedLanguage.code;
        if (!supportsSaved && _preferredVersion.isNotEmpty) {
          _preferredVersion = selectedLanguage.sanitizeVersion(
            _preferredVersion,
          );
          _versionWarning = _labels.unavailableVersion;
        }
        _menuLanguage = PreferenceLanguageCatalog.resolve(
          languages,
          _menuLanguage,
        ).code;
        _catalogLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _catalogLoading = false;
        _catalogFallback = true;
      });
    }
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _displayName.dispose();
    _country.dispose();
    _yearOfBirth.dispose();
    _organization.dispose();
    _bio.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (_dirty) {
      return;
    }
    setState(() {
      _dirty = true;
    });
    widget.onDirtyChanged?.call(true);
  }

  void _setDirty() {
    if (!_dirty) {
      setState(() {
        _dirty = true;
      });
      widget.onDirtyChanged?.call(true);
    }
  }

  void _reset() {
    final profile = widget.initialProfile;
    _firstName.text = profile.firstName;
    _lastName.text = profile.lastName;
    _displayName.text = profile.displayName;
    _country.text = profile.country;
    _yearOfBirth.text = profile.yearOfBirth?.toString() ?? '';
    _organization.text = profile.organization;
    _bio.text = profile.bio;
    setState(() {
      _menuLanguage = profile.preferences.menuLanguage;
      _contentLanguage = profile.preferences.contentLanguage;
      final option = PreferenceLanguageCatalog.resolve(
        _languages,
        _contentLanguage,
      );
      _preferredVersion = option.sanitizeVersion(
        profile.preferences.preferredVersion,
      );
      _timezone = profile.timezone.isEmpty ? 'UTC' : profile.timezone;
      _showDiacritics = profile.preferences.showDiacritics;
      _interlinearEnabled = profile.preferences.interlinearEnabled;
      _showTopicNames = profile.preferences.showTopicNamesInChapter;
      _zoom = profile.preferences.zoomLevel;
      _saveError = null;
      _versionWarning =
          option.supportsVersion(profile.preferences.preferredVersion)
          ? null
          : _labels.unavailableVersion;
      _dirty = false;
      _menuManuallyChanged = false;
    });
    widget.onMenuLanguagePreview?.call(_menuLanguage);
    widget.onDirtyChanged?.call(false);
  }

  String? _requiredNameValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return _labels.requiredField;
    }
    if (value.trim().length > 80) {
      return _labels.tooLong;
    }
    return null;
  }

  String? _optionalLength(String? value, int maximum) {
    return (value?.trim().length ?? 0) > maximum ? _labels.tooLong : null;
  }

  String? _yearValidator(String? value) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) {
      return null;
    }
    final year = int.tryParse(normalized);
    if (year == null || year < 1900 || year > DateTime.now().year) {
      return _labels.invalidYear;
    }
    return null;
  }

  Future<void> _save() async {
    setState(() {
      _saveError = null;
    });
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final contentOption = _contentOption;
    if (!contentOption.supportsVersion(_preferredVersion)) {
      setState(() {
        _saveError = _labels.selectVersion;
      });
      return;
    }

    final rawYear = _yearOfBirth.text.trim();
    final profile = widget.initialProfile.copyWith(
      firstName: _firstName.text.trim(),
      lastName: _lastName.text.trim(),
      displayName: _displayName.text.trim(),
      country: _country.text.trim(),
      timezone: _timezone == 'Not set' ? '' : _timezone,
      yearOfBirth: rawYear.isEmpty ? null : int.parse(rawYear),
      clearYearOfBirth: rawYear.isEmpty,
      organization: _organization.text.trim(),
      bio: _bio.text.trim(),
      profileCompleted: true,
      preferences: UserPreferences(
        menuLanguage: _menuLanguage,
        contentLanguage: contentOption.code,
        preferredVersion: contentOption.sanitizeVersion(_preferredVersion),
        showDiacritics: contentOption.code == 'arabic' && _showDiacritics,
        zoomLevel: _zoom,
        interlinearEnabled: _interlinearEnabled,
        showTopicNamesInChapter: _showTopicNames,
      ),
    );

    setState(() {
      _saving = true;
    });
    try {
      await widget.onSave(profile);
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _dirty = false;
        _versionWarning = null;
      });
      widget.onDirtyChanged?.call(false);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _saveError = _labels.saveError;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final labels = _labels;
    final direction = PreferenceLanguageCatalog.resolve(
      _languages,
      _menuLanguage,
    ).direction;
    final timezoneOptions = <String>{
      'UTC',
      'Asia/Beirut',
      'Asia/Jerusalem',
      'Asia/Amman',
      'Asia/Dubai',
      'Europe/London',
      'Europe/Paris',
      'America/New_York',
      'America/Chicago',
      'America/Los_Angeles',
      _timezone,
    }.where((value) => value.isNotEmpty).toList();

    return Directionality(
      textDirection: direction,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.setupMode) ...[
              Text(
                labels.setupDescription,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 20),
            ],
            if (_catalogFallback)
              _InfoPanel(message: labels.loadError, warning: true),
            if (_versionWarning != null)
              _InfoPanel(message: _versionWarning!, warning: true),
            if (_saveError != null)
              _InfoPanel(message: _saveError!, error: true),
            _SectionCard(
              title: labels.profile,
              child: LayoutBuilder(
                builder: (context, constraints) => _FieldWrap(
                  width: constraints.maxWidth,
                  children: [
                    TextFormField(
                      key: const Key('profile-first-name'),
                      controller: _firstName,
                      decoration: InputDecoration(labelText: labels.firstName),
                      textInputAction: TextInputAction.next,
                      validator: _requiredNameValidator,
                    ),
                    TextFormField(
                      key: const Key('profile-last-name'),
                      controller: _lastName,
                      decoration: InputDecoration(labelText: labels.lastName),
                      textInputAction: TextInputAction.next,
                      validator: _requiredNameValidator,
                    ),
                    TextFormField(
                      controller: _displayName,
                      decoration: InputDecoration(
                        labelText: labels.displayName,
                        helperText: labels.optional,
                      ),
                      validator: (value) => _optionalLength(value, 80),
                    ),
                    TextFormField(
                      controller: _country,
                      decoration: InputDecoration(
                        labelText: labels.country,
                        helperText: labels.optional,
                      ),
                      validator: (value) => _optionalLength(value, 80),
                    ),
                    DropdownButtonFormField<String>(
                      key: ValueKey('profile-timezone-$_timezone'),
                      initialValue: _timezone,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: labels.timezone),
                      items: timezoneOptions
                          .map(
                            (timezone) => DropdownMenuItem<String>(
                              value: timezone,
                              child: Text(timezone),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setState(() => _timezone = value);
                        _setDirty();
                      },
                    ),
                    TextFormField(
                      controller: _yearOfBirth,
                      decoration: InputDecoration(
                        labelText: labels.yearOfBirth,
                        helperText: labels.optional,
                      ),
                      keyboardType: TextInputType.number,
                      validator: _yearValidator,
                    ),
                    TextFormField(
                      controller: _organization,
                      decoration: InputDecoration(
                        labelText: labels.organization,
                        helperText: labels.optional,
                      ),
                      validator: (value) => _optionalLength(value, 120),
                    ),
                  ],
                ),
              ),
            ),
            _SectionCard(
              title: labels.bio,
              child: TextFormField(
                controller: _bio,
                minLines: 3,
                maxLines: 5,
                maxLength: 500,
                decoration: InputDecoration(hintText: labels.optional),
                validator: (value) => _optionalLength(value, 500),
              ),
            ),
            _SectionCard(
              title: labels.languageTranslation,
              child: LayoutBuilder(
                builder: (context, constraints) => _FieldWrap(
                  width: constraints.maxWidth,
                  children: [
                    DropdownButtonFormField<String>(
                      key: ValueKey('profile-menu-language-$_menuLanguage'),
                      initialValue: _menuLanguage,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: labels.menuLanguage,
                      ),
                      items: _languages
                          .map(
                            (language) => DropdownMenuItem<String>(
                              value: language.code,
                              child: Text(language.label),
                            ),
                          )
                          .toList(),
                      onChanged: _catalogLoading
                          ? null
                          : (value) {
                              if (value == null) {
                                return;
                              }
                              setState(() {
                                _menuLanguage = value;
                                _menuManuallyChanged = true;
                              });
                              widget.onMenuLanguagePreview?.call(value);
                              _setDirty();
                            },
                      validator: (value) => value == null || value.isEmpty
                          ? labels.selectLanguage
                          : null,
                    ),
                    DropdownButtonFormField<String>(
                      key: ValueKey(
                        'profile-content-language-$_contentLanguage',
                      ),
                      initialValue: _contentLanguage,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: labels.contentLanguage,
                      ),
                      items: _languages
                          .map(
                            (language) => DropdownMenuItem<String>(
                              value: language.code,
                              child: Text(language.label),
                            ),
                          )
                          .toList(),
                      onChanged: _catalogLoading
                          ? null
                          : (value) {
                              if (value == null) {
                                return;
                              }
                              final option = PreferenceLanguageCatalog.resolve(
                                _languages,
                                value,
                              );
                              setState(() {
                                _contentLanguage = option.code;
                                _preferredVersion =
                                    widget.setupMode &&
                                        option.versions.length > 1
                                    ? ''
                                    : option.defaultVersion;
                                _showDiacritics =
                                    option.code == 'arabic' && _showDiacritics;
                                _versionWarning = null;
                                if (!_menuManuallyChanged) {
                                  _menuLanguage = option.code;
                                }
                              });
                              if (!_menuManuallyChanged) {
                                widget.onMenuLanguagePreview?.call(option.code);
                              }
                              _setDirty();
                            },
                    ),
                    DropdownButtonFormField<String>(
                      key: ValueKey(
                        'profile-version-$_contentLanguage-$_preferredVersion',
                      ),
                      initialValue:
                          _contentOption.supportsVersion(_preferredVersion)
                          ? _preferredVersion
                          : null,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: labels.preferredVersion,
                      ),
                      items: _contentOption.versions
                          .map(
                            (version) => DropdownMenuItem<String>(
                              value: version.id,
                              child: Text(version.label),
                            ),
                          )
                          .toList(),
                      onChanged: _catalogLoading
                          ? null
                          : (value) {
                              if (value == null) {
                                return;
                              }
                              setState(() {
                                _preferredVersion = value;
                                _versionWarning = null;
                              });
                              _setDirty();
                            },
                      validator: (value) =>
                          value == null ||
                              !_contentOption.supportsVersion(value)
                          ? labels.selectVersion
                          : null,
                    ),
                  ],
                ),
              ),
            ),
            _SectionCard(
              title: labels.readingPreferences,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(labels.defaultZoom)),
                      Text('${(_zoom * 100).round()}%'),
                    ],
                  ),
                  Slider(
                    key: const Key('profile-default-zoom'),
                    value: _zoom,
                    min: minimumProfileZoom,
                    max: maximumProfileZoom,
                    divisions: 8,
                    label: '${(_zoom * 100).round()}%',
                    onChanged: (value) {
                      setState(() => _zoom = value);
                      _setDirty();
                    },
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text(labels.showDiacritics),
                    value: _showDiacritics,
                    onChanged: _contentLanguage == 'arabic'
                        ? (value) {
                            setState(() => _showDiacritics = value);
                            _setDirty();
                          }
                        : null,
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text(labels.showTopicNames),
                    value: _showTopicNames,
                    onChanged: (value) {
                      setState(() => _showTopicNames = value);
                      _setDirty();
                    },
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text(labels.interlinear),
                    value: _interlinearEnabled,
                    onChanged: (value) {
                      setState(() => _interlinearEnabled = value);
                      _setDirty();
                    },
                  ),
                ],
              ),
            ),
            _SectionCard(
              title: labels.accountInformation,
              child: TextFormField(
                initialValue: widget.initialProfile.email,
                readOnly: true,
                decoration: InputDecoration(
                  labelText: labels.email,
                  prefixIcon: const Icon(Icons.lock_outline),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 12,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _saving || !_dirty ? null : _reset,
                  child: Text(labels.reset),
                ),
                FilledButton.icon(
                  key: const Key('profile-save'),
                  onPressed: _saving || _catalogLoading ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(
                    widget.setupMode
                        ? labels.completeSetup
                        : labels.saveChanges,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _FieldWrap extends StatelessWidget {
  const _FieldWrap({required this.width, required this.children});

  final double width;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final fieldWidth = width >= 720 ? (width - 16) / 2 : width;
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: children
          .map((child) => SizedBox(width: fieldWidth, child: child))
          .toList(),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({
    required this.message,
    this.warning = false,
    this.error = false,
  });

  final String message;
  final bool warning;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = error
        ? colors.errorContainer
        : warning
        ? colors.tertiaryContainer
        : colors.secondaryContainer;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(message),
    );
  }
}
