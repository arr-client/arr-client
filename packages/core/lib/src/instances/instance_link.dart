import 'instance_link_type.dart';

/// An explicit link to another instance of the same profile.
final class InstanceLink {
  /// Creates an [InstanceLink].
  const InstanceLink({required this.type, required this.instanceId});

  /// What the link means.
  final InstanceLinkType type;

  /// The instance linked to.
  final String instanceId;
}
