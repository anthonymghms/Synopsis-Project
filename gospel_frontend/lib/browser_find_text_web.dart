// ignore_for_file: deprecated_member_use

import 'dart:async';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

class BrowserFindText extends StatefulWidget {
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
  State<BrowserFindText> createState() => _BrowserFindTextState();
}

class _BrowserFindTextState extends State<BrowserFindText> {
  static final Set<_BrowserFindTextState> _instances =
      <_BrowserFindTextState>{};
  static StreamSubscription<html.Event>? _selectionChangeSubscription;
  static Timer? _selectionPollTimer;

  html.DivElement? _textLayerElement;
  html.EventListener? _beforeMatchListener;
  bool _ensureVisibleScheduled = false;

  @override
  void initState() {
    super.initState();
    _instances.add(this);
    _ensureSelectionObservers();
  }

  static void _ensureSelectionObservers() {
    _selectionChangeSubscription ??= html.document.onSelectionChange.listen(
      (_) => _checkActiveSelection(),
    );
    _selectionPollTimer ??= Timer.periodic(
      const Duration(milliseconds: 150),
      (_) => _checkActiveSelection(),
    );
  }

  static void _checkActiveSelection() {
    final selection = html.window.getSelection();
    if (selection == null || selection.rangeCount == 0) {
      return;
    }

    for (final instance in List<_BrowserFindTextState>.of(_instances)) {
      if (instance._selectionTouchesTextLayer(selection)) {
        instance._scheduleEnsureVisible();
        return;
      }
    }
  }

  void _configureTextLayer(Object element) {
    _removeBeforeMatchListener();
    final div = element as html.DivElement;
    final style = widget.style;
    final direction =
        widget.textDirection ??
        Directionality.maybeOf(context) ??
        TextDirection.ltr;

    div
      ..text = widget.text
      ..setAttribute('aria-hidden', 'true')
      ..setAttribute('role', 'presentation')
      ..setAttribute('hidden', 'until-found');
    _textLayerElement = div;
    _beforeMatchListener = _handleBeforeMatch;
    div.addEventListener('beforematch', _beforeMatchListener);

    div.style
      ..display = 'block'
      ..width = '100%'
      ..height = '100%'
      ..boxSizing = 'border-box'
      ..overflow = 'hidden'
      ..pointerEvents = 'none'
      ..userSelect = 'text'
      ..color = 'transparent'
      ..setProperty('-webkit-text-fill-color', 'transparent')
      ..background = 'transparent'
      ..filter = 'none'
      ..textShadow = 'none'
      ..fontFamily = _fontFamily(style)
      ..fontSize = _fontSize(style)
      ..fontWeight = _fontWeight(style)
      ..fontStyle = _fontStyle(style)
      ..lineHeight = _lineHeight(style)
      ..letterSpacing = _letterSpacing(style)
      ..textAlign = _textAlign(widget.textAlign, direction)
      ..direction = direction == TextDirection.rtl ? 'rtl' : 'ltr'
      ..whiteSpace = widget.maxLines == 1 ? 'nowrap' : 'normal'
      ..textOverflow = widget.maxLines == 1 ? 'ellipsis' : 'clip';
  }

  void _handleBeforeMatch(html.Event event) {
    _scheduleEnsureVisible();
  }

  bool _selectionTouchesTextLayer(html.Selection selection) {
    final element = _textLayerElement;
    if (!mounted || element == null) {
      return false;
    }

    try {
      if (selection.containsNode(element, true)) {
        return true;
      }
    } catch (_) {
      // Some browser-owned find selections do not expose a normal DOM range.
    }

    return _containsNode(element, selection.anchorNode) ||
        _containsNode(element, selection.focusNode);
  }

  bool _containsNode(html.Element element, html.Node? node) {
    html.Node? current = node;
    while (current != null) {
      if (identical(current, element)) {
        return true;
      }
      current = current.parentNode;
    }
    return false;
  }

  void _removeBeforeMatchListener() {
    final element = _textLayerElement;
    final listener = _beforeMatchListener;
    if (element != null && listener != null) {
      element.removeEventListener('beforematch', listener);
    }
    _beforeMatchListener = null;
  }

  void _scheduleEnsureVisible() {
    if (_ensureVisibleScheduled) {
      return;
    }
    _ensureVisibleScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureVisibleScheduled = false;
      if (!mounted) {
        return;
      }
      Scrollable.ensureVisible(
        context,
        duration: Duration.zero,
        alignment: 0.5,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      );
    });
  }

  String _fontFamily(TextStyle? style) {
    final family = style?.fontFamily;
    if (family == null || family.trim().isEmpty) {
      return 'Roboto, Arial, sans-serif';
    }
    final fallback = style?.fontFamilyFallback;
    final families = [
      _quoteFontFamily(family),
      if (fallback != null) ...fallback.map(_quoteFontFamily),
      'Arial',
      'sans-serif',
    ];
    return families.join(', ');
  }

  String _quoteFontFamily(String family) {
    final trimmed = family.trim();
    if (trimmed.contains(' ') && !trimmed.startsWith('"')) {
      return '"$trimmed"';
    }
    return trimmed;
  }

  String _fontSize(TextStyle? style) {
    final size = style?.fontSize;
    return size == null ? '14px' : '${size}px';
  }

  String _fontWeight(TextStyle? style) {
    final weight = style?.fontWeight;
    if (weight == null) {
      return '400';
    }
    return '${(weight.index + 1) * 100}';
  }

  String _fontStyle(TextStyle? style) {
    return style?.fontStyle == FontStyle.italic ? 'italic' : 'normal';
  }

  String _lineHeight(TextStyle? style) {
    final height = style?.height;
    return height == null ? 'normal' : '$height';
  }

  String _letterSpacing(TextStyle? style) {
    final spacing = style?.letterSpacing;
    return spacing == null ? 'normal' : '${spacing}px';
  }

  String _textAlign(TextAlign? align, TextDirection direction) {
    switch (align) {
      case TextAlign.center:
        return 'center';
      case TextAlign.right:
        return 'right';
      case TextAlign.left:
        return 'left';
      case TextAlign.end:
        return direction == TextDirection.rtl ? 'left' : 'right';
      case TextAlign.justify:
        return 'justify';
      case TextAlign.start:
      case null:
        return direction == TextDirection.rtl ? 'right' : 'left';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.text.trim().isEmpty) {
      return widget.child;
    }

    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        Positioned.fill(
          child: ExcludeFocus(
            child: ExcludeSemantics(
              child: HtmlElementView.fromTagName(
                key: ValueKey(
                  Object.hash(
                    widget.text,
                    widget.style,
                    widget.textAlign,
                    widget.textDirection,
                    widget.maxLines,
                  ),
                ),
                tagName: 'div',
                isVisible: true,
                hitTestBehavior: PlatformViewHitTestBehavior.transparent,
                onElementCreated: _configureTextLayer,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _instances.remove(this);
    if (_instances.isEmpty) {
      _selectionChangeSubscription?.cancel();
      _selectionChangeSubscription = null;
      _selectionPollTimer?.cancel();
      _selectionPollTimer = null;
    }
    _removeBeforeMatchListener();
    super.dispose();
  }
}
