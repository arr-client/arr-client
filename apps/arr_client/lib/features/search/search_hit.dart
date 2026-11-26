/// One title as the search shows it, and how the answers of several sources are
/// put together (spec story 3).
library;

import 'package:core/core.dart';

/// A title found by one or more sources.
final class SearchHit {
  const SearchHit._({
    required this.kind,
    required this.title,
    required this.externalIds,
    required this.year,
    required this.parentTitle,
    required this.overview,
    required this.images,
    required this.artworkInstanceId,
    required this.existingRefs,
    required this.sourceByInstance,
    required this.discovered,
  });

  /// What a `LookupProvider` of [instanceId] found.
  factory SearchHit.fromLookup(String instanceId, AddCandidate candidate) =>
      SearchHit._(
        kind: candidate.kind,
        title: candidate.title,
        externalIds: candidate.externalIds,
        year: candidate.year,
        parentTitle: candidate.parentTitle,
        overview: candidate.overview,
        images: candidate.images,
        artworkInstanceId: candidate.images.isEmpty ? null : instanceId,
        existingRefs: candidate.existingRefs,
        sourceByInstance: candidate.sourceByInstance,
        discovered: const {},
      );

  /// What the request service [instanceId] found.
  factory SearchHit.fromDiscovery(String instanceId, DiscoveryTitle found) =>
      SearchHit._(
        kind: switch (found.mediaType) {
          DiscoveryMediaType.movie => MediaKind.movie,
          DiscoveryMediaType.series => MediaKind.series,
        },
        title: found.title,
        externalIds: ExternalIds(tmdbId: found.tmdbId, tvdbId: found.tvdbId),
        year: found.year,
        parentTitle: null,
        overview: null,
        images: [?found.poster],
        artworkInstanceId: found.poster == null ? null : instanceId,
        existingRefs: const [],
        sourceByInstance: const {},
        discovered: {instanceId: found},
      );

  final MediaKind kind;
  final String title;
  final ExternalIds externalIds;
  final int? year;
  final String? parentTitle;
  final String? overview;
  final List<MediaImage> images;

  /// The instance whose loader reads [images]; null without any.
  final String? artworkInstanceId;

  /// One for each instance that has the title.
  final List<ItemRef> existingRefs;

  /// The lookup record of each instance whose search found it.
  final Map<String, JsonObject> sourceByInstance;

  /// What each request service that found it says.
  final Map<String, DiscoveryTitle> discovered;

  /// Whether a library service found it, so that it can be added.
  bool get canAdd => sourceByInstance.isNotEmpty;

  AddCandidate get candidate => AddCandidate(
    kind: kind,
    title: title,
    externalIds: externalIds,
    year: year,
    parentTitle: parentTitle,
    overview: overview,
    images: images,
    existingRefs: existingRefs,
    sourceByInstance: sourceByInstance,
  );

  /// Whether [other] is the same title by a shared identifier. Titles and years
  /// are never compared: without a shared identifier two results stay apart.
  bool isSameTitle(SearchHit other) {
    if (kind != other.kind) return false;
    final mine = externalIds;
    final theirs = other.externalIds;
    bool shared(Object? a, Object? b) => a != null && a == b;
    return switch (kind) {
      MediaKind.movie => shared(mine.tmdbId, theirs.tmdbId),
      // TVDB is what a series server knows a series by: two TVDB ids are two
      // series, whatever else they share.
      MediaKind.series =>
        mine.tvdbId != null && theirs.tvdbId != null
            ? mine.tvdbId == theirs.tvdbId
            : shared(mine.tmdbId, theirs.tmdbId),
      MediaKind.artist ||
      MediaKind.album => shared(mine.musicBrainzId, theirs.musicBrainzId),
      // A book or author id means something only to the metadata source it came
      // from, which two servers need not share.
      MediaKind.author ||
      MediaKind.book ||
      MediaKind.episode ||
      MediaKind.track => false,
    };
  }

  /// This title with what [other] knows of it. What is already shown stays;
  /// [other] only fills gaps. Artwork an instance serves itself also replaces
  /// artwork of other hosts only, which the user may have switched off.
  SearchHit mergedWith(SearchHit other) {
    final mine = externalIds;
    final theirs = other.externalIds;
    bool served(List<MediaImage> images) =>
        images.any((image) => image.instancePath != null);
    final keepImages =
        images.isNotEmpty && (served(images) || !served(other.images));
    return SearchHit._(
      kind: kind,
      title: title,
      externalIds: ExternalIds(
        tmdbId: mine.tmdbId ?? theirs.tmdbId,
        tvdbId: mine.tvdbId ?? theirs.tvdbId,
        imdbId: mine.imdbId ?? theirs.imdbId,
        musicBrainzId: mine.musicBrainzId ?? theirs.musicBrainzId,
        foreignId: mine.foreignId ?? theirs.foreignId,
      ),
      year: year ?? other.year,
      parentTitle: parentTitle ?? other.parentTitle,
      overview: overview ?? other.overview,
      images: keepImages ? images : other.images,
      artworkInstanceId: keepImages
          ? artworkInstanceId
          : other.artworkInstanceId,
      existingRefs: [
        ...existingRefs,
        for (final ref in other.existingRefs)
          if (!existingRefs.any((own) => own.instanceId == ref.instanceId)) ref,
      ],
      sourceByInstance: {...other.sourceByInstance, ...sourceByInstance},
      discovered: {...other.discovered, ...discovered},
    );
  }
}

/// [shown] with [arrived] merged in. No hit of [shown] moves or goes away: one
/// that matches is updated where it is, and the others follow at the end.
List<SearchHit> mergeHits(List<SearchHit> shown, Iterable<SearchHit> arrived) {
  final hits = [...shown];
  for (final hit in arrived) {
    final at = hits.indexWhere((other) => other.isSameTitle(hit));
    if (at < 0) {
      hits.add(hit);
    } else {
      hits[at] = hits[at].mergedWith(hit);
    }
  }
  return hits;
}
