import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gospel_frontend/admin_api_client.dart';
import 'package:gospel_frontend/admin_portal.dart';
import 'package:gospel_frontend/admin_users_panel.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _UsersClient implements AdminClient {
  _UsersClient({this.users});
  final paths = <String>[];
  final posts = <({String path, Map<String, dynamic> body})>[];
  List<Map<String, dynamic>>? users;
  Map<String, dynamic>? reloadedUser;
  AdminApiException? mutationError;
  bool failNextPage = false;

  @override
  Future<Map<String, dynamic>> getJson(String path) async {
    paths.add(path);
    if (path == '/admin/overview') {
      return {
        'counts': {
          'bibleLanguages': 3,
          'bibleVersions': 7,
          'topicLanguages': 3,
          'failedImports': 0,
        },
        'bibleLanguages': <dynamic>[],
        'topicLanguages': <dynamic>[],
        'recentImports': <dynamic>[],
      };
    }
    if (path.startsWith('/admin/users/')) {
      return {'user': reloadedUser ?? users!.first};
    }
    if (users != null) return {'users': users, 'nextPageToken': null};
    final token = Uri.parse(path).queryParameters['pageToken'];
    if (token != null && failNextPage) {
      failNextPage = false;
      throw const AdminApiException('Temporary directory failure');
    }
    return {
      'users': [
        if (token == null)
          {
            'uid': 'admin-1',
            'displayName': 'Anna Admin',
            'email': 'anna@example.test',
            'role': 'admin',
            'roleSource': 'users_role',
            'permissions': ['read_content', 'manage_content', 'view_users'],
            'emailVerified': true,
            'isCurrentUser': true,
          }
        else
          {
            'uid': 'reader-2',
            'displayName': 'Rita Reader',
            'email': 'rita@example.test',
            'role': 'subscribed',
            'roleSource': 'default',
            'permissions': [],
            'disabled': true,
          },
      ],
      'nextPageToken': token == null ? 'cursor+with=padding' : null,
    };
  }

  @override
  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    posts.add((path: path, body: Map<String, dynamic>.from(body)));
    if (mutationError case final error?) throw error;
    final current = reloadedUser ?? users!.first;
    final role = body['role'];
    final updated = <String, dynamic>{
      ...current,
      'role': role,
      'roleSource': 'membership',
      'revision': 'saved-revision',
      'guestExpiresOn': role == 'guest' ? body['guestExpiresOn'] : null,
      'guestExpired': false,
      'canRead': true,
      'accessStatus': 'active',
      'permissions': [
        'read_content',
        'manage_own_profile',
        if (role == 'admin') ...[
          'manage_content',
          'view_users',
          'manage_users',
        ],
      ],
    };
    users = [updated];
    return {'user': updated};
  }

  @override
  Future<Map<String, dynamic>> upload(
    String path, {
    required Map<String, String> fields,
    required List<AdminUploadFile> files,
    required String fileField,
  }) => throw UnimplementedError();
}

