import 'discovery_ref.dart';
import 'issue_comment.dart';
import 'issue_status.dart';
import 'issue_type.dart';
import 'service_user.dart';

/// A reported problem with a title.
final class Issue {
  /// Creates an [Issue].
  const Issue({
    required this.id,
    required this.type,
    required this.status,
    required this.mediaRef,
    required this.title,
    required this.createdBy,
    required this.createdAt,
    this.comments = const [],
  });

  /// The server's id of the issue.
  final int id;

  /// What is wrong.
  final IssueType type;

  /// Open or resolved.
  final IssueStatus status;

  /// The title, with its TMDB id.
  final DiscoveryRef mediaRef;

  /// The title concerned.
  final String title;

  /// Who reported it.
  final ServiceUser createdBy;

  /// When it was reported.
  final DateTime createdAt;

  /// The conversation, where loaded.
  final List<IssueComment> comments;
}
