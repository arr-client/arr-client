import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:core/core.dart';
import 'package:flutter/foundation.dart';

/// [NetworkConnectivity] read from the device through connectivity_plus.
///
/// It says what the device is connected over, not whether a server can be
/// reached. On Android a network that does not claim to offer internet access
/// is reported as offline, so no request should be refused because of it.
final class DeviceNetworkConnectivity implements NetworkConnectivity {
  DeviceNetworkConnectivity([Connectivity? plugin])
    : _plugin = plugin ?? Connectivity();

  final Connectivity _plugin;

  @override
  Future<NetworkStatus> current() async =>
      _status(await _plugin.checkConnectivity());

  /// A new listener may first be told the network the device already has.
  ///
  /// A move between two networks of the same kind, such as from one Wi-Fi
  /// network to another, is only seen if the device reports something else in
  /// between.
  @override
  Stream<NetworkStatus> get changes => _plugin.onConnectivityChanged
      .map(_status)
      .distinct((a, b) => setEquals(a.transports, b.transports));

  static NetworkStatus _status(List<ConnectivityResult> results) =>
      NetworkStatus(Set.unmodifiable(results.map(_transport).nonNulls));

  static NetworkTransport? _transport(ConnectivityResult result) =>
      switch (result) {
        ConnectivityResult.wifi => NetworkTransport.wifi,
        ConnectivityResult.ethernet => NetworkTransport.ethernet,
        ConnectivityResult.mobile => NetworkTransport.cellular,
        ConnectivityResult.vpn => NetworkTransport.vpn,
        ConnectivityResult.bluetooth ||
        ConnectivityResult.satellite ||
        ConnectivityResult.other => NetworkTransport.other,
        ConnectivityResult.none => null,
      };
}
