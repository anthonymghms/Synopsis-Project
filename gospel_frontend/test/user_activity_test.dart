import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gospel_frontend/user_activity.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('active estimates exclude idle and background intervals', () async {
    var now = DateTime.utc(2026, 10, 11);
    final events = <Map<String, dynamic>>[];
    final tracker = UserActivityController(
      clock: () => now,
      sessionIdFactory: () => 'session-one',
      client: MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer token');
        expect(request.url.path, '/account/activity');
        events.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response('{}', 200);
      }),
    );
    addTearDown(tracker.dispose);
    tracker.beginSession('reader', () async => 'token');
    now = now.add(const Duration(minutes: 1));
    await tracker.flush();
    expect(events.last['activeSeconds'], 60);
    now = now.add(const Duration(minutes: 9));
    await tracker.flush();
    expect(events.last['activeSeconds'], 120);
    tracker.recordInteraction();
    now = now.add(const Duration(seconds: 30));
    tracker.setForeground(false);
    await tracker.flush();
    expect(events.last['activeSeconds'], 150);
    now = now.add(const Duration(hours: 1));
    await tracker.flush();
    expect(events.last['activeSeconds'], 150);
    tracker.setForeground(true);
    now = now.add(const Duration(seconds: 20));
    await tracker.endSession();
    expect(events.last['event'], 'end');
    expect(events.last['activeSeconds'], 170);
    expect(events.where((event) => event['event'] == 'start'), hasLength(1));
  });

  test(
    'failed session registration retries before sending cumulative time',
    () async {
      var now = DateTime.utc(2026, 10, 11);
      var starts = 0;
      final events = <Map<String, dynamic>>[];
      final tracker = UserActivityController(
        clock: () => now,
        sessionIdFactory: () => 'retry-session',
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          events.add(body);
          if (body['event'] == 'start' && ++starts == 1) {
            return http.Response('{}', 503);
          }
          return http.Response('{}', 200);
        }),
      );
      addTearDown(tracker.dispose);
      tracker.beginSession('reader', () async => 'token');
      await tracker.flush();
      expect(events.map((e) => e['event']), ['start', 'start', 'heartbeat']);
      now = now.add(const Duration(seconds: 15));
      await tracker.flush();
      expect(events.last['activeSeconds'], 15);
    },
  );

  test('account changes end the old session using its own token', () async {
    var id = 0;
    final requests = <http.Request>[];
    final tracker = UserActivityController(
      sessionIdFactory: () => 'session-${++id}',
      client: MockClient((request) async {
        requests.add(request);
        return http.Response('{}', 200);
      }),
    );
    addTearDown(tracker.dispose);
    tracker.beginSession('first', () async => 'first-token');
    tracker.beginSession('second', () async => 'second-token');
    await tracker.flush();
    expect(requests.map((r) => r.headers['Authorization']), [
      'Bearer first-token',
      'Bearer first-token',
      'Bearer second-token',
      'Bearer second-token',
    ]);
    expect(requests.map((r) => jsonDecode(r.body)['event']), [
      'start',
      'end',
      'start',
      'heartbeat',
    ]);
    expect(jsonDecode(requests[1].body)['sessionId'], 'session-1');
    expect(jsonDecode(requests[2].body)['sessionId'], 'session-2');
  });

  test(
    'background sign-in records a session without counting hidden time',
    () async {
      var now = DateTime.utc(2026, 10, 11);
      final seconds = <int>[];
      final tracker = UserActivityController(
        clock: () => now,
        client: MockClient((request) async {
          seconds.add(jsonDecode(request.body)['activeSeconds'] as int);
          return http.Response('{}', 200);
        }),
      );
      addTearDown(tracker.dispose);
      tracker.setForeground(false);
      tracker.beginSession('reader', () async => 'token');
      now = now.add(const Duration(minutes: 10));
      await tracker.flush();
      expect(seconds, [0, 0]);
    },
  );
}
