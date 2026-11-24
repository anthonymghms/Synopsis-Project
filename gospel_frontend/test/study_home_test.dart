import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gospel_frontend/account_access.dart';
import 'package:gospel_frontend/main.dart';
import 'package:gospel_frontend/study_theme.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  tearDown(() => MenuLanguageController.instance.update('english'));

  Future<void> openHome(
    WidgetTester tester,
    Size size, {
    bool authorized = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MenuLanguageScope(
        notifier: MenuLanguageController.instance.notifier,
        child: MaterialApp(
          theme: StudyTheme.theme,
          home: GospelHomeScreen(authenticated: authorized),
          onGenerateRoute: (settings) => MaterialPageRoute<void>(
            settings: settings,
            builder: (_) =>
                Scaffold(appBar: AppBar(), body: Text(settings.name!)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  testWidgets(
    'desktop has three landscape cards and opens each real dataset route',
    (tester) async {
      await openHome(tester, const Size(1440, 920));
      final first = find.byKey(const ValueKey('home-card-harmony'));
      final last = find.byKey(const ValueKey('home-card-parables'));
      expect(tester.getTopLeft(first).dy, tester.getTopLeft(last).dy);
      expect(tester.getSize(first).height, inInclusiveRange(100, 270));
      expect(
        find.text('Sign in to preview passages from the Harmony table.'),
        findsOneWidget,
      );
      for (final id in ['harmony', 'miracles', 'parables']) {
        await tester.tap(find.byKey(ValueKey('home-card-$id')));
        await tester.pumpAndSettle();
        expect(
          find.text(id == 'harmony' ? '/topics' : '/topics?dataset=$id'),
          findsOneWidget,
        );
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('How it works'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('Filter the table by Gospel'), findsOneWidget);
    },
  );

  testWidgets(
    'phone has full-width stacked cards, Arabic navigation and a working Parables shortcut',
    (tester) async {
      await openHome(tester, const Size(390, 844));
      final first = find.byKey(const ValueKey('home-card-harmony'));
      expect(tester.getSize(first).width, greaterThan(340));
      await tester.tap(find.byTooltip('Menu language'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(CheckedPopupMenuItem<String>, 'العربية'),
      );
      await tester.pumpAndSettle();
      expect(find.text('تعمّق في تعاليم يسوع'), findsOneWidget);
      expect(Directionality.of(tester.element(first)), TextDirection.rtl);
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('الأمثال'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('/topics?dataset=parables'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'authorized preview uses authenticated Harmony rows and shares the cache across rebuilds',
    (tester) async {
      final original = accountAccess;
      final requests = <String>[];
      final client = MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer fixture-token');
        requests.add(request.url.path);
        final body = switch (request.url.path) {
          '/account/access' => {
            'uid': 'preview-reader',
            'role': 'subscribed',
            'canRead': true,
            'accessStatus': 'active',
          },
          '/harmony/topics' => {
            'topics': [
              {
                'id': '101',
                'references': [
                  {'book': 'Mark', 'chapter': 4, 'verses': '1-2'},
                ],
              },
            ],
          },
          '/topic-localizations/english' => {
            'topics': [
              {'id': '101', 'name': 'Localized fixture from the API'},
            ],
          },
          _ => throw StateError('Unexpected path ${request.url.path}'),
        };
        return http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      accountAccess = AccountAccessController(
        client: client,
        tokenProvider: () async => 'fixture-token',
      )..beginSession('preview-reader');
      addTearDown(() {
        accountAccess.dispose();
        accountAccess = original;
        client.close();
      });
      await http.runWithClient(() async {
        await openHome(tester, const Size(1440, 920), authorized: true);
        await tester.ensureVisible(find.text('Localized fixture from the API'));
        expect(find.text('4:1–2'), findsOneWidget);
        tester.view.physicalSize = const Size(1150, 900);
        await tester.pumpAndSettle();
        expect(
          requests.where((path) => path == '/harmony/topics'),
          hasLength(1),
        );
        expect(
          requests.where((path) => path == '/topic-localizations/english'),
          hasLength(1),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        accountAccess.clear();
      }, () => client);
    },
  );
}
