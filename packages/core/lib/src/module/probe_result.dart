import '../models/session_info.dart';

/// What a successful probe found.
final class ProbeResult {
  /// Creates a [ProbeResult].
  const ProbeResult({
    required this.product,
    required this.version,
    this.session,
    this.newerThanTested = false,
  });

  /// The server's product, which can differ from the module's name (a fork or
  /// predecessor).
  final String product;

  /// The server's version.
  final String version;

  /// Newer than the tested versions: allowed, with a notice.
  final bool newerThanTested;

  /// The signed-in identity, for services that have one.
  final SessionInfo? session;
}
