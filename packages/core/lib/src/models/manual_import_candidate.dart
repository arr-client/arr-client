import 'item_ref.dart';
import 'json_object.dart';
import 'language.dart';
import 'quality.dart';

/// A file awaiting manual import.
final class ManualImportCandidate {
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

  final String path;

  final int size;

  final String? downloadId;

  /// The movie, series, artist or author.
  final ItemRef? matchedRef;

  final List<int> episodeIds;

  final int? albumId;

  final List<int> trackIds;

  final int? bookId;

  final Quality? quality;

  final List<Language> languages;

  final List<String> rejections;

  final bool selected;

  final JsonObject rawJson;
}
