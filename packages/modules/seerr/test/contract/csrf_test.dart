// Writes to a server with CSRF protection, over HTTP and HTTPS (research R18).
// The server marks its cookies Secure but does not look at the transport.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

typedef _Write = ({
  String route,
  Answer Function() answer,
  Future<Result<Object?, ServiceFailure>> Function(RequestProvider) run,
});

Future<Result<Object?, ServiceFailure>> _done(
  Future<Result<void, ServiceFailure>> result,
) async => switch (await result) {
  Ok() => const Ok(null),
  Err(:final error) => Err(error),
};

/// Every write, with what a server answers to it.
final _writes = <String, _Write>{
  'request': (
    route: 'POST api/v1/request',
    answer: () => answered(201, fixture('request_created_movie')),
    run: (provider) => provider.request(title(), is4k: false),
  ),
  'approve': (
    route: 'POST api/v1/request/9/approve',
    answer: () => ok(fixture('approve')),
    run: (provider) => _done(provider.approve(9)),
  ),
  'decline': (
    route: 'POST api/v1/request/9/decline',
    answer: () => ok(fixture('decline')),
    run: (provider) => _done(provider.decline(9)),
  ),
  'retry': (
    route: 'POST api/v1/request/9/retry',
    answer: () => ok(fixture('retry')),
    run: (provider) => _done(provider.retry(9)),
  ),
  'delete': (
    route: 'DELETE api/v1/request/9',
    answer: () => answered(204, ''),
    run: (provider) => _done(provider.delete(9)),
  ),
  'report an issue': (
    route: 'POST api/v1/issue',
    answer: () => answered(201, fixture('issue_created')),
    run: (provider) => provider.reportIssue(title(), IssueType.video, 'Broken'),
  ),
  'comment': (
    route: 'POST api/v1/issue/4/comment',
    answer: () => ok(fixture('issue_comment')),
    run: (provider) => _done(provider.comment(4, 'More')),
  ),
  'resolve an issue': (
    route: 'POST api/v1/issue/4/resolved',
    answer: () => ok(fixture('issue_resolved')),
    run: (provider) => _done(provider.setIssueStatus(4, IssueStatus.resolved)),
  ),
};

FakeSeerr _server(_Write write, {required bool csrf}) => FakeSeerr(csrf: csrf)
  ..set(write.route, write.answer())
  // What the module may read to name the title of an issue.
  ..set('GET api/v1/movie/10331', ok(fixture('movie_requested')));

void main() {
  for (final scheme in ['http', 'https']) {
    group('over $scheme', () {
      // With an API key too: the instance here signs in with one.
      for (final MapEntry(key: name, value: write) in _writes.entries) {
        test('$name sends the token with its cookie', () async {
          final http = _server(write, csrf: true);
          final provider = requests(http, url: '$scheme://server.test/seerr');

          valueOf(await write.run(provider));

          expect(http.writes, hasLength(1));
          final request = http.writes.single;
          expect(header(request, 'x-xsrf-token'), csrfToken);
          expect(cookiesOf(header(request, 'cookie'))['_csrf'], csrfSecret);
        });
      }
    });
  }

  group('without protection', () {
    for (final MapEntry(key: name, value: write) in _writes.entries) {
      test('$name sends no token', () async {
        final http = _server(write, csrf: false);

        valueOf(await write.run(requests(http)));

        expect(http.writes, hasLength(1));
        expect(header(http.writes.single, 'x-xsrf-token'), isNull);
      });
    }
  });

  group('a server that still rejects the write', () {
    for (final MapEntry(key: name, value: write) in _writes.entries) {
      test('$name reports writes refused and does not repeat', () async {
        final http = _server(write, csrf: true)
          ..set(write.route, answered(403, fixture('csrf_refused')));

        expect(
          failureOf(await write.run(requests(http))),
          isA<WritesRefused>(),
        );
        expect(http.writes, hasLength(1));
      });
    }

    for (final product in Product.values) {
      test('is recognised on ${product.label}', () async {
        final http = FakeSeerr(product: product)
          ..set(
            'POST api/v1/request/9/approve',
            answered(403, fixture('csrf_refused', product)),
          );

        expect(
          failureOf<void>(await requests(http).approve(9)),
          isA<WritesRefused>(),
        );
      });
    }
  });

  test('a later write is accepted once protection is switched on', () async {
    final write = _writes['approve']!;
    final http = _server(write, csrf: false);
    final provider = requests(http);
    valueOf(await write.run(provider));

    http.csrf = true;
    final first = await write.run(provider);
    // The first may fail, but nothing remembered may keep the next one out.
    if (first is Err) valueOf(await write.run(provider));

    expect(header(http.writes.last, 'x-xsrf-token'), csrfToken);
  });
}
