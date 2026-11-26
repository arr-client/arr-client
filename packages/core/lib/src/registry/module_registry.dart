import '../instances/probe_snapshot.dart';
import '../module/probe_result.dart';
import '../module/service_module.dart';

/// The modules the app is built with.
final class ModuleRegistry {
  /// Two modules with one id are an [ArgumentError].
  ModuleRegistry(Iterable<ServiceModule> modules) {
    for (final module in modules) {
      if (_modules.containsKey(module.id)) {
        throw ArgumentError.value(module.id, 'modules', 'registered twice');
      }
      _modules[module.id] = module;
    }
  }

  final _modules = <String, ServiceModule>{};

  /// All modules, in the order they were registered.
  Iterable<ServiceModule> get modules => _modules.values;

  /// The module of an `Instance.serviceType`, or null if there is none.
  ServiceModule? operator [](String serviceType) => _modules[serviceType];

  /// What to keep of a successful [probe] by the module of [serviceType]: the
  /// `probe` of an `InstanceDraft` or of `ProfileRepository.recordProbe`.
  /// A [serviceType] that is not registered is an [ArgumentError].
  ProbeSnapshot snapshotOf(String serviceType, ProbeResult probe) {
    final module = _modules[serviceType];
    if (module == null) {
      throw ArgumentError.value(serviceType, 'serviceType', 'not registered');
    }
    return ProbeSnapshot(
      product: probe.product,
      version: probe.version,
      capabilities: module.capabilitiesFor(probe, probe.session),
      permissions: probe.session?.permissions ?? const {},
    );
  }
}
