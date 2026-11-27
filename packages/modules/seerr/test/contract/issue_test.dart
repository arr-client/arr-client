// Reporting, reading, commenting and resolving issues (spec story 9, scenario
// 5). An issue is filed against the server's media record, `mediaInfo.id`
// (data-model DiscoveryTitle.mediaId).

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _film = DiscoveryRef(mediaType: DiscoveryMediaType.movie, tmdbId: 10331);

/// A server of [product] that also answers the title of the recorded issues.
FakeSeerr _server([Product product = Product.seerr]) =>
    FakeSeerr(product: product)
      ..set('GET api/v1/issue', ok(fixture('issues', product)))
      ..set(
        'GET api/v1/issue/${recorded('issue', product)['id']}',
        ok(fixture('issue', product)),
      )
      ..set('GET api/v1/movie/10331', ok(fixture('movie_requested', product)));

String _movieTitle(Product product) =>
    recorded('movie_requested', product)['title']! as String;

void _expectMatches(Issue issue, Map<String, Object?> wire) {
  final user = wire['createdBy']! as Map<String, Object?>;
  expect(issue.id, wire['id']);
  expect(issue.type, IssueType.video);
  expect(
    issue.status,
    wire['status'] == 1 ? IssueStatus.open : IssueStatus.resolved,
  );
  expect(issue.mediaRef, _film);
  expect(issue.createdBy.id, user['id']);
  expect(issue.createdBy.name, user['displayName']);
  expect(issue.createdAt, DateTime.parse(wire['createdAt']! as String));
}

