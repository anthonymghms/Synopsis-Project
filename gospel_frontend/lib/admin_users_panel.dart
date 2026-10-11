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
      'Manage user roles, access and accounts',
      'إدارة أدوار المستخدمين ووصولهم وحساباتهم',
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
    final subscribed = user['role'] == 'subscribed';
    if (subscribed && user['subscriptionPermanent'] != false) {
      return _t('Permanent subscription', 'اشتراك دائم');
    }
    final date = user[subscribed ? 'subscriptionExpiresOn' : 'guestExpiresOn']
        ?.toString();
    final timezone = user['expiryTimezone']?.toString() ?? 'Asia/Beirut';
    if (date == null || date.isEmpty) {
      return subscribed
          ? _t('Subscription expiry not set', 'لم يُحدّد تاريخ انتهاء الاشتراك')
          : _t('Guest expiry not set', 'لم يُحدّد تاريخ انتهاء وصول الضيف');
    }
    final label = subscribed
        ? _t('Subscription expiry date', 'تاريخ انتهاء الاشتراك')
        : _t('Guest expiry date', 'تاريخ انتهاء وصول الضيف');
    return '$label: $date ($timezone)';
  }

  String? _expiryInstant(Map<String, dynamic> user) {
    final value = DateTime.tryParse(
      user[user['role'] == 'subscribed'
                  ? 'subscriptionExpiresAt'
                  : 'guestExpiresAt']
              ?.toString() ??
          '',
    );
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

  Future<void> _showDetails(Map<String, dynamic> user) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _UserDetailsDialog(
        client: widget.client,
        arabic: widget.arabic,
        user: user,
      ),
    );
  }

  Future<void> _accountAction(Map<String, dynamic> user, String action) async {
    final response = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UserAccountActionDialog(
        client: widget.client,
        arabic: widget.arabic,
        user: user,
        action: action,
      ),
    );
    if (!mounted || response == null) return;
    setState(() {
      if (response['deleted'] == true) {
        _users.removeWhere((row) => row['uid'] == response['uid']);
      } else {
        final updated = Map<String, dynamic>.from(response['user'] as Map);
        _users = [
          for (final row in _users)
            if (row['uid'] == updated['uid']) updated else row,
        ];
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          response['deleted'] == true
              ? _t('User deleted.', 'تم حذف المستخدم.')
              : _t('Account status updated.', 'تم تحديث حالة الحساب.'),
        ),
      ),
    );
  }

  String _statusLabel(Map<String, dynamic> user) =>
      switch (user['accountStatus']) {
        'suspended' => _t('Suspended', 'موقوف مؤقتًا'),
        'terminated' => _t('Terminated', 'منتهي'),
        'deleting' => _t('Deletion in progress', 'الحذف جارٍ'),
        _ =>
          user['disabled'] == true
              ? _t('Disabled', 'معطّل')
              : user['guestExpired'] == true && user['role'] == 'guest'
              ? _t('Guest access expired', 'انتهى وصول الضيف')
              : user['subscriptionExpired'] == true &&
                    user['role'] == 'subscribed'
              ? _t('Subscription expired', 'انتهى الاشتراك')
              : _t('Active', 'نشط'),
      };

  Widget _userCard(Map<String, dynamic> user) {
    final name = (user['displayName'] ?? '').toString();
    final email = (user['email'] ?? '').toString();
    final disabled = user['disabled'] == true;
    final admin = user['role'] == 'admin';
    final guest = user['role'] == 'guest';
    final subscribed = user['role'] == 'subscribed';
    final expired =
        (guest && user['guestExpired'] == true) ||
        (subscribed && user['subscriptionExpired'] == true);
    final canEdit =
        user['isCurrentUser'] != true &&
        user['canEditAccess'] != false &&
        user['accountStatus'] != 'deleting';
    final permissions = (user['permissions'] as List? ?? []).cast<String>();
    final canManage =
        user['isCurrentUser'] != true && user['canManageAccount'] != false;
    final restricted =
        user['accountStatus'] == 'suspended' ||
        user['accountStatus'] == 'terminated';
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
                  _statusLabel(user),
                  if (user['isCurrentUser'] == true) _t('You', 'أنت'),
                ].join(' · '),
              ),
              if (guest || subscribed)
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
          if ((guest || subscribed) && _expiryInstant(user) != null) ...[
            Text(_expiryInstant(user)!),
            const SizedBox(height: 12),
          ],
          if (expired && !disabled) ...[
            Text(
              _t(
                'Reading is blocked until access is extended or the role is changed.',
                'القراءة محظورة حتى تمديد الوصول أو تغيير الدور.',
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
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: ValueKey('view-user-details-${user['uid']}'),
            onPressed: _loading ? null : () => _showDetails(user),
            icon: const Icon(Icons.insights_outlined),
            label: Text(
              _t('View settings & activity', 'عرض الإعدادات والنشاط'),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: ValueKey(
                  '${restricted ? 'resume' : 'suspend'}-user-${user['uid']}',
                ),
                onPressed:
                    _loading ||
                        !canManage ||
                        user['accountStatus'] == 'deleting'
                    ? null
                    : () => _accountAction(
                        user,
                        restricted ? 'resume' : 'suspend',
                      ),
                icon: Icon(restricted ? Icons.play_arrow : Icons.pause),
                label: Text(
                  restricted
                      ? _t('Resume access', 'استئناف الوصول')
                      : _t('Suspend', 'إيقاف مؤقت'),
                ),
              ),
              OutlinedButton.icon(
                key: ValueKey('terminate-user-${user['uid']}'),
                onPressed:
                    _loading ||
                        !canManage ||
                        user['accountStatus'] == 'terminated' ||
                        user['accountStatus'] == 'deleting'
                    ? null
                    : () => _accountAction(user, 'terminate'),
                icon: const Icon(Icons.block),
                label: Text(_t('Terminate access', 'إنهاء الوصول')),
              ),
              OutlinedButton.icon(
                key: ValueKey('delete-user-${user['uid']}'),
                onPressed: _loading || !canManage
                    ? null
                    : () => _accountAction(user, 'delete'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                icon: const Icon(Icons.delete_outline),
                label: Text(
                  user['accountStatus'] == 'deleting'
                      ? _t('Retry deletion', 'إعادة محاولة الحذف')
                      : _t('Delete user', 'حذف المستخدم'),
                ),
              ),
            ],
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
              'Manage roles, subscription dates and account status. View saved preferences and activity. New guests receive 30 days of reading access.',
              'أدِر الأدوار وتواريخ الاشتراك وحالة الحساب. اعرض التفضيلات المحفوظة والنشاط. يحصل الضيوف الجدد على ٣٠ يومًا للقراءة.',
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
  final _subscriptionExpiry = TextEditingController();
  late Map<String, dynamic> _user;
  late String _role;
  bool _subscriptionPermanent = true;
  bool _busy = false, _conflict = false;
  bool _hasCurrentAccess = false;
  String? _error;
  static const _roles = ['guest', 'subscribed', 'admin'];

  String _t(String english, String arabic) => widget.arabic ? arabic : english;
  String get _path =>
      '/admin/users/${Uri.encodeComponent(_user['uid'].toString())}';
  String get _timezone => _user['expiryTimezone']?.toString() ?? 'Asia/Beirut';
  bool get _editable =>
      _user['isCurrentUser'] != true &&
      _user['canEditAccess'] != false &&
      _user['accountStatus'] != 'deleting';
  TextEditingController get _dateController =>
      _role == 'subscribed' ? _subscriptionExpiry : _expiry;
  String get _suggestedDate =>
      (_role == 'subscribed'
              ? _user['suggestedSubscriptionExpiresOn'] ??
                    _user['suggestedGuestExpiresOn']
              : _user['suggestedGuestExpiresOn'])
          ?.toString() ??
      '';
  bool get _dirty =>
      _role != _user['role'] ||
      (_role == 'guest' &&
          _expiry.text.trim() != (_user['guestExpiresOn'] ?? '')) ||
      (_role == 'subscribed' &&
          (_subscriptionPermanent !=
                  (_user['subscriptionPermanent'] != false) ||
              (!_subscriptionPermanent &&
                  _subscriptionExpiry.text.trim() !=
                      (_user['subscriptionExpiresOn'] ?? ''))));

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
    _subscriptionPermanent = user['subscriptionPermanent'] != false;
    _subscriptionExpiry.text =
        (user['subscriptionExpiresOn'] ??
                user['suggestedSubscriptionExpiresOn'] ??
                user['suggestedGuestExpiresOn'] ??
                '')
            .toString();
  }

  @override
  void dispose() {
    _expiry.dispose();
    _subscriptionExpiry.dispose();
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
    final suggested = _parseDate(_suggestedDate);
    if (suggested == null) return;
    var result = suggested;
    final current = _parseDate(_dateController.text.trim());
    if (extend && current != null) {
      final extended = current.add(const Duration(days: 30));
      if (extended.isAfter(result)) result = extended;
    }
    setState(() => _dateController.text = _dateText(result));
  }

  Future<void> _pickDate() async {
    final parsed =
        _parseDate(_dateController.text.trim()) ??
        _parseDate(_suggestedDate) ??
        DateTime.now();
    final earliest = DateTime(1900);
    final latest = DateTime(9999, 12, 31);
    final candidate = DateTime(parsed.year, parsed.month, parsed.day);
    final selected = await showDatePicker(
      context: context,
      initialDate: candidate.isBefore(earliest) ? earliest : candidate,
      firstDate: earliest,
      lastDate: latest,
      helpText: _role == 'subscribed'
          ? _t('Last day of subscription access', 'آخر يوم للاشتراك')
          : _t('Last day of guest access', 'آخر يوم لوصول الضيف'),
      cancelText: _t('Cancel', 'إلغاء'),
      confirmText: _t('Choose date', 'اختيار التاريخ'),
      fieldLabelText: _t('Expiry date', 'تاريخ الانتهاء'),
      fieldHintText: _t('Enter a date', 'أدخل تاريخًا'),
      textDirection: widget.arabic ? TextDirection.rtl : TextDirection.ltr,
    );
    if (selected != null && mounted) {
      setState(() => _dateController.text = _dateText(selected));
    }
  }

  Future<void> _reload() async {
    setState(() {
      _busy = true;
      _hasCurrentAccess = false;
      _error = null;
    });
    try {
      final response = await widget.client.getJson(_path);
      if (!mounted) return;
      setState(() {
        _setUser(Map<String, dynamic>.from(response['user'] as Map));
        _hasCurrentAccess = true;
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
        !_hasCurrentAccess ||
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
        if (_role == 'subscribed')
          'subscriptionPermanent': _subscriptionPermanent,
        if (_role == 'subscribed' && !_subscriptionPermanent)
          'subscriptionExpiresOn': _subscriptionExpiry.text.trim(),
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
    final suggested = _parseDate(_suggestedDate);
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
                        'Choose permanent access or a subscription ending on a specific date.',
                        'اختر وصولًا دائمًا أو اشتراكًا ينتهي في تاريخ محدّد.',
                      ),
                      _ => _t(
                        'Guests can read through the selected date. Reading is blocked after access expires.',
                        'يمكن للضيوف القراءة حتى نهاية التاريخ المحدّد. تُحظر القراءة بعد انتهاء الوصول.',
                      ),
                    }),
                    if (_role == 'subscribed') ...[
                      const SizedBox(height: 20),
                      DropdownButtonFormField<bool>(
                        key: ValueKey(
                          'subscription-term-$_subscriptionPermanent',
                        ),
                        initialValue: _subscriptionPermanent,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: _t(
                            'Subscription duration',
                            'مدة الاشتراك',
                          ),
                          border: const OutlineInputBorder(),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: true,
                            child: Text(_t('Permanent', 'دائم')),
                          ),
                          DropdownMenuItem(
                            value: false,
                            child: Text(_t('Timed', 'محدّد المدة')),
                          ),
                        ],
                        onChanged: !_editable
                            ? null
                            : (value) {
                                if (value != null) {
                                  setState(
                                    () => _subscriptionPermanent = value,
                                  );
                                }
                              },
                      ),
                    ],
                    if (_role == 'guest' ||
                        (_role == 'subscribed' && !_subscriptionPermanent)) ...[
                      const SizedBox(height: 20),
                      TextFormField(
                        key: ValueKey(
                          _role == 'subscribed'
                              ? 'subscription-expiry-date'
                              : 'guest-expiry-date',
                        ),
                        controller: _dateController,
                        enabled: _editable,
                        textDirection: TextDirection.ltr,
                        keyboardType: TextInputType.datetime,
                        decoration: InputDecoration(
                          labelText: _role == 'subscribed'
                              ? _t(
                                  'Last day of subscription access',
                                  'آخر يوم للاشتراك',
                                )
                              : _t(
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
                    if (_conflict ||
                        _user['revision'] == null ||
                        !_hasCurrentAccess)
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
                      !_hasCurrentAccess ||
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

class _UserAccountActionDialog extends StatefulWidget {
  const _UserAccountActionDialog({
    required this.client,
    required this.arabic,
    required this.user,
    required this.action,
  });

  final AdminClient client;
  final bool arabic;
  final Map<String, dynamic> user;
  final String action;

  @override
  State<_UserAccountActionDialog> createState() =>
      _UserAccountActionDialogState();
}

class _UserAccountActionDialogState extends State<_UserAccountActionDialog> {
  final _confirmation = TextEditingController();
  late Map<String, dynamic> _user;
  bool _busy = false, _ready = false, _conflict = false;
  String? _error;

  String _t(String english, String arabic) => widget.arabic ? arabic : english;
  String get _uid => _user['uid'].toString();
  String get _path => '/admin/users/${Uri.encodeComponent(_uid)}';
  bool get _delete => widget.action == 'delete';
  bool get _confirmed =>
      !_delete ||
      _confirmation.text.trim() == _uid ||
      ((_user['email'] ?? '').toString().isNotEmpty &&
          _confirmation.text.trim() == _user['email']);
  bool get _allowed =>
      _user['isCurrentUser'] != true &&
      _user['canManageAccount'] != false &&
      (_user['accountStatus'] != 'deleting' || _delete) &&
      (widget.action != 'resume' ||
          _user['accountStatus'] == 'suspended' ||
          _user['accountStatus'] == 'terminated');

  String get _title => switch (widget.action) {
    'suspend' => _t('Suspend user?', 'إيقاف المستخدم مؤقتًا؟'),
    'resume' => _t('Resume user access?', 'استئناف وصول المستخدم؟'),
    'terminate' => _t('Terminate user access?', 'إنهاء وصول المستخدم؟'),
    _ => _t('Delete user permanently?', 'حذف المستخدم نهائيًا؟'),
  };
  String get _buttonLabel => switch (widget.action) {
    'suspend' => _t('Confirm suspension', 'تأكيد الإيقاف المؤقت'),
    'resume' => _t('Confirm resume', 'تأكيد الاستئناف'),
    'terminate' => _t('Confirm termination', 'تأكيد الإنهاء'),
    _ => _t('Delete permanently', 'حذف نهائي'),
  };
  String get _effect => switch (widget.action) {
    'suspend' => _t(
      'Reading and administrator access will be blocked. Their profile and preferences will be kept. An administrator can resume access later.',
      'سيُحظر الوصول للقراءة والإدارة. سيُحتفظ بالملف الشخصي والتفضيلات. يمكن للمسؤول استئناف الوصول لاحقًا.',
    ),
    'resume' => _t(
      'Access will be restored according to this account’s role. Its existing role and expiry date still apply; expired access must also be extended. A separately disabled sign-in account remains disabled.',
      'سيُستعاد الوصول حسب دور هذا الحساب. يظل دوره وتاريخ انتهاء وصوله ساريين؛ يجب أيضًا تمديد الوصول المنتهي. يبقى حساب تسجيل الدخول المعطّل بشكل منفصل معطّلًا.',
    ),
    'terminate' => _t(
      'Reading and administrator access will be blocked and existing sessions revoked. Their account, preferences and logs will be kept. An administrator can restore access later.',
      'سيُحظر الوصول للقراءة والإدارة وتُلغى الجلسات الحالية. سيُحتفظ بالحساب والتفضيلات والسجلات. يمكن للمسؤول استعادة الوصول لاحقًا.',
    ),
    _ => _t(
      'The sign-in account, saved profile, access settings and activity logs will be deleted. This cannot be undone.',
      'سيُحذف حساب تسجيل الدخول والملف الشخصي المحفوظ وإعدادات الوصول وسجلات النشاط. لا يمكن التراجع عن ذلك.',
    ),
  };

  @override
  void initState() {
    super.initState();
    _user = Map<String, dynamic>.from(widget.user);
    _reload();
  }

  @override
  void dispose() {
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _busy = true;
      _ready = false;
      _error = null;
    });
    try {
      final response = await widget.client.getJson(_path);
      if (!mounted) return;
      setState(() {
        _user = Map<String, dynamic>.from(response['user'] as Map);
        _ready = _user['revision'] != null;
        _conflict = false;
        _confirmation.clear();
      });
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = error is AdminApiException
            ? error.message
            : _t(
                'Current account could not be loaded. Try again.',
                'تعذر تحميل الحساب الحالي. حاول مجددًا.',
              ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (_busy || !_ready || !_allowed || !_confirmed || _conflict) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final response = await widget.client.postJson('$_path/actions', {
        'action': widget.action,
        'revision': _user['revision'],
        'confirmation': _uid,
      });
      if (mounted) Navigator.of(context).pop(response);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _conflict =
            error is AdminApiException &&
            (error.status == 409 || error.code == 'membership_conflict');
        _error = _conflict
            ? _t(
                'This account changed. Reload the account and confirm the action again.',
                'تغيّر هذا الحساب. أعد تحميله وأكّد الإجراء مجددًا.',
              )
            : error is AdminApiException
            ? error.message
            : _t(
                'The action could not be completed. Try again.',
                'تعذر إكمال الإجراء. حاول مجددًا.',
              );
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = (_user['email'] ?? '').toString();
    return Directionality(
      textDirection: widget.arabic ? TextDirection.rtl : TextDirection.ltr,
      child: PopScope(
        canPop: !_busy,
        child: AlertDialog(
          scrollable: true,
          title: Text(_title),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (_user['displayName'] ?? email).toString(),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (email.isNotEmpty) SelectableText(email),
                SelectableText('${_t('User ID', 'معرّف المستخدم')}: $_uid'),
                const SizedBox(height: 16),
                Text(_effect),
                if (!_allowed) ...[
                  const SizedBox(height: 12),
                  Text(
                    _t(
                      'This action is unavailable for this account.',
                      'هذا الإجراء غير متاح لهذا الحساب.',
                    ),
                  ),
                ],
                if (_delete) ...[
                  const SizedBox(height: 16),
                  Text(
                    _t(
                      'Type the email address or user ID above to confirm deletion.',
                      'اكتب البريد الإلكتروني أو معرّف المستخدم أعلاه لتأكيد الحذف.',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    key: const ValueKey('delete-user-confirmation'),
                    controller: _confirmation,
                    enabled: !_busy && _ready && !_conflict,
                    textDirection: TextDirection.ltr,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: _t(
                        'Email or user ID',
                        'البريد الإلكتروني أو معرّف المستخدم',
                      ),
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                if (_conflict || _error != null || (!_ready && !_busy))
                  TextButton.icon(
                    key: const ValueKey('reload-user-action'),
                    onPressed: _busy ? null : _reload,
                    icon: const Icon(Icons.refresh),
                    label: Text(_t('Reload account', 'إعادة تحميل الحساب')),
                  ),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: LinearProgressIndicator(),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              child: Text(_t('Cancel', 'إلغاء')),
            ),
            FilledButton(
              key: const ValueKey('confirm-user-action'),
              style: widget.action == 'resume'
                  ? null
                  : FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                    ),
              onPressed:
                  _busy || !_ready || !_allowed || !_confirmed || _conflict
                  ? null
                  : _submit,
              child: Text(_buttonLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _UserDetailsDialog extends StatefulWidget {
  const _UserDetailsDialog({
    required this.client,
    required this.arabic,
    required this.user,
  });
  final AdminClient client;
  final bool arabic;
  final Map<String, dynamic> user;

  @override
  State<_UserDetailsDialog> createState() => _UserDetailsDialogState();
}

class _UserDetailsDialogState extends State<_UserDetailsDialog> {
  Map<String, dynamic>? _user, _summary;
  final List<Map<String, dynamic>> _logins = [], _sessions = [];
  String? _userError, _activityError, _nextToken;
  bool _userBusy = false, _activityBusy = false;

  String _t(String english, String arabic) => widget.arabic ? arabic : english;
  String get _path =>
      '/admin/users/${Uri.encodeComponent(widget.user['uid'].toString())}';

  @override
  void initState() {
    super.initState();
    _loadUser();
    _loadActivity();
  }

  Future<void> _loadUser() async {
    setState(() {
      _userBusy = true;
      _userError = null;
    });
    try {
      final response = await widget.client.getJson(_path);
      if (mounted) {
        setState(
          () => _user = Map<String, dynamic>.from(response['user'] as Map),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _userError = error is AdminApiException
              ? error.message
              : _t('Preferences could not be loaded.', 'تعذر تحميل التفضيلات.'),
        );
      }
    } finally {
      if (mounted) setState(() => _userBusy = false);
    }
  }

  Future<void> _loadActivity({bool more = false}) async {
    if (_activityBusy) return;
    setState(() {
      _activityBusy = true;
      _activityError = null;
    });
    try {
      final path = Uri(
        path: '$_path/activity',
        queryParameters: {
          'pageSize': '25',
          if (more && _nextToken != null) 'pageToken': _nextToken!,
        },
      ).toString();
      final response = await widget.client.getJson(path);
      if (!mounted) return;
      setState(() {
        _summary = Map<String, dynamic>.from(response['summary'] as Map? ?? {});
        if (!more) {
          _logins.clear();
          _sessions.clear();
        }
        for (final raw
            in (response['logins'] as List? ?? []).whereType<Map>()) {
          final login = Map<String, dynamic>.from(raw);
          if (login['id'] == null ||
              !_logins.any((row) => row['id'] == login['id'])) {
            _logins.add(login);
          }
        }
        for (final raw
            in (response['sessions'] as List? ?? []).whereType<Map>()) {
          final session = Map<String, dynamic>.from(raw);
          if (session['id'] == null ||
              !_sessions.any((row) => row['id'] == session['id'])) {
            _sessions.add(session);
          }
        }
        _nextToken = response['nextPageToken'] as String?;
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _activityError = error is AdminApiException
              ? error.message
              : _t('Activity could not be loaded.', 'تعذر تحميل النشاط.'),
        );
      }
    } finally {
      if (mounted) setState(() => _activityBusy = false);
    }
  }

  String _value(dynamic value) {
    if (value == null || value.toString().isEmpty) {
      return _t('Not saved', 'غير محفوظ');
    }
    if (value is bool) {
      return value ? _t('On', 'مفعّل') : _t('Off', 'غير مفعّل');
    }
    return value.toString();
  }

  String _time(dynamic raw) {
    final date = DateTime.tryParse(raw?.toString() ?? '');
    if (date == null) return _t('Not recorded', 'غير مسجّل');
    final local = date.toLocal();
    final locale = MaterialLocalizations.of(context);
    return '${locale.formatMediumDate(local)} ${locale.formatTimeOfDay(TimeOfDay.fromDateTime(local), alwaysUse24HourFormat: true)}';
  }

  String _duration(dynamic raw) {
    final seconds = raw is num
        ? raw.toInt()
        : int.tryParse(raw?.toString() ?? '') ?? 0;
    final minutes = seconds ~/ 60;
    if (minutes < 60) {
      return '$minutes ${_t('min', 'دقيقة')} ${seconds % 60} ${_t('sec', 'ثانية')}';
    }
    return '${minutes ~/ 60} ${_t('h', 'ساعة')} ${minutes % 60} ${_t('min', 'دقيقة')}';
  }

  Widget _heading(String english, String arabic) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 8),
    child: Text(
      _t(english, arabic),
      style: Theme.of(context).textTheme.titleMedium,
    ),
  );

  Widget _setting(String english, String arabic, dynamic value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Text('${_t(english, arabic)}: ${_value(value)}'),
  );

  @override
  Widget build(BuildContext context) {
    final prefs = Map<String, dynamic>.from(
      _user?['preferences'] as Map? ?? {},
    );
    return Directionality(
      textDirection: widget.arabic ? TextDirection.rtl : TextDirection.ltr,
      child: AlertDialog(
        scrollable: true,
        title: Text(_t('User settings & activity', 'إعدادات المستخدم والنشاط')),
        content: SizedBox(
          width: 640,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                (widget.user['displayName'] ?? widget.user['email'] ?? '')
                    .toString(),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              SelectableText(
                (widget.user['email'] ?? widget.user['uid']).toString(),
              ),
              _heading('Saved preferences', 'التفضيلات المحفوظة'),
              if (_userBusy) const LinearProgressIndicator(),
              if (_userError != null) ...[
                Text(
                  _userError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                TextButton(
                  onPressed: _userBusy ? null : _loadUser,
                  child: Text(_t('Retry preferences', 'إعادة تحميل التفضيلات')),
                ),
              ],
              if (_user != null) ...[
                Text(
                  _user!['profileCompleted'] == true
                      ? _t('Profile completed: Yes', 'الملف الشخصي مكتمل: نعم')
                      : _t('Profile completed: No', 'الملف الشخصي مكتمل: لا'),
                ),
                if (prefs.isEmpty || _user!['preferencesSource'] == 'not_saved')
                  Text(
                    _t(
                      'No preferences have been saved by this user.',
                      'لم يحفظ هذا المستخدم أي تفضيلات.',
                    ),
                  )
                else ...[
                  _setting(
                    'Interface language',
                    'لغة الواجهة',
                    prefs['menuLanguage'],
                  ),
                  _setting(
                    'Topic language',
                    'لغة المواضيع',
                    prefs['topicLanguage'] ?? prefs['preferredTopicLanguage'],
                  ),
                  _setting(
                    'Bible language',
                    'لغة الكتاب المقدس',
                    prefs['bibleLanguage'] ?? prefs['contentLanguage'],
                  ),
                  _setting(
                    'Bible translation',
                    'ترجمة الكتاب المقدس',
                    prefs['bibleVersion'] ??
                        prefs['preferredBibleVersion'] ??
                        prefs['preferredVersion'],
                  ),
                  _setting(
                    'Arabic diacritics',
                    'التشكيل العربي',
                    prefs['showDiacritics'],
                  ),
                  _setting(
                    'Interlinear reading',
                    'القراءة بين السطور',
                    prefs['interlinearEnabled'],
                  ),
                  _setting(
                    'Topic names in chapters',
                    'أسماء المواضيع في الفصول',
                    prefs['showTopicNamesInChapter'],
                  ),
                  _setting(
                    'Translation labels',
                    'عناوين الترجمات',
                    prefs['showTranslationLabels'],
                  ),
                  _setting(
                    'Text size',
                    'حجم النص',
                    prefs['zoomLevel'] is num
                        ? '${((prefs['zoomLevel'] as num) * 100).round()}%'
                        : null,
                  ),
                ],
              ],
              _heading('Activity', 'النشاط'),
              Text(
                _t(
                  'Estimated active time counts foreground interaction and excludes idle or background time. Tracking starts with this update; earlier activity is not available. Times are shown in your device’s local time.',
                  'يحسب وقت النشاط التقديري التفاعل أثناء ظهور التطبيق ويستثني وقت الخمول أو الخلفية. يبدأ التتبّع مع هذا التحديث؛ النشاط السابق غير متاح. تُعرض الأوقات حسب توقيت جهازك المحلي.',
                ),
              ),
              const SizedBox(height: 12),
              if (_summary != null) ...[
                Text(
                  '${_t('Last activity', 'آخر نشاط')}: ${_time(_summary!['lastActiveAt'])}',
                ),
                Text(
                  '${_t('Estimated active time', 'وقت النشاط التقديري')}: ${_duration(_summary!['totalActiveSeconds'])}',
                ),
                Text(
                  '${_t('Sessions', 'الجلسات')}: ${_summary!['sessionCount'] ?? 0}',
                ),
                Text(
                  '${_t('Logins', 'مرات تسجيل الدخول')}: ${_summary!['loginCount'] ?? 0}',
                ),
              ],
              if (_activityError != null) ...[
                Text(
                  _activityError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                TextButton(
                  onPressed: _activityBusy
                      ? null
                      : () => _loadActivity(
                          more: _summary != null && _nextToken != null,
                        ),
                  child: Text(_t('Retry activity', 'إعادة تحميل النشاط')),
                ),
              ],
              if (_summary != null) ...[
                _heading('Login history', 'سجل تسجيل الدخول'),
                if (_logins.isEmpty)
                  Text(
                    _t('No logins recorded yet.', 'لم تُسجّل مرات دخول بعد.'),
                  ),
                for (final login in _logins)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text(
                      '${_t('Signed in', 'تسجيل الدخول')}: ${_time(login['signedInAt'])}',
                    ),
                  ),
                _heading('Session history', 'سجل الجلسات'),
                if (_sessions.isEmpty)
                  Text(_t('No sessions recorded yet.', 'لم تُسجّل جلسات بعد.')),
                for (final session in _sessions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_t('Started', 'البداية')}: ${_time(session['startedAt'])}',
                        ),
                        Text(
                          '${_t('Last activity', 'آخر نشاط')}: ${_time(session['lastActiveAt'])}',
                        ),
                        if (session['endedAt'] != null)
                          Text(
                            '${_t('Ended', 'النهاية')}: ${_time(session['endedAt'])}',
                          ),
                        Text(
                          '${_t('Estimated active time', 'وقت النشاط التقديري')}: ${_duration(session['activeSeconds'])}',
                        ),
                      ],
                    ),
                  ),
                if (_nextToken != null)
                  TextButton.icon(
                    key: const ValueKey('load-more-user-activity'),
                    onPressed: _activityBusy
                        ? null
                        : () => _loadActivity(more: true),
                    icon: const Icon(Icons.expand_more),
                    label: Text(
                      _t('Load older activity', 'تحميل النشاط الأقدم'),
                    ),
                  ),
              ],
              if (_activityBusy) const LinearProgressIndicator(),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(_t('Close', 'إغلاق')),
          ),
        ],
      ),
    );
  }
}
