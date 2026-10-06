import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gospel_frontend/reader_language_route.dart';

void main() {
  testWidgets('covered readers cannot undo a newer language; pop restores it', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    final activations = <String>[];
    late StateSetter rebuildArabic;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        navigatorObservers: [readerLanguageRouteObserver],
        home: StatefulBuilder(
          builder: (context, setState) {
            rebuildArabic = setState;
            return ReaderLanguageRoute(
              onActivated: () => activations.add('arabic'),
              child: const Scaffold(body: Text('Arabic reader')),
            );
          },
        ),
      ),
    );
    expect(activations, ['arabic']);

    unawaited(
      navigator.currentState!.push<void>(
        MaterialPageRoute(
          builder: (_) => ReaderLanguageRoute(
            onActivated: () => activations.add('english'),
            child: const Scaffold(body: Text('English table')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(activations, ['arabic', 'english']);

    rebuildArabic(() {});
    await tester.pumpAndSettle();
    expect(activations, ['arabic', 'english']);

    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(activations, ['arabic', 'english', 'arabic']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an asynchronous covered mount waits until it is current', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    final loaded = Completer<void>();
    final activations = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        navigatorObservers: [readerLanguageRouteObserver],
        home: FutureBuilder<void>(
          future: loaded.future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Scaffold(body: Text('Loading Arabic reader'));
            }
            return ReaderLanguageRoute(
              onActivated: () => activations.add('arabic'),
              child: const Scaffold(body: Text('Arabic reader')),
            );
          },
        ),
      ),
    );

    unawaited(
      navigator.currentState!.push<void>(
        MaterialPageRoute(
          builder: (_) => ReaderLanguageRoute(
            onActivated: () => activations.add('english'),
            child: const Scaffold(body: Text('English table')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    loaded.complete();
    await tester.pumpAndSettle();
    expect(activations, ['english']);

    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(activations, ['english', 'arabic']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ordinary rebuilds preserve the mounted route selection', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    final activations = <String>[];
    late StateSetter rebuild;
    var callbackLanguage = 'english';
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        navigatorObservers: [readerLanguageRouteObserver],
        home: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            final capturedLanguage = callbackLanguage;
            return ReaderLanguageRoute(
              onActivated: () => activations.add(capturedLanguage),
              child: const Scaffold(body: Text('Reader')),
            );
          },
        ),
      ),
    );
    rebuild(() => callbackLanguage = 'arabic');
    await tester.pumpAndSettle();
    expect(activations, ['english']);

    unawaited(
      navigator.currentState!.push<void>(
        MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('Settings')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(activations, ['english', 'english']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dismissing language menus and dialogs does not reactivate', (
    tester,
  ) async {
    final activations = <String>[];
    var selectedLanguage = 'arabic';
    late BuildContext pageContext;
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [readerLanguageRouteObserver],
        home: ReaderLanguageRoute(
          onActivated: () {
            activations.add('arabic');
            selectedLanguage = 'arabic';
          },
          child: Builder(
            builder: (context) {
              pageContext = context;
              return Scaffold(
                body: PopupMenuButton<String>(
                  onSelected: (value) => selectedLanguage = value,
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'english', child: Text('English')),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(selectedLanguage, 'english');
    expect(activations, ['arabic']);

    unawaited(
      showDialog<void>(
        context: pageContext,
        builder: (context) => AlertDialog(
          content: const Text('Translation details'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(selectedLanguage, 'english');
    expect(activations, ['arabic']);
    expect(tester.takeException(), isNull);
  });
}
