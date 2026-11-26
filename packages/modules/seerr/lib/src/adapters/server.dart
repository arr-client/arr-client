/// Where the products and their versions differ in what they answer
/// (data-model DiscoveryTitle, research R10).
library;

import 'package:core/core.dart';

import '../api/probe.dart';

/// The product and version of one instance, as last probed.
final class SeerrServer {
  const SeerrServer._(this._product, this._numbers);

  /// Without a [probe], the newest Seerr. A development build has no version
  /// number, and counts as newer than every release.
  factory SeerrServer.of(ProbeSnapshot? probe) => SeerrServer._(
    probe?.product ?? 'Seerr',
    probe == null ? null : releaseNumbers(probe.version),
  );

  final String _product;

  // Null for the newest.
  final String? _numbers;

  bool _since(String version) {
    final numbers = _numbers;
    return numbers == null || compareVersions(numbers, version) >= 0;
  }

  // Seerr, and Jellyseerr from 2.6.0, name the source of a proxied image and
  // know of deleted titles by the number 7.
  bool get _recent => switch (_product) {
    'Overseerr' => false,
    'Jellyseerr' => _since('2.6.0'),
    _ => true,
  };

  /// Where the instance serves the poster [path] from its image cache.
  String proxiedPoster(String size, String path) =>
      'imageproxy/${_recent ? 'tmdb/' : ''}t/p/$size$path';

  /// The availability that [number] stands for. From 6 on, it depends on the
  /// product.
  Availability availability(Object? number) => switch (number) {
    2 => Availability.pending,
    3 => Availability.processing,
    4 => Availability.partial,
    5 => Availability.available,
    6 when _product != 'Overseerr' => Availability.blocklisted,
    // Overseerr has no blocklist, and 1.34 stops at 5.
    6 when _since('1.35.0') => Availability.deleted,
    7 when _recent => Availability.deleted,
    _ => Availability.unknown,
  };
}
