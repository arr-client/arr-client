import 'package:core/core.dart';

import '../adapters/seasons.dart';

/// What the screens of one instance read and send.
///
/// Compared by identity, so one object serves an instance for as long as it is
/// connected: the screens' state is kept under it.
final class SeerrSource {
  /// Creates the [SeerrSource] of an instance.
  SeerrSource({
    required this.instanceId,
    required this.discovery,
    required this.requests,
    required this.seasons,
    required this.artwork,
    required this.logger,
  });

  /// The instance.
  final String instanceId;

  /// Its titles.
  final DiscoveryProvider discovery;

  /// Its requests.
  final RequestProvider requests;

  /// The seasons of its series.
  final SeerrSeasonAdapter seasons;

  /// Loads its posters.
  final ArtworkLoader artwork;

  /// The diagnostic log.
  final Logger logger;

  /// What [read] gives. An error it throws is logged by its type only, as its
  /// text may quote an address or a secret, and is [otherwise].
  ServiceResult<T> guard<T>(
    ServiceResult<T> Function() read, {
    ServiceFailure otherwise = const MalformedResponse(),
  }) async {
    try {
      return await read();
    } catch (error) {
      logger.log(
        LogLevel.error,
        'A request service call failed (${error.runtimeType})',
      );
      return Err(otherwise);
    }
  }
}
