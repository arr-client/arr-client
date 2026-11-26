/// Requests to one Seerr, Overseerr or Jellyseerr server, and what their
/// failures mean (contracts/upstream-apis.md).
library;

import 'package:core/core.dart';

import 'csrf.dart';
import 'refusals.dart';

/// Sends the requests of one instance. Paths are relative to `api/v1/`.
final class SeerrApi {
  const SeerrApi(this._context);

  final InstanceContext _context;

  /// `GET api/v1/[path]`.
  Future<Result<ServiceResponse, HttpError>> read(
    String path, {
    Map<String, List<String>> query = const {},
  }) async {
    final answer = await _context.http.send(
      ServiceRequest(HttpMethod.get, 'api/v1/$path', query: query),
    );
    // A web page where data was expected, whatever its content type says.
    if (answer case Ok(:final value) when value.text.startsWith('<')) {
      return Err(HttpError(const ProxyInterception(), response: value));
    }
    return answer;
  }

  /// The JSON object that `GET api/v1/[path]` answers.
  ServiceResult<Map<String, Object?>> readObject(String path) async =>
      switch (await read(path)) {
        Err(:final error) => Err(error.failure),
        Ok(:final value) => switch (jsonObjectOf(value)) {
          final object? => Ok(object),
          null => const Err(MalformedResponse()),
        },
      };

  /// Sends a write once, with the CSRF token if the server wants one. A write
  /// that was refused keeps its response, which may say why.
  ///
  /// The token comes from `auth/me`, which needs a signed-in user, so that a
  /// session that has expired is renewed before the write, which is never
  /// repeated.
  ///
  /// A 401 is how the server refuses to delete a request or change an issue
  /// that is not one's own, so it is [Forbidden] here. Whether it also was a
  /// rejection of the credential is for the core to decide.
  Future<Result<ServiceResponse, HttpError>> write(
    HttpMethod method,
    String path, {
    Object? body,
  }) async {
    final Map<String, String> headers;
    switch (await csrfHeaders(_context.http, 'auth/me')) {
      case Ok(:final value):
        headers = value;
      case Err(:final error):
        return Err(error);
    }
    final answer = await _context.http.send(
      ServiceRequest(
        method,
        'api/v1/$path',
        headers: headers,
        body: body == null ? null : JsonBody(body),
      ),
    );
    if (answer case Err(error: HttpError(:final response?))) {
      if (isCsrfRefusal(response)) {
        return Err(HttpError(const WritesRefused(), response: response));
      }
      if (response.statusCode == 401) {
        return Err(HttpError(const Forbidden(), response: response));
      }
    }
    return answer;
  }
}
