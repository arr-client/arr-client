import '../models/service_permission.dart';
import '../module/capability_kind.dart';

/// What the last successful probe found, kept so navigation works offline.
final class ProbeSnapshot {
  const ProbeSnapshot({
    required this.product,
    required this.version,
    required this.capabilities,
    this.permissions = const {},
  });

  final String product;

  final String version;

  final Set<CapabilityKind> capabilities;

  final Set<ServicePermission> permissions;
}
