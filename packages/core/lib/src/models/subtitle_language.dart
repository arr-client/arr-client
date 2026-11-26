/// A wanted or present subtitle language.
final class SubtitleLanguage {
  /// Creates a [SubtitleLanguage].
  const SubtitleLanguage({
    required this.code,
    this.forced = false,
    this.hi = false,
  });

  /// The service's language code.
  final String code;

  /// Only the parts in a foreign language.
  final bool forced;

  /// For the hearing impaired.
  final bool hi;
}
