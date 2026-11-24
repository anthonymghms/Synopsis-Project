import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The shared palette, type and layout used by the study and reading screens.
abstract final class StudyTheme {
  static const ivory = Color(0xfffcf6ee);
  static const paper = Color(0xfffffbf7);
  static const plum = Color(0xff613768);
  static const ink = Color(0xff362533);
  static const muted = Color(0xff705e60);
  static const lavender = Color(0xffeaddec);
  static const tint = Color(0xfff6eef4);
  static const line = Color(0xffdfcfd0);
  static const serif = 'Study Serif';
  static const sans = 'Study Sans';
  static const fallbacks = ['Study Arabic'];
  static const compact = 700.0;
  static const wide = 1050.0;
  static const maxWidth = 1480.0;
  static const radius = 16.0;
  static const gap = 16.0;
  static const sectionGap = 28.0;

  static double inset(double width) =>
      width < compact ? 18 : (width * .055).clamp(24.0, 88.0).toDouble();

  static TextStyle heading(double size, {Color color = ink}) => TextStyle(
    fontFamily: serif,
    fontFamilyFallback: fallbacks,
    fontWeight: FontWeight.w600,
    fontSize: size,
    height: 1.12,
    color: color,
  );

  static final theme = _build();

  static ThemeData _build() {
    final colors = ColorScheme.fromSeed(seedColor: plum).copyWith(
      primary: plum,
      onPrimary: Colors.white,
      primaryContainer: lavender,
      onPrimaryContainer: ink,
      secondary: const Color(0xff78566e),
      secondaryContainer: tint,
      surface: paper,
      onSurface: ink,
      onSurfaceVariant: muted,
      surfaceContainerLowest: paper,
      surfaceContainerLow: ivory,
      surfaceContainer: tint,
      surfaceContainerHighest: lavender,
      outline: const Color(0xffa78e98),
      outlineVariant: line,
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colors,
      fontFamily: sans,
      fontFamilyFallback: fallbacks,
      scaffoldBackgroundColor: ivory,
    );
    final type = base.textTheme.apply(bodyColor: ink, displayColor: ink);
    final edge = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: const BorderSide(color: line),
    );
    return base.copyWith(
      textTheme: type.copyWith(
        headlineLarge: heading(34),
        headlineMedium: heading(28),
        headlineSmall: heading(24),
        titleLarge: heading(21),
      ),
      appBarTheme: AppBarThemeData(
        backgroundColor: paper,
        foregroundColor: plum,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        shape: const Border(bottom: BorderSide(color: line)),
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        titleTextStyle: heading(24),
      ),
      cardTheme: CardThemeData(
        color: paper,
        elevation: 0,
        shape: edge,
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: paper,
        shape: edge,
        titleTextStyle: heading(24),
      ),
      popupMenuTheme: PopupMenuThemeData(color: paper, shape: edge),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: paper,
        selectedColor: lavender,
        side: const BorderSide(color: line),
        shape: const StadiumBorder(),
      ),
      dividerTheme: const DividerThemeData(color: line, thickness: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(44, 44)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 44),
          foregroundColor: plum,
          side: const BorderSide(color: Color(0xffb198ad)),
        ),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: paper,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: line),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: plum),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: paper,
        indicatorColor: lavender,
        elevation: 0,
        height: 66,
        labelTextStyle: WidgetStatePropertyAll(type.labelMedium),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: const WidgetStatePropertyAll(lavender),
        dividerThickness: 1,
        headingTextStyle: heading(17),
      ),
    );
  }
}

class StudyPhoto extends StatelessWidget {
  const StudyPhoto({
    super.key,
    required this.compact,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
  });
  final bool compact;
  final BoxFit fit;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/study/study-${compact ? 'compact' : 'wide'}.webp',
    width: double.infinity,
    height: double.infinity,
    fit: fit,
    alignment: alignment,
    excludeFromSemantics: true,
    filterQuality: FilterQuality.medium,
  );
}

class StudyBrand extends StatelessWidget {
  const StudyBrand({
    super.key,
    required this.name,
    this.onPressed,
    this.small = false,
  });
  final String name;
  final VoidCallback? onPressed;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.menu_book_outlined,
          color: StudyTheme.plum,
          size: small ? 30 : 40,
        ),
        SizedBox(width: small ? 7 : 10),
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: StudyTheme.heading(small ? 22 : 28),
          ),
        ),
      ],
    );
    if (onPressed == null) return content;
    return TextButton(onPressed: onPressed, child: content);
  }
}
