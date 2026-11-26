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
  });

  final ItemRef ref;
  final String title;
  final String sortTitle;
  final int? year;
  final String? overview;
  final List<MediaImage> images;
  final bool monitored;
  final ItemState state;
  final int? qualityProfileId;
  final Set<int> tagIds;
  final String? path;
  final int sizeOnDisk;
  final DateTime? addedAt;
}
