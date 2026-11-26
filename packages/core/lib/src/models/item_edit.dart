import 'minimum_availability.dart';
import 'series_type.dart';

/// The fields the user changed; null means unchanged.
final class ItemEdit {
  /// Creates an [ItemEdit].
  const ItemEdit({
    this.monitored,
    this.qualityProfileId,
    this.metadataProfileId,
    this.tagIds,
    this.seriesType,
    this.seasonFolder,
    this.minimumAvailability,
  });

  /// Monitored flag.
  final bool? monitored;

  /// Quality profile.
  final int? qualityProfileId;

  /// Metadata profile.
  final int? metadataProfileId;

  /// The full new set of tags.
  final Set<int>? tagIds;

  /// Series type.
  final SeriesType? seriesType;

  /// Whether episodes go into season folders.
  final bool? seasonFolder;

  /// Minimum availability.
  final MinimumAvailability? minimumAvailability;
}
