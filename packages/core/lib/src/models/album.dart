part of 'library_item.dart';

/// An album.
final class Album extends LibraryItem {
  /// Creates an [Album].
  const Album({
    required super.ref,
    required super.title,
    required super.sortTitle,
    required super.monitored,
    required super.state,
    super.year,
    super.overview,
    super.images,
    super.qualityProfileId,
    super.tagIds,
    super.path,
    super.sizeOnDisk,
    super.addedAt,
    super.parent,
    super.parentTitle,
    this.albumType,
    this.releaseDate,
    this.tracks = const [],
  });

  /// The server's type, such as album, EP or single.
  final String? albumType;

  /// When it was released.
  final DateTime? releaseDate;

  /// The album's tracks.
  final List<Track> tracks;
}
