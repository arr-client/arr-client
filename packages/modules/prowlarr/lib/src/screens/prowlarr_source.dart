import 'package:core/core.dart';

/// What the screens of one instance read.
///
/// Compared by identity, so one object serves an instance for as long as it is
/// connected: the screens' state is kept under it.
final class ProwlarrSource {
  /// Creates the [ProwlarrSource] of an instance.
  ProwlarrSource({
    required this.instanceId,
    required this.provider,
    required this.logger,
  });

  /// The instance.
  final String instanceId;

  /// Its indexers.
  final IndexerSearchProvider provider;

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
        'A Prowlarr request failed (${error.runtimeType})',
      );
      return Err(otherwise);
    }
  }
}
