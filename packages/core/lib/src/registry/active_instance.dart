import '../instances/instance.dart';
import '../models/service_permission.dart';
import '../module/capability.dart';
import '../module/capability_kind.dart';
import '../module/instance_context.dart';
import '../module/service_module.dart';
import 'instance_connection.dart';

/// An enabled instance of the active profile, as the `InstanceRegistry` has it.
final class ActiveInstance {
  /// Made by the registry. [isCurrent] answers [ActiveInstance.isCurrent].
  ActiveInstance({
    required this.module,
    required this.context,
    required this._isCurrent,
    this.connection = const ConnectionUnknown(),
    Map<CapabilityKind, Capability>? built,
  }) : _built = built ?? {};

  /// The instance's module.
  final ServiceModule module;

  /// What the module works with.
  final InstanceContext context;

  /// What is known about reaching it.
  final InstanceConnection connection;

  final bool Function() _isCurrent;
  final Map<CapabilityKind, Capability> _built;

  /// The instance's record.
  Instance get instance => context.instance;

  /// False once the profile has been switched away from, or the instance has
  /// been edited, disabled or removed. Nothing more is then sent for it, and
  /// what it still answers must not be shown.
  bool get isCurrent => _isCurrent();

  /// What the last successful probe found it offers; nothing before one, nor
  /// while the server's version is too old (`Instance.unsupportedVersion`).
  Set<CapabilityKind> get capabilities => instance.unsupportedVersion != null
      ? const {}
      : instance.lastProbe?.capabilities ?? const {};

  /// What the signed-in identity may do, as of that probe.
  Set<ServicePermission> get permissions =>
      instance.lastProbe?.permissions ?? const {};

  /// The module's implementation of [kind], or null if the instance does not
  /// offer it. Needs no network.
  T? capability<T extends Capability>(CapabilityKind<T> kind) {
    if (!capabilities.contains(kind)) return null;
    final known = _built[kind];
    if (known != null) return known as T;
    final made = kind.of(module, context);
    if (made != null) _built[kind] = made;
    return made;
  }

  /// The same instance with another [connection].
  ActiveInstance withConnection(InstanceConnection connection) =>
      ActiveInstance(
        module: module,
        context: context,
        isCurrent: _isCurrent,
        connection: connection,
        built: _built,
      );
}
