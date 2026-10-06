import 'package:flutter/material.dart';

import 'admin_api_client.dart';

/// Account directory and access settings backed by the admin-only API.
class AdminUsersPanel extends StatefulWidget {
  const AdminUsersPanel({
    super.key,
    required this.client,
    required this.arabic,
  });

  final AdminClient client;
  final bool arabic;

  @override
  State<AdminUsersPanel> createState() => _AdminUsersPanelState();
}

class _AdminUsersPanelState extends State<AdminUsersPanel> {
  final _filter = TextEditingController();
  List<Map<String, dynamic>> _users = [];
  List<String?> _pageTokens = [null];
  String? _nextToken;
  String? _error;
  bool _loading = true;
  int _page = 0;
  int _retryPage = 0;
  String? _retryToken;

  String _t(String english, String arabic) => widget.arabic ? arabic : english;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  Future<void> _load({
    int page = 0,
    String? token,
    bool refresh = false,
  }) async {
    setState(() {
      _loading = true;
      _error = null;
      _retryPage = page;
      _retryToken = token;
    });
    try {
      final path = Uri(
        path: '/admin/users',
        queryParameters: {
          'pageSize': '50',
          if (token != null) 'pageToken': token,
        },
      ).toString();
      final response = await widget.client.getJson(path);
      if (!mounted) return;
      setState(() {
        _users = (response['users'] as List? ?? [])
            .whereType<Map>()
            .map((user) => Map<String, dynamic>.from(user))
            .toList();
        _nextToken = response['nextPageToken'] as String?;
        _page = page;
        if (refresh) _pageTokens = [null];
        _pageTokens = [..._pageTokens.take(page), token];
        _filter.clear();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is AdminApiException
            ? error.message
            : _t(
                'Users could not be loaded. Try again.',
                'تعذر تحميل المستخدمين. حاول مجددًا.',
              );
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _permission(String permission) => switch (permission) {
    'read_content' => _t(
      'Read Bible and topics',
      'قراءة الكتاب المقدس والمواضيع',
    ),
    'manage_own_profile' => _t(
      'Edit own profile and preferences',
      'تعديل الملف الشخصي والتفضيلات',
    ),
    'manage_content' => _t(
      'Import and edit Bible, topics and interface text',
      'استيراد وتعديل الكتاب المقدس والمواضيع ونصوص الواجهة',
    ),
    'view_import_history' => _t('View import history', 'عرض سجل الاستيراد'),
    'view_users' => _t(
      'View users and permissions',
      'عرض المستخدمين والصلاحيات',
    ),
    'manage_users' => _t(
      'Manage user roles and guest access',
      'إدارة أدوار المستخدمين ووصول الضيوف',
    ),
    _ => permission,
  };

  String _roleSource(String? source) => switch (source) {
    'custom_claim' => _t('Firebase account role', 'دور حساب Firebase'),
    'users_role' => _t(
      'Administrator-assigned profile role',
      'دور الملف الشخصي المعيّن من الإدارة',
    ),
    'membership' => _t('Account access settings', 'إعدادات صلاحيات الحساب'),
    'default_guest' => _t('Default guest access', 'صلاحيات الضيف الافتراضية'),
    'new_account' => _t(
      'New account: 30-day guest access',
      'حساب جديد: وصول ضيف لمدة ٣٠ يومًا',
    ),
    'legacy_account' => _t('Existing account access', 'صلاحيات الحساب السابق'),
    _ => _t('Standard account access', 'صلاحيات الحساب العادي'),
  };

  String _date(dynamic raw) {
    final date = DateTime.tryParse(raw?.toString() ?? '');
    if (date == null) return _t('Not recorded', 'غير مسجّل');
    return MaterialLocalizations.of(context).formatMediumDate(date.toLocal());
  }

  String _roleLabel(String? role) => switch (role) {
    'admin' => _t('Administrator', 'مسؤول'),
    'subscribed' => _t('Subscribed', 'مشترك'),
    'guest' => _t('Guest', 'ضيف'),
    _ => _t('Access not configured', 'لم تُحدّد صلاحيات الوصول'),
  };

  String _expiryLabel(Map<String, dynamic> user) {
    final date = user['guestExpiresOn']?.toString();
    final timezone = user['expiryTimezone']?.toString() ?? 'Asia/Beirut';
    if (date == null || date.isEmpty) {
      return _t('Guest expiry not set', 'لم يُحدّد تاريخ انتهاء وصول الضيف');
    }
    return '${_t('Guest expiry date', 'تاريخ انتهاء وصول الضيف')}: $date ($timezone)';
  }

  String? _expiryInstant(Map<String, dynamic> user) {
    final value = DateTime.tryParse(user['guestExpiresAt']?.toString() ?? '');
    if (value == null) return null;
    final instant = value
        .toUtc()
        .toIso8601String()
        .replaceFirst('T', ' ')
        .replaceFirst(RegExp(r'\.\d+Z$'), ' UTC');
    return '${_t('Exact access cutoff', 'وقت انتهاء الوصول بدقة')}: $instant';
  }

  Future<void> _editAccess(Map<String, dynamic> user) async {
    final updated = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UserAccessDialog(
        client: widget.client,
        arabic: widget.arabic,
        user: user,
      ),
    );
    if (!mounted || updated == null) return;
    setState(() {
      _users = [
        for (final row in _users)
          if (row['uid'] == updated['uid']) updated else row,
      ];
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_t('User access updated.', 'تم تحديث صلاحيات المستخدم.')),
      ),
    );
  }

  Widget _userCard(Map<String, dynamic> user) {
    final name = (user['displayName'] ?? '').toString();
    final email = (user['email'] ?? '').toString();
    final disabled = user['disabled'] == true;
    final admin = user['role'] == 'admin';
    final guest = user['role'] == 'guest';
    final expired = guest && user['guestExpired'] == true;
    final canEdit =
        user['isCurrentUser'] != true && user['canEditAccess'] != false;
    final permissions = (user['permissions'] as List? ?? []).cast<String>();
    final role = _roleLabel(user['role']?.toString());
    return Card(
      child: ExpansionTile(
        key: ValueKey('admin-user-${user['uid']}'),
        leading: Icon(
          admin ? Icons.admin_panel_settings_outlined : Icons.person_outline,
        ),
        title: Text(
          name.isNotEmpty
              ? name
              : (email.isNotEmpty
                    ? email
                    : _t('Unnamed account', 'حساب دون اسم')),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (email.isNotEmpty && name.isNotEmpty) Text(email),
              const SizedBox(height: 4),
              Text(
                [
                  role,
                  disabled
                      ? _t('Disabled', 'معطّل')
                      : expired
                      ? _t('Guest access expired', 'انتهى وصول الضيف')
                      : _t('Active', 'نشط'),
                  if (user['isCurrentUser'] == true) _t('You', 'أنت'),
                ].join(' · '),
              ),
              if (guest)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(_expiryLabel(user)),
                ),
            ],
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          SelectableText('${_t('User ID', 'معرّف المستخدم')}: ${user['uid']}'),
          const SizedBox(height: 8),
          Text(
            '${_t('Role source', 'مصدر الصلاحية')}: ${_roleSource(user['roleSource'] as String?)}',
          ),
          const SizedBox(height: 8),
          Text(
            user['emailVerified'] == true
                ? _t('Email verified', 'البريد الإلكتروني مؤكّد')
                : _t('Email not verified', 'البريد الإلكتروني غير مؤكّد'),
          ),
          const SizedBox(height: 8),
          Text('${_t('Joined', 'تاريخ التسجيل')}: ${_date(user['createdAt'])}'),
          Text(
            '${_t('Last sign-in', 'آخر تسجيل دخول')}: ${_date(user['lastSignInAt'])}',
          ),
          const SizedBox(height: 16),
          if (guest && _expiryInstant(user) != null) ...[
            Text(_expiryInstant(user)!),
            const SizedBox(height: 12),
          ],
          if (expired && !disabled) ...[
            Text(
              _t(
                'Reading is blocked until guest access is extended or the role is changed.',
                'القراءة محظورة حتى تمديد وصول الضيف أو تغيير دوره.',
              ),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 12),
          ],
          OutlinedButton.icon(
            key: ValueKey('edit-user-access-${user['uid']}'),
            onPressed: _loading || !canEdit ? null : () => _editAccess(user),
            icon: const Icon(Icons.manage_accounts_outlined),
            label: Text(_t('Edit role & access', 'تعديل الدور والوصول')),
          ),
          if (user['isCurrentUser'] == true)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _t(
                  'Your own access cannot be changed here.',
                  'لا يمكنك تغيير صلاحيات حسابك من هنا.',
                ),
              ),
            ),
          const SizedBox(height: 16),
          Text(
            _t('Permissions', 'الصلاحيات'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          if (disabled)
            Text(
              _t(
                'This account is disabled and cannot sign in.',
                'هذا الحساب معطّل ولا يمكنه تسجيل الدخول.',
              ),
            )
          else
            for (final permission in permissions)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_permission(permission))),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = _filter.text.trim().toLowerCase();
    final filtered = _users
        .where(
          (user) =>
              query.isEmpty ||
              ['displayName', 'email', 'uid'].any(
                (key) =>
                    (user[key] ?? '').toString().toLowerCase().contains(query),
              ),
        )
        .toList();
    return Directionality(
      textDirection: widget.arabic ? TextDirection.rtl : TextDirection.ltr,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 12,
            children: [
              Text(
                _t('User administration', 'إدارة المستخدمين'),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              OutlinedButton.icon(
                onPressed: _loading ? null : () => _load(refresh: true),
                icon: const Icon(Icons.refresh),
                label: Text(_t('Refresh users', 'تحديث المستخدمين')),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _t(
              'Manage account roles and guest expiry dates. New guests receive 30 days of reading access.',
              'أدِر أدوار الحسابات وتواريخ انتهاء وصول الضيوف. يحصل الضيوف الجدد على ٣٠ يومًا للقراءة.',
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _filter,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: _t(
                'Filter this page by name, email or user ID',
                'تصفية هذه الصفحة حسب الاسم أو البريد أو المعرّف',
              ),
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_error!),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _loading
                          ? null
                          : () => _load(page: _retryPage, token: _retryToken),
                      icon: const Icon(Icons.refresh),
                      label: Text(_t('Retry', 'إعادة المحاولة')),
                    ),
                  ],
                ),
              ),
            ),
          if (!_loading && _error == null && filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Text(
                _users.isEmpty
                    ? _t(
                        'No registered users found.',
                        'لم يتم العثور على مستخدمين مسجّلين.',
                      )
                    : _t(
                        'No matching users on this page.',
                        'لا يوجد مستخدمون مطابقون في هذه الصفحة.',
                      ),
              ),
            ),
          for (final user in filtered) _userCard(user),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: _loading || _page == 0
                    ? null
                    : () =>
                          _load(page: _page - 1, token: _pageTokens[_page - 1]),
                child: Text(_t('Previous', 'السابق')),
              ),
              Text(
                '${_t('Page', 'الصفحة')} ${_page + 1} · ${_users.length} ${_t('accounts', 'حسابات')}',
              ),
              OutlinedButton(
                onPressed: _loading || _nextToken == null
                    ? null
                    : () => _load(page: _page + 1, token: _nextToken),
                child: Text(_t('Next', 'التالي')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _UserAccessDialog extends StatefulWidget {
  const _UserAccessDialog({
    required this.client,
    required this.arabic,
    required this.user,
  });
  final AdminClient client;
  final bool arabic;
  final Map<String, dynamic> user;

  @override
  State<_UserAccessDialog> createState() => _UserAccessDialogState();
}

class _UserAccessDialogState extends State<_UserAccessDialog> {
  final _form = GlobalKey<FormState>();
  final _expiry = TextEditingController();
  late Map<String, dynamic> _user;
  late String _role;
  bool _busy = false, _conflict = false;
  String? _error;
  static const _roles = ['guest', 'subscribed', 'admin'];

  String _t(String english, String arabic) => widget.arabic ? arabic : english;
  String get _path =>
      '/admin/users/${Uri.encodeComponent(_user['uid'].toString())}';
  String get _timezone => _user['expiryTimezone']?.toString() ?? 'Asia/Beirut';
  bool get _editable =>
      _user['isCurrentUser'] != true && _user['canEditAccess'] != false;
  bool get _dirty =>
      _role != _user['role'] ||
      (_role == 'guest' &&
          _expiry.text.trim() != (_user['guestExpiresOn'] ?? ''));

  @override
  void initState() {
    super.initState();
    _setUser(widget.user);
    _reload();
  }

  void _setUser(Map<String, dynamic> user) {
    _user = Map<String, dynamic>.from(user);
    _role = _roles.contains(user['role']) ? user['role'] as String : 'guest';
    _expiry.text =
        (user['guestExpiresOn'] ?? user['suggestedGuestExpiresOn'] ?? '')
            .toString();
  }

  @override
  void dispose() {
    _expiry.dispose();
    super.dispose();
  }

  DateTime? _parseDate(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return null;
    final parts = value.split('-').map(int.parse).toList();
    if (parts[0] == 0 || value == '9999-12-31') return null;
    final date = DateTime.utc(parts[0], parts[1], parts[2]);
    if (date.year != parts[0] ||
        date.month != parts[1] ||
        date.day != parts[2]) {
      return null;
    }
    return date;
  }

  String _dateText(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  void _grantThirtyDays({bool extend = false}) {
    final suggested = _parseDate(
      _user['suggestedGuestExpiresOn']?.toString() ?? '',
    );
    if (suggested == null) return;
    var result = suggested;
    final current = _parseDate(_expiry.text.trim());
    if (extend && current != null) {
      final extended = current.add(const Duration(days: 30));
      if (extended.isAfter(result)) result = extended;
    }
    setState(() => _expiry.text = _dateText(result));
  }

  Future<void> _pickDate() async {
    final parsed =
        _parseDate(_expiry.text.trim()) ??
        _parseDate(_user['suggestedGuestExpiresOn']?.toString() ?? '') ??
        DateTime.now();
    final earliest = DateTime(1900);
    final latest = DateTime(9999, 12, 31);
    final candidate = DateTime(parsed.year, parsed.month, parsed.day);
    final selected = await showDatePicker(
      context: context,
      initialDate: candidate.isBefore(earliest) ? earliest : candidate,
      firstDate: earliest,
      lastDate: latest,
      helpText: _t('Last day of guest access', 'آخر يوم لوصول الضيف'),
      cancelText: _t('Cancel', 'إلغاء'),
      confirmText: _t('Choose date', 'اختيار التاريخ'),
      fieldLabelText: _t('Expiry date', 'تاريخ الانتهاء'),
      fieldHintText: _t('Enter a date', 'أدخل تاريخًا'),
      textDirection: widget.arabic ? TextDirection.rtl : TextDirection.ltr,
    );
    if (selected != null && mounted) {
      setState(() => _expiry.text = _dateText(selected));
    }
  }

  Future<void> _reload() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final response = await widget.client.getJson(_path);
      if (!mounted) return;
      setState(() {
        _setUser(Map<String, dynamic>.from(response['user'] as Map));
        _conflict = false;
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is AdminApiException
              ? error.message
              : _t(
                  'Current access could not be loaded. Try again.',
                  'تعذر تحميل الصلاحيات الحالية. حاول مجددًا.',
                ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_busy ||
        !_editable ||
        !_dirty ||
        _conflict ||
        !_form.currentState!.validate()) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final response = await widget.client.postJson(_path, {
        'revision': _user['revision'],
        'role': _role,
        if (_role == 'guest') 'guestExpiresOn': _expiry.text.trim(),
      });
      if (!mounted) return;
      Navigator.of(
        context,
      ).pop(Map<String, dynamic>.from(response['user'] as Map));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _conflict =
            error is AdminApiException &&
            (error.status == 409 || error.code == 'membership_conflict');
        _error = _conflict
            ? _t(
                'This account changed while you were editing. Your changes are still here. Reload current access before saving.',
                'تغيّر هذا الحساب أثناء التعديل. لا تزال تعديلاتك موجودة. أعد تحميل الصلاحيات الحالية قبل الحفظ.',
              )
            : error is AdminApiException
            ? error.message
            : _t(
                'Access could not be saved. Try again.',
                'تعذر حفظ الصلاحيات. حاول مجددًا.',
              );
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _roleLabel(String role) => switch (role) {
    'admin' => _t('Administrator', 'مسؤول'),
    'subscribed' => _t('Subscribed', 'مشترك'),
    _ => _t('Guest', 'ضيف'),
  };

  @override
  Widget build(BuildContext context) {
    final name = (_user['displayName'] ?? _user['email'] ?? _user['uid'])
        .toString();
    final suggested = _parseDate(
      _user['suggestedGuestExpiresOn']?.toString() ?? '',
    );
    return Directionality(
      textDirection: widget.arabic ? TextDirection.rtl : TextDirection.ltr,
      child: PopScope(
        canPop: !_busy,
        child: AlertDialog(
          scrollable: true,
          title: Text(_t('Edit role & access', 'تعديل الدور والوصول')),
          content: SizedBox(
            width: 480,
            child: Form(
              key: _form,
              child: AbsorbPointer(
                absorbing: _busy,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: Theme.of(context).textTheme.titleMedium),
                    if ((_user['email'] ?? '').toString().isNotEmpty &&
                        _user['email'] != name)
                      Text(_user['email'].toString()),
                    const SizedBox(height: 20),
                    if (!_editable)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          _t(
                            'Your own access cannot be changed here.',
                            'لا يمكنك تغيير صلاحيات حسابك من هنا.',
                          ),
                        ),
                      ),
                    DropdownButtonFormField<String>(
                      key: ValueKey('user-role-$_role'),
                      initialValue: _role,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: _t('Role', 'الدور'),
                        border: const OutlineInputBorder(),
                      ),
                      items: [
                        for (final role in _roles)
                          DropdownMenuItem(
                            value: role,
                            child: Text(_roleLabel(role)),
                          ),
                      ],
                      onChanged: !_editable
                          ? null
                          : (value) {
                              if (value != null) setState(() => _role = value);
                            },
                    ),
                    const SizedBox(height: 12),
                    Text(switch (_role) {
                      'admin' => _t(
                        'Administrators can read, edit content, and manage other users’ roles and access.',
                        'يمكن للمسؤولين القراءة وتعديل المحتوى وإدارة أدوار المستخدمين الآخرين ووصولهم.',
                      ),
                      'subscribed' => _t(
                        'Subscribed users can read without a guest expiry date.',
                        'يمكن للمشتركين القراءة دون تاريخ انتهاء خاص بالضيوف.',
                      ),
                      _ => _t(
                        'Guests can read through the selected date. Reading is blocked after access expires.',
                        'يمكن للضيوف القراءة حتى نهاية التاريخ المحدّد. تُحظر القراءة بعد انتهاء الوصول.',
                      ),
                    }),
                    if (_role == 'guest') ...[
                      const SizedBox(height: 20),
                      TextFormField(
                        key: const ValueKey('guest-expiry-date'),
                        controller: _expiry,
                        enabled: _editable,
                        textDirection: TextDirection.ltr,
                        keyboardType: TextInputType.datetime,
                        decoration: InputDecoration(
                          labelText: _t(
                            'Last day of guest access',
                            'آخر يوم لوصول الضيف',
                          ),
                          hintText: 'YYYY-MM-DD',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            onPressed: !_editable ? null : _pickDate,
                            tooltip: _t(
                              'Choose expiry date',
                              'اختيار تاريخ الانتهاء',
                            ),
                            icon: const Icon(Icons.calendar_month),
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                        validator: (value) =>
                            _parseDate((value ?? '').trim()) == null
                            ? _t(
                                'Enter a valid date as YYYY-MM-DD.',
                                'أدخل تاريخًا صحيحًا بالصيغة YYYY-MM-DD.',
                              )
                            : null,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${_t('Access includes this entire date in', 'يشمل الوصول هذا اليوم كاملًا بتوقيت')} $_timezone.',
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          TextButton(
                            onPressed: !_editable || suggested == null
                                ? null
                                : () => _grantThirtyDays(),
                            child: Text(
                              _t('30 days from today', '٣٠ يومًا من اليوم'),
                            ),
                          ),
                          TextButton(
                            onPressed: !_editable || suggested == null
                                ? null
                                : () => _grantThirtyDays(extend: true),
                            child: Text(
                              _t('Extend by 30 days', 'تمديد ٣٠ يومًا'),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (_user['disabled'] == true)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          _t(
                            'This account is disabled. Changing its role does not enable sign-in.',
                            'هذا الحساب معطّل. تغيير دوره لا يفعّل تسجيل الدخول.',
                          ),
                        ),
                      ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    if (_conflict || _user['revision'] == null)
                      TextButton.icon(
                        onPressed: _busy ? null : _reload,
                        icon: const Icon(Icons.refresh),
                        label: Text(
                          _t(
                            'Reload current access (replaces draft)',
                            'تحميل الصلاحيات الحالية (يستبدل المسودة)',
                          ),
                        ),
                      ),
                    if (_busy)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: LinearProgressIndicator(),
                      ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              child: Text(_t('Cancel', 'إلغاء')),
            ),
            FilledButton(
              key: const ValueKey('save-user-access'),
              onPressed:
                  _busy ||
                      !_editable ||
                      !_dirty ||
                      _conflict ||
                      _user['revision'] == null
                  ? null
                  : _save,
              child: Text(_t('Save access', 'حفظ الصلاحيات')),
            ),
          ],
        ),
      ),
    );
  }
}
