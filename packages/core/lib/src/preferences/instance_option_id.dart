/// The id of a server option, such as a tag or quality profile, which is only
/// meaningful together with its instance.
final class InstanceOptionId {
  /// Creates an [InstanceOptionId].
  const InstanceOptionId(this.instanceId, this.optionId);

  /// The instance that has the option.
  final String instanceId;

  /// The server's id of the option.
  final int optionId;

  @override
  bool operator ==(Object other) =>
      other is InstanceOptionId &&
      other.instanceId == instanceId &&
      other.optionId == optionId;

  @override
  int get hashCode => Object.hash(instanceId, optionId);
}
