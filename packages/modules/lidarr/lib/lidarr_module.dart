/// Lidarr service module for arr-client.
library;

import 'package:core/core.dart';

/// The Lidarr service. Declared for its contract tests (T114); T116 to T118
/// implement it.
final class LidarrModule implements ServiceModule {
  @override
  String get id => throw UnimplementedError('T116');

  @override
  ModuleDescriptor get descriptor => throw UnimplementedError('T116');

  @override
  SessionHandler? get sessionHandler => throw UnimplementedError('T116');

  @override
  ServiceResult<ProbeResult> probe(InstanceContext context) =>
      throw UnimplementedError('T116');

  @override
  Set<CapabilityKind> capabilitiesFor(
    ProbeResult probe,
    SessionInfo? session,
  ) => throw UnimplementedError('T116');

  @override
  T? capability<T extends Capability>(InstanceContext context) =>
      throw UnimplementedError('T116 and T117');

  @override
  List<ModuleScreen> routes() => throw UnimplementedError('T118');
}
