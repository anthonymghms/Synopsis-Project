/// Language choices retain their own names regardless of the menu locale.
/// Imported languages not listed here use their administrator-provided label.
String nativeLanguageName(String code, String fallbackLabel) {
  final normalized = code.trim().toLowerCase().replaceAll(RegExp(r'[ _-]'), '');
  return switch (normalized) {
    'en' || 'eng' || 'english' => 'English',
    'ar' || 'ara' || 'arabic' || 'arabic2' => 'العربية',
    'fr' || 'fra' || 'fre' || 'french' || 'français' => 'Français',
    'grc' || 'ancientgreek' => 'Ἑλληνική',
    'el' || 'ell' || 'greek' || 'moderngreek' => 'Ελληνικά',
    'he' || 'heb' || 'hebrew' => 'עברית',
    'de' || 'deu' || 'german' => 'Deutsch',
    'es' || 'spa' || 'spanish' => 'Español',
    'it' || 'ita' || 'italian' => 'Italiano',
    'pt' || 'por' || 'portuguese' => 'Português',
    'la' || 'lat' || 'latin' => 'Latina',
    _ => fallbackLabel.trim().isNotEmpty ? fallbackLabel.trim() : code.trim(),
  };
}
