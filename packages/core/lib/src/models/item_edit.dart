import 'minimum_availability.dart';
import 'series_type.dart';

/// The fields the user changed; null means unchanged.
final class ItemEdit {
  const ItemEdit({
    this.monitored,
    this.qualityProfileId,
    this.metadataProfileId,
    this.tagIds,
    this.seriesType,
    this.seasonFolder,
    this.minimumAvailability,
  });

  final bool? monitored;

  final int? qualityProfileId;

  final int? metadataProfileId;

  final Set<int>? tagIds;

  final SeriesType? seriesType;

  final bool? seasonFolder;

  final MinimumAvailability? minimumAvailability;
}
