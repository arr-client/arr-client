/// Every request the qBittorrent module may make (FR-019, FR-031), from
/// specs/001-arr-companion-app/contracts/upstream-apis.md. Adapter tests run
/// through it.
///
/// A download client is never written to: there are reads and the login, and
/// nothing else. The app does not sign out, so `auth/logout` is not here.
library;

import 'package:core/core.dart';
import 'package:core/testing/allow_list.dart';

const _required = ParamRule.any(required: true);

/// The qBittorrent allow-list.
final allowList = AllowList([
  AllowedRequest.read('api/v2/app/version'),
  AllowedRequest.read('api/v2/app/webapiVersion'),
  // Every torrent: matching is done on the device.
  AllowedRequest.read('api/v2/torrents/info'),
  AllowedRequest.authentication(
    HttpMethod.post,
    'api/v2/auth/login',
    body: const BodyRule.form({'username': _required, 'password': _required}),
  ),
]);
