import '../module/service_failure.dart';
import 'service_response.dart';

/// A request that did not succeed.
final class HttpError {
  /// Creates a [HttpError].
  const HttpError(this.failure, {this.response});

  /// The core's classification. A module may refine it from [response].
  final ServiceFailure failure;

  /// Null when no response arrived.
  final ServiceResponse? response;
}
