import 'service_permission.dart';

/// The identity the app is signed in as.
final class SessionInfo {
  const SessionInfo({required this.permissions});

  final Set<ServicePermission> permissions;
}
