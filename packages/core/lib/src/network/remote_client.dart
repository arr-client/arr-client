/// The HTTP client of public hosts, which gets nothing of any instance
/// (constitution III).
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../instances/instance_rules.dart';
import 'service_response.dart';
import 'trust.dart';

const _maximumRedirects = 5;

const _redirectStatuses = {301, 302, 303, 307, 308};

/// Whether [url] may be asked for without credentials: http or https, with a
/// host and without user information, which would be sent as a login.
bool isRemoteAddress(Uri url) =>
    (url.isScheme('http') || url.isScheme('https')) &&
    url.host.isNotEmpty &&
    url.userInfo.isEmpty;

/// Whether a redirect from [from] to [to] is followed: within the origin, or
/// from http to https of the same host on their default ports.
///
/// The app talks only to hosts that a service points to (constitution III,
/// SC-007), which the target of a redirect to elsewhere is not. It could also
/// be an address on the user's own network.
bool followsRemoteRedirect(Uri from, Uri to) =>
    isRemoteAddress(to) &&
    (!isOtherOrigin(from, to) ||
        (from.isScheme('http') &&
            from.port == 80 &&
            to.isScheme('https') &&
            to.port == 443 &&
            to.host == from.host));

/// Reads from public hosts, such as those of artwork.
///
/// It is given an address and nothing else, so it can send no credential,
/// cookie or custom header. It keeps no cookies. Only the redirects of
/// [followsRemoteRedirect] are followed. Certificates are checked against the
/// system's roots, and no proxy is used.
final class RemoteClient {
  /// [timeout] limits each wait for the server; a whole read may take four
  /// times that. An answer over [maximumBytes] is given up on.
  RemoteClient({
    this._timeout = const Duration(seconds: 30),
    this._maximumBytes = 20 * 1024 * 1024,
  });

  final Duration _timeout;
  final int _maximumBytes;
  late final HttpClient _client = newHttpClient()..connectionTimeout = _timeout;

  /// The answer to a `GET` of [url], whatever its status.
  ///
  /// [allowed] is asked before every request, that of each redirect included, as
  /// the user may switch public hosts off while one is under way.
  ///
  /// Throws if there is none, [url] is not [isRemoteAddress], a redirect is not
  /// followed, or [allowed] says no. The text of what is thrown may quote an
  /// address: never log or show it.
  Future<ServiceResponse> get(
    Uri url, {
    required bool Function() allowed,
  }) async {
    final elapsed = Stopwatch()..start();
    var address = url;
    for (var redirects = 0; ; redirects++) {
      if (!isRemoteAddress(address)) {
        throw const HttpException('Not a public address');
      }
      if (!allowed()) throw const HttpException('Switched off');
      final request = await _client.getUrl(address.removeFragment());
      // Followed here, so that every target is checked.
      request.followRedirects = false;
      final response = await request.close().timeout(
        _timeout,
        onTimeout: () {
          request.abort();
          throw TimeoutException('No answer');
        },
      );
      final location = response.headers.value(HttpHeaders.locationHeader);
      if (!_redirectStatuses.contains(response.statusCode) ||
          location == null) {
        return _read(response, elapsed);
      }
      // The connection is not reused, so the body need not be read.
      await response.listen(null).cancel();
      final target = address.resolve(location);
      if (redirects == _maximumRedirects ||
          !followsRemoteRedirect(address, target)) {
        throw const HttpException('Redirect not followed');
      }
      address = target;
    }
  }

  Future<ServiceResponse> _read(
    HttpClientResponse response,
    Stopwatch elapsed,
  ) async {
    final bytes = BytesBuilder(copy: false);
    // Leaving the loop early drops the connection.
    await for (final chunk in response.timeout(_timeout)) {
      bytes.add(chunk);
      if (bytes.length > _maximumBytes) {
        throw const HttpException('Answer too large');
      }
      if (elapsed.elapsed > _timeout * 4) {
        throw TimeoutException('Answer too slow');
      }
    }
    final headers = <String, List<String>>{};
    response.headers.forEach((name, values) => headers[name] = values);
    return ServiceResponse(
      statusCode: response.statusCode,
      bytes: bytes.takeBytes(),
      headers: headers,
    );
  }

  /// Drops every connection. Later reads fail.
  void close() => _client.close(force: true);
}
