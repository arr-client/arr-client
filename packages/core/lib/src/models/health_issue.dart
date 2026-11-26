import 'health_level.dart';

/// A problem the server reports.
final class HealthIssue {
  const HealthIssue({
    required this.source,
    required this.level,
    required this.message,
    this.helpUrl,
  });

  final String source;

  final HealthLevel level;

  final String message;

  final Uri? helpUrl;
}
