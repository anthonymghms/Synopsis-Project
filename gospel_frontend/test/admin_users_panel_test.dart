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
  AdminApiException? activityError;
  AdminApiException? detailError;
  List<Map<String, dynamic>> activityPages = [];
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
    if (Uri.parse(path).path.endsWith('/activity')) {
      if (activityError case final error?) throw error;
      final token = Uri.parse(path).queryParameters['pageToken'];
      return activityPages.isEmpty
          ? {'summary': {}, 'logins': [], 'sessions': []}
          : activityPages[token == null ? 0 : 1];
    }
    if (path.startsWith('/admin/users/')) {
      if (detailError case final error?) throw error;
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
    if (path.endsWith('/actions')) {
      if (body['action'] == 'delete') {
        users = [];
        return {'deleted': true, 'uid': current['uid']};
      }
      final status = switch (body['action']) {
        'suspend' => 'suspended',
        'terminate' => 'terminated',
        _ => 'active',
      };
      final updated = <String, dynamic>{
        ...current,
        'accountStatus': status,
        'revision': 'saved-revision',
        'disabled': current['disabled'] == true,
      };
      users = [updated];
      reloadedUser = updated;
      return {'user': updated};
    }
    final role = body['role'];
    final updated = <String, dynamic>{
      ...current,
      'role': role,
      'roleSource': 'membership',
      'revision': 'saved-revision',
      'guestExpiresOn': role == 'guest' ? body['guestExpiresOn'] : null,
      'subscriptionPermanent': role == 'subscribed'
          ? body['subscriptionPermanent']
          : null,
      'subscriptionExpiresOn': role == 'subscribed'
          ? body['subscriptionExpiresOn']
          : null,
      'subscriptionExpired': false,
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
  'canManageAccount': !self,
  'accountStatus': 'active',
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
    'a separately disabled sign-in account does not offer membership resume',
    (tester) async {
      final client = _UsersClient(
        users: [
          {..._guest(role: 'subscribed', expired: false), 'disabled': true},
        ],
      );
      await _pump(tester, client);
      expect(find.text('Subscribed · Disabled'), findsOneWidget);
      await _tap(tester, find.text('Grace Guest'));
      expect(find.byKey(const ValueKey('resume-user-guest-1')), findsNothing);
      expect(
        find.byKey(const ValueKey('suspend-user-guest-1')),
        findsOneWidget,
      );
      expect(
        find.text('This account is disabled and cannot sign in.'),
        findsOneWidget,
      );
      expect(client.posts, isEmpty);
    },
  );

  testWidgets(
    'failed account reload blocks saving until current access is loaded',
    (tester) async {
      final client = _UsersClient(users: [_guest()])
        ..detailError = const AdminApiException('Current account unavailable');
      await _pump(tester, client);
      await _openAccess(tester);
      await tester.enterText(
        find.byKey(const ValueKey('guest-expiry-date')),
        '2027-03-28',
      );
      await tester.pumpAndSettle();
      expect(find.text('Current account unavailable'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('save-user-access')),
            )
            .onPressed,
        isNull,
      );
      expect(client.posts, isEmpty);
      client.detailError = null;
      await _tap(tester, find.text('Reload current access (replaces draft)'));
      await tester.enterText(
        find.byKey(const ValueKey('guest-expiry-date')),
        '2027-03-28',
      );
      await _tap(tester, find.byKey(const ValueKey('save-user-access')));
      expect(client.posts.single.body['guestExpiresOn'], '2027-03-28');
    },
  );

  testWidgets(
    'Arabic subscription editing, details and delete confirmation fit phone width',
    (tester) async {
      final client = _UsersClient(
        users: [_guest(role: 'subscribed', expired: false)],
      );
      await _pump(tester, client, arabic: true, size: const Size(390, 844));
      await _openAccess(tester);
      await _tap(tester, find.byKey(const ValueKey('subscription-term-true')));
      await _tap(tester, find.text('محدّد المدة').last);
      await tester.enterText(
        find.byKey(const ValueKey('subscription-expiry-date')),
        '2027-03-28',
      );
      await _tap(tester, find.byKey(const ValueKey('save-user-access')));
      expect(client.posts.single.body['subscriptionExpiresOn'], '2027-03-28');
      await _tap(
        tester,
        find.byKey(const ValueKey('view-user-details-guest-1')),
      );
      expect(find.text('إعدادات المستخدم والنشاط'), findsOneWidget);
      await _tap(tester, find.text('إغلاق'));
      await _tap(tester, find.byKey(const ValueKey('delete-user-guest-1')));
      await tester.enterText(
        find.byKey(const ValueKey('delete-user-confirmation')),
        'guest-1',
      );
      await _tap(tester, find.byKey(const ValueKey('confirm-user-action')));
      expect(client.posts.last.body['action'], 'delete');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'timed subscriptions save inclusive dates and can become permanent',
    (tester) async {
      final client = _UsersClient(
        users: [_guest(role: 'subscribed', expired: false)],
      );
      await _pump(tester, client);
      expect(find.text('Permanent subscription'), findsOneWidget);
      await _openAccess(tester);
      await _tap(tester, find.byKey(const ValueKey('subscription-term-true')));
      await _tap(tester, find.text('Timed').last);
      expect(
        find.text('Access includes this entire date in Asia/Beirut.'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('subscription-expiry-date')),
        '2027-03-28',
      );
      await _tap(tester, find.byKey(const ValueKey('save-user-access')));
      expect(client.posts.single.body, {
        'revision': 'original-revision',
        'role': 'subscribed',
        'subscriptionPermanent': false,
        'subscriptionExpiresOn': '2027-03-28',
      });
      expect(
        find.text('Subscription expiry date: 2027-03-28 (Asia/Beirut)'),
        findsOneWidget,
      );
      await _tap(
        tester,
        find.byKey(const ValueKey('edit-user-access-guest-1')),
      );
      await _tap(tester, find.byKey(const ValueKey('subscription-term-false')));
      await _tap(tester, find.text('Permanent').last);
      expect(
        find.byKey(const ValueKey('subscription-expiry-date')),
        findsNothing,
      );
      await _tap(tester, find.byKey(const ValueKey('save-user-access')));
      expect(client.posts.last.body, {
        'revision': 'saved-revision',
        'role': 'subscribed',
        'subscriptionPermanent': true,
      });
      expect(find.text('Permanent subscription'), findsOneWidget);
    },
  );

  testWidgets(
    'expired subscriptions show expiry and reject invalid timed dates',
    (tester) async {
      final client = _UsersClient(
        users: [
          {
            ..._guest(role: 'subscribed', expired: false),
            'subscriptionPermanent': false,
            'subscriptionExpiresOn': '2026-09-01',
            'subscriptionExpired': true,
          },
        ],
      );
      await _pump(tester, client);
      expect(find.text('Subscribed · Subscription expired'), findsOneWidget);
      await _openAccess(tester);
      await tester.enterText(
        find.byKey(const ValueKey('subscription-expiry-date')),
        '2027-02-30',
      );
      await _tap(tester, find.byKey(const ValueKey('save-user-access')));
      expect(find.text('Enter a valid date as YYYY-MM-DD.'), findsOneWidget);
      expect(client.posts, isEmpty);
    },
  );

  testWidgets(
    'suspend and resume require confirmation and show updated account status',
    (tester) async {
      final client = _UsersClient(users: [_guest(expired: false)]);
      await _pump(tester, client);
      await _tap(tester, find.text('Grace Guest'));
      await _tap(tester, find.byKey(const ValueKey('suspend-user-guest-1')));
      expect(find.text('Suspend user?'), findsOneWidget);
      expect(find.text('grace@example.test'), findsWidgets);
      expect(
        find.textContaining('profile and preferences will be kept'),
        findsOneWidget,
      );
      expect(client.posts, isEmpty);
      await _tap(tester, find.text('Cancel'));
      expect(client.posts, isEmpty);
      await _tap(tester, find.byKey(const ValueKey('suspend-user-guest-1')));
      await _tap(tester, find.byKey(const ValueKey('confirm-user-action')));
      expect(client.posts.single.path, '/admin/users/guest-1/actions');
      expect(client.posts.single.body, {
        'revision': 'original-revision',
        'action': 'suspend',
        'confirmation': 'guest-1',
      });
      expect(find.text('Guest · Suspended'), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('resume-user-guest-1')));
      expect(
        find.textContaining('existing role and expiry date still apply'),
        findsOneWidget,
      );
      await _tap(tester, find.byKey(const ValueKey('confirm-user-action')));
      expect(client.posts.last.body['action'], 'resume');
      expect(find.text('Guest · Active'), findsOneWidget);
    },
  );

  testWidgets(
    'termination conflicts require reload before confirmation with a fresh revision',
    (tester) async {
      final client = _UsersClient(users: [_guest(expired: false)])
        ..mutationError = const AdminApiException(
          'Stale account',
          status: 409,
          code: 'membership_conflict',
        );
      await _pump(tester, client);
      await _tap(tester, find.text('Grace Guest'));
      await _tap(tester, find.byKey(const ValueKey('terminate-user-guest-1')));
      expect(find.textContaining('existing sessions revoked'), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('confirm-user-action')));
      expect(
        find.text(
          'This account changed. Reload the account and confirm the action again.',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('confirm-user-action')),
            )
            .onPressed,
        isNull,
      );
      client.mutationError = null;
      client.reloadedUser = {
        ..._guest(expired: false),
        'revision': 'fresh-revision',
      };
      await _tap(tester, find.byKey(const ValueKey('reload-user-action')));
      await _tap(tester, find.byKey(const ValueKey('confirm-user-action')));
      expect(client.posts.last.body, {
        'revision': 'fresh-revision',
        'action': 'terminate',
        'confirmation': 'guest-1',
      });
      expect(find.text('Guest · Terminated'), findsOneWidget);
    },
  );

  testWidgets(
    'deletion requires matching typed identity and removes the confirmed account',
    (tester) async {
      final client = _UsersClient(users: [_guest(expired: false)]);
      await _pump(tester, client);
      await _tap(tester, find.text('Grace Guest'));
      await _tap(tester, find.byKey(const ValueKey('delete-user-guest-1')));
      expect(find.textContaining('This cannot be undone.'), findsOneWidget);
      final button = find.byKey(const ValueKey('confirm-user-action'));
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      await tester.enterText(
        find.byKey(const ValueKey('delete-user-confirmation')),
        'wrong@example.test',
      );
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      expect(client.posts, isEmpty);
      await tester.enterText(
        find.byKey(const ValueKey('delete-user-confirmation')),
        'grace@example.test',
      );
      await _tap(tester, button);
      expect(client.posts.single.body, {
        'revision': 'original-revision',
        'action': 'delete',
        'confirmation': 'guest-1',
      });
      expect(find.text('Grace Guest'), findsNothing);
      expect(find.text('User deleted.'), findsOneWidget);
    },
  );

  testWidgets(
    'incomplete deletion can be retried while other changes are disabled',
    (tester) async {
      final client = _UsersClient(
        users: [
          {..._guest(), 'accountStatus': 'deleting'},
        ],
      );
      await _pump(tester, client);
      expect(find.text('Guest · Deletion in progress'), findsOneWidget);
      await _tap(tester, find.text('Grace Guest'));
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('suspend-user-guest-1')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('terminate-user-guest-1')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('edit-user-access-guest-1')),
            )
            .onPressed,
        isNull,
      );
      expect(find.text('Retry deletion'), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('delete-user-guest-1')));
      await tester.enterText(
        find.byKey(const ValueKey('delete-user-confirmation')),
        'guest-1',
      );
      await _tap(tester, find.byKey(const ValueKey('confirm-user-action')));
      expect(client.posts.single.body['action'], 'delete');
      expect(find.text('Grace Guest'), findsNothing);
    },
  );

  testWidgets(
    'details load saved preferences and paginated login and session activity',
    (tester) async {
      final client = _UsersClient(users: [_guest()])
        ..reloadedUser = {
          ..._guest(),
          'profileCompleted': true,
          'preferencesSource': 'saved_profile',
          'preferences': {
            'menuLanguage': 'arabic',
            'topicLanguage': 'french',
            'bibleLanguage': 'english',
            'bibleVersion': 'kjv',
            'zoomLevel': 1.2,
            'showDiacritics': true,
            'interlinearEnabled': false,
            'showTranslationLabels': true,
            'showTopicNamesInChapter': false,
          },
        }
        ..activityPages = [
          {
            'summary': {
              'lastActiveAt': '2026-10-11T09:05:00Z',
              'totalActiveSeconds': 3660,
              'loginCount': 2,
              'sessionCount': 2,
            },
            'logins': [
              {'id': 'login-new', 'signedInAt': '2026-10-11T09:00:00Z'},
            ],
            'sessions': [
              {
                'id': 'session-new',
                'startedAt': '2026-10-11T09:00:00Z',
                'lastActiveAt': '2026-10-11T09:05:00Z',
                'activeSeconds': 300,
              },
            ],
            'nextPageToken': 'activity+cursor=',
          },
          {
            'summary': {
              'lastActiveAt': '2026-10-11T09:05:00Z',
              'totalActiveSeconds': 3660,
              'loginCount': 2,
              'sessionCount': 2,
            },
            'logins': [
              {'id': 'login-old', 'signedInAt': '2026-10-10T08:00:00Z'},
            ],
            'sessions': [
              {
                'id': 'session-old',
                'startedAt': '2026-10-10T08:00:00Z',
                'lastActiveAt': '2026-10-10T08:56:00Z',
                'endedAt': '2026-10-10T09:00:00Z',
                'activeSeconds': 3360,
              },
            ],
            'nextPageToken': null,
          },
        ];
      await _pump(tester, client);
      await _tap(tester, find.text('Grace Guest'));
      await _tap(
        tester,
        find.byKey(const ValueKey('view-user-details-guest-1')),
      );
      expect(find.text('Interface language: arabic'), findsOneWidget);
      expect(find.text('Topic language: french'), findsOneWidget);
      expect(find.text('Bible translation: kjv'), findsOneWidget);
      expect(find.text('Text size: 120%'), findsOneWidget);
      expect(find.text('Arabic diacritics: On'), findsOneWidget);
      expect(find.text('Profile completed: Yes'), findsOneWidget);
      expect(
        find.textContaining('excludes idle or background time'),
        findsOneWidget,
      );
      expect(find.text('Estimated active time: 1 h 1 min'), findsOneWidget);
      expect(find.text('Logins: 2'), findsOneWidget);
      expect(find.textContaining('Signed in:'), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('load-more-user-activity')));
      expect(
        Uri.parse(client.paths.last).queryParameters['pageToken'],
        'activity+cursor=',
      );
      expect(find.textContaining('Signed in:'), findsNWidgets(2));
      expect(find.textContaining('Ended:'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('load-more-user-activity')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'details distinguish missing preferences and retry activity errors',
    (tester) async {
      final client = _UsersClient(users: [_guest()])
        ..activityError = const AdminApiException(
          'Activity temporarily unavailable',
        );
      await _pump(tester, client);
      await _tap(tester, find.text('Grace Guest'));
      await _tap(
        tester,
        find.byKey(const ValueKey('view-user-details-guest-1')),
      );
      expect(
        find.text('No preferences have been saved by this user.'),
        findsOneWidget,
      );
      expect(find.text('Activity temporarily unavailable'), findsOneWidget);
      client.activityError = null;
      await _tap(tester, find.text('Retry activity'));
      expect(find.text('No logins recorded yet.'), findsOneWidget);
      expect(find.text('No sessions recorded yet.'), findsOneWidget);
      expect(client.posts, isEmpty);
    },
  );

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
        'subscriptionPermanent': true,
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
      expect(
        find.text('Manage user roles, access and accounts'),
        findsOneWidget,
      );
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
    for (final action in ['suspend', 'terminate', 'delete']) {
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(ValueKey('$action-user-guest-1')),
            )
            .onPressed,
        isNull,
      );
    }
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
