import 'package:flutter_test/flutter_test.dart';
import 'package:gospel_frontend/gospel_filter.dart';
import 'package:gospel_frontend/main.dart';
import 'package:gospel_frontend/topic_language_catalog.dart';
import 'package:gospel_frontend/topics_table_document.dart';

void main() {
  test('CSV preserves Unicode, commas, quotes and multiline topic names', () {
    const document = TopicsTableDocument(
      title: 'Topics',
      headers: ['المواضيع', 'متى'],
      rows: [
        ['يسوع، "تعليم"\nsecond line', '1:1–3'],
        ['=1+1', '@SUM(A1)'],
      ],
    );
    expect(
      document.toCsv(),
      '\uFEFF"المواضيع","متى"\r\n'
      '"يسوع، ""تعليم""\nsecond line","1:1–3"\r\n'
      '"\'=1+1","\'@SUM(A1)"\r\n',
    );
  });

  test('print escapes content and includes the complete table', () {
    final document = TopicsTableDocument(
      title: '<Topics & references>',
      isRtl: true,
      headers: ['Topics', 'Matthew', 'Mark', 'Luke', 'John'],
      rows: [
        for (var i = 1; i <= 289; i++)
          ['$i <script>alert(1)</script>', '1:1', '2:2', '3:3', '4:4'],
      ],
    );
    final html = document.toPrintHtml();
    expect(html, contains('dir="rtl"'));
    expect(html, contains('&lt;Topics &amp; references&gt;'));
    expect(html, isNot(contains('<script>')));
    expect(html, contains('289 &lt;script&gt;'));
    expect('<tr>'.allMatches(html), hasLength(290));
  });

  test('outputs follow filtering, chronology and column visibility', () {
    final topics = [
      Topic(
        id: '1',
        name: 'Later',
        references: [
          GospelReference(book: 'Luke', chapter: 2, verses: '1'),
          GospelReference(book: 'John', chapter: 3, verses: '1'),
        ],
      ),
      Topic(
        id: '2',
        name: 'Excluded',
        references: [GospelReference(book: 'Matthew', chapter: 1, verses: '1')],
      ),
      Topic(
        id: '3',
        name: 'Earlier',
        references: [GospelReference(book: 'Luke', chapter: 1, verses: '1')],
      ),
    ];
    final columns = ColumnVisibilityState(visibleMask: Gospel.luke.bit);
    final processed = processHarmonyTopics(
      topics,
      GospelFilterState(includeMask: Gospel.luke.bit),
      const GospelSortState(mode: TopicSortMode.luke),
      columns,
    );
    final document = buildTopicsTableDocument(
      topics: processed.topics,
      sourceIndexes: processed.sourceIndexes,
      topicLanguage: bundledTopicLanguages.first,
      visibleGospels: columns.visibleGospels.toList(),
      title: 'Topics',
    );
    expect(document.headers, ['Subjects', 'Luke']);
    expect(document.rows, [
      ['3 Earlier', '1:1'],
      ['1 Later', '2:1'],
    ]);
    expect(document.toCsv(), isNot(contains('Excluded')));
    expect(document.toPrintHtml(), isNot(contains('<th>John</th>')));
  });

  test('Arabic output retains numbering and compact reference notation', () {
    final document = buildTopicsTableDocument(
      topics: [
        Topic(
          id: '289',
          name: 'الموضوع',
          references: [
            GospelReference(book: 'Luke', chapter: 1, verses: '78-80'),
            GospelReference(
              book: 'Luke',
              chapter: 2,
              verses: '1-7',
              separatorBefore: '+',
            ),
            GospelReference(
              book: 'Luke',
              chapter: 2,
              verses: '20',
              separatorBefore: ',',
            ),
            GospelReference(
              book: 'Luke',
              chapter: 3,
              verses: '5',
              separatorBefore: ';',
            ),
          ],
        ),
      ],
      topicLanguage: bundledTopicLanguages.last,
      visibleGospels: [Gospel.luke, Gospel.john],
      title: 'المواضيع',
    );
    expect(document.isRtl, isTrue);
    expect(document.rows.single.first, '٢٨٩ الموضوع');
    final reference = document.rows.single[1].replaceAll(
      RegExp('[\u200f\u2067\u2069]'),
      '',
    );
    expect(reference, '١:٧٨ ٢:٧، ٢٠؛ ٣:٥');
    expect(document.rows.single.last, '—');
  });
}
