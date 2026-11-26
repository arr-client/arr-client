import 'dart:async';

import '../src/module/result.dart';
import '../src/network/http_error.dart';
import '../src/network/service_http_client.dart';
import '../src/network/service_request.dart';
import '../src/network/service_response.dart';
import 'allow_list.dart';

/// Passes on to another client only what an [AllowList] permits.
///
/// A refused request never reaches that client. It fails the running test even
/// if the code under test catches what [send] throws: the violation is also
/// reported as an uncaught error to the zone this client was created in. Create
/// it inside `setUp` or the test.
final class AllowListClient implements ServiceHttpClient {
  /// Creates an [AllowListClient] in front of, usually, a fake.
  AllowListClient(this.allowList, this._inner) : _zone = Zone.current;

  /// What may be sent.
  final AllowList allowList;

  final ServiceHttpClient _inner;
  final Zone _zone;

  @override
  Future<Result<ServiceResponse, HttpError>> send(
    ServiceRequest request,
  ) async {
    if (!allowList.permits(request)) {
      final violation = AllowListViolation(request);
      _zone.handleUncaughtError(violation, StackTrace.current);
      throw violation;
    }
    return _inner.send(request);
  }
}
