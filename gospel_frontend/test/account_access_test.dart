import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gospel_frontend/account_access.dart';
import 'package:gospel_frontend/native_language_names.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  Map<String, dynamic> payload({
    String role = 'guest',
    bool canRead = true,
    String status = 'active',
    DateTime? now,
    DateTime? expires,
  }) => {
    'uid': 'reader',
    'role': role,
    'canRead': canRead,
    'accessStatus': status,
    if (now != null) 'serverTime': now.toIso8601String(),
    if (expires != null) 'guestExpiresAt': expires.toIso8601String(),
  };

  test(
    'native names are stable and standalone translations preserve their title',
    () {
      expect(nativeLanguageName('english', 'Anglais'), 'English');
      expect(nativeLanguageName('arabic', 'Arabic'), 'العربية');
      expect(nativeLanguageName('french', 'الفرنسية'), 'Français');
      expect(nativeLanguageName('ancientgreek', 'Ancient Greek'), 'Ἑλληνική');
      expect(
        nativeLanguageName('translation_0123456789abcdef', 'My Translation'),
        'My Translation',
      );
    },
  );

  test(
    'access fetch and reader calls send Firebase bearer authorization',
    () async {
      final paths = <String>[];
      final controller = AccountAccessController(
        tokenProvider: () async => 'fresh-token',
        client: MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer fresh-token');
          paths.add(request.url.path);
          return http.Response(jsonEncode(payload(role: 'subscribed')), 200);
        }),
      );
      addTearDown(controller.dispose);
      controller.beginSession('reader');
      await controller.ensureCanRead();
      expect(controller.canRead, isTrue);
      final client = MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer fresh-token');
        return http.Response('[]', 200);
      });
      await controller.authenticatedGet(
        Uri.parse('http://local/get_chapter'),
        client: client,
      );
      expect(paths, ['/account/access']);
    },
  );

  test(
    'guest expiry uses server time and never a later browser clock',
    () async {
      var browserNow = DateTime.utc(2026, 10, 1);
      final serverNow = DateTime.utc(2026, 10, 6);
      final controller = AccountAccessController(
        tokenProvider: () async => 'token',
        clock: () => browserNow,
        client: MockClient(
          (_) async => http.Response(
            jsonEncode(
              payload(
                now: serverNow,
                expires: serverNow.add(const Duration(seconds: 10)),
              ),
            ),
            200,
          ),
        ),
      );
      addTearDown(controller.dispose);
      controller.beginSession('reader');
      await controller.ensureCanRead();
      expect(controller.canRead, isTrue);
      browserNow = browserNow.add(const Duration(seconds: 11));
      expect(controller.canRead, isFalse);
      await expectLater(
        controller.ensureCanRead(),
        throwsA(isA<ReadingAccessException>()),
      );
    },
  );

  test(
    'server denial and failed recheck revoke previously cached access',
    () async {
      var status = 200;
      final controller = AccountAccessController(
        tokenProvider: () async => 'token',
        client: MockClient(
          (_) async =>
              http.Response(jsonEncode(payload(role: 'admin')), status),
        ),
      );
      addTearDown(controller.dispose);
      controller.beginSession('reader');
      await controller.refresh();
      final activeRevision = controller.revision;
      expect(controller.canRead, isTrue);
      controller.handleDeniedResponse(
        http.Response(
          jsonEncode({
            'error': {'code': 'guest_access_expired', 'message': 'Expired'},
          }),
          403,
        ),
      );
      expect(controller.canRead, isFalse);
      expect(controller.revision, greaterThan(activeRevision));
      status = 503;
      await controller.refresh(force: true);
      expect(controller.canRead, isFalse);
      expect(controller.error, isNotNull);
    },
  );

  testWidgets(
    'expired guests cannot build reader content but retain account actions',
    (tester) async {
      var settingsOpened = false;
      var signedOut = false;
      var readerBuilds = 0;
      final controller = AccountAccessController(
        tokenProvider: () async => 'token',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode(
              payload(
                canRead: false,
                status: 'expired',
                expires: DateTime.utc(2020),
              ),
            ),
            200,
          ),
        ),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: AccountAccessBoundary(
            controller: controller,
            uid: 'reader',
            builder: (_) {
              readerBuilds++;
              return const Text('Protected chapter');
            },
            onSettings: () => settingsOpened = true,
            onSignOut: () => signedOut = true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Protected chapter'), findsNothing);
      expect(readerBuilds, 0);
      expect(find.text('Your guest access has expired.'), findsOneWidget);
      await tester.tap(find.text('Account settings'));
      await tester.tap(find.text('Sign out'));
      expect(settingsOpened, isTrue);
      expect(signedOut, isTrue);
      await tester.pumpWidget(const SizedBox());
      controller.clear();
    },
  );

  for (final role in ['subscribed', 'admin']) {
    testWidgets(
      '$role readers remain available and revoke after resume recheck',
      (tester) async {
        var enabled = true;
        var requests = 0;
        final controller = AccountAccessController(
          tokenProvider: () async => 'token',
          client: MockClient((_) async {
            requests++;
            return http.Response(
              jsonEncode(
                payload(
                  role: role,
                  canRead: enabled,
                  status: enabled ? 'active' : 'disabled',
                ),
              ),
              200,
            );
          }),
        );
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: AccountAccessBoundary(
              controller: controller,
              uid: 'reader',
              builder: (_) => const Text('Protected chapter'),
              onSettings: () {},
              onSignOut: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Protected chapter'), findsOneWidget);
        enabled = false;
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(requests, 2);
        expect(find.text('Protected chapter'), findsNothing);
        expect(find.text('Reading access is unavailable.'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        controller.clear();
      },
    );
  }

  testWidgets('an open guest reader closes at the expiry time', (tester) async {
    var now = DateTime.utc(2026, 10, 6);
    final expiry = now.add(const Duration(seconds: 2));
    final controller = AccountAccessController(
      tokenProvider: () async => 'token',
      clock: () => now,
      client: MockClient(
        (_) async => http.Response(
          jsonEncode(
            payload(
              now: now,
              expires: expiry,
              canRead: now.isBefore(expiry),
              status: now.isBefore(expiry) ? 'active' : 'expired',
            ),
          ),
          200,
        ),
      ),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: AccountAccessBoundary(
          controller: controller,
          uid: 'reader',
          builder: (_) => const Text('Protected chapter'),
          onSettings: () {},
          onSignOut: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Protected chapter'), findsOneWidget);
    now = expiry;
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Protected chapter'), findsNothing);
    expect(find.text('Your guest access has expired.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    controller.clear();
  });
}
