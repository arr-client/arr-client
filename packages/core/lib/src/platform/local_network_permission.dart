import 'local_network_permission_state.dart';

/// The local network permission, implemented by the app, which decides from
/// the host and the current network whether it applies.
abstract interface class LocalNetworkPermission {
  /// Never prompts, so it is safe in the background and after a timeout.
  Future<LocalNetworkPermissionState> status(String host);

  /// Prompts if the permission is needed and not granted. Foreground only.
  Future<LocalNetworkPermissionState> request(String host);
}
