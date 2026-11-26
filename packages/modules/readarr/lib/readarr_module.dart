/// Readarr service module for arr-client, also for its fork Bookshelf.
library;

import 'package:core/core.dart';

/// The Readarr service. Not implemented yet: T119 to T121 replace every
/// member, and the contract tests say what T119 and T120 are to make of them.
final class ReadarrModule implements ServiceModule {
  @override
  String get id => throw UnimplementedError('T119');

  @override
  ModuleDescriptor get descriptor => throw UnimplementedError('T119');

  @override
  SessionHandler? get sessionHandler => throw UnimplementedError('T119');

  @override
  ServiceResult<ProbeResult> probe(InstanceContext context) =>
      throw UnimplementedError('T119');

  @override
  Set<CapabilityKind> capabilitiesFor(
    ProbeResult probe,
    SessionInfo? session,
  ) => throw UnimplementedError('T119');

  @override
  T? capability<T extends Capability>(InstanceContext context) =>
      throw UnimplementedError('T119');

  @override
  List<ModuleScreen> routes() => throw UnimplementedError('T121');
}
