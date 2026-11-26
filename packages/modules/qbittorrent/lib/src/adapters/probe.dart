/// Recognising a qBittorrent server and its version.
library;

import 'package:core/core.dart';

import '../api/qbittorrent_api.dart';

// As in "v5.3.1", "v4.4.3.1" and "v5.0.0rc1". Few enough digits per part for
// `int.parse`.
final _versionPattern = RegExp(
  r'^v(\d{1,9}(?:\.\d{1,9}){1,3})((?:alpha|beta|rc)\d*)?$',
);

/// Reads the version, which only a qBittorrent server answers in this form.
ServiceResult<ProbeResult> probeQbittorrent(
  InstanceContext context, {
  required String product,
  required String minimumVersion,
  required String testedVersion,
}) async {
  final String text;
  switch (await QbittorrentApi(context).appVersion()) {
    case Ok(:final value):
      text = value;
    case Err(error: NotFound()):
      return const Err(WrongService());
    case Err(:final error):
      return Err(error);
  }

  final match = _versionPattern.firstMatch(text);
  if (match == null) return const Err(WrongService());
  final numbers = match[1]!;
  final version = '$numbers${match[2] ?? ''}';
  if (_compareVersions(numbers, minimumVersion) < 0) {
    return Err(UnsupportedVersion(version: version));
  }
  return Ok(
    ProbeResult(
      product: product,
      version: version,
      newerThanTested: _compareVersions(numbers, testedVersion) > 0,
    ),
  );
}

/// Compares dotted versions part by part as numbers; a missing part is zero.
int _compareVersions(String a, String b) {
  final left = a.split('.').map(int.parse).toList();
  final right = b.split('.').map(int.parse).toList();
  for (var i = 0; i < left.length || i < right.length; i++) {
    final order = (i < left.length ? left[i] : 0).compareTo(
      i < right.length ? right[i] : 0,
    );
    if (order != 0) return order;
  }
  return 0;
}
