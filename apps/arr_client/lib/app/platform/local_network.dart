import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:platform_local_network/platform_local_network.dart';

/// Resolves a host name, throwing [SocketException] when it cannot.
typedef HostLookup = Future<List<InternetAddress>> Function(String host);

/// [LocalNetworkPermission] for Android (research R6).
///
/// The permission applies from Android 17, with Wi-Fi or Ethernet connected,
/// to a host whose name ends in `.local` or any of whose addresses is on the
/// local network and not carried by a VPN. A name that cannot be resolved needs
/// no permission, so that the connection reports the DNS failure.
///
/// Without the permission a connection typically times out, so call [status]
/// after a timeout, before treating the host as unreachable or falling back.
final class DeviceLocalNetworkPermission implements LocalNetworkPermission {
  DeviceLocalNetworkPermission({
    this._platform = const LocalNetworkPlatform(),
    this._lookup = InternetAddress.lookup,
  });

  final LocalNetworkPlatform _platform;
  final HostLookup _lookup;

  /// [host] is a name or an address without a port; IPv6 may be in brackets.
  @override
  Future<LocalNetworkPermissionState> status(String host) async {
    final snapshot = await _platform.snapshot();
    final lanRoutes = snapshot.lanRoutes;
    if (!snapshot.enforced ||
        lanRoutes == null ||
        !await _isLocal(host, lanRoutes, snapshot.vpnRoutes)) {
      return LocalNetworkPermissionState.notRequired;
    }
    return snapshot.granted
        ? LocalNetworkPermissionState.granted
        : LocalNetworkPermissionState.denied;
  }

  /// Answers [LocalNetworkPermissionState.denied] without a prompt in the
  /// background, and when the system no longer shows one after refusals.
  @override
  Future<LocalNetworkPermissionState> request(String host) async {
    final current = await status(host);
    if (current != LocalNetworkPermissionState.denied) return current;
    return await _platform.requestPermission()
        ? LocalNetworkPermissionState.granted
        : LocalNetworkPermissionState.denied;
  }

  Future<bool> _isLocal(
    String host,
    List<NetworkRoute> lanRoutes,
    List<NetworkRoute> vpnRoutes,
  ) async {
    var name = host.toLowerCase();
    if (name.startsWith('[') && name.endsWith(']')) {
      name = name.substring(1, name.length - 1);
    }
    // The zone of a link-local address does not change what it is. In a name,
    // `%` is an escape and stays.
    if (name.contains(':')) name = name.split('%').first;
    if (name.endsWith('.')) name = name.substring(0, name.length - 1);

    final literal = InternetAddress.tryParse(name);
    // Resolving such a name is itself local network traffic.
    if (literal == null && name.endsWith('.local')) return true;

    final List<InternetAddress> addresses;
    try {
      addresses = literal != null ? [literal] : await _lookup(name);
    } on SocketException {
      return false;
    }
    return addresses.any((address) {
      final bytes = _unmapped(address.rawAddress);
      return _isLocalAddress(bytes, lanRoutes) && !_viaVpn(bytes, vpnRoutes);
    });
  }

  /// The IPv4 address inside an IPv4-mapped IPv6 address, otherwise [bytes].
  static Uint8List _unmapped(Uint8List bytes) =>
      bytes.length == 16 && _samePrefix(bytes, _mappedIpv4, 96)
      ? bytes.sublist(12)
      : bytes;

  static final _mappedIpv4 = InternetAddress('::ffff:0.0.0.0').rawAddress;

  /// The ranges of Android's local network definition.
  static final _localRanges = [
    for (final (address, prefixLength) in const [
      ('10.0.0.0', 8), // private
      ('172.16.0.0', 12), // private
      ('192.168.0.0', 16), // private
      ('169.254.0.0', 16), // link-local
      ('100.64.0.0', 10), // carrier-grade NAT
      ('224.0.0.0', 4), // multicast
      ('255.255.255.255', 32), // broadcast
      ('fe80::', 10), // link-local
      ('ff00::', 8), // multicast
    ])
      NetworkRoute(InternetAddress(address).rawAddress, prefixLength),
  ];

  /// IPv6 has no private ranges in Android's definition: besides link-local and
  /// multicast, what a local network routes more narrowly than by its default
  /// route is local, whether directly connected or in a further subnet.
  static bool _isLocalAddress(Uint8List bytes, List<NetworkRoute> lanRoutes) =>
      _localRanges.any((range) => _covers(range, bytes)) ||
      bytes.length == 16 &&
          lanRoutes.any(
            (route) => route.prefixLength > 0 && _covers(route, bytes),
          );

  /// The most specific VPN route decides, as it does for the system.
  static bool _viaVpn(Uint8List bytes, List<NetworkRoute> vpnRoutes) {
    NetworkRoute? best;
    for (final route in vpnRoutes) {
      if (_covers(route, bytes) &&
          (best == null || route.prefixLength > best.prefixLength)) {
        best = route;
      }
    }
    return best != null && !best.excluded;
  }

  static bool _covers(NetworkRoute route, Uint8List bytes) =>
      route.address.length == bytes.length &&
      _samePrefix(bytes, route.address, route.prefixLength);

  /// Whether the first [bits] bits of two addresses of one family are equal.
  static bool _samePrefix(Uint8List a, Uint8List b, int bits) {
    for (var i = 0; i * 8 < bits; i++) {
      final left = bits - i * 8;
      final mask = left >= 8 ? 0xff : 0xff << (8 - left);
      if ((a[i] ^ b[i]) & mask != 0) return false;
    }
    return true;
  }
}
