import '../network/service_response.dart';
import 'service_failure.dart';

/// How a service expects its API key, so the core client can send it.
final class ApiKeyHeader {
  /// Creates an [ApiKeyHeader].
  const ApiKeyHeader(
    this.name, {
    this.prefix = '',
    this.rejectionStatus,
    this.check,
  });

  /// The header's name, for example `X-Api-Key` or `Authorization`.
  final String name;

  /// Put before the key in the value, for example `Bearer `.
  final String prefix;

  /// A status besides 401 with which the service rejects a wrong key, for
  /// example 403. The core client then reports [AuthFailed], which latches the
  /// instance. Leave it null where the status can also refuse a good key.
  final int? rejectionStatus;

  /// For a service whose answer to a wrong key does not by itself say that the
  /// key is wrong.
  final ApiKeyCheck? check;
}

/// How the core client finds out whether a service rejected the API key.
///
/// A 401, or a refusal that [refuses] recognises, is then no verdict on its own:
/// the client reads [path] with the same key. If that answers with either, the
/// request fails with [AuthFailed], which latches the instance. Otherwise,
/// including when [path] cannot be read, it fails with [Forbidden]. Both keep
/// the request's own response.
final class ApiKeyCheck {
  /// Creates an [ApiKeyCheck].
  const ApiKeyCheck({required this.path, required this.refuses});

  /// A read that every accepted key may make, relative to the instance's
  /// address, as in `ServiceRequest.path`.
  final String path;

  /// Whether [response] is how the service refuses a wrong key other than with
  /// a 401. It may refuse a good key the same way.
  final bool Function(ServiceResponse response) refuses;
}
