/// Records of artists, albums and tracks.
library;

import 'package:core/core.dart';

import 'json_fields.dart';
import 'media_record.dart';

/// The state of an artist or album (data-model.md LibraryItem.state). What it
/// wants is what the server counts in `trackCount`.
ItemState containerState(JsonObject record, {required bool downloading}) {
  final statistics = objectIn(record, 'statistics');
  final wanted = optionalNumber(statistics, 'trackCount') ?? 0;
  final present = optionalNumber(statistics, 'trackFileCount') ?? 0;
  return ItemState.resolve(
    downloading: downloading,
    allWantedPresent: wanted > 0 && present >= wanted,
    anyPresent: present > 0,
    monitored: record['monitored'] == true,
    released: wanted > 0,
  );
}

/// The state of a track of [album] at [now]. A track is monitored and released
/// when its album is.
///
/// Downloads are of albums, and the queue does not say which tracks one holds:
/// [albumQueued] counts for the tracks still without a file.
ItemState trackState(
  JsonObject record, {
  required JsonObject album,
  required bool albumQueued,
  required DateTime now,
}) {
  final hasFile = record['hasFile'] == true;
  final released = optionalTime(album, 'releaseDate');
  return ItemState.resolve(
    downloading: albumQueued && !hasFile,
    allWantedPresent: hasFile,
    anyPresent: hasFile,
    monitored: album['monitored'] == true,
    released: released != null && !released.isAfter(now),
  );
}

/// The name of the artist a record of an album embeds.
String? embeddedArtistName(JsonObject album) =>
    optionalText(objectIn(album, 'artist'), 'artistName');

/// A record of `GET artist`.
Artist readArtist(JsonObject record, ItemRef ref, ItemState state) {
  final title = requireText(record, 'artistName');
  return Artist(
    ref: ref,
    title: title,
    sortTitle: optionalText(record, 'sortName') ?? title,
    monitored: record['monitored'] == true,
    state: state,
    overview: optionalText(record, 'overview'),
    images: readImages(record['images']),
    qualityProfileId: optionalPositive(record, 'qualityProfileId'),
    metadataProfileId: optionalPositive(record, 'metadataProfileId'),
    tagIds: {
      if (record['tags'] case final List<Object?> tags)
        ...tags.whereType<int>(),
    },
    path: optionalText(record, 'path'),
    sizeOnDisk: _sizeOnDisk(record),
    addedAt: optionalTime(record, 'added'),
  );
}

/// A record of `GET album`. Albums have no sort title of their own.
Album readAlbum(
  JsonObject record, {
  required ItemRef ref,
  required ItemRef artist,
  required String? artistName,
  required ItemState state,
}) {
  final title = requireText(record, 'title');
  final released = optionalTime(record, 'releaseDate');
  return Album(
    ref: ref,
    title: title,
    sortTitle: title.toLowerCase(),
    monitored: record['monitored'] == true,
    state: state,
    year: released?.year,
    overview: optionalText(record, 'overview'),
    images: readImages(record['images']),
    sizeOnDisk: _sizeOnDisk(record),
    addedAt: optionalTime(record, 'added'),
    parent: artist,
    parentTitle: artistName,
    albumType: optionalText(record, 'albumType'),
    releaseDate: released,
  );
}

/// A record of `GET track`, which has no monitored flag of its own.
Track readTrack(
  JsonObject record, {
  required ItemRef ref,
  required ItemRef album,
  required String? albumTitle,
  required bool monitored,
  required ItemState state,
}) {
  final disc = optionalPositive(record, 'mediumNumber') ?? 1;
  final position = optionalPositive(record, 'absoluteTrackNumber') ?? 0;
  String padded(int number) => '$number'.padLeft(6, '0');
  return Track(
    ref: ref,
    title: optionalText(record, 'title') ?? '',
    // The place on the album.
    sortTitle: '${padded(disc)}x${padded(position)}',
    monitored: monitored,
    state: state,
    parent: album,
    parentTitle: albumTitle,
    trackNumber: optionalText(record, 'trackNumber') ?? '',
    discNumber: disc,
    duration: switch (optionalPositive(record, 'duration')) {
      final milliseconds? => Duration(milliseconds: milliseconds),
      null => null,
    },
    hasFile: record['hasFile'] == true,
  );
}

int _sizeOnDisk(JsonObject record) =>
    optionalNumber(objectIn(record, 'statistics'), 'sizeOnDisk')?.toInt() ?? 0;
