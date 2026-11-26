import 'minimum_availability.dart';
import 'series_type.dart';

/// What the user chose when adding an item.
final class AddChoices {
  /// Creates an [AddChoices].
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

  /// Where the server stores the item.
  final int rootFolderId;

  /// The quality profile to use.
  final int qualityProfileId;

  /// The chosen `MonitorOption.id`.
  final String monitorOptionId;

  /// Whether to search as soon as it is added.
  final bool searchNow;

  /// Music and books.
  final int? metadataProfileId;

  /// Tags to assign.
  final Set<int> tagIds;

  /// Series.
  final SeriesType? seriesType;

  /// Series.
  final bool? seasonFolder;

  /// Movies.
  final MinimumAvailability? minimumAvailability;
}
