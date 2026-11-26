/// Signing in with a local or a media server account
/// (contracts/upstream-apis.md, sign-in bodies).
library;

import 'package:core/core.dart';

import 'csrf.dart';
import 'refusals.dart';

const _sessionCookie = 'connect.sid';

/// The session handling of Seerr, Overseerr and Jellyseerr.
final class SeerrSessionHandler implements SessionHandler {
  const SeerrSessionHandler();

  @override
  ServiceResult<String> login({
    required AuthKind authKind,
    required Credential credential,
    required ServiceHttpClient http,
  }) async {
    final (path, name) = switch (authKind) {
      AuthKind.userPassword => ('auth/local', 'email'),
      AuthKind.mediaServerAccount => ('auth/jellyfin', 'username'),
      AuthKind.apiKey || AuthKind.none => throw ArgumentError.value(
        authKind,
        'authKind',
        'has no sign-in',
      ),
    };
    final Map<String, String> headers;
    // Public, as there is no session yet.
    switch (await csrfHeaders(http, 'settings/public')) {
      case Ok(:final value):
        headers = value;
      case Err(:final error):
        return Err(error.failure);
    }
    final answer = await http.send(
      ServiceRequest(
        HttpMethod.post,
        'api/v1/$path',
        headers: headers,
        // No host name or server type: those set up a new server.
        body: JsonBody({
          name: credential.username ?? '',
          'password': credential.password ?? '',
        }),
      ),
    );
    switch (answer) {
      case Err(:final error):
        return Err(_classify(error));
      case Ok(:final value):
        // Only the session: a CSRF cookie is fetched anew for every write.
        final session = setCookies(value)[_sessionCookie];
        return session == null
            ? const Err(MalformedResponse())
            : Ok('$_sessionCookie=$session');
    }
  }

  /// A request without a session gets 401, and one with a session the server
  /// does not know gets the 403 of a missing permission. A refused delete or
  /// status change is a 401 too; claiming it keeps the core from taking it for
  /// a rejected account.
  @override
  bool isSessionExpired(ServiceResponse response) =>
      response.statusCode == 401 || isNoPermission(response);

  static ServiceFailure _classify(HttpError error) {
    final response = error.response;
    if (response == null) return error.failure;
    // Refused before the password was looked at.
    if (isCsrfRefusal(response)) return const WritesRefused();
    return switch (response.statusCode) {
      401 || 403 => const AuthFailed(),
      _ => error.failure,
    };
  }
}
