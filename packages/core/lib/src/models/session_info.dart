import 'service_permission.dart';

/// The identity the app is signed in as.
final class SessionInfo {
  /// Creates a [SessionInfo].
  const SessionInfo({required this.permissions});

  /// What the identity may do.
  final Set<ServicePermission> permissions;
}
