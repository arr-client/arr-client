import 'discovery_ref.dart';
import 'issue_comment.dart';
import 'issue_status.dart';
import 'issue_type.dart';
import 'service_user.dart';

/// A reported problem with a title.
final class Issue {
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

  final int id;

  final IssueType type;

  final IssueStatus status;

  /// The title, with its TMDB id.
  final DiscoveryRef mediaRef;

  final String title;

  final ServiceUser createdBy;

  final DateTime createdAt;

  final List<IssueComment> comments;
}
