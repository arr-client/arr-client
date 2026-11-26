import '../module/service_failure.dart';

/// What is known about reaching an instance (data-model.md Transitions). Not
/// persisted.
sealed class InstanceConnection {
  const InstanceConnection();
}

/// Not checked since the profile was activated, the instance edited or the
/// network changed.
final class ConnectionUnknown extends InstanceConnection {
  /// Creates a [ConnectionUnknown].
  const ConnectionUnknown();
}

/// Being checked.
final class ConnectionProbing extends InstanceConnection {
  /// Creates a [ConnectionProbing].
  const ConnectionProbing();
}

/// The last check succeeded.
final class ConnectionOnline extends InstanceConnection {
  /// Creates a [ConnectionOnline].
  const ConnectionOnline();
}

/// The last check failed.
final class ConnectionOffline extends InstanceConnection {
  /// Creates a [ConnectionOffline].
  const ConnectionOffline(this.failure);

  /// Why.
  final ServiceFailure failure;
}
