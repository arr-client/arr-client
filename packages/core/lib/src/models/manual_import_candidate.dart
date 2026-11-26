import 'item_ref.dart';
import 'json_object.dart';
import 'language.dart';
import 'quality.dart';

/// A file awaiting manual import.
final class ManualImportCandidate {
  /// Creates a [ManualImportCandidate].
  const ManualImportCandidate({
    required this.path,
    required this.size,
    required this.rawJson,
    this.downloadId,
    this.matchedRef,
    this.albumId,
    this.bookId,
    this.quality,
    this.episodeIds = const [],
    this.trackIds = const [],
    this.languages = const [],
    this.rejections = const [],
    this.selected = false,
  });

  /// The file on the server.
  final String path;

  /// Bytes.
  final int size;

  /// The download it came from.
  final String? downloadId;

  /// The movie, series, artist or author.
  final ItemRef? matchedRef;

  /// Matched episodes.
  final List<int> episodeIds;

  /// Matched album.
  final int? albumId;

  /// Matched tracks.
  final List<int> trackIds;

  /// Matched book.
  final int? bookId;

  /// Matched quality.
  final Quality? quality;

  /// Matched languages.
  final List<Language> languages;

  /// Why the server would not import it by itself.
  final List<String> rejections;

  /// Whether it is to be imported.
  final bool selected;

  /// The server's record, sent back on import.
  final JsonObject rawJson;
}