Future<void> _pump(
  WidgetTester tester,
  _UsersClient client, {
  bool arabic = false,
  Size size = const Size(1100, 1100),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AdminUsersPanel(client: client, arabic: arabic),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Map<String, dynamic> _guest({
  String role = 'guest',
  bool expired = true,
  bool self = false,
}) => {
  'uid': 'guest-1',
  'displayName': 'Grace Guest',
  'email': 'grace@example.test',
  'role': role,
  'roleSource': 'membership',
  'revision': 'original-revision',
  'guestExpiresOn': role == 'guest' ? '2026-09-01' : null,
  'guestExpiresAt': role == 'guest' ? '2026-09-01T21:00:00+00:00' : null,
  'suggestedGuestExpiresOn': '2026-11-05',
  'expiryTimezone': 'Asia/Beirut',
  'guestExpired': expired && role == 'guest',
  'accessStatus': expired && role == 'guest' ? 'expired' : 'active',
  'canRead': !expired || role != 'guest',
  'canEditAccess': !self,
  'isCurrentUser': self,
  'emailVerified': true,
  'permissions': [
    'manage_own_profile',
    if (!expired || role != 'guest') 'read_content',
  ],
};

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _openAccess(WidgetTester tester) async {
  await _tap(tester, find.text('Grace Guest'));
  await _tap(tester, find.byKey(const ValueKey('edit-user-access-guest-1')));
}

Future<void> _selectRole(
  WidgetTester tester,
  String current,
  String label,
) async {
  await _tap(tester, find.byKey(ValueKey('user-role-$current')));
  await _tap(tester, find.text(label).last);
}

void main() {
  testWidgets(
    'expired guests show their cutoff and blocked reading; subscribed save refreshes permissions',
    (tester) async {
      final client = _UsersClient(users: [_guest()]);
      await _pump(tester, client);
      expect(find.text('Guest · Guest access expired'), findsOneWidget);
      expect(
        find.text('Guest expiry date: 2026-09-01 (Asia/Beirut)'),
        findsOneWidget,
      );
      await _openAccess(tester);
      await _selectRole(tester, 'guest', 'Subscribed');
      expect(find.byKey(const ValueKey('guest-expiry-date')), findsNothing);
      await _tap(tester, find.byKey(const ValueKey('save-user-access')));
      expect(client.posts.single.path, '/admin/users/guest-1');
      expect(client.posts.single.body, {
        'revision': 'original-revision',
        'role': 'subscribed',
      });
      expect(find.text('Subscribed · Active'), findsOneWidget);
      expect(find.text('Read Bible and topics'), findsOneWidget);
      expect(find.text('Guest · Guest access expired'), findsNothing);
    },
  );

  testWidgets(
    'guest expiry is sent as an inclusive date without client timezone conversion',
    (tester) async {
      final client = _UsersClient(users: [_guest()]);
      await _pump(tester, client);
      await _openAccess(tester);
      await tester.enterText(
        find.byKey(const ValueKey('guest-expiry-date')),
        '2027-03-28',
      );
      await _tap(tester, find.byKey(const ValueKey('save-user-access')));
      expect(client.posts.single.body, {
        'revision': 'original-revision',
        'role': 'guest',
        'guestExpiresOn': '2027-03-28',
      });
      expect(
        find.text('Guest expiry date: 2027-03-28 (Asia/Beirut)'),
        findsOneWidget,
      );
      expect(find.text('Guest · Active'), findsOneWidget);
    },
  );

  testWidgets(
    'grant and extend use the server date and preserve future guest time',
    (tester) async {
      final client = _UsersClient(users: [_guest()]);
      await _pump(tester, client);
      await _openAccess(tester);
      await _tap(tester, find.text('30 days from today'));
      final field = find.byKey(const ValueKey('guest-expiry-date'));
      expect(
        tester.widget<TextFormField>(field).controller!.text,
        '2026-11-05',
      );
      await tester.enterText(field, '2026-12-01');
      await _tap(tester, find.text('Extend by 30 days'));
      expect(
        tester.widget<TextFormField>(field).controller!.text,
        '2026-12-31',
      );
      await _tap(tester, find.byKey(const ValueKey('save-user-access')));
      expect(client.posts.single.body['guestExpiresOn'], '2026-12-31');
    },
  );

  testWidgets('invalid expiry dates do not mutate access', (tester) async {
    final client = _UsersClient(users: [_guest()]);
    await _pump(tester, client);
    await _openAccess(tester);
    await tester.enterText(
      find.byKey(const ValueKey('guest-expiry-date')),
      '2027-02-30',
    );
    await _tap(tester, find.byKey(const ValueKey('save-user-access')));
    expect(find.text('Enter a valid date as YYYY-MM-DD.'), findsOneWidget);
    expect(client.posts, isEmpty);
  });

  testWidgets(
    'conflicts retain the draft and require reloading before another save',
    (tester) async {
      final client = _UsersClient(users: [_guest()])
        ..mutationError = const AdminApiException(
          'Stale access',
          code: 'membership_conflict',
          status: 409,
        );
      await _pump(tester, client);
      await _openAccess(tester);
      await _selectRole(tester, 'guest', 'Administrator');
      await _tap(tester, find.byKey(const ValueKey('save-user-access')));
      expect(find.byKey(const ValueKey('user-role-admin')), findsOneWidget);
      expect(
        find.textContaining('Your changes are still here'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('save-user-access')),
            )
            .onPressed,
        isNull,
      );
      client.mutationError = null;
      client.reloadedUser = {
        ..._guest(role: 'subscribed'),
        'revision': 'fresh-revision',
      };
      await _tap(tester, find.text('Reload current access (replaces draft)'));
      expect(
        find.byKey(const ValueKey('user-role-subscribed')),
        findsOneWidget,
      );
      await _selectRole(tester, 'subscribed', 'Administrator');
      await _tap(tester, find.byKey(const ValueKey('save-user-access')));
      expect(client.posts.last.body, {
        'revision': 'fresh-revision',
        'role': 'admin',
      });
      expect(find.text('Manage user roles and guest access'), findsOneWidget);
    },
  );

  testWidgets('administrators cannot edit their own access', (tester) async {
    final client = _UsersClient(users: [_guest(role: 'admin', self: true)]);
    await _pump(tester, client);
    await _tap(tester, find.text('Grace Guest'));
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('edit-user-access-guest-1')),
          )
          .onPressed,
      isNull,
    );
    expect(
      find.text('Your own access cannot be changed here.'),
      findsOneWidget,
    );
    expect(client.posts, isEmpty);
  });

  testWidgets('Arabic guest access editing remains usable at phone width', (
    tester,
  ) async {
    final client = _UsersClient(users: [_guest()]);
    await _pump(tester, client, arabic: true, size: const Size(390, 844));
    await _openAccess(tester);
    expect(
      Directionality.of(
        tester.element(find.byKey(const ValueKey('save-user-access'))),
      ),
      TextDirection.rtl,
    );
    await _tap(tester, find.text('٣٠ يومًا من اليوم'));
    await _tap(tester, find.byKey(const ValueKey('save-user-access')));
    expect(client.posts.single.body['guestExpiresOn'], '2026-11-05');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Arabic admin phone navigation opens Users and shows permissions',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = _UsersClient();
      await tester.pumpWidget(
        MaterialApp(
          home: AdminPortal(
            apiBaseUrl: 'https://example.test',
            client: client,
            adminCheck: Future.value(true),
            arabic: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(NavigationBar), findsOneWidget);
      await tester.tap(find.text('المستخدمون'));
      await tester.pumpAndSettle();
      expect(find.text('إدارة المستخدمين'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Anna Admin'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('عرض المستخدمين والصلاحيات'));
      await tester.pumpAndSettle();
      expect(find.text('عرض المستخدمين والصلاحيات'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byIcon(Icons.dashboard_outlined));
      await tester.pumpAndSettle();
      expect(find.byType(AdminUsersPanel), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'shows account details and effective permissions, pages in both directions',
    (tester) async {
      final client = _UsersClient();
      await _pump(tester, client);
      expect(find.text('Anna Admin'), findsOneWidget);
      await tester.tap(find.text('Anna Admin'));
      await tester.pumpAndSettle();
      expect(find.text('View users and permissions'), findsOneWidget);
      expect(
        find.text('Role source: Administrator-assigned profile role'),
        findsOneWidget,
      );
      expect(find.text('Email verified'), findsOneWidget);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(
        Uri.parse(client.paths.last).queryParameters['pageToken'],
        'cursor+with=padding',
      );
      expect(find.text('Rita Reader'), findsOneWidget);
      await tester.tap(find.text('Rita Reader'));
      await tester.pumpAndSettle();
      expect(
        find.text('This account is disabled and cannot sign in.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Next'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Previous'));
      await tester.pumpAndSettle();
      expect(find.text('Anna Admin'), findsOneWidget);
      expect(Uri.parse(client.paths.last).queryParameters['pageToken'], isNull);
    },
  );

  testWidgets(
    'a failed next page preserves current accounts and retries the failed page',
    (tester) async {
      final client = _UsersClient()..failNextPage = true;
      await _pump(tester, client);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Anna Admin'), findsOneWidget);
      expect(find.text('Temporary directory failure'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Rita Reader'), findsOneWidget);
      expect(
        Uri.parse(client.paths.last).queryParameters['pageToken'],
        'cursor+with=padding',
      );
    },
  );

  testWidgets('filter is local to page and Arabic labels render', (
    tester,
  ) async {
    final client = _UsersClient();
    await _pump(tester, client, arabic: true);
    expect(find.text('إدارة المستخدمين'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'unmatched');
    await tester.pumpAndSettle();
    expect(
      find.text('لا يوجد مستخدمون مطابقون في هذه الصفحة.'),
      findsOneWidget,
    );
    expect(client.paths, hasLength(1));
  });

  test(
    'real API client preserves encoded directory pagination query',
    () async {
      final client = AdminApiClient(
        baseUrl: 'https://example.test',
        tokenProvider: () async => 'admin-token',
        client: MockClient((request) async {
          expect(
            request.url.queryParameters['pageToken'],
            'cursor+with=padding',
          );
          expect(request.url.queryParameters['pageSize'], '50');
          expect(request.headers['Authorization'], 'Bearer admin-token');
          return http.Response('{"users":[]}', 200);
        }),
      );
      await client.getJson(
        '/admin/users?pageSize=50&pageToken=cursor%2Bwith%3Dpadding',
      );
    },
  );
}
