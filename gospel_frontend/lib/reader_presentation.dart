import 'package:flutter/material.dart';

import 'study_theme.dart';

/// Keeps the passage in view on phones, including when reading in landscape.
class ReaderTools extends StatefulWidget {
  const ReaderTools({
    super.key,
    required this.label,
    required this.version,
    required this.child,
  });

  final String label;
  final String version;
  final Widget child;

  @override
  State<ReaderTools> createState() => _ReaderToolsState();
}

class _ReaderToolsState extends State<ReaderTools> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final compact =
        viewport.width < StudyTheme.compact || viewport.height < 490;
    if (!compact) return widget.child;

    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            expanded: _expanded,
            child: InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.tune, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.label,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                      Flexible(
                        child: Text(
                          widget.version,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ),
                      Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_expanded)
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: viewport.height * .27),
              child: SingleChildScrollView(primary: false, child: widget.child),
            ),
        ],
      ),
    );
  }
}

TextStyle scriptureStyle(ThemeData theme) =>
    theme.textTheme.bodyLarge!.copyWith(
      fontFamily: StudyTheme.serif,
      fontSize: 19,
      height: 1.65,
      letterSpacing: 0,
    );

/// Applies the user's reading zoom in addition to the platform's accessibility
/// scale. Nested verse groups may already inherit the adjusted scaler.
class ReadingTextScaler extends TextScaler {
  const ReadingTextScaler(this.platformScale, this.zoom);

  final TextScaler platformScale;
  final double zoom;

  static TextScaler of(BuildContext context, double zoom) {
    final inherited = MediaQuery.textScalerOf(context);
    if (inherited is ReadingTextScaler && inherited.zoom == zoom) {
      return inherited;
    }
    return ReadingTextScaler(
      inherited is ReadingTextScaler ? inherited.platformScale : inherited,
      zoom,
    );
  }

  @override
  double scale(double fontSize) => platformScale.scale(fontSize) * zoom;

  @override
  double get textScaleFactor => scale(16) / 16;

  @override
  bool operator ==(Object other) =>
      other is ReadingTextScaler &&
      other.platformScale == platformScale &&
      other.zoom == zoom;

  @override
  int get hashCode => Object.hash(platformScale, zoom);
}
