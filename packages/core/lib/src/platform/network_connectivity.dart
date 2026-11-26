import 'network_status.dart';

/// Connectivity, implemented by the app.
abstract interface class NetworkConnectivity {
  Future<NetworkStatus> current();

  /// Emits when the network changes.
  Stream<NetworkStatus> get changes;
}
