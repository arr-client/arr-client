import 'subtitle_language.dart';
import 'subtitle_media_type.dart';

/// A subtitle file on the server.
final class SubtitleFile {
  /// Creates a [SubtitleFile].
  const SubtitleFile({
    required this.mediaType,
    required this.mediaId,
    required this.path,
    required this.language,
    this.seriesId,
  });

  /// Episode or movie.
  final SubtitleMediaType mediaType;

  /// The movie's or episode's id.
  final int mediaId;

  /// The episode's series.
  final int? seriesId;

  /// The file on the server.
  final String path;

  /// Its language.
  final SubtitleLanguage language;
}
