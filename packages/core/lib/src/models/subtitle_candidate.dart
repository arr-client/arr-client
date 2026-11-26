import 'subtitle_language.dart';

/// A subtitle a provider offers.
final class SubtitleCandidate {
  /// Creates a [SubtitleCandidate].
  const SubtitleCandidate({
    required this.provider,
    required this.language,
    required this.score,
    required this.originalFormat,
    required this.token,
    this.matches = const [],
    this.dontMatches = const [],
  });

  /// The provider offering it.
  final String provider;

  /// Its language.
  final SubtitleLanguage language;

  /// How well it matches.
  final double score;

  /// Properties that match.
  final List<String> matches;

  /// Properties that do not match.
  final List<String> dontMatches;

  /// Sent back when downloading.
  final String originalFormat;

  /// Identifies the candidate when downloading.
  final String token;
}
