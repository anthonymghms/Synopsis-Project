// ignore_for_file: deprecated_member_use

import 'dart:async';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'package:flutter/widgets.dart';
import 'topics_table_document.dart';

void downloadTopicsCsv(TopicsTableDocument document, String filename) {
  final blob = html.Blob([document.toCsv()], 'text/csv;charset=utf-8');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..download = filename
    ..style.display = 'none';
  html.document.body!.append(anchor);
  anchor.click();
  anchor.remove();
  Timer(const Duration(seconds: 1), () => html.Url.revokeObjectUrl(url));
}

void printTopicsTable() => html.window.print();

/// Browser menu/Ctrl+P and the toolbar print action share the same full table.
class TopicsTablePrintScope extends StatefulWidget {
  const TopicsTablePrintScope({
    super.key,
    required this.document,
    required this.child,
  });

  final TopicsTableDocument? document;
  final Widget child;

  @override
  State<TopicsTablePrintScope> createState() => _TopicsTablePrintScopeState();
}

class _TopicsTablePrintScopeState extends State<TopicsTablePrintScope> {
  late final StreamSubscription<html.Event> _beforePrint;
  late final StreamSubscription<html.Event> _afterPrint;
  html.DivElement? _root;
  html.StyleElement? _style;
  bool _isCurrentRoute = true;

  @override
  void initState() {
    super.initState();
    _beforePrint = html.window.on['beforeprint'].listen((_) => _prepare());
    _afterPrint = html.window.on['afterprint'].listen((_) => _clear());
  }

  void _prepare() {
    final document = widget.document;
    if (!_isCurrentRoute || document == null) return;
    _clear();
    _style = html.StyleElement()..text = topicsPrintStyles;
    // All document content is escaped by toPrintHtml; only our markup is trusted.
    _root = html.DivElement()
      ..id = 'harmony-print-root'
      ..setInnerHtml(
        document.toPrintHtml(),
        treeSanitizer: html.NodeTreeSanitizer.trusted,
      );
    html.document.head!.append(_style!);
    html.document.body!
      ..append(_root!)
      ..classes.add('harmony-printing');
  }

  void _clear() {
    if (_root == null) return;
    _root!.remove();
    _style?.remove();
    html.document.body?.classes.remove('harmony-printing');
    _root = null;
    _style = null;
  }

  @override
  Widget build(BuildContext context) {
    _isCurrentRoute = ModalRoute.isCurrentOf(context) ?? true;
    return widget.child;
  }

  @override
  void dispose() {
    _beforePrint.cancel();
    _afterPrint.cancel();
    _clear();
    super.dispose();
  }
}
