import 'subtitle_language.dart';
import 'subtitle_media.dart';

/// Subtitles a title lacks.
final class SubtitleWant {
  /// Creates a [SubtitleWant].
  const SubtitleWant({
    required this.media,
    required this.title,
    required this.missing,
  });

  /// The movie or episode.
  final SubtitleMedia media;

  /// Title to show.
  final String title;

  /// The languages lacking.
  final List<SubtitleLanguage> missing;
}