void main() {
  group('issues', () {
    for (final product in Product.values) {
      test('lists those of ${product.label} with their titles', () async {
        final http = _server(product);

        final page = valueOf(await requests(http).issues());

        final query = http.reads('issue').single.query;
        expect(query['skip'], ['0']);
        expect(int.parse(query['take']!.single), greaterThan(0));
        // Resolved ones too, whatever the server shows unasked.
        expect(query['filter'], ['all']);
        final wire = results('issues', product);
        expect(page.items, hasLength(wire.length));
        _expectMatches(page.items.single, wire.single);
        // An issue names no title of its own.
        expect(page.items.single.title, _movieTitle(product));
        expect(page.hasMore, isFalse);
        expect(http.writes, isEmpty);
      });

      test('reads one of ${product.label} with its comments', () async {
        final wire = recorded('issue', product);

        final issue = valueOf(
          await requests(_server(product)).issueDetail(wire['id']! as int),
        );

        _expectMatches(issue, wire);
        expect(issue.title, _movieTitle(product));
        final comments = (wire['comments']! as List<Object?>)
            .cast<Map<String, Object?>>();
        expect(issue.comments, hasLength(comments.length));
        for (final (index, comment) in issue.comments.indexed) {
          final user = comments[index]['user']! as Map<String, Object?>;
          expect(comment.id, comments[index]['id']);
          expect(comment.message, comments[index]['message']);
          expect(comment.author.id, user['id']);
          expect(comment.author.name, user['displayName']);
          expect(
            comment.createdAt,
            DateTime.parse(comments[index]['createdAt']! as String),
          );
        }
      });
    }

    test('keeps the list when a title cannot be read', () async {
      final http = _server()
        ..set('GET api/v1/movie/10331', answered(500, '{"message":"x"}'));

      final page = valueOf(await requests(http).issues());

      expect(page.items.single.mediaRef, _film);
    });

    test('reads every type and status', () async {
      final first = results('issues').single;
      final http = _server()
        ..set(
          'GET api/v1/issue',
          json({
            ...recorded('issues'),
            'results': [
              for (final (index, type) in [1, 2, 3, 4, 99].indexed)
                {
                  ...first,
                  'id': index,
                  'issueType': type,
                  'status': index < 2 ? index + 1 : 99,
                },
            ],
          }),
        );

      final page = valueOf(await requests(http).issues());

      expect(page.items.map((issue) => issue.type), [
        IssueType.video,
        IssueType.audio,
        IssueType.subtitles,
        IssueType.other,
        IssueType.other,
      ]);
      expect(page.items.map((issue) => issue.status), [
        IssueStatus.open,
        IssueStatus.resolved,
        IssueStatus.unknown,
        IssueStatus.unknown,
        IssueStatus.unknown,
      ]);
    });

    test('reports one that is gone', () async {
      expect(
        failureOf(await requests(_server()).issueDetail(999)),
        isA<NotFound>(),
      );
    });
  });

  group('report', () {
    // Seerr answers 201, its predecessors 200.
    FakeSeerr server() =>
        _server()
          ..set('POST api/v1/issue', answered(201, fixture('issue_created')));

    final types = {
      IssueType.video: 1,
      IssueType.audio: 2,
      IssueType.subtitles: 3,
      IssueType.other: 4,
    };
    for (final MapEntry(key: type, value: number) in types.entries) {
      test('files a ${type.name} issue against the media record', () async {
        final http = server();

        final issue = valueOf(
          await requests(http).reportIssue(
            title(tmdbId: 10331, mediaId: 9),
            type,
            'The picture breaks up',
          ),
        );

        expect(sent(http.writes.single), {
          'issueType': number,
          'message': 'The picture breaks up',
          'mediaId': 9,
        });
        expect(issue.id, recorded('issue_created')['id']);
        expect(issue.mediaRef, _film);
      });
    }

    test('sends nothing for a title the server does not know', () async {
      final http = server();

      final result = await requests(http)
          .reportIssue(title(mediaId: null), IssueType.video, 'Broken');

      failureOf(result);
      expect(http.writes, isEmpty);
    });

    Future<ServiceFailure> refused(Answer answer) async {
      final http = _server()..set('POST api/v1/issue', answer);
      final failure = failureOf(
        await requests(http).reportIssue(title(), IssueType.other, 'Broken'),
      );
      expect(http.writes, hasLength(1));
      return failure;
    }

    test('reports a media record that is gone', () async {
      expect(
        await refused(answered(404, fixture('issue_unknown_media'))),
        isA<NotFound>(),
      );
    });

    test('reports a missing permission', () async {
      expect(await refused(answered(403, noPermission)), isA<Forbidden>());
    });
  });

  group('comment', () {
    test('adds one', () async {
      final http = _server()
        ..set('POST api/v1/issue/4/comment', ok(fixture('issue_comment')));

      expectOk(await requests(http).comment(4, 'Looking into it'));

      expect(http.writes.single.path, 'api/v1/issue/4/comment');
      expect(sent(http.writes.single), {'message': 'Looking into it'});
    });

    test('reports a missing permission', () async {
      final http = _server()
        ..set(
          'POST api/v1/issue/4/comment',
          answered(
            403,
            '{"message":"You do not have permission to comment on this '
            'issue."}',
          ),
        );

      expect(
        failureOf<void>(await requests(http).comment(4, 'x')),
        isA<Forbidden>(),
      );
    });
  });

  group('status', () {
    const states = {IssueStatus.resolved: 'resolved', IssueStatus.open: 'open'};
    for (final MapEntry(key: status, value: segment) in states.entries) {
      test('sets $segment', () async {
        final http = _server()
          ..set('POST api/v1/issue/4/$segment', ok(fixture('issue_resolved')));

        expectOk(await requests(http).setIssueStatus(4, status));

        expect(http.writes.single.path, 'api/v1/issue/4/$segment');
        expect(http.writes.single.body, isNull);
      });
    }

    test('sends nothing for a status the app does not know', () async {
      final http = _server();

      failureOf<void>(
        await requests(http).setIssueStatus(4, IssueStatus.unknown),
      );

      expect(http.writes, isEmpty);
    });

    // A 401 about one issue, not about the identity.
    test('reports a refused change as forbidden', () async {
      final http = _server()
        ..set(
          'POST api/v1/issue/4/resolved',
          answered(
            401,
            '{"message":"You do not have permission to modify this issue."}',
          ),
        );

      expect(
        failureOf<void>(
          await requests(http).setIssueStatus(4, IssueStatus.resolved),
        ),
        isA<Forbidden>(),
      );
    });
  });
}
