import 'csv_download.dart';
import 'topics_table_document.dart';

export 'topics_table_output_native.dart'
    if (dart.library.html) 'topics_table_output_web.dart';

Future<void> downloadTopicsCsv(TopicsTableDocument document, String filename) =>
    downloadCsv(document.toCsv(), filename);
