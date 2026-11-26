/// Bazarr service module for arr-client.
library;

import 'package:core/core.dart';

/// The Bazarr service. Declared for its contract tests (T135); T136 and T137
/// implement it.
final class BazarrModule implements ServiceModule {
  @override
  String get id => throw UnimplementedError('T136');

  @override
  ModuleDescriptor get descriptor => throw UnimplementedError('T136');

  @override
  SessionHandler? get sessionHandler => throw UnimplementedError('T136');

  @override
  ServiceResult<ProbeResult> probe(InstanceContext context) =>
      throw UnimplementedError('T136');

  @override
  Set<CapabilityKind> capabilitiesFor(
    ProbeResult probe,
    SessionInfo? session,
  ) => throw UnimplementedError('T136');

  @override
  T? capability<T extends Capability>(InstanceContext context) =>
      throw UnimplementedError('T136');

  @override
  List<ModuleScreen> routes() => throw UnimplementedError('T137');
}
