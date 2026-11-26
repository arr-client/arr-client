/// A [Credential] as the text kept in secure storage. Not for logs, the
/// database or unencrypted files.
library;

import 'dart:convert';

import 'credential.dart';

/// Writes a credential. Equal credentials give equal texts.
String encodeCredential(Credential credential) => jsonEncode({
  'apiKey': ?credential.apiKey,
  'username': ?credential.username,
  'password': ?credential.password,
  'basicUser': ?credential.basicUser,
  'basicPassword': ?credential.basicPassword,
  'sessionCookie': ?credential.sessionCookie,
  if (credential.customHeaders.isNotEmpty)
    'customHeaders': {
      for (final name in credential.customHeaders.keys.toList()..sort())
        name: credential.customHeaders[name],
    },
});

/// Reads a credential, ignoring what it does not know. Null if [text] is not
/// one. It does not throw, as the error would quote the secrets.
Credential? decodeCredential(String text) {
  final Object? json;
  try {
    json = jsonDecode(text);
  } on FormatException {
    return null;
  }
  if (json is! Map<String, Object?>) return null;

  final fields = json;
  String? string(String key) => switch (fields[key]) {
    final String value => value,
    _ => null,
  };

  final headers = fields['customHeaders'];
  return Credential(
    apiKey: string('apiKey'),
    username: string('username'),
    password: string('password'),
    basicUser: string('basicUser'),
    basicPassword: string('basicPassword'),
    sessionCookie: string('sessionCookie'),
    customHeaders: {
      if (headers is Map<String, Object?>)
        for (final MapEntry(:key, :value) in headers.entries)
          if (value is String) key: value,
    },
  );
}
