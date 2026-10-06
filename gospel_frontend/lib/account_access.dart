import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const _accessApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8010',
);

class AccountAccess {
  const AccountAccess({
    required this.uid,
    required this.role,
    required this.canRead,
    required this.status,
    this.guestExpiresAt,
    this.serverTime,
  });

  final String uid;
  final String role;
  final bool canRead;
  final String status;
  final DateTime? guestExpiresAt;
  final DateTime? serverTime;

  factory AccountAccess.fromJson(Map<String, dynamic> data) => AccountAccess(
    uid: (data['uid'] ?? '').toString(),
    role: (data['role'] ?? 'guest').toString(),
    canRead: data['canRead'] == true,
    status: (data['accessStatus'] ?? 'disabled').toString(),
    guestExpiresAt: DateTime.tryParse(
      (data['guestExpiresAt'] ?? '').toString(),
    )?.toUtc(),
    serverTime: DateTime.tryParse(
      (data['serverTime'] ?? '').toString(),
    )?.toUtc(),
  );

  bool permitsReading(DateTime now) =>
      canRead &&
      status == 'active' &&
      (role != 'guest' ||
          (guestExpiresAt != null && now.isBefore(guestExpiresAt!)));
}

class ReadingAccessException implements Exception {
  const ReadingAccessException(this.code);
  final String code;
  @override
  String toString() => code == 'guest_access_expired'
      ? 'Your guest reading access has expired.'
      : 'Reading access could not be verified. Please check your account.';
}

/// One server-verified access snapshot per signed-in account. UI timers provide
/// prompt feedback; the backend remains authoritative for every content request.
class AccountAccessController extends ChangeNotifier {
  AccountAccessController({
    this.baseUrl = _accessApiBaseUrl,
    http.Client? client,
    Future<String?> Function()? tokenProvider,
    DateTime Function()? clock,
    this.refreshInterval = const Duration(minutes: 1),
  }) : _client = client,
       _tokenProvider =
           tokenProvider ??
           (() =>
               FirebaseAuth.instance.currentUser?.getIdToken() ??
               Future<String?>.value(null)),
       _clock = clock ?? (() => DateTime.now().toUtc());

  final String baseUrl;
  final http.Client? _client;
  final Future<String?> Function() _tokenProvider;
  final DateTime Function() _clock;
  final Duration refreshInterval;
  AccountAccess? _access;
  String? _uid;
  String? _error;
  DateTime? _lastChecked;
  Duration _serverOffset = Duration.zero;
  Future<void>? _pending;
  Timer? _refreshTimer;
  Timer? _expiryTimer;
  bool _disposed = false;
  int _session = 0;
  int _revision = 0;

  AccountAccess? get access => _access;
  String? get error => _error;
  String? get uid => _uid;
  int get revision => _revision;
  bool get loading => _pending != null;
  DateTime get serverNow => _clock().toUtc().add(_serverOffset);
  bool get canRead =>
      _error == null && (_access?.permitsReading(serverNow) ?? false);
  bool get expired =>
      _access?.status == 'expired' ||
      (_access?.role == 'guest' &&
          _access?.guestExpiresAt != null &&
          !serverNow.isBefore(_access!.guestExpiresAt!));

  void beginSession(String uid) {
    if (_uid == uid) return;
    clear();
    _uid = uid;
    _revision++;
  }

  void clear() {
    _session++;
    _refreshTimer?.cancel();
    _expiryTimer?.cancel();
    _refreshTimer = null;
    _expiryTimer = null;
    _pending = null;
    _access = null;
    _uid = null;
    _error = null;
    _lastChecked = null;
    _serverOffset = Duration.zero;
    _revision++;
    if (!_disposed) notifyListeners();
  }

  Future<Map<String, String>> authorizationHeaders() async {
    final token = await _tokenProvider().timeout(const Duration(seconds: 15));
    if (token == null || token.trim().isEmpty) {
      throw const ReadingAccessException('authentication_required');
    }
    return {'Authorization': 'Bearer $token'};
  }

  Future<void> refresh({bool force = false}) {
    if (_pending != null) return _pending!;
    if (_uid == null) return Future<void>.value();
    if (!force &&
        _lastChecked != null &&
        _clock().toUtc().difference(_lastChecked!) < refreshInterval &&
        _error == null) {
      return Future<void>.value();
    }
    final session = _session;
    final future = _load(session);
    _pending = future;
    return future.whenComplete(() {
      if (identical(_pending, future)) {
        _pending = null;
        if (!_disposed) notifyListeners();
      }
    });
  }

