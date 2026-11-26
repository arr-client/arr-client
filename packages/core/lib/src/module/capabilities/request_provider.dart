import '../../models/discovery_title.dart';
import '../../models/issue.dart';
import '../../models/issue_status.dart';
import '../../models/issue_type.dart';
import '../../models/media_request.dart';
import '../../models/quota.dart';
import '../../models/result_page.dart';
import '../../models/session_user.dart';
import '../capability.dart';
import '../module_route.dart';
import '../service_result.dart';

/// Requests and issues in a request service. Pages start at 1.
abstract interface class RequestProvider implements Capability {
  /// The signed-in user.
  ServiceResult<SessionUser> session();

  /// The user's remaining requests.
  ServiceResult<Quota> quota();

  /// [seasons] applies to series only.
  ServiceResult<MediaRequest> request(
    DiscoveryTitle title, {
    required bool is4k,
    List<int> seasons = const [],
  });

  /// Requests the user may see.
  ServiceResult<ResultPage<MediaRequest>> list({int page = 1});

  /// Approves a request.
  ServiceResult<void> approve(int requestId);

  /// Declines a request.
  ServiceResult<void> decline(int requestId);

  /// Retries a failed request.
  ServiceResult<void> retry(int requestId);

  /// Deletes a request.
  ServiceResult<void> delete(int requestId);

  /// Issues the user may see.
  ServiceResult<ResultPage<Issue>> issues({int page = 1});

  /// One issue with its comments.
  ServiceResult<Issue> issueDetail(int issueId);

  /// Only for a title with a [DiscoveryTitle.mediaId].
  ServiceResult<Issue> reportIssue(
    DiscoveryTitle title,
    IssueType type,
    String message,
  );

  /// Adds a comment to an issue.
  ServiceResult<void> comment(int issueId, String message);

  /// Resolves or reopens an issue.
  ServiceResult<void> setIssueStatus(int issueId, IssueStatus status);

  /// The screen to request [title].
  ModuleRoute requestRoute(DiscoveryTitle title, {required bool is4k});

  /// The list of requests.
  ModuleRoute requestsRoute();

  /// The list of issues.
  ModuleRoute issuesRoute();
}
