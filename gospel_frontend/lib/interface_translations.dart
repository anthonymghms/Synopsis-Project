import 'bundled_interface_translations.dart';

export 'bundled_interface_translations.dart';

final _uploadedInterfaceTranslations = <String, Map<String, String>>{};

void registerInterfaceTranslations(
  String language,
  Map<String, String> labels,
) {
  _uploadedInterfaceTranslations[language.trim().toLowerCase()] = labels;
}

/// Reader interface strings with per-key English fallback.
class LocalizedUiLabels {
  const LocalizedUiLabels(this.values);
  final Map<String, String> values;

  factory LocalizedUiLabels.forLanguage(
    String language, [
    Map<String, String> overrides = const {},
  ]) => LocalizedUiLabels({
    ...bundledLabelsForLanguage(language),
    for (final entry
        in (_uploadedInterfaceTranslations[language.trim().toLowerCase()] ??
                <String, String>{})
            .entries)
      if (entry.value.trim().isNotEmpty) entry.key: entry.value,
    for (final entry in overrides.entries)
      if (entry.value.trim().isNotEmpty) entry.key: entry.value,
  });

  String text(String key) {
    final value = values[key]?.trim();
    return value != null && value.isNotEmpty
        ? value
        : englishInterfaceTranslations[key] ?? key;
  }

  List<String> get gospelHeaders => [
    for (final book in const ['Matthew', 'Mark', 'Luke', 'John'])
      text('gospel$book'),
  ];
  String formatGospelTitle(String book) =>
      gospelTitle.replaceAll('{book}', book);
  String formatChapterTitle(String gospel, String number) =>
      chapterTitle.replaceAllMapped(
        RegExp(r'\{(gospel|number)\}'),
        (match) => match[1] == 'gospel' ? gospel : number,
      );
  String get title => text('title');
  String get description => text('description');
  String get downloadPdf => text('downloadPdf');
  String get resetTable => text('resetTable');
  String get pdfUnavailableMessage => text('pdfUnavailableMessage');
  String get subjectsHeader => text('subjectsHeader');
  String get tooltipMessage => text('tooltipMessage');
  String get comparePrompt => text('comparePrompt');
  String get columns => text('columns');
  String get showColumns => text('showColumns');
  String get sort => text('sort');
  String get sortBy => text('sortBy');
  String get defaultSort => text('defaultSort');
  String get visibleColumns => text('visibleColumns');
  String get resetColumns => text('resetColumns');
  String get filter => text('filter');
  String get operation => text('operation');
  String get union => text('union');
  String get intersection => text('intersection');
  String get includeGospels => text('includeGospels');
  String get exclude => text('exclude');
  String get currentFilter => text('currentFilter');
  String get finalResult => text('finalResult');
  String get topics => text('topics');
  String get references => text('references');
  String get atLeastOneColumnVisible => text('atLeastOneColumnVisible');
  String get filterUpdatesLive => text('filterUpdatesLive');
  String get gospelCombinations => text('gospelCombinations');
  String get searchFilters => text('searchFilters');
  String get included => text('included');
  String get excluded => text('excluded');
  String get unrestricted => text('unrestricted');
  String get fourIncludedGospels => text('fourIncludedGospels');
  String get threeIncludedGospels => text('threeIncludedGospels');
  String get twoIncludedGospels => text('twoIncludedGospels');
  String get oneIncludedGospel => text('oneIncludedGospel');
  String get noExcludedGospels => text('noExcludedGospels');
  String get oneExcludedGospel => text('oneExcludedGospel');
  String get twoExcludedGospels => text('twoExcludedGospels');
  String get threeExcludedGospels => text('threeExcludedGospels');
  String get applyFilter => text('applyFilter');
  String get noMatchingFilterCombinations =>
      text('noMatchingFilterCombinations');
  String get clearFilter => text('clearFilter');
  String get allTopics => text('allTopics');
  String get results => text('results');
  String get language => text('language');
  String get version => text('version');
  String get bibleLanguage => text('bibleLanguage');
  String get translation => text('translation');
  String get changeTopicLanguage => text('changeTopicLanguage');
  String get addTranslation => text('addTranslation');
  String get addComparison => text('addComparison');
  String get interlinearView => text('interlinearView');
  String get zoom => text('zoom');
  String get backToMainTable => text('backToMainTable');
  String get nextChapter => text('nextChapter');
  String get previousChapter => text('previousChapter');
  String get nextTopic => text('nextTopic');
  String get previousTopic => text('previousTopic');
  String get nextBook => text('nextBook');
  String get previousBook => text('previousBook');
  String get chapter => text('chapter');
  String get addDiacritics => text('addDiacritics');
  String get removeDiacritics => text('removeDiacritics');
  String get selectVersion => text('selectVersion');
  String get selectVersions => text('selectVersions');
  String get selectTranslationToAdd => text('selectTranslationToAdd');
  String get selectLanguage => text('selectLanguage');
  String get versions => text('versions');
  String get noAlternativeVersions => text('noAlternativeVersions');
  String get comparisonScopeChapter => text('comparisonScopeChapter');
  String get comparisons => text('comparisons');
  String get change => text('change');
  String get changeTranslation => text('changeTranslation');
  String get changeMainTranslation => text('changeMainTranslation');
  String get removeComparison => text('removeComparison');
  String get editComparisonRange => text('editComparisonRange');
  String get cancel => text('cancel');
  String get done => text('done');
  String get save => text('save');
  String get saveRange => text('saveRange');
  String get customRange => text('customRange');
  String get entireChapter => text('entireChapter');
  String get highlightedReference => text('highlightedReference');
  String get startVerse => text('startVerse');
  String get endVerse => text('endVerse');
  String get selected => text('selected');
  String get showTranslationLabels => text('showTranslationLabels');
  String get duplicateComparison => text('duplicateComparison');
  String get noPassageText => text('noPassageText');
  String get unableToOpenReference => text('unableToOpenReference');
  String get topicNotFound => text('topicNotFound');
  String get reference => text('reference');
  String get clickToReadInChapter => text('clickToReadInChapter');
  String get clickToReadAllReferences => text('clickToReadAllReferences');
  String get showTopicNames => text('showTopicNames');
  String get hideTopicNames => text('hideTopicNames');
  String get menuLanguage => text('menuLanguage');
  String get settings => text('settings');
  String get logout => text('logout');
  String get account => text('account');
  String get continueAction => text('continueAction');
  String get compare => text('compare');
  String get chooseAuthors => text('chooseAuthors');
  String get gospelTitle => text('gospelTitle');
  String get chapterTitle => text('chapterTitle');
}

String interfaceLanguageKey(String language) =>
    switch (language.trim().toLowerCase()) {
      'fr' || 'fr-fr' || 'fr_fr' || 'français' || 'francais' => 'french',
      'en' => 'english',
      'ar' => 'arabic',
      final code => code,
    };

Map<String, String> bundledLabelsForLanguage(String language) =>
    bundledInterfaceTranslations[interfaceLanguageKey(language)] ?? const {};
