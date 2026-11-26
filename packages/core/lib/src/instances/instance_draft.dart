import 'auth_kind.dart';
import 'instance_link.dart';
import 'probe_snapshot.dart';

/// What the add and edit form saves: the whole editable state of an instance.
final class InstanceDraft {
  /// Creates an [InstanceDraft].
  const InstanceDraft({
    required this.name,
    required this.serviceType,
    required this.url,
    required this.authKind,
    this.acceptedCertPin,
    this.customCa,
    this.probe,
    this.enabled = true,
    this.links = const [],
  });

  /// The user's name for the instance.
  final String name;

  /// The id of a registered module. Cannot differ from the saved one.
  final String serviceType;

  /// http or https, possibly with a sub-path.
  final Uri url;

  /// How the instance authenticates.
  final AuthKind authKind;

  /// A certificate fingerprint newly accepted for [url]. Null keeps the stored
  /// one, unless the scheme, host or port of the url changes.
  final String? acceptedCertPin;

  /// A private certificate authority, PEM, stored as given. Null removes it.
  final String? customCa;

  /// What a successful test of this draft found, or null if there was none.
  final ProbeSnapshot? probe;

  /// Whether the instance contributes content and traffic.
  final bool enabled;

  /// Instances this one is linked to.
  final List<InstanceLink> links;
}
