import 'language.dart';
import 'quality.dart';

/// A file on the server.
final class MediaFile {
  /// Creates a [MediaFile].
  const MediaFile({
    required this.id,
    required this.path,
    required this.size,
    this.quality,
    this.video,
    this.audio,
    this.languages = const [],
  });

  /// The server's id of the file.
  final int id;

  /// Where it is on the server.
  final String path;

  /// Bytes.
  final int size;

  /// Its quality.
  final Quality? quality;

  /// Its audio languages.
  final List<Language> languages;

  /// The video codec and format, as text.
  final String? video;

  /// The audio codec and format, as text.
  final String? audio;
}
