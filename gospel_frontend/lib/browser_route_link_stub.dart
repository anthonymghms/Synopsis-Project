import 'package:flutter/widgets.dart';

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

  static void blockFor(Duration duration) {
    final until =
        DateTime.now().microsecondsSinceEpoch + duration.inMicroseconds;
    if (until > _blockedUntilMicros) {
      _blockedUntilMicros = until;
    }
  }
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
