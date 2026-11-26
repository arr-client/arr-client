import '../models/service_permission.dart';
import '../module/capability_kind.dart';

/// What the last successful probe found, kept so navigation works offline.
final class ProbeSnapshot {
  /// Creates a [ProbeSnapshot].
  const ProbeSnapshot({
    required this.product,
    required this.version,
    required this.capabilities,
    this.permissions = const {},
  });

  /// The server's product.
  final String product;

  /// The server's version.
  final String version;

  /// What the instance offered to the signed-in identity.
  final Set<CapabilityKind> capabilities;

  /// What that identity was permitted to do.
  final Set<ServicePermission> permissions;
}
