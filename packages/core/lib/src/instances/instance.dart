import 'auth_kind.dart';
import 'instance_link.dart';
import 'probe_snapshot.dart';

/// One service entry in one profile. Holds no secrets.
final class Instance {
  const Instance({
    required this.id,
    required this.profileId,
    required this.name,
    required this.serviceType,
    required this.url,
    required this.authKind,
    required this.createdAt,
    required this.updatedAt,
    this.certPin,
    this.customCa,
    this.detectedVersion,
    this.lastProbe,
    this.authFailed = false,
    this.enabled = true,
    this.sortOrder = 0,
    this.links = const [],
  });

  /// A UUID, never changed.
  final String id;

  final String profileId;

  final String name;

  /// The id of a registered module, never changed.
  final String serviceType;

  /// http or https, possibly with a sub-path.
  final Uri url;

  final AuthKind authKind;

  /// Set by a rejected token or login; blocks automatic authenticated requests.
  final bool authFailed;

  /// SHA-256 of an accepted self-signed leaf certificate.
  final String? certPin;

  /// A private certificate authority for this instance, PEM.
  final String? customCa;

  final bool enabled;

  final int sortOrder;

  /// From the last successful test.
  final String? detectedVersion;

  final ProbeSnapshot? lastProbe;

  final List<InstanceLink> links;

  /// UTC.
  final DateTime createdAt;

  /// UTC.
  final DateTime updatedAt;
}
