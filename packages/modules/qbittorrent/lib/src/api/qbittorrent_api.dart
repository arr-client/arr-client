/// The reads of qBittorrent's Web API, and what their failures mean
/// (contracts/upstream-apis.md).
library;

import 'package:core/core.dart';

import '../l10n/texts.dart';

/// Sends one instance's reads. Neither `Origin` nor `Referer` is set.
final class QbittorrentApi {
  const QbittorrentApi(this._context);

  final InstanceContext _context;

  /// `app/version`, for example `v5.3.1`.
  ServiceResult<String> appVersion() => _read('app/version');

  /// `torrents/info`: every torrent, as JSON.
  ServiceResult<String> torrents() => _read('torrents/info');

  /// The body of a successful `GET api/v2/[path]`, without surrounding space.
  ServiceResult<String> _read(String path) async {
    final answer = await _context.http.send(
      ServiceRequest(HttpMethod.get, 'api/v2/$path'),
    );
    switch (answer) {
      case Err(:final error):
        return Err(_classify(error));
      case Ok(:final value):
        final text = value.text.trim();
        // A web page where data was expected, whatever its content type says.
        return text.startsWith('<') ? const Err(ProxyInterception()) : Ok(text);
    }
  }

  ServiceFailure _classify(HttpError error) {
    final status = error.response?.statusCode;
    return switch (error.failure) {
      // A refused host name looks the same as a refused credential.
      AuthFailed() when status == 401 => const AuthFailed(
        hint: unauthorizedHint,
      ),
      // How a wrong API key is refused. The core client reports it so itself.
      Forbidden() when _context.instance.authKind == AuthKind.apiKey =>
        const AuthFailed(),
      // Includes a rejected sign-in, which the session reports with no
      // response and with the handler's hint.
      final failure => failure,
    };
  }
}
