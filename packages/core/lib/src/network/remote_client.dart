/// The HTTP client of public hosts, which gets nothing of any instance
/// (constitution III).
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

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

/// Whether a redirect from [from] to [to] may be followed, as far as the
/// addresses alone say: to any host and port, but not from https down to http,
/// which would show what is loaded to the network. [RemoteClient] also refuses
/// to be led from a public host to a local one.
bool followsRemoteRedirect(Uri from, Uri to) =>
    isRemoteAddress(to) && !(from.isScheme('https') && to.isScheme('http'));

/// Whether [host], a name or an address without port or brackets, is this
/// device or may be on a network near it: loopback, private, link-local,
/// carrier-grade NAT, multicast or reserved. A name is if any of its addresses
/// is.
///
/// Throws a [SocketException] if a name cannot be resolved.
Future<bool> isLocalHost(String host) async {
  var name = host.toLowerCase();
  // The zone of a link-local address does not change what it is.
  if (name.contains(':')) name = name.split('%').first;
  if (name.endsWith('.')) name = name.substring(0, name.length - 1);
  final literal = InternetAddress.tryParse(name);
  // Resolving a `.local` name is itself local network traffic.
  if (literal == null &&
      (name == 'localhost' ||
          name.endsWith('.localhost') ||
          name.endsWith('.local'))) {
    return true;
  }
  final addresses = literal != null
      ? [literal]
      : await InternetAddress.lookup(name);
  return addresses.any((address) => _isLocalAddress(address.rawAddress));
}

bool _isLocalAddress(List<int> bytes) {
  if (bytes.length == 4) {
    final second = bytes[1];
    return switch (bytes[0]) {
      0 || 10 || 127 => true,
      100 => second >= 64 && second < 128,
      169 => second == 254,
      172 => second >= 16 && second < 32,
      192 => second == 168,
      final first => first >= 224,
    };
  }
  // An IPv4 address written as IPv6.
  if (bytes.take(10).every((byte) => byte == 0) &&
      bytes[10] == 0xff &&
      bytes[11] == 0xff) {
    return _isLocalAddress(bytes.sublist(12));
  }
  // The unspecified and the loopback address.
  if (bytes.take(15).every((byte) => byte == 0) && bytes[15] <= 1) return true;
  return bytes[0] & 0xfe == 0xfc || // unique local
      (bytes[0] == 0xfe && bytes[1] >= 0x80) || // link- and site-local
      bytes[0] == 0xff; // multicast
}

/// Reads from public hosts, such as those of artwork.
///
/// It is given an address and nothing else, so it can send no credential,
/// cookie or custom header, to the first host or to one it is redirected to. It
/// keeps no cookies. Certificates are checked against the system's roots, and no
/// proxy is used.
///
/// A service may name any address, and up to five redirects of it are followed,
/// to other hosts too. Not followed are those that [followsRemoteRedirect]
/// refuses, and one from a public host to a local one: only the address a
/// service gave may lead into the user's own network. That is judged by what a
/// name resolves to just before the request, so it does not hold against a name
/// server that answers differently the second time.
final class RemoteClient {
  /// [timeout] limits each wait for the server; a whole read may take four
  /// times that. An answer over [maximumBytes] is given up on. [isLocal] says
  /// which hosts are local, in place of [isLocalHost].
  RemoteClient({
    this._timeout = const Duration(seconds: 30),
    this._maximumBytes = 20 * 1024 * 1024,
    this._isLocal = isLocalHost,
  });

  final Duration _timeout;
  final int _maximumBytes;
  final Future<bool> Function(String host) _isLocal;
  late final HttpClient _client = newHttpClient()..connectionTimeout = _timeout;

  /// The answer to a `GET` of [url], whatever its status.
  ///
  /// [allowed] is asked before every request and name lookup, those of each
  /// redirect included, as the user may switch public hosts off while one is
  /// under way.
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
      _check(allowed);
      final request = await _client.getUrl(address.removeFragment());
      // Connecting takes a while.
      if (!allowed()) {
        request.abort();
        _check(allowed);
      }
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
          !followsRemoteRedirect(address, target) ||
          await _leadsInward(address, target, allowed)) {
        throw const HttpException('Redirect not followed');
      }
      address = target;
    }
  }

  /// Whether going from [from] to [to] leaves the public hosts for a local one.
  Future<bool> _leadsInward(Uri from, Uri to, bool Function() allowed) async {
    if (from.host == to.host) return false;
    _check(allowed);
    if (!await _isLocal(to.host).timeout(_timeout)) return false;
    _check(allowed);
    return !await _isLocal(from.host).timeout(_timeout);
  }

  static void _check(bool Function() allowed) {
    if (!allowed()) throw const HttpException('Switched off');
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
