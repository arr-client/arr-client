import '../models/session_info.dart';
import 'capability.dart';
import 'capability_kind.dart';
import 'instance_context.dart';
import 'module_descriptor.dart';
import 'module_screen.dart';
import 'probe_result.dart';
import 'service_result.dart';
import 'session_handler.dart';

/// One supported service. A module is registered by the app and nowhere else.
abstract interface class ServiceModule {
  /// Stable; used in storage and exports.
  String get id;

  ModuleDescriptor get descriptor;

  /// How to sign in, for a module whose [ModuleDescriptor.authKinds] include a
  /// session-based one; otherwise null.
  SessionHandler? get sessionHandler;

  /// Verifies that the address is this service and reports its version.
  ///
  /// A version below the minimum is an [UnsupportedVersion] failure.
  ServiceResult<ProbeResult> probe(InstanceContext context);

  /// What a server that answered [probe] offers to the identity in [session].
  /// A capability the identity may not use at all is left out.
  Set<CapabilityKind> capabilitiesFor(ProbeResult probe, SessionInfo? session);

  /// The module's implementation of the capability [T] for one instance, or
  /// null if it has none. Must work without a network request, so that cached
  /// screens work offline. [CapabilityKind.of] calls this with the right [T].
  T? capability<T extends Capability>(InstanceContext context);

  /// The screens the module owns, for the app to register with its router.
  List<ModuleScreen> routes();
}
