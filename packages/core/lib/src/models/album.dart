part of 'library_item.dart';

/// An album.
final class Album extends LibraryItem {
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
    this.albumType,
    this.releaseDate,
    this.tracks = const [],
  });

  final String? albumType;
  final DateTime? releaseDate;
  final List<Track> tracks;
}
