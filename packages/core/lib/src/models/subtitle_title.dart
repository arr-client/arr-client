import 'subtitle_file.dart';
import 'subtitle_language.dart';
import 'subtitle_media.dart';

/// The subtitle state of a title.
final class SubtitleTitle {
  /// Creates a [SubtitleTitle].
  const SubtitleTitle({
    required this.media,
    required this.title,
    this.year,
    this.missingCount = 0,
    this.missing = const [],
    this.files = const [],
  });

  /// The movie, series or episode.
  final SubtitleMedia media;

  /// Title to show.
  final String title;

  /// Year of first release.
  final int? year;

  /// Number of missing subtitles.
  final int missingCount;

  /// The languages a movie or episode lacks; what an automatic search can be
  /// asked for. Empty for a series, which has [missingCount] only.
  final List<SubtitleLanguage> missing;

  /// Subtitles present.
  final List<SubtitleFile> files;
}
