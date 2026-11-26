part of 'library_item.dart';

/// A music artist.
final class Artist extends LibraryItem {
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
    this.metadataProfileId,
    this.albums = const [],
  });

  final int? metadataProfileId;
  final List<Album> albums;
}
