import 'dart:convert';
import 'dart:typed_data';

/// What a server answered.
final class ServiceResponse {
  const ServiceResponse({
    required this.statusCode,
    required this.bytes,
    this.headers = const {},
  });

  final int statusCode;

  /// Names are lower case. A header such as `set-cookie` can have several
  /// values.
  final Map<String, List<String>> headers;

  final Uint8List bytes;

  /// [bytes] as UTF-8.
  String get text => utf8.decode(bytes, allowMalformed: true);
}
