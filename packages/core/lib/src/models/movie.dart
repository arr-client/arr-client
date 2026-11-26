part of 'library_item.dart';

/// A movie.
final class Movie extends LibraryItem {
  const Movie({
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
    this.runtime,
    this.certification,
    this.studio,
    this.inCinemas,
    this.digitalRelease,
    this.physicalRelease,
    this.file,
    this.genres = const [],
    this.ratings = const [],
    this.minimumAvailability = MinimumAvailability.unknown,
  });

  final Duration? runtime;
  final List<String> genres;
  final String? certification;
  final List<Rating> ratings;
  final String? studio;
  final DateTime? inCinemas;
  final DateTime? digitalRelease;
  final DateTime? physicalRelease;
  final MinimumAvailability minimumAvailability;
  final MediaFile? file;
}
