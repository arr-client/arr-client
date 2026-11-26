import 'service_user.dart';

/// A comment on an issue.
final class IssueComment {
  /// Creates an [IssueComment].
  const IssueComment({
    required this.id,
    required this.author,
    required this.message,
    required this.createdAt,
  });

  /// The server's id of the comment.
  final int id;

  /// Who wrote it.
  final ServiceUser author;

  /// The text.
  final String message;

  /// When it was written.
  final DateTime createdAt;
}
