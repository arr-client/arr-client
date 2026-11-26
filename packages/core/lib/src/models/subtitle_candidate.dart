import 'subtitle_language.dart';

/// A subtitle a provider offers.
final class SubtitleCandidate {
  const SubtitleCandidate({
    required this.provider,
    required this.language,
    required this.score,
    required this.originalFormat,
    required this.token,
    this.matches = const [],
    this.dontMatches = const [],
  });

  final String provider;

  final SubtitleLanguage language;

  final double score;

  final List<String> matches;

  final List<String> dontMatches;

  /// Sent back when downloading.
  final String originalFormat;

  /// Identifies the candidate when downloading.
  final String token;
}
