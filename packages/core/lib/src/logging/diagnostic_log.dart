import 'dart:collection';

import '../instances/credential.dart';
import 'log_entry.dart';
import 'log_level.dart';
import 'logger.dart';
import 'secret_redactor.dart';

/// The diagnostic log the user can read and share.
///
/// It keeps the newest entries in memory, redacted by a [SecretRedactor] before
/// they are stored, and writes nowhere else. Register each credential with
/// [addCredential] as soon as it is read, entered or issued.
final class DiagnosticLog implements Logger {
  /// Keeps at most [capacity] entries.
  DiagnosticLog({this.capacity = 500, this._clock = DateTime.now});

  /// Longer texts are cut off, after redaction.
  static const maximumTextLength = 4000;

  /// How many entries are kept.
  final int capacity;

  final DateTime Function() _clock;
  final _redactor = SecretRedactor();
  final _entries = Queue<LogEntry>();

  /// The entries kept, oldest first.
  List<LogEntry> get entries => List.unmodifiable(_entries);

  /// Registers values to remove from past and future entries.
  void addSecrets(Iterable<String> secrets) {
    _redactor.addSecrets(secrets);
    _redactStored();
  }

  /// Registers the secrets of [credential], as [addSecrets] does.
  void addCredential(Credential credential) {
    _redactor.addCredential(credential);
    _redactStored();
  }

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
        stackTrace: stackTrace == null ? null : _clean('$stackTrace'),
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
    return redacted.length <= maximumTextLength
        ? redacted
        : '${redacted.substring(0, maximumTextLength)}...';
  }

  static String _describe(Object error) {
    // Its toString quotes an excerpt of the input, which can cut a secret short
    // so that it is no longer recognised.
    if (error is FormatException) return 'FormatException: ${error.message}';
    try {
      return error.toString();
    } catch (_) {
      // Logging must not fail because the error cannot describe itself.
      return 'Unprintable ${error.runtimeType}';
    }
  }

  void _redactStored() {
    String? again(String? text) =>
        text == null ? null : _redactor.redactKnown(text);
    final redacted = [
      for (final entry in _entries)
        LogEntry(
          time: entry.time,
          level: entry.level,
          message: _redactor.redactKnown(entry.message),
          error: again(entry.error),
          stackTrace: again(entry.stackTrace),
        ),
    ];
    _entries
      ..clear()
      ..addAll(redacted);
  }
}
