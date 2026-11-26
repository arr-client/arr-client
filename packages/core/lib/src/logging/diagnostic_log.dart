import 'dart:collection';
import 'dart:math';

import '../instances/credential.dart';
import 'log_entry.dart';
import 'log_level.dart';
import 'logger.dart';
import 'secret_redactor.dart';

/// The diagnostic log the user can read and share.
///
/// It keeps the newest entries in memory, redacted by a [SecretRedactor] before
/// they are stored, and writes nowhere else.
///
/// Register first: call [addCredential] as soon as a credential is read, entered
/// or issued, before anything can log it. Registering later only drops the
/// stored entries that contain the first characters of a new value. It misses
/// an entry where redaction or truncation had already left less than those.
final class DiagnosticLog implements Logger {
  /// Keeps at most [capacity] entries, which must not be negative.
  DiagnosticLog({this.capacity = 500, this._clock = DateTime.now})
    : assert(capacity >= 0, 'capacity must not be negative');

  /// Longer texts are cut off, after redaction.
  static const maximumTextLength = 4000;

  /// How many entries are kept.
  final int capacity;

  /// How much of a value marks a stored entry as containing it.
  static const _startLength = 6;

  final DateTime Function() _clock;
  final _redactor = SecretRedactor();
  final _entries = Queue<LogEntry>();

  /// The entries kept, oldest first.
  List<LogEntry> get entries => List.unmodifiable(_entries);

  /// Registers values to remove from entries logged from now on, and drops
  /// stored entries that appear to contain them.
  void addSecrets(Iterable<String> secrets) =>
      _drop(_redactor.addSecrets(secrets));

  /// Registers the secrets of [credential], as [addSecrets] does.
  void addCredential(Credential credential) =>
      _drop(_redactor.addCredential(credential));

  @override
  void log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    _entries.add(
      LogEntry(
        time: _clock(),
        level: level,
        message: _clean(message),
        error: error == null ? null : _clean(_describe(error)),
        stackTrace: stackTrace == null ? null : _clean(_describe(stackTrace)),
      ),
    );
    while (_entries.length > capacity) {
      _entries.removeFirst();
    }
  }

  /// Every entry as one text, for the user to share.
  String export() => _entries.join('\n');

  /// Removes all entries. Registered secrets stay registered.
  void clear() => _entries.clear();

  String _clean(String text) {
    final redacted = _redactor.redact(text);
    if (redacted.length <= maximumTextLength) return redacted;
    var end = maximumTextLength;
    // Not between the two halves of a surrogate pair.
    if (redacted.codeUnitAt(end - 1) & 0xFC00 == 0xD800) end--;
    return '${redacted.substring(0, end)}...';
  }

  static String _describe(Object error) {
    try {
      // Its toString quotes an excerpt of the input, which can cut a secret
      // short so that it is no longer recognised.
      if (error is FormatException) return 'FormatException: ${error.message}';
      return error.toString();
    } catch (_) {
      // Logging must not fail because the error cannot describe itself.
      return 'Unprintable ${error.runtimeType}';
    }
  }

  void _drop(Set<String> forms) {
    if (forms.isEmpty) return;
    final starts = {
      for (final form in forms)
        form.substring(0, min(form.length, _startLength)).toLowerCase(),
    };
    _entries.removeWhere((entry) {
      final text = [
        entry.message,
        ?entry.error,
        ?entry.stackTrace,
      ].join('\n').toLowerCase();
      return starts.any(text.contains);
    });
  }
}
