/// The parts of series and episode records that describe artwork and files.
library;

import 'package:core/core.dart';

import 'json_fields.dart';

// The web UI's address of a stored cover, which may be under a URL base.
final _coverPath = RegExp(
  r'^(?:/[^?#]*)?/MediaCover/(\d+)/([\w-]+\.\w+)(\?[^#]*)?$',
);

/// The `images` of a record.
List<MediaImage> readImages(Object? json) => [
  if (json is List<Object?>)
    for (final image in json.whereType<JsonObject>()) ?_image(image),
];

/// A stored cover is read through the API, which takes the key; the address
/// the server gives is behind the web UI's sign-in.
MediaImage? _image(JsonObject record) {
  final cover = _coverPath.firstMatch(optionalText(record, 'url') ?? '');
  final instancePath = cover == null
      ? null
      : 'api/v3/mediacover/${cover[1]}/${cover[2]}${cover[3] ?? ''}';
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

/// An episode file.
MediaFile readFile(JsonObject record) {
  final media = switch (record['mediaInfo']) {
    final JsonObject media => media,
    _ => const <String, Object?>{},
  };
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
    languages: [
      if (record['languages'] case final List<Object?> languages)
        for (final language in languages)
          if (language case {'id': final int id, 'name': final String name})
            Language(id: id, name: name),
    ],
    video: _words([
      optionalText(media, 'videoCodec'),
      optionalText(media, 'resolution'),
    ]),
    audio: _words([
      optionalText(media, 'audioCodec'),
      // As channel layouts are written: 2.0, 5.1.
      switch (optionalNumber(media, 'audioChannels')) {
        final channels? when channels > 0 => '${channels.toDouble()}',
        _ => null,
      },
    ]),
  );
}

String? _words(List<String?> words) {
  final text = words.nonNulls.where((word) => word.isNotEmpty).join(' ');
  return text.isEmpty ? null : text;
}
