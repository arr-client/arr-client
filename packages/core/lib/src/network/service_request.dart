import 'http_method.dart';
import 'request_body.dart';

/// A request relative to an instance's address.
final class ServiceRequest {
  /// Throws [ArgumentError] if [path] could leave the instance's address.
  ServiceRequest(
    this.method,
    this.path, {
    this.query = const {},
    this.headers = const {},
    this.body,
    this.timeout,
  }) {
    if (!_staysUnderAddress(path)) {
      // The value is left out of the error, which may be logged.
      throw ArgumentError('Not a relative path', 'path');
    }
  }

  /// The HTTP method.
  final HttpMethod method;

  /// Appended to the instance's address including its sub-path, for example
  /// `api/v3/movie`. Not percent-encoded; no leading `/`, query or fragment.
  final String path;

  /// Names and values are percent-encoded by the client per RFC 3986: a space
  /// is `%20` and every reserved character is escaped. A name may repeat.
  final Map<String, List<String>> query;

  /// Added to those the client sets. A `Cookie` here is sent along with the
  /// session cookie.
  final Map<String, String> headers;

  /// What to send.
  final RequestBody? body;

  /// How long to wait for the answer to a read, and for each pause while
  /// receiving it, instead of the client's own limit. For a read the server
  /// takes long to answer, such as one that has it ask other services. It does
  /// not change how long connecting may take, and a write ignores it.
  final Duration? timeout;

  static bool _staysUnderAddress(String path) {
    final segments = path.split('/');
    return !path.startsWith('/') &&
        !path.contains(RegExp(r'[?#\\]')) &&
        // A colon in the first segment reads as a URL scheme.
        !segments.first.contains(':') &&
        !segments.any((segment) => segment == '.' || segment == '..');
  }
}
