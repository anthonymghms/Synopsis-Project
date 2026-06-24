// ignore_for_file: deprecated_member_use

// ignore: avoid_web_libraries_in_flutter
import 'dart:async';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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

class BrowserRouteLink extends StatefulWidget {
  const BrowserRouteLink({super.key, required this.uri, required this.builder});

  final Uri? uri;
  final BrowserRouteLinkBuilder builder;

  @override
  State<BrowserRouteLink> createState() => _BrowserRouteLinkState();
}

class _BrowserRouteLinkState extends State<BrowserRouteLink> {
  static const int _navigationDedupeMicros = 100000;

  StreamSubscription<html.MouseEvent>? _clickSubscription;
  int _lastNavigationMicros = 0;

  String? get _href {
    final uri = widget.uri;
    if (uri == null) {
      return null;
    }
    if (uri.hasScheme || uri.hasAuthority) {
      return uri.toString();
    }
    return ui_web.urlStrategy?.prepareExternalUrl(uri.toString()) ??
        uri.toString();
  }

  void _follow() {
    final target = widget.uri;
    if (target == null ||
        !mounted ||
        BrowserRouteLinkNavigation.isBlocked ||
        _browserModifierPressed) {
      return;
    }
    final now = DateTime.now().microsecondsSinceEpoch;
    if (now - _lastNavigationMicros < _navigationDedupeMicros) {
      return;
    }
    _lastNavigationMicros = now;
    Navigator.of(context).pushNamed(target.toString());
  }

  void _configureAnchor(Object element) {
    _clickSubscription?.cancel();

    final anchor = element as html.AnchorElement;
    final href = _href;
    if (href == null) {
      anchor.removeAttribute('href');
    } else {
      anchor.href = href;
    }
    anchor
      ..target = '_self'
      ..rel = 'noreferrer noopener'
      ..tabIndex = -1
      ..setAttribute('aria-hidden', 'true');
    anchor.style
      ..opacity = '0'
      ..display = 'block'
      ..width = '100%'
      ..height = '100%'
      ..cursor = 'inherit';

    _clickSubscription = anchor.onClick.listen((event) {
      if (BrowserRouteLinkNavigation.isBlocked) {
        event.preventDefault();
        return;
      }
      if (_shouldLetBrowserHandle(event)) {
        return;
      }
      event.preventDefault();
      _follow();
    });
  }

  bool _shouldLetBrowserHandle(html.MouseEvent event) {
    return event.button != 0 ||
        event.ctrlKey ||
        event.metaKey ||
        event.altKey ||
        event.shiftKey;
  }

  bool get _browserModifierPressed {
    final keyboard = HardwareKeyboard.instance;
    return keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isAltPressed ||
        keyboard.isShiftPressed;
  }

  @override
  void dispose() {
    _clickSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final href = _href;
    final followLink = widget.uri == null ? null : _follow;
    final child = Semantics(
      link: widget.uri != null,
      linkUrl: widget.uri,
      child: widget.builder(context, followLink),
    );

    if (href == null) {
      return child;
    }

    return Stack(
      fit: StackFit.passthrough,
      children: [
        child,
        Positioned.fill(
          child: ExcludeFocus(
            child: ExcludeSemantics(
              child: HtmlElementView.fromTagName(
                key: ValueKey(href),
                tagName: 'a',
                isVisible: false,
                hitTestBehavior: PlatformViewHitTestBehavior.transparent,
                onElementCreated: _configureAnchor,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
