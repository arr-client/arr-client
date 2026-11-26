/// Artwork of public hosts carries nothing of any instance (constitution III).
library;

import 'package:core/core.dart';
import 'package:core/src/network/remote_client.dart';
import 'package:flutter_test/flutter_test.dart';

import '../network/certificates.dart';
import '../network/support.dart';
import 'support.dart';

/// All that a request to a public host may carry.
const _plainHeaders = {
  'host',
  'user-agent',
  'accept-encoding',
  'content-length',
};

void main() {
  setUpImages();

  /// A loader of an instance whose client holds every kind of secret.
  ArtworkLoader loader({bool Function()? loadRemote}) =>
      cacheIn(temporaryDirectory(), loadRemote: loadRemote).loaderFor(
        'radarr-1',
        clientFor(settingsFor(Uri.parse('http://127.0.0.1:1'))),
      );

  void expectPlain(Received received) {
    expect(received.method, 'GET');
    expect(received.headers.keys.toSet().difference(_plainHeaders), isEmpty);
    for (final secret in secretValues) {
      expect('${received.target} ${received.headers}', isNot(contains(secret)));
    }
  }

  test('is read without credential, cookie or custom header', () async {
    final server = await pictureServer(twoPixels);

    final width = await widthOf(
      loader().image(remoteImage(server.url('/t/p/a.jpg?w=500'))),
    );

    expect(width, 2);
    expect(server.requests.single.target, '/t/p/a.jpg?w=500');
    expectPlain(server.requests.single);
  });

  /// Redirects `/poster` to [location] and answers anything else.
  Future<TestServer> redirecting(String location) => TestServer.start(
    (received, response) => received.target == '/poster'
        ? reply(
            response,
            status: 302,
            headers: {'location': location, 'set-cookie': 'track=1'},
          )
        : picture(response, threePixels),
  );

  test('follows a redirect within the origin, carrying nothing', () async {
    final server = await redirecting('/moved');

    final width = await widthOf(
      loader().image(remoteImage(server.url('/poster'))),
    );

    expect(width, 3);
    expect(server.requests.map((r) => r.target), ['/poster', '/moved']);
    server.requests.forEach(expectPlain);
  });

  for (final (name, location) in <(String, String Function(int port))>[
    ('port', (port) => 'http://127.0.0.1:$port/'),
    ('host', (port) => 'http://localhost:$port/'),
    ('host without a scheme', (port) => '//localhost:$port/'),
  ]) {
    test('does not follow a redirect to another $name', () async {
      final target = await RawServer.start();
      final server = await redirecting(location(target.port));

      await expectLater(
        widthOf(loader().image(remoteImage(server.url('/poster')))),
        throwsArtworkException,
      );
      await pause();
      expect(target.connections, 0);
      expect(server.requests, hasLength(1));
    });
  }

  test('gives up on a chain of redirects', () async {
    final server = await TestServer.start(
      (_, response) =>
          reply(response, status: 302, headers: {'location': '/again'}),
    );

    await expectLater(
      widthOf(loader().image(remoteImage(server.url('/poster')))),
      throwsArtworkException,
    );
    expect(server.requests, hasLength(6));
  });

  test('does not follow a redirect to a login in the address', () async {
    late final TestServer server;
    server = await TestServer.start(
      (_, response) => reply(
        response,
        status: 302,
        headers: {'location': 'http://a:b@127.0.0.1:${server.port}/x'},
      ),
    );

    await expectLater(
      widthOf(loader().image(remoteImage(server.url('/poster')))),
      throwsArtworkException,
    );
    await pause();
    expect(server.requests, hasLength(1));
  });

  group('a redirect', () {
    bool follows(String from, String to) =>
        followsRemoteRedirect(Uri.parse(from), Uri.parse(to));

    for (final (from, to) in [
      ('http://a.example/p', 'http://a.example/q'),
      ('https://a.example/p', 'https://A.example:443/q'),
      ('http://a.example/p', 'https://a.example/p'),
      ('http://a.example:80/p', 'https://a.example:443/p'),
    ]) {
      test('from $from to $to is followed', () {
        expect(follows(from, to), isTrue);
      });
    }

    for (final (from, to) in [
      ('https://a.example/p', 'http://a.example/p'),
      ('https://a.example/p', 'https://b.example/p'),
      ('https://a.example/p', 'https://img.a.example/p'),
      ('https://a.example/p', 'https://a.example:8443/p'),
      ('http://a.example/p', 'https://b.example/p'),
      ('http://a.example:8080/p', 'https://a.example/p'),
      ('http://a.example/p', 'https://a.example:8443/p'),
      ('http://a.example/p', 'http://192.168.1.1/p'),
      ('http://a.example/p', 'http://127.0.0.1/p'),
      ('http://a.example/p', 'http://[::1]/p'),
      ('https://a.example/p', 'https://10.0.0.1/p'),
      ('http://a.example/p', 'http://user@a.example/p'),
      ('http://a.example/p', 'file:///etc/hosts'),
    ]) {
      test('from $from to $to is not followed', () {
        expect(follows(from, to), isFalse);
      });
    }
  });

  for (final url in [
    'file:///data/poster.jpg',
    'ftp://example.org/poster.jpg',
    'http://user:password@example.org/poster.jpg',
    '/MediaCover/1/poster.jpg',
  ]) {
    test('$url is not loaded', () {
      expect(loader().image(remoteImage(Uri.parse(url))), isNull);
    });
  }

  test('sends nothing to an untrusted certificate', () async {
    final server = await TlsServer.start(
      TestCertificate.selfSigned.serverContext(),
    );

    await expectLater(
      widthOf(loader().image(remoteImage(server.url('/poster')))),
      throwsArtworkException,
    );
    await server.closedByClient();
    expect(server.bytes, isEmpty);
  });

  test('is not loaded when switched off', () {
    final provider = loader(loadRemote: () => false)
        .image(remoteImage(Uri.parse('https://image.tmdb.org/t/p/w500/a.jpg')));

    expect(provider, isNull);
  });

  test('is not asked for when switched off after the image was made', () async {
    final server = await RawServer.start();
    var allowed = true;
    final provider = loader(loadRemote: () => allowed)
        .image(remoteImage(server.url('/poster')));
    allowed = false;

    await expectLater(widthOf(provider), throwsArtworkException);
    await pause();
    expect(server.connections, 0);
  });

  test('an error does not quote the address', () async {
    final server = await TestServer.start(
      (_, response) => reply(response, status: 500),
    );

    await expectLater(
      widthOf(loader().image(remoteImage(server.url('/p?token=hidden')))),
      throwsA(
        predicate((Object e) => !'$e'.contains('hidden'), 'without address'),
      ),
    );
  });
}
