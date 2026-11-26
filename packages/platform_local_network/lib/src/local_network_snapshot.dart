import 'network_route.dart';

/// What the device says about the local network at one moment.
final class LocalNetworkSnapshot {
  /// A system that enforces the permission.
  const LocalNetworkSnapshot({
    required this.granted,
    required this.lanRoutes,
    this.vpnRoutes = const [],
  }) : enforced = true;

  /// A system older than Android 17, which asks for nothing.
  const LocalNetworkSnapshot.notEnforced()
    : enforced = false,
      granted = true,
      lanRoutes = null,
      vpnRoutes = const [];

  /// Whether the system enforces the permission.
  final bool enforced;

  /// Whether the app may use the local network.
  final bool granted;

  /// The routes of the connected Wi-Fi and Ethernet networks, or null when
  /// there is no such network.
  final List<NetworkRoute>? lanRoutes;

  /// The routes of the VPN this app's traffic uses, empty without one.
  final List<NetworkRoute> vpnRoutes;
}
