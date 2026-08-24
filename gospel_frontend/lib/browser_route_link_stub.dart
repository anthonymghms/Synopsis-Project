import 'dart:async';

import 'package:flutter/material.dart';

typedef BrowserRouteLinkBuilder =
    Widget Function(BuildContext context, VoidCallback? followLink);

class BrowserRouteLinkNavigation {
  static int _blockDepth = 0;
  static int _blockedUntilMicros = 0;

  static bool get isBlocked {
    if (_blockDepth > 0) {
      return true;
    }
    return DateTime.now().microsecondsSinceEpoch < _blockedUntilMicros;
  }

  static void pushBlock() {
    _blockDepth++;
  }

  static void popBlock() {
    if (_blockDepth > 0) {
      _blockDepth--;
    }
  }

  static void popBlockAfterEvent() {
    Timer.run(popBlock);
  }

  static void blockFor(Duration duration) {
    final until =
        DateTime.now().microsecondsSinceEpoch + duration.inMicroseconds;
    if (until > _blockedUntilMicros) {
      _blockedUntilMicros = until;
    }
  }
}

Future<T?> showBrowserSafeDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) async {
  BrowserRouteLinkNavigation.pushBlock();
  try {
    return await showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: builder,
    );
  } finally {
    BrowserRouteLinkNavigation.popBlockAfterEvent();
  }
}

class BrowserRouteHistory {
  static Stream<Uri> get changes => const Stream<Uri>.empty();

  static void update(Uri uri, {bool replace = false}) {}
}

class BrowserRouteLink extends StatelessWidget {
  const BrowserRouteLink({
    super.key,
    required this.uri,
    required this.builder,
    this.openInNewTab = false,
  });

  final Uri? uri;
  final BrowserRouteLinkBuilder builder;
  final bool openInNewTab;

  void _follow(BuildContext context) {
    final target = uri;
    if (target == null || BrowserRouteLinkNavigation.isBlocked) {
      return;
    }
    Navigator.of(context).pushNamed(target.toString());
  }

  @override
  Widget build(BuildContext context) {
    return builder(context, uri == null ? null : () => _follow(context));
  }
}
