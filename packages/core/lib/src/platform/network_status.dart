import 'network_transport.dart';

/// The device's current network.
final class NetworkStatus {
  /// Creates a [NetworkStatus].
  const NetworkStatus(this.transports);

  /// Empty when offline.
  final Set<NetworkTransport> transports;
}
