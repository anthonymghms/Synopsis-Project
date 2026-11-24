import 'dart:convert';

/// A print-only group. CSV remains a rectangular snapshot of [rows].
class TopicsTableDocumentGroup {
  const TopicsTableDocumentGroup({required this.label, required this.rows});

  final String label;
  final List<List<String>> rows;
  int get count => rows.length;
}

/// A snapshot of every row in the current table, independent of its viewport.
class TopicsTableDocument {
  const TopicsTableDocument({
    required this.title,
    required this.headers,
    required this.rows,
    this.isRtl = false,
    this.groups = const [],
  });

  final String title;
  final List<String> headers;
  final List<List<String>> rows;
  final bool isRtl;

  /// Complete matching groups, including rows in sections collapsed on screen.
  final List<TopicsTableDocumentGroup> groups;

  String toCsv() {
    String cell(String value) {
      // Quoting alone does not stop spreadsheets from evaluating formulas.
      if (RegExp(r'^\s*[=+@-]').hasMatch(value)) value = "'$value";
      return '"${value.replaceAll('"', '""')}"';
    }

    // Excel uses the BOM to recognize Arabic and other UTF-8 text.
    return '\uFEFF${[headers, ...rows].map((row) => row.map(cell).join(',')).join('\r\n')}\r\n';
  }

  String toPrintHtml() {
    const escape = HtmlEscape();
    String row(List<String> cells, String tag) =>
        '<tr>${cells.map((cell) => '<$tag>${escape.convert(cell)}</$tag>').join()}</tr>';
    // A presentation snapshot must never make matching rows disappear. If a
    // caller supplies incomplete groups, retain the complete flat snapshot.
    final body = _groupsContainEveryRow
        ? groups
              .map(
                (group) =>
                    '<tbody><tr class="topic-type-group"><th '
                    'colspan="${headers.length}" scope="rowgroup">'
                    '${escape.convert(group.label)} — ${group.count}</th></tr>'
                    '${group.rows.map((cells) => row(cells, 'td')).join()}</tbody>',
              )
              .join()
        : '<tbody>${rows.map((cells) => row(cells, 'td')).join()}</tbody>';
    final numbered = headers.length > 1 && headers.first == '#';
    final columns = numbered
        ? '<col style="width:5%"><col style="width:35%">${List.filled(headers.length - 2, '<col>').join()}'
        : '<col style="width:44%">${List.filled(headers.isEmpty ? 0 : headers.length - 1, '<col>').join()}';
    return '<section dir="${isRtl ? 'rtl' : 'ltr'}">'
        '<h1>${escape.convert(title)}</h1>'
        '<table><colgroup>$columns</colgroup>'
        '<thead>${row(headers, 'th')}</thead>'
        '$body'
        '</table></section>';
  }

  /// A self-contained document for the Android and iOS system print services.
  String toStandalonePrintHtml() =>
      '<!doctype html><html><head><meta charset="utf-8">'
      '<style>$_printedTableStyles</style></head>'
      '<body id="harmony-print-root">${toPrintHtml()}</body></html>';

  bool get _groupsContainEveryRow {
    if (groups.isEmpty) return false;
    final remaining = <String, int>{};
    for (final row in rows) {
      final key = jsonEncode(row);
      remaining[key] = (remaining[key] ?? 0) + 1;
    }
    for (final group in groups) {
      for (final row in group.rows) {
        final key = jsonEncode(row);
        final count = remaining[key] ?? 0;
        if (count == 0) return false;
        if (count == 1) {
          remaining.remove(key);
        } else {
          remaining[key] = count - 1;
        }
      }
    }
    return remaining.isEmpty;
  }
}

const topicsPrintStyles =
    '''
#harmony-print-root { display: none; }
@media print {
  @page { size: A4 landscape; margin: 10mm; }
  html:has(body.harmony-printing), body.harmony-printing {
    position: static !important;
    width: auto !important;
    height: auto !important;
    overflow: visible !important;
  }
  body.harmony-printing > :not(#harmony-print-root) { display: none !important; }
  body.harmony-printing #harmony-print-root {
    display: block !important;
    position: static;
    width: 100%;
  }
  $_printedTableStyles
}
''';

const _printedTableStyles = '''
  #harmony-print-root {
    color: #111;
    background: white;
    font: 10pt Arial, sans-serif;
  }
  #harmony-print-root h1 { font-size: 16pt; margin: 0 0 6mm; }
  #harmony-print-root table { width: 100%; border-collapse: collapse; table-layout: fixed; }
  #harmony-print-root thead { display: table-header-group; }
  #harmony-print-root tr { break-inside: avoid; page-break-inside: avoid; }
  #harmony-print-root th, #harmony-print-root td {
    border: 0.5pt solid #888;
    padding: 2mm;
    text-align: start;
    vertical-align: top;
    overflow-wrap: anywhere;
    white-space: pre-wrap;
  }
  #harmony-print-root th { background: #eee; font-weight: bold; }
  #harmony-print-root .topic-type-group th {
    background: #ddd;
    break-after: avoid;
    page-break-after: avoid;
  }
''';
