/// A wanted or present subtitle language.
final class SubtitleLanguage {
  const SubtitleLanguage({
    required this.code,
    this.forced = false,
    this.hi = false,
  });

  /// The service's language code.
  final String code;

  final bool forced;

  /// For the hearing impaired.
  final bool hi;
}
