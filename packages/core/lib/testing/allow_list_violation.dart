import '../src/network/service_request.dart';

/// A module made a request its allow-list does not permit.
///
/// An [Error], so that an `on Exception` clause does not catch it.
final class AllowListViolation extends Error {
  /// Creates an [AllowListViolation].
  AllowListViolation(this.request);

  /// What was refused.
  final ServiceRequest request;

  /// Names the request without any value of its query, headers or body.
  @override
  String toString() =>
      'Request not in the allow-list: ${request.method.name.toUpperCase()} '
      '"${request.path}", query parameters ${request.query.keys.toList()}, '
      'headers ${request.headers.keys.toList()}, '
      'body ${request.body.runtimeType}';
}
