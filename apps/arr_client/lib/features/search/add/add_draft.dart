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

/// What the add form of one instance holds. A required choice is null where
/// the server offers nothing to choose, or no longer offers what was chosen.
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
    this.gone = const {},
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

  /// The choices that the server no longer offers: the user has to choose
  /// again, as no other is taken in their place.
  final Set<ServerOptionKind> gone;

  /// What to send, or null while a required choice is empty.
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

  /// This draft with only what [options] offers. A root folder or profile that
  /// is gone is left empty and noted in [gone]; where none was chosen yet the
  /// first is taken. A tag that is gone is dropped.
  AddDraft fitting(AddOptions options) {
    final missing = <ServerOptionKind>{};
    int? offered(ServerOptionKind kind, int? chosen) {
      final ids = [for (final option in optionsOf(options, kind)) option.id];
      if (ids.contains(chosen)) return chosen;
      if (chosen == null && !gone.contains(kind)) return ids.firstOrNull;
      missing.add(kind);
      return null;
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
      gone: missing,
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
    // What has just been chosen is no longer missing.
    gone: gone.difference({
      if (rootFolderId != null) ServerOptionKind.rootFolder,
      if (qualityProfileId != null) ServerOptionKind.qualityProfile,
      if (metadataProfileId != null) ServerOptionKind.metadataProfile,
    }),
  );

  // The required choices are given as they are to be, null included.
  AddDraft _copy({
    required int? rootFolderId,
    required int? qualityProfileId,
    required int? metadataProfileId,
    required String? monitorOptionId,
    required Set<int> tagIds,
    required bool needsMetadataProfile,
    required Set<ServerOptionKind> gone,
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
    gone: gone,
  );
}
