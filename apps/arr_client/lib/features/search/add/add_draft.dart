import 'package:core/core.dart';

/// The series types a user can choose.
const seriesTypeChoices = [
  SeriesType.standard,
  SeriesType.daily,
  SeriesType.anime,
];

/// The minimum availabilities a user can choose, as Radarr's own form does.
const minimumAvailabilityChoices = [
  MinimumAvailability.announced,
  MinimumAvailability.inCinemas,
  MinimumAvailability.released,
];

/// The options of one kind that a server offers.
List<ServerOption> optionsOf(AddOptions options, ServerOptionKind kind) => [
  for (final option in options.serverOptions)
    if (option.kind == kind) option,
];

/// What the add form of one instance holds. A required choice is null only
/// where the server offers nothing to choose.
final class AddDraft {
  const AddDraft._({
    required this.kind,
    required this.rootFolderId,
    required this.qualityProfileId,
    required this.metadataProfileId,
    required this.monitorOptionId,
    required this.tagIds,
    required this.searchNow,
    required this.seriesType,
    required this.seasonFolder,
    required this.minimumAvailability,
    required this.needsMetadataProfile,
  });

  /// The form for adding a [kind] with [options], with the [remembered]
  /// choices preselected as far as the server still offers them.
  ///
  /// Without a memory the first of each list is taken, and a search is started
  /// at once except for a series, which could be a great many downloads; the
  /// web forms of Radarr and Sonarr start likewise.
  factory AddDraft.from(
    MediaKind kind,
    AddOptions options,
    AddChoices? remembered,
  ) => AddDraft._(
    kind: kind,
    rootFolderId: remembered?.rootFolderId,
    qualityProfileId: remembered?.qualityProfileId,
    metadataProfileId: remembered?.metadataProfileId,
    monitorOptionId: remembered?.monitorOptionId,
    tagIds: remembered?.tagIds ?? const {},
    searchNow: remembered?.searchNow ?? kind != MediaKind.series,
    seriesType: kind != MediaKind.series
        ? null
        : seriesTypeChoices.contains(remembered?.seriesType)
        ? remembered?.seriesType
        : SeriesType.standard,
    seasonFolder: kind != MediaKind.series
        ? null
        : remembered?.seasonFolder ?? true,
    minimumAvailability: kind != MediaKind.movie
        ? null
        : minimumAvailabilityChoices.contains(remembered?.minimumAvailability)
        ? remembered?.minimumAvailability
        : MinimumAvailability.released,
    needsMetadataProfile: false,
  ).fitting(options);

  final MediaKind kind;
  final int? rootFolderId;
  final int? qualityProfileId;

  /// Music and books.
  final int? metadataProfileId;
  final String? monitorOptionId;
  final Set<int> tagIds;
  final bool searchNow;

  /// Series.
  final SeriesType? seriesType;

  /// Series.
  final bool? seasonFolder;

  /// Movies.
  final MinimumAvailability? minimumAvailability;

  /// Whether the server has metadata profiles, so that one has to be chosen.
  final bool needsMetadataProfile;

  /// What to send, or null while the server offers nothing for a required
  /// choice.
  AddChoices? get choices {
    final root = rootFolderId;
    final quality = qualityProfileId;
    final monitor = monitorOptionId;
    if (root == null || quality == null || monitor == null) return null;
    if (needsMetadataProfile && metadataProfileId == null) return null;
    return AddChoices(
      rootFolderId: root,
      qualityProfileId: quality,
      monitorOptionId: monitor,
      searchNow: searchNow,
      metadataProfileId: metadataProfileId,
      tagIds: tagIds,
      seriesType: seriesType,
      seasonFolder: seasonFolder,
      minimumAvailability: minimumAvailability,
    );
  }

