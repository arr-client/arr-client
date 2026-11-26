import 'package:core/core.dart';

import 'json_fields.dart';

/// A movie file, as `moviefile` lists it and a movie embeds it.
MediaFile readMediaFile(JsonObject record) {
  final info = switch (record['mediaInfo']) {
    final JsonObject info => info,
    _ => const <String, Object?>{},
  };
  return MediaFile(
    id: requireInt(record, 'id'),
    path: requireText(record, 'path'),
    size: switch (record['size']) {
      final int size => size,
      _ => 0,
    },
    quality: switch (record['quality']) {
      {'quality': {'id': final int id, 'name': final String name}} => Quality(
        id: id,
        name: name,
      ),
      _ => null,
    },
    languages: [
      for (final language in objectsIn(record, 'languages'))
        if (language case {'id': final int id, 'name': final String name})
          Language(id: id, name: name),
    ],
    video: _joined([
      optionalText(info, 'videoCodec'),
      optionalText(info, 'resolution'),
      optionalText(info, 'videoDynamicRange'),
    ]),
    audio: _joined([
      optionalText(info, 'audioCodec'),
      switch (info['audioChannels']) {
        final num channels when channels > 0 => '$channels',
        _ => null,
      },
    ]),
  );
}

String? _joined(List<String?> parts) {
  final text = parts.nonNulls.join(' ');
  return text.isEmpty ? null : text;
}
