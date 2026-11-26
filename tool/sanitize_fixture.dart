// Removes keys, hosts, paths and user data from recorded service responses (research R15).
//
//   dart run tool/sanitize_fixture.dart <raw> <sanitized> [<raw> <sanitized> ...]
//
// Pass related recordings (say a queue and a torrent list) in one run, so that equal values get
// equal placeholders and download ids still match torrent hashes. Keep raw recordings outside the
// repository.
//
// It is an allow-list: a string survives only if fixture_allow_list.dart knows it to be harmless;
// every other string is replaced, whatever its field is called. If a contract test needs a value
// that was replaced, add it there for review. Do not edit the fixture by copying the value back.
//
// It cannot judge these, so read every fixture before committing it:
// - numbers and booleans are kept unless a field name marks them as private;
// - object keys that look like field names are kept, even in a map keyed by user or host names;
// - public catalogue ids (tmdbId, imdbId and so on) are kept and show what a library holds.
// Record from the dev stack (tool/devstack/), never from a server somebody really uses.

import 'dart:convert';
import 'dart:io';

import 'fixture_allow_list.dart';

/// Thrown for input that cannot be sanitized. The message never quotes the input.
class UnsanitizableInput implements Exception {
  const UnsanitizableInput(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Sanitizes recordings. Placeholders are consistent for the lifetime of one instance.
class FixtureSanitizer {
  final _placeholders = <String, String>{};
  final _hashes = <String, String>{};
  final _keys = <String, String>{};

  /// Returns the sanitized form of one response body: JSON, or one of the few plain text or empty
  /// bodies the services send. Anything else (HTML, header dumps, logs) throws [UnsanitizableInput].
  String sanitize(String body) {
    final text = body.trim();
    if (isSafePlainText(text)) return text.isEmpty ? '' : '$text\n';
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      // The exception quotes its source, so it is not passed on.
      throw const UnsanitizableInput(
        'Not JSON and not a known plain text response.',
      );
    }
    return '${const JsonEncoder.withIndent('  ').convert(sanitizeJson(json))}\n';
  }

  /// Sanitizes a decoded JSON value.
  Object? sanitizeJson(Object? json) => _value(json, '', private: false);

  Object? _value(Object? value, String field, {required bool private}) {
    return switch (value) {
      null || bool() => value,
      // 1e999 decodes to infinity, which cannot be written back.
      num() when !value.isFinite => throw const UnsanitizableInput(
        'A number is out of range.',
      ),
      num() => private ? 0 : value,
      String() => private ? _privateString(value) : _string(value, field),
      // Items of a list are judged by the name of the list.
      List<Object?>() => [
        for (final item in value) _value(item, field, private: private),
      ],
      Map<String, Object?>() => _object(value, private: private),
      _ => throw const UnsanitizableInput('Unsupported value.'),
    };
  }

  Map<String, Object?> _object(
    Map<String, Object?> object, {
    required bool private,
  }) {
    // {"name": "port", "value": 8080}: the name is data, so any such value is private.
    final isSetting = object.keys.map(_normalize).any(_settingNames.contains);
    final result = <String, Object?>{};
    for (final MapEntry(:key, :value) in object.entries) {
      var name = _isFieldName(key) ? key : _renamedKey(key);
      while (result.containsKey(name)) {
        name = '${name}_';
      }
      result[name] = _value(
        value,
        _normalize(key),
        private:
            private ||
            _isPrivateName(key) ||
            (isSetting && _normalize(key) == 'value'),
      );
    }
    return result;
  }

  String _renamedKey(String key) =>
      _keys.putIfAbsent(key, () => 'redactedKey${_keys.length + 1}');

  String _privateString(String value) => value.isEmpty ? '' : 'redacted';

  String _string(String value, String field) {
    if (value.isEmpty || isAllowedString(value, field)) return value;
    if (_hashFields.contains(field) && _hexHash.hasMatch(value)) {
      return _fakeHash(value);
    }
    return _placeholders.putIfAbsent(
      value,
      () => _placeholder(value, _placeholders.length + 1),
    );
  }

  /// Same length and letter case, and the same fake for either case of one hash.
  String _fakeHash(String value) {
    final fake = _hashes.putIfAbsent(
      value.toLowerCase(),
      () => 'abcdef${'${_hashes.length + 1}'.padLeft(value.length - 6, '0')}',
    );
    return value == value.toUpperCase() ? fake.toUpperCase() : fake;
  }
}

/// A stand-in with the same general shape. Nothing from [value] is copied into it, except a file
/// extension from a fixed list.
String _placeholder(String value, int n) {
  final match = _extension.firstMatch(value);
  final extension = match == null ? '' : '.${match[1]!.toLowerCase()}';
  final lower = value.toLowerCase();
  for (final scheme in const ['http', 'https']) {
    if (lower.startsWith('$scheme://')) {
      return '$scheme://redacted.invalid/$n$extension';
    }
  }
  if (_email.hasMatch(value)) return 'user$n@redacted.invalid';
  if (value.startsWith(r'\\')) return '\\\\redacted.invalid\\$n$extension';
  if (_drive.hasMatch(value)) return 'C:\\redacted\\$n$extension';
  if (value.startsWith('/')) return '/redacted/$n$extension';
  return 'redacted-$n';
}

bool _isFieldName(String key) =>
    _seasonNumber.hasMatch(key) ||
    (_identifier.hasMatch(key) && _digit.allMatches(key).length <= 3);

String _normalize(String key) =>
    key.toLowerCase().replaceAll(_notAlphanumeric, '');

bool _isPrivateName(String key) {
  final joined = _normalize(key);
  if (joined == 'key' || _privateFragments.any(joined.contains)) return true;
  return _word
      .allMatches(key)
      .any((word) => _privateWords.contains(word[0]!.toLowerCase()));
}

final _hexHash = RegExp(r'^([0-9a-fA-F]{32}|[0-9a-fA-F]{40}|[0-9a-fA-F]{64})$');
final _email = RegExp(r'^[^\s/\\:]+@[^\s/\\:]+$');
final _drive = RegExp(r'^[A-Za-z]:[\\/]');
final _extension = RegExp(
  r'\.(jpg|jpeg|png|mkv|mp4|avi|srt|ass|flac|mp3|m4a|epub|mobi|nzb|torrent)$',
  caseSensitive: false,
);
final _identifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_]{0,39}$');
final _seasonNumber = RegExp(r'^\d{1,3}$');
final _digit = RegExp(r'\d');
final _notAlphanumeric = RegExp('[^a-z0-9]');
// Splits camelCase, PascalCase, snake_case and kebab-case.
final _word = RegExp('[A-Z]+(?![a-z])|[A-Z]?[a-z]+');