  Future<void> _load(int session) async {
    try {
      final headers = await authorizationHeaders();
      final uri = Uri.parse('$baseUrl/account/access');
      final response = _client == null
          ? await http
                .get(uri, headers: headers)
                .timeout(const Duration(seconds: 15))
          : await _client
                .get(uri, headers: headers)
                .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw const ReadingAccessException('account_access_denied');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw const FormatException('Invalid account access response');
      }
      final next = AccountAccess.fromJson(Map<String, dynamic>.from(decoded));
      if (session != _session || _disposed) return;
      if (next.uid != _uid) {
        throw const ReadingAccessException('account_access_denied');
      }
      _apply(next);
      _lastChecked = _clock().toUtc();
      _scheduleRefresh();
    } catch (_) {
      if (session != _session || _disposed) return;
      _error = 'Reading access could not be verified. Please try again.';
      _revision++;
      _scheduleRefresh();
      notifyListeners();
    }
  }

  void _apply(AccountAccess next) {
    final before =
        '${_access?.uid}|${_access?.role}|${_access?.canRead}|${_access?.status}|${_access?.guestExpiresAt}|$_error';
    _access = next;
    _error = null;
    if (next.serverTime != null) {
      _serverOffset = next.serverTime!.difference(_clock().toUtc());
    }
    final after =
        '${next.uid}|${next.role}|${next.canRead}|${next.status}|${next.guestExpiresAt}|$_error';
    if (before != after) _revision++;
    _expiryTimer?.cancel();
    if (next.role == 'guest' && next.guestExpiresAt != null && canRead) {
      _expiryTimer = Timer(next.guestExpiresAt!.difference(serverNow), () {
        _revision++;
        notifyListeners();
        unawaited(refresh(force: true));
      });
    }
    notifyListeners();
  }

  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(
      refreshInterval,
      () => unawaited(refresh(force: true)),
    );
  }

  Future<void> ensureCanRead() async {
    await refresh();
    if (!canRead) {
      throw ReadingAccessException(
        expired ? 'guest_access_expired' : 'account_access_denied',
      );
    }
  }

  void handleDeniedResponse(http.Response response) {
    if (response.statusCode != 401 && response.statusCode != 403) return;
    try {
      final decoded = jsonDecode(response.body);
      final error = decoded is Map ? decoded['error'] : null;
      final code = error is Map
          ? error['code']
          : decoded is Map
          ? decoded['code']
          : null;
      if (code == 'guest_access_expired' && _uid != null) {
        _apply(
          AccountAccess(
            uid: _uid!,
            role: 'guest',
            canRead: false,
            status: 'expired',
            guestExpiresAt: _access?.guestExpiresAt,
          ),
        );
        return;
      }
      final details = error is Map
          ? error['details']
          : decoded is Map
          ? decoded['details']
          : null;
      final data = details is Map ? (details['access'] ?? details) : null;
      if (data is Map && data['uid'] == _uid) {
        _apply(AccountAccess.fromJson(Map<String, dynamic>.from(data)));
        return;
      }
    } catch (_) {
      // A denial without an access snapshot still hides cached content.
    }
    _error = 'Reading access is unavailable. Refresh your account status.';
    _revision++;
    notifyListeners();
  }

  Future<http.Response> authenticatedGet(Uri uri, {http.Client? client}) async {
    final headers = await authorizationHeaders();
    final response = client == null
        ? await http
              .get(uri, headers: headers)
              .timeout(const Duration(seconds: 15))
        : await client
              .get(uri, headers: headers)
              .timeout(const Duration(seconds: 15));
    handleDeniedResponse(response);
    return response;
  }

  @override
  void dispose() {
    _disposed = true;
    _refreshTimer?.cancel();
    _expiryTimer?.cancel();
    super.dispose();
  }
}

AccountAccessController accountAccess = AccountAccessController();

class AccountAccessBoundary extends StatefulWidget {
  const AccountAccessBoundary({
    super.key,
    required this.controller,
    required this.uid,
    required this.builder,
    required this.onSettings,
    required this.onSignOut,
    this.language = 'english',
  });
  final AccountAccessController controller;
  final String uid;
  final WidgetBuilder builder;
  final VoidCallback onSettings;
  final VoidCallback onSignOut;
  final String language;

  @override
  State<AccountAccessBoundary> createState() => _AccountAccessBoundaryState();
}

class _AccountAccessBoundaryState extends State<AccountAccessBoundary>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.beginSession(widget.uid);
    widget.controller.addListener(_changed);
    unawaited(widget.controller.refresh(force: true));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.controller.refresh(force: true));
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final access = widget.controller;
    if (access.canRead) return Builder(builder: widget.builder);
    final arabic = widget.language == 'arabic';
    final french = widget.language == 'french';
    String text(String en, String ar, String fr) => arabic
        ? ar
        : french
        ? fr
        : en;
    return Scaffold(
      appBar: AppBar(
        title: Text(text('Account access', 'صلاحية الحساب', 'Accès au compte')),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (access.loading &&
                    access.access == null &&
                    access.error == null)
                  const CircularProgressIndicator()
                else ...[
                  Icon(
                    access.expired
                        ? Icons.hourglass_disabled_outlined
                        : Icons.lock_outline,
                    size: 40,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    access.expired
                        ? text(
                            'Your guest access has expired.',
                            'انتهت صلاحية الوصول كضيف.',
                            'Votre accès invité a expiré.',
                          )
                        : text(
                            'Reading access is unavailable.',
                            'الوصول إلى القراءة غير متاح.',
                            'L’accès à la lecture est indisponible.',
                          ),
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    access.error != null
                        ? text(
                            'We could not verify your access. Please check your connection and try again.',
                            'تعذر التحقق من صلاحية الوصول. تحقق من الاتصال وحاول مرة أخرى.',
                            'Impossible de vérifier votre accès. Vérifiez votre connexion et réessayez.',
                          )
                        : text(
                            'Contact your administrator to activate a subscription or extend guest access.',
                            'تواصل مع المسؤول لتفعيل اشتراك أو تمديد صلاحية الضيف.',
                            'Contactez votre administrateur pour activer un abonnement ou prolonger votre accès invité.',
                          ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: access.loading
                        ? null
                        : () => access.refresh(force: true),
                    icon: const Icon(Icons.refresh),
                    label: Text(
                      text(
                        'Check access',
                        'التحقق من الوصول',
                        'Vérifier l’accès',
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  children: [
                    TextButton(
                      onPressed: widget.onSettings,
                      child: Text(
                        text(
                          'Account settings',
                          'إعدادات الحساب',
                          'Paramètres du compte',
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: widget.onSignOut,
                      child: Text(
                        text('Sign out', 'تسجيل الخروج', 'Se déconnecter'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
