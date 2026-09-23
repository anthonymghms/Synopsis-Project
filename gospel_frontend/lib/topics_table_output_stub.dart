import 'package:flutter/widgets.dart';
import 'topics_table_document.dart';

void downloadTopicsCsv(TopicsTableDocument document, String filename) {}
void printTopicsTable() {}

class TopicsTablePrintScope extends StatelessWidget {
  const TopicsTablePrintScope({
    super.key,
    required this.document,
    required this.child,
  });

  final TopicsTableDocument? document;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