const _settingNames = {'name', 'key', 'label'};

const _hashFields = {
  'hash',
  'infohash',
  'infohashv1',
  'infohashv2',
  'torrentinfohash',
  'downloadid',
};

// Everything under a field so named is replaced, numbers included.
const _privateFragments = [
  'password',
  'passwd',
  'passphrase',
  'passkey',
  'secret',
  'token',
  'apikey',
  'accesskey',
  'privatekey',
  'rsskey',
  'cookie',
  'credential',
  'chatid',
  'webhook',
];

// Matched against whole words, so that "port" does not catch "importMode".
const _privateWords = {
  'address',
  'auth',
  'chat',
  'csrf',
  'discord',
  'email',
  'gid',
  'host',
  'ip',
  'jellyfin',
  'latitude',
  'longitude',
  'otp',
  'pass',
  'phone',
  'pin',
  'plex',
  'port',
  'pwd',
  'salt',
  'sender',
  'session',
  'sid',
  'telegram',
  'uid',
  'xsrf',
};

/// Reads every input before writing anything, so a refused input leaves no output behind.
Future<int> run(List<String> arguments, StringSink errors) async {
  if (arguments.isEmpty || arguments.length.isOdd) {
    errors.writeln(
      'Usage: dart run tool/sanitize_fixture.dart <raw> <sanitized> [...]',
    );
    return 64;
  }
  final sanitizer = FixtureSanitizer();
  final outputs = <String, String>{};
  for (var i = 0; i < arguments.length; i += 2) {
    try {
      final body = await File(arguments[i]).readAsString();
      final output = arguments[i + 1];
      if (!File(output).parent.existsSync() || Directory(output).existsSync()) {
        errors.writeln(
          'Output ${i ~/ 2 + 1}: not a file in an existing directory. '
          'Nothing was written.',
        );
        return 73;
      }
      outputs[output] = sanitizer.sanitize(body);
    } on UnsanitizableInput catch (e) {
      errors.writeln('Input ${i ~/ 2 + 1}: $e Nothing was written.');
      return 65;
    } on FileSystemException {
      errors.writeln(
        'Input ${i ~/ 2 + 1}: cannot be read as UTF-8 text. Nothing was written.',
      );
      return 66;
    }
  }
  for (final MapEntry(:key, :value) in outputs.entries) {
    try {
      await File(key).writeAsString(value);
    } on FileSystemException {
      errors.writeln('Cannot write $key. Other outputs may have been written.');
      return 73;
    }
  }
  return 0;
}

Future<void> main(List<String> arguments) async {
  exitCode = await run(arguments, stderr);
}
