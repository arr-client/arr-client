import 'health_level.dart';

/// A problem the server reports.
final class HealthIssue {
  /// Creates a [HealthIssue].
  const HealthIssue({
    required this.source,
    required this.level,
    required this.message,
    this.helpUrl,
  });

  /// The part of the server reporting it.
  final String source;

  /// How serious it is.
  final HealthLevel level;

  /// The server's message.
  final String message;

  /// The server's help link.
  final Uri? helpUrl;
}
