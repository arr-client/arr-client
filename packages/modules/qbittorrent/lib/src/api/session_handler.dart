/// Signing in with a user name and password (contracts/upstream-apis.md, login
/// responses by version).
library;

import 'package:core/core.dart';

import '../l10n/texts.dart';

/// The session handling of qBittorrent.
///
/// Every refusal of a sign-in is an [AuthFailed], which latches the instance:
/// another attempt counts towards an address ban.
final class QbittorrentSessionHandler implements SessionHandler {
  const QbittorrentSessionHandler();

  @override
  ServiceResult<String> login({
    required AuthKind authKind,
    required Credential credential,
    required ServiceHttpClient http,
  }) async {
    final answer = await http.send(
      ServiceRequest(
        HttpMethod.post,
        'api/v2/auth/login',
        body: FormBody({
          'username': credential.username ?? '',
          'password': credential.password ?? '',
        }),
      ),
    );
    return switch (answer) {
      Ok(:final value) => _read(value),
      Err(:final error) => Err(_classify(error)),
    };
  }

  /// A session qBittorrent does not know is a 403 on every version. A 401 is
  /// about the host name or a proxy, which signing in again does not mend.
  @override
  bool isSessionExpired(ServiceResponse response) => response.statusCode == 403;

  // The version is not known here, and every version refuses a host name with
  // the 401 that 5.2 and later also answer a wrong password with.
  static ServiceFailure _classify(HttpError error) =>
      switch (error.response?.statusCode) {
        401 => const AuthFailed(hint: unauthorizedHint),
        // A banned address.
        403 => const AuthFailed(hint: signInRefusedHint),
        _ => error.failure,
      };

  static Result<String, ServiceFailure> _read(ServiceResponse response) {
    final text = response.text.trim();
    if (text.startsWith('<')) return const Err(ProxyInterception());
    // How versions before 5.2 refuse a wrong user name or password.
    if (text == 'Fails.') return const Err(AuthFailed());
    // 'Ok.' before 5.2; 204 without a body from then on.
    final accepted =
        text == 'Ok.' || (response.statusCode == 204 && text.isEmpty);
    if (!accepted) return const Err(WrongService());

    // The cookie's name differs by version and can be configured, so every
    // cookie is kept, including any that a proxy added.
    final cookies = [
      for (final header in response.headers['set-cookie'] ?? const <String>[])
        header.split(';').first.trim(),
    ].where(_hasNameAndValue).join('; ');
    // Not a rejection of the account, so it must not latch the instance.
    return cookies.isEmpty ? const Err(MalformedResponse()) : Ok(cookies);
  }

  static bool _hasNameAndValue(String cookie) {
    final separator = cookie.indexOf('=');
    return separator > 0 && separator < cookie.length - 1;
  }
}
