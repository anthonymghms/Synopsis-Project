import 'dart:convert';

/// A snapshot of every row in the current table, independent of its viewport.
class TopicsTableDocument {
  const TopicsTableDocument({
    required this.title,
    required this.headers,
    required this.rows,
    this.isRtl = false,
  });

  final String title;
  final List<String> headers;
  final List<List<String>> rows;
  final bool isRtl;

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
    return '<section dir="${isRtl ? 'rtl' : 'ltr'}">'
        '<h1>${escape.convert(title)}</h1>'
        '<table><colgroup><col style="width:44%">'
        '${List.filled(headers.length - 1, '<col>').join()}</colgroup>'
        '<thead>${row(headers, 'th')}</thead>'
        '<tbody>${rows.map((cells) => row(cells, 'td')).join()}</tbody>'
        '</table></section>';
  }
}

const topicsPrintStyles = '''
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
}
''';
