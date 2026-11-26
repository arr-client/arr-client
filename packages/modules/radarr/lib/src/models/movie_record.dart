import 'package:core/core.dart';

import 'image_record.dart';
import 'json_fields.dart';
import 'media_file_record.dart';

/// The state of the movie in [record]. Whether it is in the queue is not part
/// of the record.
ItemState movieState(JsonObject record, {required bool downloading}) {
  final hasFile = record['hasFile'] == true;
  return ItemState.resolve(
    downloading: downloading,
    allWantedPresent: hasFile,
    anyPresent: hasFile,
    monitored: record['monitored'] == true,
    // The server counts its availability delay in, so the dates are not used.
    released: record['isAvailable'] != false,
  );
}

/// A record of `GET movie`.
Movie readMovie(
  JsonObject record, {
  required String instanceId,
  required ItemState state,
}) {
  final title = requireText(record, 'title');
  return Movie(
    ref: ItemRef(
      instanceId: instanceId,
      kind: MediaKind.movie,
      remoteId: requireInt(record, 'id'),
    ),
    title: title,
    sortTitle: optionalText(record, 'sortTitle') ?? title,
    monitored: record['monitored'] == true,
    state: state,
    year: _positive(record['year']),
    overview: optionalText(record, 'overview'),
    images: readImages(record),
    qualityProfileId: _positive(record['qualityProfileId']),
    tagIds: switch (record['tags']) {
      final List<Object?> tags => tags.whereType<int>().toSet(),
      _ => const {},
    },
    path: optionalText(record, 'path'),
    sizeOnDisk: _positive(record['sizeOnDisk']) ?? 0,
    addedAt: _date(record, 'added'),
    runtime: switch (_positive(record['runtime'])) {
      final minutes? => Duration(minutes: minutes),
      null => null,
    },
    genres: switch (record['genres']) {
      final List<Object?> genres => genres.whereType<String>().toList(),
      _ => const [],
    },
    certification: optionalText(record, 'certification'),
    ratings: _ratings(record['ratings']),
    studio: optionalText(record, 'studio'),
    inCinemas: _date(record, 'inCinemas'),
    digitalRelease: _date(record, 'digitalRelease'),
    physicalRelease: _date(record, 'physicalRelease'),
    minimumAvailability:
        MinimumAvailability.values.asNameMap()[record['minimumAvailability']] ??
        MinimumAvailability.unknown,
    file: switch (record['movieFile']) {
      final JsonObject file => readMediaFile(file),
      _ => null,
    },
  );
}

/// Radarr writes zero for a number it does not know.
int? _positive(Object? value) => value is int && value > 0 ? value : null;

DateTime? _date(JsonObject record, String field) =>
    DateTime.tryParse(optionalText(record, field) ?? '')?.toUtc();

/// `ratings` holds one object for each source.
List<Rating> _ratings(Object? json) => [
  if (json is JsonObject)
    for (final MapEntry(key: source, value: rating) in json.entries)
      if (rating case {'value': final num value})
        Rating(
          source: source,
          value: value.toDouble(),
          votes: switch (rating) {
            {'votes': final int votes} => votes,
            _ => null,
          },
        ),
];
