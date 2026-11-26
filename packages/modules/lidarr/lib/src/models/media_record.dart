/// The parts of records that describe artwork and files.
library;

import 'package:core/core.dart';

import 'json_fields.dart';

// The web UI's address of a stored cover, which may be under a URL base.
// Without `Albums/` it is an artist's.
final _coverPath = RegExp(
  r'^(?:/[^?#]*)?/MediaCover/(Albums/)?(\d+)/([\w-]+\.\w+)(\?[^#]*)?$',
);

/// The `images` of a record.
List<MediaImage> readImages(Object? json) => [
  if (json is List<Object?>)
    for (final image in json.whereType<JsonObject>()) ?_image(image),
];

/// A stored cover is read through the API, which takes the key; the address
/// the server gives is behind the web UI's sign-in.
///
/// `remoteUrl` of a library artist is a path on the server's disk, so only a
/// web address is taken from it.
MediaImage? _image(JsonObject record) {
  final cover = _coverPath.firstMatch(optionalText(record, 'url') ?? '');
  final instancePath = cover == null
      ? null
      : 'api/v1/mediacover/${cover[1] == null ? 'artist' : 'album'}'
            '/${cover[2]}/${cover[3]}${cover[4] ?? ''}';
  final remote = Uri.tryParse(optionalText(record, 'remoteUrl') ?? '');
  final remoteUrl =
      remote != null && (remote.isScheme('http') || remote.isScheme('https'))
      ? remote
      : null;
  if (instancePath == null && remoteUrl == null) return null;
  return MediaImage(
    type:
        MediaImageType.values.asNameMap()[record['coverType']] ??
        MediaImageType.other,
    instancePath: instancePath,
    remoteUrl: remoteUrl,
  );
}

/// A track file.
MediaFile readFile(JsonObject record) {
  final media = objectIn(record, 'mediaInfo');
  final audio = [
    ?optionalText(media, 'audioCodec'),
    // As channel layouts are written: 2.0, 5.1.
    if (optionalNumber(media, 'audioChannels') case final channels?
        when channels > 0)
      '${channels.toDouble()}',
  ].join(' ');
  return MediaFile(
    id: requireInt(record, 'id'),
    path: requireText(record, 'path'),
    size: optionalNumber(record, 'size')?.toInt() ?? 0,
    quality: switch (record['quality']) {
      {'quality': {'id': final int id, 'name': final String name}} => Quality(
        id: id,
        name: name,
      ),
      _ => null,
    },
    audio: audio.isEmpty ? null : audio,
  );
}
