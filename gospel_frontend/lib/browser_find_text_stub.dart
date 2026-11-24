import 'package:flutter/widgets.dart';

class BrowserFindText extends StatelessWidget {
  const BrowserFindText({
    super.key,
    required this.text,
    required this.child,
    this.style,
    this.textAlign,
    this.textDirection,
    this.maxLines,
  });

  final String text;
  final Widget child;
  final TextStyle? style;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    return child;
  }
}

class BrowserTableFindIndex extends StatelessWidget {
  const BrowserTableFindIndex({
    super.key,
    required this.revision,
    required this.buildRows,
    required this.onMatch,
    required this.child,
  });
  final Object revision;
  final Iterable<List<String>> Function() buildRows;
  final void Function(int row, int column) onMatch;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
