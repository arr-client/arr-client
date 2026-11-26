import 'language.dart';
import 'quality.dart';

/// A file on the server.
final class MediaFile {
  const MediaFile({
    required this.id,
    required this.path,
    required this.size,
    this.quality,
    this.video,
    this.audio,
    this.languages = const [],
  });

  final int id;

  final String path;

  final int size;

  final Quality? quality;

  final List<Language> languages;

  /// The video codec and format, as text.
  final String? video;

  /// The audio codec and format, as text.
  final String? audio;
}
