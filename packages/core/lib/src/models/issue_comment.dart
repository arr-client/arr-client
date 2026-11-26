import 'service_user.dart';

/// A comment on an issue.
final class IssueComment {
  const IssueComment({
    required this.id,
    required this.author,
    required this.message,
    required this.createdAt,
  });

  final int id;

  final ServiceUser author;

  final String message;

  final DateTime createdAt;
}
