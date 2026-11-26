import 'log_level.dart';

/// The diagnostic log. Implementations redact secrets, and callers still never
/// pass tokens, passwords, headers, cookies or URLs with queries.
abstract interface class Logger {
  void log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  });
}
