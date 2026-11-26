/// Whether the app asks for device authentication, and when.
final class AppLock {
  /// Creates an [AppLock].
  const AppLock({this.enabled = false, this.delaySeconds = 0});

  /// Whether app lock is on.
  final bool enabled;

  /// How long the app may be away before it locks again; never negative.
  final int delaySeconds;

  @override
  bool operator ==(Object other) =>
      other is AppLock &&
      other.enabled == enabled &&
      other.delaySeconds == delaySeconds;

  @override
  int get hashCode => Object.hash(enabled, delaySeconds);
}
