import 'package:core/core.dart';

import 'json_fields.dart';
import 'media_record.dart';

/// The state of an episode (data-model.md LibraryItem.state) at [now].
ItemState episodeState(
  JsonObject record, {
  required bool downloading,
  required DateTime now,
}) {
  final hasFile = record['hasFile'] == true;
  final aired = _airDate(record);
  return ItemState.resolve(
    downloading: downloading,
    allWantedPresent: hasFile,
    anyPresent: hasFile,
    monitored: record['monitored'] == true,
    released: aired != null && !aired.isAfter(now),
  );
}

/// What episodes sort by: their place in the series.
String episodeSortTitle(JsonObject record) {
  String part(String field) => '${requireInt(record, field)}'.padLeft(6, '0');
  return '${part('seasonNumber')}x${part('episodeNumber')}';
}

/// A record of `GET episode`.
Episode readEpisode(
  JsonObject record, {
  required ItemRef ref,
  required ItemRef series,
  required String? seriesTitle,
  required ItemState state,
}) {
  final file = switch (record['episodeFile']) {
    final JsonObject file => readFile(file),
    _ => null,
  };
  return Episode(
    ref: ref,
    title: optionalText(record, 'title') ?? '',
    sortTitle: episodeSortTitle(record),
    monitored: record['monitored'] == true,
    state: state,
    overview: optionalText(record, 'overview'),
    images: readImages(record['images']),
    path: file?.path,
    sizeOnDisk: file?.size ?? 0,
    parent: series,
    parentTitle: seriesTitle,
    seasonNumber: requireInt(record, 'seasonNumber'),
    episodeNumber: requireInt(record, 'episodeNumber'),
    airDateUtc: _airDate(record),
    hasFile: record['hasFile'] == true,
    file: file,
  );
}

DateTime? _airDate(JsonObject record) =>
    DateTime.tryParse(optionalText(record, 'airDateUtc') ?? '')?.toUtc();
