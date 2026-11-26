import 'dart:convert';

import '../instances/credential.dart';

/// Removes secrets from text before it is stored or shown.
///
/// Values registered with [addSecrets] or [addCredential] are removed wherever
/// they appear. Anything else is recognised only by its surroundings: URL
/// queries and user information, sensitive names such as `password` or
/// `Cookie`, `Bearer` and `Basic` tokens, and 32-digit hexadecimal API keys.
/// It errs towards removing too much.
final class SecretRedactor {
  /// What replaces a secret.
  static const marker = '[redacted]';

  /// Shorter registered values are ignored: replacing them would blank ordinary
  /// words and so give the value away.
  static const minimumSecretLength = 4;

  final _known = <String, RegExp>{};

  /// Registers values to remove, also in their URL and JSON encoded forms.
  void addSecrets(Iterable<String> secrets) {
    for (final secret in secrets) {
      for (final value in {secret, secret.trim()}) {
        if (value.length < minimumSecretLength) continue;
        final json = jsonEncode(value);
        for (final form in [
          value,
          json.substring(1, json.length - 1),
          ..._urlForms(value),
        ]) {
          _known[form] ??= RegExp(RegExp.escape(form), caseSensitive: false);
        }
      }
    }
  }

  /// Registers every secret of [credential], including the user names.
  void addCredential(Credential credential) {
    final basicUser = credential.basicUser;
    final basicPassword = credential.basicPassword;
    final cookie = credential.sessionCookie;
    addSecrets([
      ?credential.apiKey,
      ?credential.username,
      ?credential.password,
      ?basicUser,
      ?basicPassword,
      if (basicUser != null)
        base64Encode(utf8.encode('$basicUser:${basicPassword ?? ''}')),
      ...credential.customHeaders.values,
      if (cookie != null) ...[
        cookie,
        // Each value may be quoted on its own, without its name.
        for (final pair in cookie.split(';'))
          pair.substring(pair.indexOf('=') + 1),
      ],
    ]);
  }

  /// [text] without the secrets.
  String redact(String text) {
    // Registered values go first, so that no rule below cuts one in half and
    // leaves the rest of it unrecognisable.
    final result = redactKnown(text)
        .replaceAllMapped(_userInfo, (m) => '${m[1]}$marker@')
        .replaceAll(_query, '?$marker')
        .replaceAll(_fragment, '#$marker')
        .replaceAllMapped(_headerValueError, (m) => '${m[1]} $marker')
        .replaceAllMapped(_scheme, (m) => '${m[1]} $marker');
    return _redactNamed(result).replaceAll(_hexKey, marker);
  }

  /// [text] without the registered values only.
  String redactKnown(String text) {
    // All matches are found before any is replaced, so that overlapping
    // secrets leave no fragment behind.
    final spans = [
      for (final pattern in _known.values)
        for (final match in pattern.allMatches(text)) (match.start, match.end),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    if (spans.isEmpty) return text;

    final result = StringBuffer();
    var copied = 0;
    var (start, end) = spans.first;
    void replaceSpan() {
      result
        ..write(text.substring(copied, start))
        ..write(marker);
      copied = end;
    }

    for (final (nextStart, nextEnd) in spans.skip(1)) {
      if (nextStart <= end) {
        if (nextEnd > end) end = nextEnd;
      } else {
        replaceSpan();
        (start, end) = (nextStart, nextEnd);
      }
    }
    replaceSpan();
    result.write(text.substring(copied));
    return result.toString();
  }

  static List<String> _urlForms(String value) {
    try {
      return [
        Uri.encodeComponent(value),
        Uri.encodeQueryComponent(value),
        Uri.encodeFull(value),
      ];
    } on ArgumentError {
      // A lone surrogate has no encoded form.
      return const [];
    }
  }

  /// Replaces what follows a sensitive name and `:` or `=`.
  static String _redactNamed(String text) {
    final result = StringBuffer();
    var copied = 0;
    for (final match in _assignment.allMatches(text)) {
      if (match.start < copied || !_isSensitive(match[1]!)) continue;
      var start = match.end;
      if (start == text.length) continue;
      var end = _endOfLine(text, start);
      final first = text[start];
      if (first == '"' || first == "'") {
        // Only the quoted value, provided it plainly ends where it seems to.
        final quoted = RegExp(
          '$first(?:\\\\.|[^$first\\\\\\r\\n])*$first'
          r'(?=$|[\s,;&)}\]])',
        ).matchAsPrefix(text, start);
        if (quoted != null) {
          start += 1;
          end = quoted.end - 1;
        }
      } else if (first == '{' || first == '[' || first == '(') {
        end = _endOfLine(text, _endOfBrackets(text, start));
      }
      result
        ..write(text.substring(copied, start))
        ..write(marker);
      copied = end;
    }
    result.write(text.substring(copied));
    return result.toString();
  }

  static int _endOfLine(String text, int from) {
    final newline = text.indexOf('\n', from);
    return newline < 0 ? text.length : newline;
  }

  /// Just past the bracket closing the one at [from], or the end of [text].
  static int _endOfBrackets(String text, int from) {
    var depth = 0;
    for (var i = from; i < text.length; i++) {
      if ('{[('.contains(text[i])) depth++;
      if ('}])'.contains(text[i]) && --depth == 0) return i + 1;
    }
    return text.length;
  }

  static bool _isSensitive(String name) {
    final lower = name.toLowerCase();
    // A source location in a stack trace, such as `secret_store.dart:12`.
    if (lower.endsWith('.dart')) return false;
    return _sensitivePart.hasMatch(lower.replaceAll(RegExp('[-_]'), '')) ||
        lower.split(RegExp('[-_.]')).any(_sensitiveWords.contains);
  }

  /// Sensitive only as a whole word of a name.
  static const _sensitiveWords = {
    'auth',
    'key',
    'pass',
    'pwd',
    'session',
    'sid',
    'sig',
    'signature',
  };

  /// Sensitive anywhere in a name, ignoring `-` and `_`.
  static final _sensitivePart = RegExp(
    'apikey|token|password|passwd|passphrase|secret|authorization|cookie|'
    'passkey|rsskey|torrentpass|credential|sessionid|csrf|xsrf|headers|'
    'username|basicuser',
  );

  /// A name, an optional closing quote, then `:` or `=`.
  static final _assignment = RegExp(
    r'''(?<![A-Za-z0-9_.-])([A-Za-z0-9_.-]+)(?:\\*["'])?[ \t]*[:=]\s*''',
  );

  static final _userInfo = RegExp(
    r'''([a-z0-9+.-]://)[^/?#\s"<>]*@''',
    caseSensitive: false,
  );

  // The whole query goes: any parameter may carry a secret.
  static final _query = RegExp(r'\?[^\s"<>]+');

  static final _fragment = RegExp(r'#(?=[^\s"<>=]*=)[^\s"<>]+');

  // `dart:io` quotes a rejected header value, which may be a custom one.
  static final _headerValueError = RegExp(
    r'(header (?:field )?value:).*',
    caseSensitive: false,
  );

  // A word in lower case, as in "Basic authentication", is not a token.
  static final _scheme = RegExp(
    r'\b([Bb]earer|BEARER|[Bb]asic|BASIC)[ \t]+(?![a-z]+(?![\w.~+/=-]))'
    r'[\w.~+/=-]{6,}',
  );

  static final _hexKey = RegExp(
    r'(?<![0-9A-Za-z])[0-9a-fA-F]{32}(?![0-9A-Za-z])',
  );
}
