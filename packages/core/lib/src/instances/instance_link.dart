import 'instance_link_type.dart';

/// An explicit link to another instance of the same profile.
final class InstanceLink {
  const InstanceLink({required this.type, required this.instanceId});

  final InstanceLinkType type;

  /// The instance linked to.
  final String instanceId;
}
