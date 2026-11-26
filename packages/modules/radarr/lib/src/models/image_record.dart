import 'package:core/core.dart';

import 'json_fields.dart';

// A cover's `url` is the web UI's path, under the server's URL base. Titles
// outside the library have `MediaCoverProxy` instead, which no listed read
// serves.
final _cover = RegExp(r'/MediaCover/(\d+)/([\w-]+\.\w+)(?:\?(.*))?$');

// The cache busters of the cover read, which differ by Radarr version.
const _coverParameters = {'h', 'lastWrite'};

/// The `images` of a movie or a credit. One that can be loaded from neither the
/// instance nor a public address is left out.
List<MediaImage> readImages(JsonObject record) => [
  for (final image in objectsIn(record, 'images'))
    if ((_instancePath(image), _remoteUrl(image))
        case (final instancePath, final remoteUrl)
        when instancePath != null || remoteUrl != null)
      MediaImage(
        type:
            MediaImageType.values.asNameMap()[image['coverType']] ??
            MediaImageType.other,
        instancePath: instancePath,
        remoteUrl: remoteUrl,
      ),
];

/// The listed `mediacover` read of the image, if the instance has one.
String? _instancePath(JsonObject image) {
  final match = _cover.firstMatch(optionalText(image, 'url') ?? '');
  if (match == null) return null;
  final query = [
    for (final part in (match[3] ?? '').split('&'))
      if (_coverParameters.contains(part.split('=').first)) part,
  ].join('&');
  final path = 'api/v3/mediacover/${match[1]}/${match[2]}';
  return query.isEmpty ? path : '$path?$query';
}

Uri? _remoteUrl(JsonObject image) {
  final url = Uri.tryParse(optionalText(image, 'remoteUrl') ?? '');
  return url != null && (url.isScheme('http') || url.isScheme('https'))
      ? url
      : null;
}
