import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'topics_table_document.dart';

bool get supportsTableOutput =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

const _printChannel = MethodChannel('gospel_topics/print');

Future<void> printTopicsTable(TopicsTableDocument document) =>
    _printChannel.invokeMethod<void>('printTable', {
      'title': document.title,
      'html': document.toStandalonePrintHtml(),
    });

class TopicsTablePrintScope extends StatelessWidget {
  const TopicsTablePrintScope({
    super.key,
    this.document,
    this.buildDocument,
    required this.child,
  });

  final TopicsTableDocument? document;
  final TopicsTableDocument Function()? buildDocument;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
