import 'package:core/core.dart';

import '../api/permissions.dart';
import '../api/refusals.dart';
import '../api/seerr_api.dart';
import '../routes.dart';
import 'records.dart';
import 'server.dart';

/// How many requests or issues a page holds.
const _pageSize = 20;

/// The requests and issues of one instance of Seerr, Overseerr or Jellyseerr.
///
/// What the identity may do is in [session]; the server decides again with each
/// change.
final class SeerrRequestAdapter implements RequestProvider {
  SeerrRequestAdapter(InstanceContext context)
    : _api = SeerrApi(context),
      _server = SeerrServer.of(context.instance.lastProbe),
      _instanceId = context.instance.id;

  final SeerrApi _api;
  final SeerrServer _server;
  final String _instanceId;

  /// The quota is left out if it cannot be read.
  @override
  ServiceResult<SessionUser> session() async {
    final me = await readRecord(
      _api,
      'auth/me',
      (object) =>
          (user: serviceUser(object), bits: requireInt(object, 'permissions')),
    );
    switch (me) {
      case Err(:final error):
        return Err(error);
      case Ok(value: (:final user, :final bits)):
        // Says whether there is a 4K server at all.
        final Map<String, Object?> settings;
        switch (await _api.readObject('settings/public')) {
          case Err(:final error):
            return Err(error);
          case Ok(:final value):
            settings = value;
        }
        return Ok(
          SessionUser(
            id: user.id,
            name: user.name,
            permissions: permissionsOf(
              bits,
              movie4k: settings['movie4kEnabled'] == true,
              series4k: settings['series4kEnabled'] == true,
            ),
            quota: switch (await _quotaOf(user.id)) {
              Ok(:final value) => value,
              Err() => null,
            },
          ),
        );
    }
  }

  @override
  ServiceResult<Quota> quota() async {
    final me = await readRecord(
      _api,
      'auth/me',
      (object) => requireInt(object, 'id'),
    );
    return switch (me) {
      Err(:final error) => Err(error),
      Ok(:final value) => _quotaOf(value),
    };
  }

  ServiceResult<Quota> _quotaOf(int userId) => readRecord(
    _api,
    'user/$userId/quota',
    (object) =>
        Quota(movies: _usage(object['movie']), series: _usage(object['tv'])),
  );

  // Unlimited is a missing or zero limit.
  static QuotaUsage _usage(Object? value) {
    final usage = asObject(value);
    final limit = usage['limit'];
    final days = usage['days'];
    return QuotaUsage(
      used: requireInt(usage, 'used'),
      limit: limit is int && limit > 0 ? limit : null,
      days: days is int && days > 0 ? days : null,
    );
  }

  /// A series needs at least one season: without any, nothing is sent and the
  /// result is [Validation]. Why the server refused, such as a used up quota,
  /// is in the messages of a [Validation] too.
  @override
  ServiceResult<MediaRequest> request(
    DiscoveryTitle title, {
    required bool is4k,
    List<int> seasons = const [],
  }) async {
    final isSeries = title.mediaType == DiscoveryMediaType.series;
    if (isSeries && seasons.isEmpty) return const Err(Validation([]));
    final answer = await _api.write(
      HttpMethod.post,
      'request',
      body: {
        'mediaType': wireName(title.mediaType),
        // The TMDB id, whatever the name says.
        'mediaId': title.tmdbId,
        'is4k': is4k,
        if (isSeries) 'seasons': seasons,
      },
    );
    switch (answer) {
      case Err(:final error):
        final message = _messageOf(error.response);
        return Err(
          error.failure is Forbidden && message != null
              ? Validation([message])
              : error.failure,
        );
      case Ok(:final value):
        // A success status that made nothing: no season was left to request.
        if (value.statusCode == 202) {
          return Err(Validation([?_messageOf(value)]));
        }
        return decode(value, (object) => mediaRequest(object, _server));
    }
  }

  static String? _messageOf(ServiceResponse? response) {
    if (response == null) return null;
    final message = jsonObjectOf(response)?['message'];
    return message is String ? message : null;
  }

  @override
  ServiceResult<ResultPage<MediaRequest>> list({int page = 1}) => readRecord(
    _api,
    'request',
    (object) => ResultPage(
      items: [
        for (final request in asObjects(object['results']))
          mediaRequest(request, _server),
      ],
      page: page,
      hasMore: _hasMore(object, page),
    ),
    query: _paging(page),
  );

  static Map<String, List<String>> _paging(int page) => {
    'take': ['$_pageSize'],
    'skip': ['${(page - 1) * _pageSize}'],
  };

  static bool _hasMore(JsonObject object, int page) =>
      page < requireInt(asObject(object['pageInfo']), 'pages');

  @override
  ServiceResult<void> approve(int requestId) =>
      _change(HttpMethod.post, 'request/$requestId/approve');

