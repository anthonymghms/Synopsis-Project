import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

const _activityApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8010',
);

class _ActivitySession {
  _ActivitySession(this.uid, this.id, this.tokenProvider, this.startedAt)
    : accountedAt = startedAt,
      lastInteraction = startedAt;
  final String uid;
  final String id;
  Future<String?> Function() tokenProvider;
  final DateTime startedAt;
  DateTime accountedAt;
  DateTime lastInteraction;
  int activeMilliseconds = 0;
  bool registered = false;
}

/// Best-effort, foreground engagement estimates. No reading content is sent.
/// A two-minute idle window allows reading between interactions; background
/// time is excluded. The server caps and deduplicates cumulative seconds.
class UserActivityController {
  UserActivityController({
    this.baseUrl = _activityApiBaseUrl,
    http.Client? client,
    DateTime Function()? clock,
    String Function()? sessionIdFactory,
    this.idleTimeout = const Duration(minutes: 2),
    this.heartbeatInterval = const Duration(minutes: 1),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _clock = clock ?? (() => DateTime.now().toUtc()),
       _sessionIdFactory = sessionIdFactory ?? _newSessionId;

  final String baseUrl;
  final http.Client _client;
  final bool _ownsClient;
  final DateTime Function() _clock;
  final String Function() _sessionIdFactory;
  final Duration idleTimeout;
  final Duration heartbeatInterval;
  _ActivitySession? _session;
  Timer? _timer;
  bool _foreground = true;
  bool _disposed = false;
  Future<void> _queue = Future<void>.value();

  static String _newSessionId() {
    final random = Random.secure();
    return List.generate(
      24,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  void beginSession(String uid, Future<String?> Function() tokenProvider) {
    if (_disposed) return;
    if (_session?.uid == uid) {
      _session!.tokenProvider = tokenProvider;
      return;
    }
    unawaited(endSession());
    final next = _ActivitySession(
      uid,
      _sessionIdFactory(),
      tokenProvider,
      _clock(),
    );
    _session = next;
    _enqueue(next, 'start', 0);
    _timer = Timer.periodic(heartbeatInterval, (_) => unawaited(flush()));
  }

  void _accumulate() {
    final session = _session;
    if (session == null) return;
    final now = _clock();
    final idleAt = session.lastInteraction.add(idleTimeout);
    final until = now.isBefore(idleAt) ? now : idleAt;
    if (_foreground && until.isAfter(session.accountedAt)) {
      session.activeMilliseconds += until
          .difference(session.accountedAt)
          .inMilliseconds;
    }
    session.accountedAt = now;
  }

  void recordInteraction() {
    if (!_foreground || _disposed) return;
    _accumulate();
    _session?.lastInteraction = _clock();
  }

  void setForeground(bool foreground) {
    if (_foreground == foreground || _disposed) return;
    _accumulate();
    _foreground = foreground;
    if (foreground) {
      // Resuming is itself an interaction; it starts a fresh idle window.
      _session?.lastInteraction = _clock();
    } else {
      unawaited(flush());
    }
  }

  Future<void> flush() {
    _accumulate();
    final session = _session;
    if (session == null || _disposed) return _queue;
    if (_clock().difference(session.startedAt) >= const Duration(hours: 23)) {
      final uid = session.uid;
      final provider = session.tokenProvider;
      unawaited(endSession());
      beginSession(uid, provider);
      return _queue;
    }
    return _enqueue(session, 'heartbeat', session.activeMilliseconds ~/ 1000);
  }

  Future<void> endSession() {
    _accumulate();
    final session = _session;
    _session = null;
    _timer?.cancel();
    _timer = null;
    if (session == null) return _queue;
    return _enqueue(session, 'end', session.activeMilliseconds ~/ 1000);
  }

  Future<void> _enqueue(_ActivitySession session, String event, int seconds) {
    _queue = _queue.then((_) async {
      try {
        final token = await session.tokenProvider().timeout(
          const Duration(seconds: 5),
        );
        if (token == null || token.isEmpty) return;
        Future<http.Response> send(String kind, int cumulative) => _client
            .post(
              Uri.parse(
                '${baseUrl.replaceFirst(RegExp(r'/$'), '')}/account/activity',
              ),
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({
                'sessionId': session.id,
                'event': kind,
                'activeSeconds': cumulative.clamp(0, 86400),
              }),
            )
            .timeout(const Duration(seconds: 5));
        if (!session.registered) {
          final response = await send('start', 0);
          if (response.statusCode != 200) return;
          session.registered = true;
        }
        if (event == 'start') return;
        final response = await send(event, seconds);
        if (response.statusCode == 409) session.registered = false;
      } catch (_) {
        // Telemetry failure never blocks reading or account operations.
      }
    });
    return _queue;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    final pending = endSession();
    _disposed = true;
    await pending;
    if (_ownsClient) _client.close();
  }
}

final userActivity = UserActivityController();

/// Flush before sign-out while the Firebase token is still available.
Future<void> finishUserActivity() => userActivity.endSession().timeout(
  const Duration(seconds: 2),
  onTimeout: () {},
);

class UserActivityScope extends StatefulWidget {
  const UserActivityScope({super.key, required this.child});
  final Widget child;
  @override
  State<UserActivityScope> createState() => _UserActivityScopeState();
}

class _UserActivityScopeState extends State<UserActivityScope>
    with WidgetsBindingObserver {
  late final StreamSubscription<User?> _authSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    userActivity.setForeground(
      WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
    );
    HardwareKeyboard.instance.addHandler(_keyEvent);
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null) {
        unawaited(userActivity.endSession());
      } else {
        userActivity.beginSession(user.uid, () async {
          if (FirebaseAuth.instance.currentUser?.uid != user.uid) return null;
          return user.getIdToken();
        });
      }
    });
  }

  bool _keyEvent(KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      userActivity.recordInteraction();
    }
    return false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    userActivity.setForeground(state == AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    unawaited(_authSubscription.cancel());
    HardwareKeyboard.instance.removeHandler(_keyEvent);
    WidgetsBinding.instance.removeObserver(this);
    unawaited(userActivity.endSession());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (_) => userActivity.recordInteraction(),
    onPointerMove: (_) => userActivity.recordInteraction(),
    onPointerSignal: (_) => userActivity.recordInteraction(),
    child: widget.child,
  );
}
