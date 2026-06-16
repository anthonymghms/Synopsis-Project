import 'package:flutter/widgets.dart';

typedef BrowserRouteLinkBuilder =
    Widget Function(BuildContext context, VoidCallback? followLink);

class BrowserRouteLink extends StatelessWidget {
  const BrowserRouteLink({super.key, required this.uri, required this.builder});

  final Uri? uri;
  final BrowserRouteLinkBuilder builder;

  void _follow(BuildContext context) {
    final target = uri;
    if (target == null) {
      return;
    }
    Navigator.of(context).pushNamed(target.toString());
  }

  @override
  Widget build(BuildContext context) {
    return builder(context, uri == null ? null : () => _follow(context));
  }
}
