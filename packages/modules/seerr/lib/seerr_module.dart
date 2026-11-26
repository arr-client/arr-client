/// Seerr service module for arr-client, which also serves its predecessors
/// Overseerr and Jellyseerr.
library;

import 'package:core/core.dart';
import 'package:flutter/widgets.dart';

import 'src/api/probe.dart';
import 'src/api/refusals.dart';
import 'src/api/session_handler.dart';

const _product = 'Seerr';

const _descriptor = ModuleDescriptor(
  displayName: _product,
  // Material's `add_to_queue`; widgets.dart has no named icons.
  icon: IconData(0xe05f, fontFamily: 'MaterialIcons'),
  category: ModuleCategory.requests,
  authKinds: [
    AuthKind.userPassword,
    AuthKind.mediaServerAccount,
    AuthKind.apiKey,
  ],
  // A wrong key gets the 403 of a missing permission, and a refused delete a
  // 401, so the core asks `auth/me`, which needs only a good key.
  apiKeyHeader: ApiKeyHeader(
    'X-Api-Key',
    check: ApiKeyCheck(path: 'api/v1/auth/me', refuses: isNoPermission),
  ),
  defaultPort: 5055,
  minimumVersion: '3.0',
  testedVersion: '3.5.2',
);

/// The Seerr service. The adapters are yet to come (T128), and the screens
/// (T129).
final class SeerrModule implements ServiceModule {
  @override
  String get id => 'seerr';

  @override
  ModuleDescriptor get descriptor => _descriptor;

  @override
  SessionHandler? get sessionHandler => const SeerrSessionHandler();

  @override
  ServiceResult<ProbeResult> probe(InstanceContext context) => probeSeerr(
    context,
    product: _product,
    minimumVersion: _descriptor.minimumVersion,
    testedVersion: _descriptor.testedVersion,
  );

  // Every supported version and identity may browse and see requests; what else
  // it may do is in the session's permissions.
  @override
  Set<CapabilityKind> capabilitiesFor(
    ProbeResult probe,
    SessionInfo? session,
  ) => const {CapabilityKind.discovery, CapabilityKind.request};

  @override
  T? capability<T extends Capability>(InstanceContext context) =>
      throw UnimplementedError('T128');

  @override
  List<ModuleScreen> routes() => throw UnimplementedError('T129');
}
