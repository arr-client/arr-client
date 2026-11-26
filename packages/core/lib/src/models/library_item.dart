import 'edition.dart';
import 'item_ref.dart';
import 'item_state.dart';
import 'media_file.dart';
import 'media_image.dart';
import 'minimum_availability.dart';
import 'rating.dart';
import 'season.dart';
import 'series_status.dart';
import 'series_type.dart';

part 'album.dart';
part 'artist.dart';
part 'author.dart';
part 'book.dart';
part 'episode.dart';
part 'movie.dart';
part 'series.dart';
part 'track.dart';

/// What every item of a library has.
sealed class LibraryItem {
  const LibraryItem({
    required this.ref,
    required this.title,
    required this.sortTitle,
    required this.monitored,
    required this.state,
    this.year,
    this.overview,
    this.images = const [],
    this.qualityProfileId,
    this.tagIds = const {},
    this.path,
    this.sizeOnDisk = 0,
    this.addedAt,
    this.parent,
    this.parentTitle,
  });

  /// The item's key.
  final ItemRef ref;

  /// The title.
  final String title;

  /// The title to sort by.
  final String sortTitle;

  /// Year of first release.
  final int? year;

  /// Description.
  final String? overview;

  /// Artwork.
  final List<MediaImage> images;

  /// Whether the server monitors the item.
  final bool monitored;

  /// The item's state.
  final ItemState state;

  /// Its quality profile.
  final int? qualityProfileId;

  /// Its tags.
  final Set<int> tagIds;

  /// Where the server stores it.
  final String? path;

  /// Bytes used on the server.
  final int sizeOnDisk;

  /// When the server added it.
  final DateTime? addedAt;

  /// What the item belongs to: an episode's series, an album's artist, a
  /// track's album or a book's author. Null for a top-level item.
  final ItemRef? parent;

  /// The title of [parent], so that a list can show it.
  final String? parentTitle;
}
