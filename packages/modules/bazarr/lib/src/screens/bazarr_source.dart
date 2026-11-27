import 'package:core/core.dart';

/// What the screens of one instance read.
///
/// Compared by identity, so one object serves an instance for as long as it is
/// connected: the screens' state is kept under it.
final class BazarrSource {
  /// Creates the [BazarrSource] of an instance.
  BazarrSource({
    required this.instanceId,
    required this.provider,
    required this.logger,
  });

  /// The instance.
  final String instanceId;

  /// Its subtitles.
  final SubtitleProvider provider;

  /// The diagnostic log.
  final Logger logger;

  /// What [request] gives. An error it throws is logged by its type only, as
  /// its text may quote an address or a secret, and is [otherwise].
  ServiceResult<T> guard<T>(
    ServiceResult<T> Function() request, {
    ServiceFailure otherwise = const MalformedResponse(),
  }) async {
    try {
      return await request();
    } catch (error) {
      logger.log(
        LogLevel.error,
        'A Bazarr request failed (${error.runtimeType})',
      );
      return Err(otherwise);
    }
  }
}
