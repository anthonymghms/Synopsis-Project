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
