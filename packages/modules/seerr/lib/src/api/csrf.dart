/// The CSRF token a protected server wants with every write, signing in
/// included, also with an API key (research R18). A server without the
/// protection sets no cookie, and then nothing is added.
library;

import 'package:core/core.dart';

/// The headers for one write, from the cookies that a read of `api/v1/[path]`
/// sets. Nothing is remembered, so switching the protection on or off needs no
/// more.
///
/// The server marks the cookies `Secure` but does not look at the transport, so
/// they are returned to the same address over http too.
Future<Result<Map<String, String>, HttpError>> csrfHeaders(
  ServiceHttpClient http,
  String path,
) async {
  final answer = await http.send(
    ServiceRequest(HttpMethod.get, 'api/v1/$path'),
  );
  switch (answer) {
    case Err(:final error):
      return Err(error);
    case Ok(:final value):
      final cookies = setCookies(value);
      final token = cookies['XSRF-TOKEN'];
      final secret = cookies['_csrf'];
      return Ok({
        if (token != null && secret != null) ...{
          'Cookie': '_csrf=$secret',
          'X-XSRF-TOKEN': token,
        },
      });
  }
}

/// The names and values that [response] sets as cookies, without attributes.
Map<String, String> setCookies(ServiceResponse response) {
  final cookies = <String, String>{};
  for (final header in response.headers['set-cookie'] ?? const <String>[]) {
    final pair = header.split(';').first;
    final separator = pair.indexOf('=');
    if (separator <= 0) continue;
    final value = pair.substring(separator + 1).trim();
    if (value.isNotEmpty) {
      cookies[pair.substring(0, separator).trim()] = value;
    }
  }
  return cookies;
}
