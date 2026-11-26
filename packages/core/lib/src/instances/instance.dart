import 'auth_kind.dart';
import 'instance_link.dart';
import 'probe_snapshot.dart';

/// One service entry in one profile. Holds no secrets.
final class Instance {
  /// Creates an [Instance].
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
    this.unsupportedVersion,
    this.authFailed = false,
    this.enabled = true,
    this.sortOrder = 0,
    this.links = const [],
  });

  /// A UUID, never changed.
  final String id;

  /// The profile the instance belongs to.
  final String profileId;

  /// The user's name for the instance.
  final String name;

  /// The id of a registered module, never changed.
  final String serviceType;

  /// http or https, possibly with a sub-path.
  final Uri url;

  /// How the instance authenticates.
  final AuthKind authKind;

  /// Set by a rejected token or login; blocks automatic authenticated requests.
  final bool authFailed;

  /// SHA-256 of an accepted self-signed leaf certificate.
  final String? certPin;

  /// A private certificate authority for this instance, PEM.
  final String? customCa;

  /// A disabled instance contributes no content and no traffic.
  final bool enabled;

  /// Position among the profile's instances.
  final int sortOrder;

  /// From the last successful test.
  final String? detectedVersion;

  /// What the last successful probe found.
  final ProbeSnapshot? lastProbe;

  /// The version of a server that the last probe to find one found too old to
  /// be supported, which blocks the instance: it offers nothing. Empty if the
  /// server named none. Null once a probe succeeds or the url changes.
  final String? unsupportedVersion;

  /// Instances this one is explicitly linked to.
  final List<InstanceLink> links;

  /// UTC.
  final DateTime createdAt;

  /// UTC.
  final DateTime updatedAt;
}
