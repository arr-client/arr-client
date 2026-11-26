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
  ServiceResult<SessionUser> session();

  ServiceResult<Quota> quota();

  /// [seasons] applies to series only.
  ServiceResult<MediaRequest> request(
    DiscoveryTitle title, {
    required bool is4k,
    List<int> seasons = const [],
  });

  ServiceResult<ResultPage<MediaRequest>> list({int page = 1});

  ServiceResult<void> approve(int requestId);

  ServiceResult<void> decline(int requestId);

  ServiceResult<void> retry(int requestId);

  ServiceResult<void> delete(int requestId);

  ServiceResult<ResultPage<Issue>> issues({int page = 1});

  ServiceResult<Issue> issueDetail(int issueId);

  /// Only for a title with a [DiscoveryTitle.mediaId].
  ServiceResult<Issue> reportIssue(
    DiscoveryTitle title,
    IssueType type,
    String message,
  );

  ServiceResult<void> comment(int issueId, String message);

  ServiceResult<void> setIssueStatus(int issueId, IssueStatus status);

  ModuleRoute requestRoute(DiscoveryTitle title, {required bool is4k});

  ModuleRoute requestsRoute();

  ModuleRoute issuesRoute();
}
