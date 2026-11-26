import 'subtitle_language.dart';
import 'subtitle_media_type.dart';

/// A subtitle file on the server.
final class SubtitleFile {
  const SubtitleFile({
    required this.mediaType,
    required this.mediaId,
    required this.path,
    required this.language,
    this.seriesId,
  });

  final SubtitleMediaType mediaType;

  /// The movie's or episode's id.
  final int mediaId;

  final int? seriesId;

  final String path;

  final SubtitleLanguage language;
}
