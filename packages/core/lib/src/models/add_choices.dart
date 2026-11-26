import 'minimum_availability.dart';
import 'series_type.dart';

/// What the user chose when adding an item.
final class AddChoices {
  const AddChoices({
    required this.rootFolderId,
    required this.qualityProfileId,
    required this.monitorOptionId,
    required this.searchNow,
    this.metadataProfileId,
    this.seriesType,
    this.seasonFolder,
    this.minimumAvailability,
    this.tagIds = const {},
  });

  final int rootFolderId;

  final int qualityProfileId;

  final String monitorOptionId;

  final bool searchNow;

  /// Music and books.
  final int? metadataProfileId;

  final Set<int> tagIds;

  /// Series.
  final SeriesType? seriesType;

  /// Series.
  final bool? seasonFolder;

  /// Movies.
  final MinimumAvailability? minimumAvailability;
}
