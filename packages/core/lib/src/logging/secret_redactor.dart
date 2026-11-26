import 'dart:convert';

import '../instances/credential.dart';

/// Removes secrets from text before it is stored or shown.
///
/// Values registered with [addSecrets] or [addCredential] are removed wherever
/// they appear. Anything else is recognised only by its surroundings: URL
/// queries and user information, sensitive names such as `password` or
/// `Cookie`, `Bearer` and `Basic` tokens, and 32-digit hexadecimal API keys.
/// It errs towards removing too much, and removes the whole of a text that it
/// cannot process.
final class SecretRedactor {
  /// What replaces a secret.
  static const marker = '[redacted]';

  /// Shorter registered values are ignored: replacing them would blank ordinary
  /// words and so give the value away.
  static const minimumSecretLength = 4;

  final _known = <String, RegExp>{};

  /// Registers values to remove, also in their URL and JSON encoded forms.
  /// Returns whether any of them was new.
  bool addSecrets(Iterable<String> secrets) {
    final before = _known.length;
    for (final secret in secrets) {
      for (final value in {secret, secret.trim()}) {
        if (value.length < minimumSecretLength) continue;
        final json = jsonEncode(value);
        for (final form in [
          value,
          json.substring(1, json.length - 1),
          ..._urlForms(value),
        ]) {
          _known[form] ??= _literal(form);
        }
      }
    }
    return _known.length > before;
  }

