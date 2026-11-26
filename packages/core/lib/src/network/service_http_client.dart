import '../module/result.dart';
import 'http_error.dart';
import 'service_request.dart';
import 'service_response.dart';

/// The only way a module talks to its server. Implemented by the core.
///
/// Requests go to the instance's address and nowhere else, and redirects to
/// another origin are not followed. A write is never retried.
abstract interface class ServiceHttpClient {
  /// A success status is [Ok]. Anything else is [Err], classified, with the
  /// response when the server sent one. Does not throw for transport problems.
  Future<Result<ServiceResponse, HttpError>> send(ServiceRequest request);
}
