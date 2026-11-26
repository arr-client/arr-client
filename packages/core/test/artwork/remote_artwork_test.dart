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

  test('follows redirects, still carrying nothing', () async {
    final target = await pictureServer(threePixels);
    final server = await TestServer.start(
      (_, response) => reply(
        response,
        status: 302,
        headers: {
          'location': '${target.url('/moved')}',
          'set-cookie': 'track=1',
        },
      ),
    );

    final width = await widthOf(
      loader().image(remoteImage(server.url('/poster'))),
    );

    expect(width, 3);
    expectPlain(server.requests.single);
    expectPlain(target.requests.single);
  });

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
    final target = await RawServer.start();
    final server = await TestServer.start(
      (_, response) => reply(
        response,
        status: 302,
        headers: {'location': 'http://a:b@127.0.0.1:${target.port}/'},
      ),
    );

    await expectLater(
      widthOf(loader().image(remoteImage(server.url('/poster')))),
      throwsArtworkException,
    );
    await pause();
    expect(target.connections, 0);
  });

  test('which redirects are followed', () {
    final https = Uri.parse('https://a.example/p');
    final http = Uri.parse('http://a.example/p');
    expect(followsRemoteRedirect(http, https), isTrue);
    expect(
      followsRemoteRedirect(https, Uri.parse('https://b.example')),
      isTrue,
    );
    expect(followsRemoteRedirect(https, http), isFalse);
    expect(followsRemoteRedirect(http, Uri.parse('file:///etc/x')), isFalse);
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