  @override
  ServiceResult<void> decline(int requestId) =>
      _change(HttpMethod.post, 'request/$requestId/decline');

  @override
  ServiceResult<void> retry(int requestId) =>
      _change(HttpMethod.post, 'request/$requestId/retry');

  /// The server refuses what the identity may not delete; whom to offer it is
  /// [MediaRequest.canBeDeletedBy].
  @override
  ServiceResult<void> delete(int requestId) =>
      _change(HttpMethod.delete, 'request/$requestId');

  /// A write whose answer is of no interest.
  ServiceResult<void> _change(
    HttpMethod method,
    String path, {
    Object? body,
  }) async => switch (await _api.write(method, path, body: body)) {
    Err(:final error) => Err(error.failure),
    Ok() => const Ok(null),
  };

  /// Each title is read for its name; where that fails, the issue has an empty
  /// one. Comments come with [issueDetail] only.
  @override
  ServiceResult<ResultPage<Issue>> issues({int page = 1}) async {
    final answer = await readRecord(
      _api,
      'issue',
      (object) => (
        results: [
          for (final issue in asObjects(object['results']))
            (record: issue, ref: issueRef(issue)),
        ],
        hasMore: _hasMore(object, page),
      ),
      query: {
        ..._paging(page),
        // Resolved ones too.
        'filter': ['all'],
      },
    );
    switch (answer) {
      case Err(:final error):
        return Err(error);
      case Ok(value: (:final results, :final hasMore)):
        // Each title once, all together.
        final refs = {for (final issue in results) issue.ref}.toList();
        final names = Map.fromIterables(
          refs,
          await Future.wait(refs.map(_titleOf)),
        );
        return reading(
          () => ResultPage(
            items: [
              for (final issue in results)
                issueRecord(issue.record, title: names[issue.ref]!),
            ],
            page: page,
            hasMore: hasMore,
          ),
        );
    }
  }

  Future<String> _titleOf(DiscoveryRef ref) async {
    final answer = await readRecord(
      _api,
      '${wireName(ref.mediaType)}/${ref.tmdbId}',
      (object) => titleName(object, ref.mediaType),
    );
    return switch (answer) {
      Ok(:final value) => value,
      Err() => '',
    };
  }

  @override
  ServiceResult<Issue> issueDetail(int issueId) async {
    final answer = await readRecord(
      _api,
      'issue/$issueId',
      (object) => (record: object, ref: issueRef(object)),
    );
    switch (answer) {
      case Err(:final error):
        return Err(error);
      case Ok(value: (:final record, :final ref)):
        final title = await _titleOf(ref);
        return reading(
          () => issueRecord(record, title: title, withComments: true),
        );
    }
  }

  /// Without a [DiscoveryTitle.mediaId] or a message, nothing is sent and the
  /// result is [Validation].
  @override
  ServiceResult<Issue> reportIssue(
    DiscoveryTitle title,
    IssueType type,
    String message,
  ) async {
    final mediaId = title.mediaId;
    if (mediaId == null || message.trim().isEmpty) {
      return const Err(Validation([]));
    }
    final answer = await _api.write(
      HttpMethod.post,
      'issue',
      body: {
        'issueType': switch (type) {
          IssueType.video => 1,
          IssueType.audio => 2,
          IssueType.subtitles => 3,
          IssueType.other => 4,
        },
        'message': message,
        // The server's media record, not the TMDB id.
        'mediaId': mediaId,
      },
    );
    return switch (answer) {
      Err(:final error) => Err(error.failure),
      Ok(:final value) => decode(
        value,
        (object) => issueRecord(object, title: title.title, withComments: true),
      ),
    };
  }

  /// A blank [message] sends nothing and fails with [Validation].
  @override
  ServiceResult<void> comment(int issueId, String message) async {
    if (message.trim().isEmpty) return const Err(Validation([]));
    return _change(
      HttpMethod.post,
      'issue/$issueId/comment',
      body: {'message': message},
    );
  }

  /// [IssueStatus.unknown] cannot be set.
  @override
  ServiceResult<void> setIssueStatus(int issueId, IssueStatus status) async {
    final segment = switch (status) {
      IssueStatus.open => 'open',
      IssueStatus.resolved => 'resolved',
      IssueStatus.unknown => null,
    };
    if (segment == null) return const Err(Validation([]));
    return _change(HttpMethod.post, 'issue/$issueId/$segment');
  }

  @override
  ModuleRoute requestRoute(DiscoveryTitle title, {required bool is4k}) =>
      ModuleRoute(
        instanceId: _instanceId,
        path: titlePath(requestPattern, title),
        query: {'is4k': '$is4k'},
      );

  @override
  ModuleRoute requestsRoute() =>
      ModuleRoute(instanceId: _instanceId, path: requestsPattern);

  @override
  ModuleRoute issuesRoute() =>
      ModuleRoute(instanceId: _instanceId, path: issuesPattern);
}
