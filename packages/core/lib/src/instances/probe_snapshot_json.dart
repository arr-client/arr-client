/// The `lastProbe` column. Reading ignores unknown names.
library;

import 'dart:convert';

import '../models/service_permission.dart';
import '../module/capability_kind.dart';
import 'probe_snapshot.dart';

/// Writes the column.
String encodeProbeSnapshot(ProbeSnapshot probe) => jsonEncode({
  'product': probe.product,
  'version': probe.version,
  'capabilities': [for (final kind in probe.capabilities) kind.name],
  'permissions': [for (final permission in probe.permissions) permission.name],
});

/// Reads the column. Null if it is not a probe.
ProbeSnapshot? decodeProbeSnapshot(String text) {
  if (jsonDecode(text) case {
    'product': final String product,
    'version': final String version,
    'capabilities': final List<Object?> capabilities,
    'permissions': final List<Object?> permissions,
  }) {
    final kinds = CapabilityKind.values.asNameMap();
    final known = ServicePermission.values.asNameMap();
    return ProbeSnapshot(
      product: product,
      version: version,
      capabilities: {for (final name in capabilities) ?kinds[name]},
      permissions: {for (final name in permissions) ?known[name]},
    );
  }
  return null;
}
