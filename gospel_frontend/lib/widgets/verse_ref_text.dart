import 'package:flutter/material.dart';
import 'package:gospel_frontend/utils/format_verse_ref.dart';

class VerseRefText extends StatelessWidget {
  const VerseRefText({
    super.key,
    required this.value,
    required this.lang,
    this.style,
    this.textAlign,
  });

  final String value;
  final String lang;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final formatted = formatVerseRef(value, lang);
    return Directionality(
      textDirection: formatted.dir ?? Directionality.of(context),
      child: Text(
        formatted.text,
        style: style,
        textAlign: textAlign,
      ),
    );
  }
}
