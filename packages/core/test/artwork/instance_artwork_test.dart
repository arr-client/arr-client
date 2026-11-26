/// An instance's own artwork goes through its client (research R10).
library;

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../network/certificates.dart';
import '../network/support.dart';
import 'support.dart';

void main() {
  setUpImages();

  ArtworkLoader loaderFor(ConnectionSettings settings) =>
      cacheIn(temporaryDirectory()).loaderFor('radarr-1', clientFor(settings));

  test('is read under the address with the credential and query', () async {
    final server = await pictureServer(twoPixels);
    final loader = loaderFor(settingsFor(server.url('/radarr')));

    final width = await widthOf(
      loader.image(
        instanceImage('/api/v3/mediacover/1/a%20poster.jpg?lastWrite=63%2B1&x'),
      ),
    );

    expect(width, 2);
    final received = server.requests.single;
    expect(
      received.target,
      '/radarr/api/v3/mediacover/1/a%20poster.jpg?lastWrite=63%2B1&x=',
    );
    expect(received.headers['x-api-key'], apiKey);
    expect(received.headers['authorization'], basicHeader);
    expect(received.headers['x-proxy-id'], customValue);
    expect(received.headers['cookie'], sessionCookie);
  });

  test('follows a redirect within the origin', () async {
    final server = await TestServer.start(
      (received, response) => received.target == '/poster'
          ? reply(response, status: 302, headers: {'location': '/moved'})
          : picture(response, onePixel),
    );
    final loader = loaderFor(settingsFor(server.url()));

    expect(await widthOf(loader.image(instanceImage('poster'))), 1);
    expect(server.requests.map((r) => r.target), ['/poster', '/moved']);
  });

  test('does not follow a redirect to another origin', () async {
    final other = await RawServer.start();
    final server = await TestServer.start(
      (_, response) => reply(
        response,
        status: 302,
        headers: {'location': '${other.url('/steal')}'},
      ),
    );
    final loader = loaderFor(settingsFor(server.url()));

    await expectLater(
      widthOf(loader.image(instanceImage('poster'))),
      throwsArtworkException,
    );
    await pause();
    expect(other.connections, 0);
  });

  test('sends nothing to a certificate that does not match the pin', () async {
    final server = await TlsServer.start(
      TestCertificate.selfSigned.serverContext(),
    );
    final loader = loaderFor(
      settingsFor(
        server.url(),
        certPin: TestCertificate.selfSignedOther.sha256,
      ),
    );

    await expectLater(
      widthOf(loader.image(instanceImage('poster'))),
      throwsA(
        isA<ArtworkException>().having(
          (e) => e.reason,
          'reason',
          'CertificateChanged',
        ),
      ),
    );
    await server.closedByClient();
    expect(server.bytes, isEmpty);
  });

  test('is read from a server with the pinned certificate', () async {
    // A body of ASCII, as the server writes its answer as latin-1.
    final server = await TlsServer.start(
      TestCertificate.selfSigned.serverContext(),
    );
    final loader = loaderFor(
      settingsFor(server.url(), certPin: TestCertificate.selfSigned.sha256),
    );

    // Answered `{}`, which is no picture.
    await expectLater(
      widthOf(loader.image(instanceImage('poster'))),
      throwsA(anything),
    );

    expect(server.received, startsWith('GET /poster HTTP/1.1'));
    expect(server.received, contains(apiKey));
  });

  test('a path that looks like a host stays on the instance', () async {
    final server = await pictureServer(onePixel);
    final loader = loaderFor(settingsFor(server.url('/base')));

    expect(
      await widthOf(loader.image(instanceImage('//elsewhere.example/x'))),
      1,
    );

    expect(server.requests.single.target, '/base/elsewhere.example/x');
  });

  for (final path in [
    '',
    '/',
    '?h=1',
    'http://elsewhere/poster',
    '//elsewhere.example:80/poster',
    '../poster',
    '%2e%2e/poster',
    'a%2Fb',
    r'a\b',
    'broken%zz',
    'a%ff',
    'a%C3',
    'poster?h=%ff',
    'poster?%ff=1',
  ]) {
    test('"$path" is no path to load', () {
      final loader = loaderFor(settingsFor(Uri.parse('http://127.0.0.1:1')));

      expect(loader.image(instanceImage(path)), isNull);
    });
  }

  test('an unusable path leaves the remote address', () async {
    final remote = await pictureServer(threePixels);
    final loader = loaderFor(settingsFor(Uri.parse('http://127.0.0.1:1')));

    final width = await widthOf(
      loader.image(instanceImage('../x', remoteUrl: remote.url('/p'))),
    );

    expect(width, 3);
  });

  test('is preferred to the remote address, even when it fails', () async {
    final server = await TestServer.start(
      (_, response) => reply(response, status: 500),
    );
    final remote = await RawServer.start();
    final loader = loaderFor(settingsFor(server.url()));

    await expectLater(
      widthOf(
        loader.image(instanceImage('poster', remoteUrl: remote.url('/p'))),
      ),
      throwsArtworkException,
    );
    await pause();
    expect(remote.connections, 0);
  });
}
