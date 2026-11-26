/// Recognising Seerr, Overseerr and Jellyseerr, their versions and the
/// signed-in identity.
library;

import 'package:core/core.dart';

import 'permissions.dart';
import 'refusals.dart';
import 'seerr_api.dart';

// As in "3.5.2". Few enough digits per part for `int.parse`.
final _release = RegExp(r'^(\d{1,9}(?:\.\d{1,9}){2})(?:[-+][0-9A-Za-z.+-]*)?$');

// A build of the development branch is named after its commit, not a version.
final _development = RegExp(r'^develop-[0-9a-f]{7,40}$');

/// A product, told apart by the major version it uses.
typedef _Product = ({String name, String minimum, String tested});

const _Product _overseerr = (
  name: 'Overseerr',
  minimum: '1.34',
  tested: '1.35.0',
);
const _Product _jellyseerr = (
  name: 'Jellyseerr',
  minimum: '2.0',
  tested: '2.7.3',
);

/// The numbers of a released [version], and null of anything else, such as a
/// development build.
String? releaseNumbers(String version) => _release.firstMatch(version)?[1];

/// Reads the version, the identity and the settings that bound what it may do.
/// Nothing is written.
///
/// A development build is accepted as newer than tested. Its version does not
/// say which product it is: Overseerr's settings have no media server type, and
/// anything else is taken for Seerr.
ServiceResult<ProbeResult> probeSeerr(
  InstanceContext context, {
  required String product,
  required String minimumVersion,
  required String testedVersion,
}) async {
  final api = SeerrApi(context);

  // Public: it says nothing about the credential.
  final String version;
  switch (await api.read('status')) {
    case Err(error: HttpError(failure: NotFound())):
      return const Err(WrongService());
    case Err(:final error):
      return Err(error.failure);
    case Ok(:final value):
      final found = jsonObjectOf(value)?['version'];
      if (found is! String) return const Err(WrongService());
      version = found;
  }

  final numbers = releaseNumbers(version);
  if (numbers == null && !_development.hasMatch(version)) {
    return const Err(WrongService());
  }
  var detected = (
    name: product,
    minimum: minimumVersion,
    tested: testedVersion,
  );
  var newer = true;
  if (numbers != null) {
    detected = switch (int.parse(numbers.split('.').first)) {
      // Nothing older is known, so the oldest minimum turns it away.
      0 || 1 => _overseerr,
      2 => _jellyseerr,
      _ => detected,
    };
    if (compareVersions(numbers, detected.minimum) < 0) {
      return Err(UnsupportedVersion(version: version));
    }
    newer = compareVersions(numbers, detected.tested) > 0;
  }

  // Needs no permission, so a refusal of an account's session is of the account.
  // The core already reports a rejected API key as such: a refusal left over is
  // something else's, such as a firewall's, and says nothing about the key.
  // Only the core latches the instance, by the rules of the descriptor and the
  // session.
  final Map<String, Object?> me;
  switch (await api.readObject('auth/me')) {
    case Err(error: Forbidden())
        when context.instance.authKind != AuthKind.apiKey:
      return const Err(AuthFailed());
    case Err(:final error):
      return Err(error);
    case Ok(:final value):
      me = value;
  }
  final bits = me['permissions'];
  if (bits is! int) return const Err(MalformedResponse());

  final Map<String, Object?> settings;
  switch (await api.readObject('settings/public')) {
    case Err(:final error):
      return Err(error);
    case Ok(:final value):
      settings = value;
  }
  if (numbers == null && !settings.containsKey('mediaServerType')) {
    detected = _overseerr;
  }

  return Ok(
    ProbeResult(
      product: detected.name,
      version: version,
      newerThanTested: newer,
      session: SessionInfo(
        permissions: permissionsOf(
          bits,
          movie4k: settings['movie4kEnabled'] == true,
          series4k: settings['series4kEnabled'] == true,
        ),
      ),
    ),
  );
}

/// Compares dotted versions part by part as numbers; a missing part is zero.
int compareVersions(String a, String b) {
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