  /// Registers every secret of [credential], including the user names. Returns
  /// whether any of them was new.
  bool addCredential(Credential credential) {
    final basicUser = credential.basicUser;
    final basicPassword = credential.basicPassword;
    final cookie = credential.sessionCookie;
    return addSecrets([
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
  String redact(String text) => _guarded(() {
    // Registered values are found in the original text, so that no rule can cut
    // one in half. The rules see neither them nor their markers, so that a
    // registered `pass` or `https` cannot stop a rule from recognising what
    // follows it.
    final spans = _knownSpans(text);
    var unseen = text;
    for (final rule in _rules) {
      final found = [
        for (final (start, end) in rule(unseen))
          if (end > start) (start, end),
      ];
      spans.addAll(found);
      // Later rules skip what this one found. Positions stay as they were.
      unseen = _replace(unseen, found, (length) => '\u0001' * length);
    }
    return _replace(text, spans, (_) => marker);
  });

  /// [text] without the registered values only.
  ///
  /// If [text] was [cutOff] from a longer one, this also removes its end where
  /// that is the start of a registered value.
  String redactKnown(String text, {bool cutOff = false}) => _guarded(() {
    final spans = _knownSpans(text);
    if (cutOff) {
      for (final form in _known.keys) {
        final start = _startOfCutValue(text, form);
        if (start != null) spans.add((start, text.length));
      }
    }
    return _replace(text, spans, (_) => marker);
  });

  /// Never lets text through unredacted, and never fails the caller.
  static String _guarded(String Function() redaction) {
    try {
      return redaction();
    } catch (_) {
      // A regular expression can overflow the stack on a very large input.
      return marker;
    }
  }

  List<(int, int)> _knownSpans(String text) => [
    for (final pattern in _known.values)
      for (final match in pattern.allMatches(text)) (match.start, match.end),
  ];

  /// Where [text] ends in the first part of [form], if that part is at least
  /// [minimumSecretLength] long.
  static int? _startOfCutValue(String text, String form) {
    final lower = form.toLowerCase();
    final opening = _literal(form.substring(0, minimumSecretLength));
    final earliest = text.length > form.length ? text.length - form.length : 0;
    for (final match in opening.allMatches(text, earliest)) {
      if (lower.startsWith(text.substring(match.start).toLowerCase())) {
        return match.start;
      }
    }
    return null;
  }

  static RegExp _literal(String value) =>
      RegExp(RegExp.escape(value), caseSensitive: false);

  /// Replaces each of [spans], joining those that touch so that overlapping
  /// secrets leave no fragment behind.
  static String _replace(
    String text,
    List<(int, int)> spans,
    String Function(int length) replacement,
  ) {
    if (spans.isEmpty) return text;
    spans.sort((a, b) => a.$1.compareTo(b.$1));

    final result = StringBuffer();
    var copied = 0;
    var (start, end) = spans.first;
    void replaceSpan() {
      result
        ..write(text.substring(copied, start))
        ..write(replacement(end - start));
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
      final component = Uri.encodeComponent(value);
      return [
        component,
        // Strict RFC 3986, as requests are sent: these are escaped too.
        component.replaceAllMapped(
          RegExp("[!'()*]"),
          (m) => '%${m[0]!.codeUnitAt(0).toRadixString(16).toUpperCase()}',
        ),
        Uri.encodeQueryComponent(value),
        Uri.encodeFull(value),
      ];
    } on ArgumentError {
      // A lone surrogate has no encoded form.
      return const [];
    }
  }

  /// The parts of a text that each rule takes for secrets, in the order the
  /// rules are applied.
  static final _rules = <Iterable<(int, int)> Function(String)>[
    (text) => _afterPrefix(_userInfo, text, suffix: 1),
    (text) => _afterPrefix(_query, text),
    (text) => _afterPrefix(_fragment, text),
    (text) => _afterPrefix(_headerValueError, text),
    (text) => _afterPrefix(_scheme, text),
    _namedValues,
    (text) => _hexKey.allMatches(text).map((m) => (m.start, m.end)),
  ];

  /// Each match of [pattern] without its first group, which is kept, and
  /// without its last [suffix] characters.
  static Iterable<(int, int)> _afterPrefix(
    RegExp pattern,
    String text, {
    int suffix = 0,
  }) => pattern
      .allMatches(text)
      .map((m) => (m.start + m[1]!.length, m.end - suffix));

  /// What follows a sensitive name and `:` or `=`.
  static Iterable<(int, int)> _namedValues(String text) sync* {
    var done = 0;
    for (final match in _assignment.allMatches(text)) {
      if (match.start < done || !_isSensitive(match[1]!)) continue;
      var start = match.end;
      if (start == text.length) continue;
      final int end;
      final first = text[start];
      final closing = first == '"' || first == "'"
          ? _closingQuote(text, start)
          : null;
      if (closing != null) {
        // Only the quoted value.
        start += 1;
        end = closing;
      } else if (first == '{' || first == '[' || first == '(') {
        end = _endOfLine(text, _endOfBrackets(text, start));
      } else {
        end = _endOfLine(text, start);
      }
      yield (start, end);
      done = end;
    }
  }

  /// The quote closing the one at [open], if the value plainly ends there.
  /// Scanned by hand: a regular expression overflows on a very long value.
  static int? _closingQuote(String text, int open) {
    for (var i = open + 1; i < text.length; i++) {
      if (text[i] == '\n' || text[i] == '\r') return null;
      if (text[i] == r'\') {
        i++;
      } else if (text[i] == text[open]) {
        final next = i + 1;
        return next == text.length || _delimiter.hasMatch(text[next])
            ? i
            : null;
      }
    }
    return null;
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

  static final _delimiter = RegExp(r'[\s,;&)}\]]');

  /// A name, an optional closing quote or bracket, then `:` or `=`. The bracket
  /// is how `ArgumentError` writes a name: `(password): "..."`.
  static final _assignment = RegExp(
    r'''(?<![A-Za-z0-9_.-])([A-Za-z0-9_.-]+)(?:\\*["']|\))?[ \t]*[:=]\s*''',
  );

  // In the patterns below, the first group is what is kept.

  static final _userInfo = RegExp(
    r'''([a-z0-9+.-]://)[^/?#\s"<>]*@''',
    caseSensitive: false,
  );

  // The whole query goes: any parameter may carry a secret.
  static final _query = RegExp(r'(\?)[^\s"<>]+');

  // The lookahead stops at the next `#`, or a run of them takes quadratic time.
  static final _fragment = RegExp(r'(#)(?=[^\s"<>=#]*=)[^\s"<>]+');

  // `dart:io` quotes a rejected header value, which may be a custom one.
  static final _headerValueError = RegExp(
    r'(header (?:field )?value: ?).*',
    caseSensitive: false,
  );

  // A word in lower case, as in "Basic authentication", is not a token.
  static final _scheme = RegExp(
    r'\b((?:[Bb]earer|BEARER|[Bb]asic|BASIC)[ \t]+)(?![a-z]+(?![\w.~+/=-]))'
    r'[\w.~+/=-]{6,}',
  );

  static final _hexKey = RegExp(
    r'(?<![0-9A-Za-z])[0-9a-fA-F]{32}(?![0-9A-Za-z])',
  );
}
