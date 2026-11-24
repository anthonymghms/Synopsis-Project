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
  static final _layers = <html.Element, _BrowserFindTextState>{};
  static _BrowserFindTextState? _lastSelection;
  static StreamSubscription<html.Event>? _selectionChangeSubscription;
  static Timer? _selectionPollTimer;

  html.DivElement? _textLayerElement;
  html.EventListener? _beforeMatchListener;
  bool _ensureVisibleScheduled = false;

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
    _BrowserFindTextState? layerFor(html.Node? node) {
      while (node != null) {
        final state = _layers[node];
        if (state != null) return state;
        node = node.parentNode;
      }
      return null;
    }

    final active =
        layerFor(selection?.focusNode) ?? layerFor(selection?.anchorNode);
    if (_lastSelection != active) {
      _lastSelection = active;
      active?._scheduleEnsureVisible();
    }
  }

  void _configureTextLayer(Object element) {
    _removeBeforeMatchListener();
    final div = element as html.DivElement;
    _layers[div] = this;
    _ensureSelectionObservers();
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

  void _removeBeforeMatchListener() {
    final element = _textLayerElement;
    final listener = _beforeMatchListener;
    if (element != null && listener != null) {
      element.removeEventListener('beforematch', listener);
    }
    _layers.remove(element);
    if (_lastSelection == this) _lastSelection = null;
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
    if (context.dependOnInheritedWidgetOfExactType<_IndexedTable>() != null ||
        widget.text.trim().isEmpty) {
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
                isVisible: false,
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
    _removeBeforeMatchListener();
    if (_layers.isEmpty) {
      _selectionChangeSubscription?.cancel();
      _selectionChangeSubscription = null;
      _selectionPollTimer?.cancel();
      _selectionPollTimer = null;
    }
    super.dispose();
  }
}

/// One searchable DOM text index for the complete, filtered table. Interactive
/// Flutter cells and native anchors can then be mounted only near the viewport.
class BrowserTableFindIndex extends StatefulWidget {
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
  State<BrowserTableFindIndex> createState() => _BrowserTableFindIndexState();
}

class _BrowserTableFindIndexState extends State<BrowserTableFindIndex> {
  html.DivElement? _root;
  StreamSubscription<html.Event>? _matches;
  StreamSubscription<html.Event>? _selections;
  bool _active = false;

  void _reveal(html.Node? node) {
    final cell = node is html.Element ? node : node?.parent;
    if (!_active || cell == null || cell.parent != _root) return;
    final row = int.tryParse(cell.dataset['row'] ?? '');
    final column = int.tryParse(cell.dataset['column'] ?? '');
    if (row != null && column != null) widget.onMatch(row, column);
  }

  void _attach(Object element) {
    if (!mounted) return;
    _detach();
    final root = _root = element as html.DivElement;
    root.dataset['gospelFindIndex'] = '';
    root.setAttribute('aria-hidden', 'true');
    root.style
      ..opacity = '0'
      ..width = '100%'
      ..height = '100%'
      ..overflow = 'hidden'
      ..pointerEvents = 'none'
      ..userSelect = 'text'
      ..whiteSpace = 'pre'
      ..lineHeight = '1px';
    _matches = root.on['beforematch'].listen((event) {
      final target = event.target;
      if (target is html.Node) _reveal(target);
    });
    _selections = html.document.onSelectionChange.listen((_) {
      _reveal(html.window.getSelection()?.focusNode);
    });
    _populate();
  }

  void _populate() {
    final root = _root;
    if (!_active || root == null) return;
    final fragment = html.DocumentFragment();
    var row = 0;
    for (final cells in widget.buildRows()) {
      for (var column = 0; column < cells.length; column++) {
        if (cells[column].isEmpty) continue;
        final cell = html.DivElement()
          ..text = cells[column]
          ..setAttribute('hidden', 'until-found')
          // Keep native beforematch notifications and browser-driven text
          // selection available (including window.find on desktop Chrome).
          ..style.display = 'block'
          ..style.setProperty('content-visibility', 'visible')
          ..dataset['row'] = row.toString()
          ..dataset['column'] = column.toString();
        fragment.append(cell);
      }
      row++;
    }
    root.nodes.clear();
    root.append(fragment);
  }

  @override
  void didUpdateWidget(BrowserTableFindIndex oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision) _populate();
  }

  @override
  Widget build(BuildContext context) {
    _active = ModalRoute.isCurrentOf(context) ?? true;
    return _IndexedTable(
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (_active)
            PositionedDirectional(
              start: 0,
              top: 0,
              width: 1,
              height: 1,
              child: ExcludeSemantics(
                child: IgnorePointer(
                  child: HtmlElementView.fromTagName(
                    tagName: 'div',
                    isVisible: false,
                    onElementCreated: _attach,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _detach() {
    _matches?.cancel();
    _selections?.cancel();
    _root = null;
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }
}

class _IndexedTable extends InheritedWidget {
  const _IndexedTable({required super.child});
  @override
  bool updateShouldNotify(_IndexedTable oldWidget) => false;
}
