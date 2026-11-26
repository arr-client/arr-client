import 'dart:typed_data';

/// The destinations covered by one route of a network.
final class NetworkRoute {
  /// Creates a [NetworkRoute].
  const NetworkRoute(this.address, this.prefixLength, {this.excluded = false});

  /// The destination in network byte order: 4 bytes for IPv4, 16 for IPv6.
  final Uint8List address;

  /// How many leading bits of [address] a destination must share.
  final int prefixLength;

  /// Whether a VPN leaves these destinations out of its tunnel.
  final bool excluded;
}
