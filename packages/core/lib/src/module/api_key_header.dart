import 'service_failure.dart';

/// How a service expects its API key, so the core client can send it.
final class ApiKeyHeader {
  /// Creates an [ApiKeyHeader].
  const ApiKeyHeader(this.name, {this.prefix = '', this.rejectionStatus});

  /// The header's name, for example `X-Api-Key` or `Authorization`.
  final String name;

  /// Put before the key in the value, for example `Bearer `.
  final String prefix;

  /// A status besides 401 with which the service rejects a wrong key, for
  /// example 403. The core client then reports [AuthFailed], which latches the
  /// instance. Leave it null where the status can also refuse a good key.
  final int? rejectionStatus;
}
