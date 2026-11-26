import 'dart:convert';

import 'package:core/core.dart';

import '../api/bazarr_api.dart';

/// The oldest supported version.
const minimumVersion = '1.5';

/// The newest tested version.
const testedVersion = '1.6.2';

// Numbers with dots, at most nine digits each so that they fit an int, and
// possibly a suffix such as `-beta.3`.
final _versionPattern = RegExp(r'^(\d{1,9}(?:\.\d{1,9})+)(?:-[0-9A-Za-z.]+)?$');

/// Verifies that the address is Bazarr, by its system status.
ServiceResult<ProbeResult> probeBazarr(ServiceHttpClient http) async {
  final answer = await http.send(
    ServiceRequest(HttpMethod.get, 'api/system/status'),
  );
  return switch (answer) {
    Ok(:final value) => _readStatus(value.text),
    // Every supported Bazarr has the path, so this is something else.
    Err(:final error) when error.failure is NotFound => const Err(
      WrongService(),
    ),
    Err(:final error) => Err(error.failure),
  };
}

Result<ProbeResult, ServiceFailure> _readStatus(String text) {
  if (isWebPage(text)) return const Err(ProxyInterception());

  final Object? body;
  try {
    body = jsonDecode(text);
  } on FormatException {
    return const Err(MalformedResponse());
  }
  // No other service of the family names a version of Bazarr.
  final status = body is JsonObject ? body['data'] : null;
  if (status is! JsonObject || !status.containsKey('bazarr_version')) {
    return const Err(WrongService());
  }

  final version = status['bazarr_version'];
  final numbers = version is String
      ? _versionPattern.firstMatch(version)?.group(1)
      : null;
  if (version is! String || numbers == null) {
    return const Err(MalformedResponse());
  }
  if (_compareVersions(numbers, minimumVersion) < 0) {
    return Err(UnsupportedVersion(version: version));
  }
  return Ok(
    ProbeResult(
      product: 'Bazarr',
      version: version,
      newerThanTested: _compareVersions(numbers, testedVersion) > 0,
    ),
  );
}

/// Compares dotted versions number by number; a missing number is zero.
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