  /// This draft with only what [options] offers: a choice that is gone gives
  /// way to the first one, and a tag that is gone is dropped.
  AddDraft fitting(AddOptions options) {
    int? offered(ServerOptionKind kind, int? chosen) {
      final ids = [for (final option in optionsOf(options, kind)) option.id];
      return ids.contains(chosen) ? chosen : ids.firstOrNull;
    }

    final monitors = [for (final option in options.monitorOptions) option.id];
    final tags = {
      for (final tag in optionsOf(options, ServerOptionKind.tag)) tag.id,
    };
    return _copy(
      rootFolderId: offered(ServerOptionKind.rootFolder, rootFolderId),
      qualityProfileId: offered(
        ServerOptionKind.qualityProfile,
        qualityProfileId,
      ),
      metadataProfileId: offered(
        ServerOptionKind.metadataProfile,
        metadataProfileId,
      ),
      monitorOptionId: monitors.contains(monitorOptionId)
          ? monitorOptionId
          : monitors.firstOrNull,
      tagIds: tagIds.intersection(tags),
      needsMetadataProfile: optionsOf(
        options,
        ServerOptionKind.metadataProfile,
      ).isNotEmpty,
    );
  }

  AddDraft withRootFolder(int id) => _with(rootFolderId: id);
  AddDraft withQualityProfile(int id) => _with(qualityProfileId: id);
  AddDraft withMetadataProfile(int id) => _with(metadataProfileId: id);
  AddDraft withMonitorOption(String id) => _with(monitorOptionId: id);
  AddDraft withSearchNow(bool value) => _with(searchNow: value);
  AddDraft withSeriesType(SeriesType type) => _with(seriesType: type);
  AddDraft withSeasonFolder(bool value) => _with(seasonFolder: value);
  AddDraft withMinimumAvailability(MinimumAvailability value) =>
      _with(minimumAvailability: value);
  AddDraft withTag(int id, {required bool chosen}) =>
      _with(tagIds: chosen ? {...tagIds, id} : tagIds.difference({id}));

  AddDraft _with({
    int? rootFolderId,
    int? qualityProfileId,
    int? metadataProfileId,
    String? monitorOptionId,
    Set<int>? tagIds,
    bool? searchNow,
    SeriesType? seriesType,
    bool? seasonFolder,
    MinimumAvailability? minimumAvailability,
  }) => _copy(
    rootFolderId: rootFolderId ?? this.rootFolderId,
    qualityProfileId: qualityProfileId ?? this.qualityProfileId,
    metadataProfileId: metadataProfileId ?? this.metadataProfileId,
    monitorOptionId: monitorOptionId ?? this.monitorOptionId,
    tagIds: tagIds ?? this.tagIds,
    searchNow: searchNow ?? this.searchNow,
    seriesType: seriesType ?? this.seriesType,
    seasonFolder: seasonFolder ?? this.seasonFolder,
    minimumAvailability: minimumAvailability ?? this.minimumAvailability,
    needsMetadataProfile: needsMetadataProfile,
  );

  // The required choices are given as they are to be, null included.
  AddDraft _copy({
    required int? rootFolderId,
    required int? qualityProfileId,
    required int? metadataProfileId,
    required String? monitorOptionId,
    required Set<int> tagIds,
    required bool needsMetadataProfile,
    bool? searchNow,
    SeriesType? seriesType,
    bool? seasonFolder,
    MinimumAvailability? minimumAvailability,
  }) => AddDraft._(
    kind: kind,
    rootFolderId: rootFolderId,
    qualityProfileId: qualityProfileId,
    metadataProfileId: metadataProfileId,
    monitorOptionId: monitorOptionId,
    tagIds: tagIds,
    searchNow: searchNow ?? this.searchNow,
    seriesType: seriesType ?? this.seriesType,
    seasonFolder: seasonFolder ?? this.seasonFolder,
    minimumAvailability: minimumAvailability ?? this.minimumAvailability,
    needsMetadataProfile: needsMetadataProfile,
  );
}
