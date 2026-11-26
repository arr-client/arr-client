part of 'library_item.dart';

/// A music artist.
final class Artist extends LibraryItem {
  /// Creates an [Artist].
  const Artist({
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
    this.metadataProfileId,
    this.albums = const [],
  });

  /// The artist's metadata profile.
  final int? metadataProfileId;

  /// The artist's albums.
  final List<Album> albums;
}
