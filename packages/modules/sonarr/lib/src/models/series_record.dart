import 'package:core/core.dart';

import 'json_fields.dart';
import 'media_record.dart';

/// The state of a series (data-model.md LibraryItem.state). What it wants is
/// what the server counts in `episodeCount`.
ItemState seriesState(JsonObject record, {required bool downloading}) {
  final statistics = _statistics(record);
  final wanted = optionalNumber(statistics, 'episodeCount') ?? 0;
  final present = optionalNumber(statistics, 'episodeFileCount') ?? 0;
  return ItemState.resolve(
    downloading: downloading,
    allWantedPresent: wanted > 0 && present >= wanted,
    anyPresent: present > 0,
    monitored: record['monitored'] == true,
    released: wanted > 0,
  );
}

/// A record of `GET series`.
Series readSeries(JsonObject record, ItemRef ref, ItemState state) {
  final title = requireText(record, 'title');
  return Series(
    ref: ref,
    title: title,
    sortTitle: optionalText(record, 'sortTitle') ?? title,
    monitored: record['monitored'] == true,
    state: state,
    year: optionalPositive(record, 'year'),
    overview: optionalText(record, 'overview'),
    images: readImages(record['images']),
    qualityProfileId: optionalPositive(record, 'qualityProfileId'),
    tagIds: {
      if (record['tags'] case final List<Object?> tags)
        ...tags.whereType<int>(),
    },
    path: optionalText(record, 'path'),
    sizeOnDisk: optionalNumber(_statistics(record), 'sizeOnDisk')?.toInt() ?? 0,
    addedAt: DateTime.tryParse(optionalText(record, 'added') ?? '')?.toUtc(),
    network: optionalText(record, 'network'),
    runtime: switch (optionalPositive(record, 'runtime')) {
      final minutes? => Duration(minutes: minutes),
      null => null,
    },
    certification: optionalText(record, 'certification'),
    seriesType:
        SeriesType.values.asNameMap()[record['seriesType']] ??
        SeriesType.unknown,
    seasonFolder: record['seasonFolder'] == true,
    status:
        SeriesStatus.values.asNameMap()[record['status']] ??
        SeriesStatus.unknown,
    genres: [
      if (record['genres'] case final List<Object?> genres)
        ...genres.whereType<String>(),
    ],
    ratings: _ratings(record['ratings']),
    seasons: [
      if (record['seasons'] case final List<Object?> seasons)
        for (final season in seasons) _season(asObject(season)),
    ],
  );
}

JsonObject _statistics(JsonObject record) => switch (record['statistics']) {
  final JsonObject statistics => statistics,
  _ => const {},
};

/// Sonarr gives one score and does not say whose it is.
List<Rating> _ratings(Object? json) {
  if (json is! JsonObject) return const [];
  final value = optionalNumber(json, 'value');
  if (value == null || value <= 0) return const [];
  return [
    Rating(
      source: '',
      value: value.toDouble(),
      votes: optionalNumber(json, 'votes')?.toInt(),
    ),
  ];
}

Season _season(JsonObject record) {
  final statistics = _statistics(record);
  int count(String field) => optionalNumber(statistics, field)?.toInt() ?? 0;
  return Season(
    number: requireInt(record, 'seasonNumber'),
    monitored: record['monitored'] == true,
    episodeCount: count('episodeCount'),
    episodeFileCount: count('episodeFileCount'),
    totalEpisodeCount: count('totalEpisodeCount'),
  );
}
