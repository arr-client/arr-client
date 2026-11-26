/// Seerr service module for arr-client.
library;

import 'package:core/core.dart';

/// The Seerr service, and its predecessors Overseerr and Jellyseerr. Declared
/// for its contract tests (T126); T127 and T128 implement it.
final class SeerrModule implements ServiceModule {
  @override
  String get id => throw UnimplementedError('T127');

  @override
  ModuleDescriptor get descriptor => throw UnimplementedError('T127');

  @override
  SessionHandler? get sessionHandler => throw UnimplementedError('T127');

  @override
  ServiceResult<ProbeResult> probe(InstanceContext context) =>
      throw UnimplementedError('T127');

  @override
  Set<CapabilityKind> capabilitiesFor(
    ProbeResult probe,
    SessionInfo? session,
  ) => throw UnimplementedError('T127');

  @override
  T? capability<T extends Capability>(InstanceContext context) =>
      throw UnimplementedError('T128');

  @override
  List<ModuleScreen> routes() => throw UnimplementedError('T129');
}
