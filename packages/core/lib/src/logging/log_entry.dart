import 'log_level.dart';

/// One redacted entry of the diagnostic log.
final class LogEntry {
  /// Creates a [LogEntry]. The texts must already be redacted.
  const LogEntry({
    required this.time,
    required this.level,
    required this.message,
    this.error,
    this.stackTrace,
  });

  /// When it was recorded.
  final DateTime time;

  /// How serious it is.
  final LogLevel level;

  /// What happened.
  final String message;

  /// The cause, as text.
  final String? error;

  /// Where the cause was thrown, as text.
  final String? stackTrace;

  @override
  String toString() => [
    '${time.toUtc().toIso8601String()} ${level.name}: $message',
    ?error,
    ?stackTrace,
  ].join('\n');
}
