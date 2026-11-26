part of 'library_item.dart';

/// A movie.
final class Movie extends LibraryItem {
  /// Creates a [Movie].
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
    super.parent,
    super.parentTitle,
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

  /// Running time.
  final Duration? runtime;

  /// Genres.
  final List<String> genres;

  /// Age rating.
  final String? certification;

  /// Scores.
  final List<Rating> ratings;

  /// Studio.
  final String? studio;

  /// Cinema release date.
  final DateTime? inCinemas;

  /// Digital release date.
  final DateTime? digitalRelease;

  /// Physical release date.
  final DateTime? physicalRelease;

  /// When it counts as available.
  final MinimumAvailability minimumAvailability;

  /// The movie's file.
  final MediaFile? file;
}
