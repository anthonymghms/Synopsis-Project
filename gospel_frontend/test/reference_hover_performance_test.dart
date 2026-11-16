import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gospel_frontend/account_access.dart';
import 'package:gospel_frontend/catalog_events.dart';
import 'package:gospel_frontend/main.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  for (final combined in [false, true]) {
    final kind = combined ? 'combined' : 'single';
    testWidgets(
      '$kind hover starts promptly, reuses text, and only repositions on movement',
      (tester) async {
        final previousAccess = accountAccess;
        final pending = <String, Completer<http.Response>>{};
        var requests = 0;
        final client = MockClient((request) async {
          if (request.url.path == '/account/access') {
            return http.Response(
              jsonEncode({
                'uid': 'reader',
                'role': 'subscribed',
                'canRead': true,
                'accessStatus': 'active',
              }),
              200,
            );
          }
          expect(request.url.path, '/get_verse');
          expect(request.headers['Authorization'], 'Bearer test-token');
          requests++;
          final response = Completer<http.Response>();
          pending[request.url.queryParameters['verse']!] = response;
          return response.future;
        });
        accountAccess = AccountAccessController(
          tokenProvider: () async => 'test-token',
          client: client,
        )..beginSession('reader');
        final offset = ValueNotifier<double>(0);
        final menuLanguage = ValueNotifier<String>('english');
        addTearDown(() {
          accountAccess.dispose();
          accountAccess = previousAccess;
          offset.dispose();
          menuLanguage.dispose();
          client.close();
        });

        await http.runWithClient(() async {
          await accountAccess.refresh(force: true);
          notifyCatalogChanged();
          const references = [
            GospelReference(book: 'John', chapter: 1, verses: '1'),
            GospelReference(book: 'John', chapter: 1, verses: '2'),
          ];
          final preview = combined
              ? const ReferenceCellHoverPreview(
                  references: references,
                  language: 'english',
                  version: 'kjv',
                  child: Text('John 1:1; 2'),
                )
              : ReferenceHoverText(
                  reference: references.first,
                  language: 'english',
                  version: 'kjv',
                  showHoverTooltip: false,
                );
          await tester.pumpWidget(
            MaterialApp(
              home: MenuLanguageScope(
                notifier: menuLanguage,
                child: Scaffold(
                  body: Center(
                    child: ValueListenableBuilder<double>(
                      valueListenable: offset,
                      child: preview,
                      builder: (context, value, child) => Transform.translate(
                        offset: Offset(value, 0),
                        child: child,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          final target = combined
              ? find.byType(ReferenceCellHoverPreview)
              : find.byType(ReferenceHoverText);
          final gesture = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await gesture.addPointer(location: Offset.zero);
          await gesture.moveTo(tester.getCenter(target));
          await tester.pump(const Duration(milliseconds: 150));
          expect(requests, 0);
          await gesture.moveTo(Offset.zero);
          await tester.pump(const Duration(milliseconds: 300));
          expect(requests, 0, reason: 'Passing over a link must not fetch it.');

          await gesture.moveTo(tester.getCenter(target));
          await tester.pump(const Duration(milliseconds: 249));
          expect(requests, 0);
          await tester.pump(const Duration(milliseconds: 1));
          expect(requests, combined ? 2 : 1);
          expect(find.byType(CircularProgressIndicator), findsOneWidget);
          for (final entry in pending.entries) {
            entry.value.complete(
              http.Response(
                jsonEncode([
                  {
                    'verse': int.parse(entry.key),
                    'text': 'Preview ${entry.key}',
                  },
                ]),
                200,
              ),
            );
          }
          await tester.pumpAndSettle();

          final text = find.textContaining('Preview 1', findRichText: true);
          expect(text, findsOneWidget);
          final originalTextWidget = tester.widget(text);
          for (var i = 0; i < 5; i++) {
            await tester.pump(const Duration(milliseconds: 16));
          }
          expect(
            identical(tester.widget(text), originalTextWidget),
            isTrue,
            reason: 'A stationary preview must not rebuild its verse content.',
          );

          final beforeMove = tester.getTopLeft(text);
          offset.value = 4;
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 16));
          expect(tester.getTopLeft(text).dx, closeTo(beforeMove.dx + 4, 0.1));
          expect(tester.getTopLeft(text).dy, closeTo(beforeMove.dy, 0.1));

          await gesture.moveTo(Offset.zero);
          await tester.pump(const Duration(milliseconds: 200));
          await gesture.moveTo(tester.getCenter(target));
          await tester.pump(const Duration(milliseconds: 250));
          await tester.pump();
          expect(text, findsOneWidget);
          expect(requests, combined ? 2 : 1);

          await gesture.moveTo(Offset.zero);
          await tester.pump(const Duration(milliseconds: 200));
          await gesture.removePointer();
          await tester.pumpWidget(const SizedBox());
          accountAccess.clear();
        }, () => client);
      },
    );
  }
}
