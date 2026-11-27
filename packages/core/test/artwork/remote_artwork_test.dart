/// Artwork of public hosts carries nothing of any instance (constitution III).
library;

import 'dart:async';
import 'dart:io';

import 'package:core/core.dart';
import 'package:core/src/network/remote_client.dart';
import 'package:flutter/painting.dart';
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
    ('port', (port) => 'http://127.0.0.1:$port/image'),
    ('host', (port) => 'http://localhost:$port/image'),
    ('host without a scheme', (port) => '//localhost:$port/image'),
  ]) {
    test('follows a redirect to another $name, carrying nothing', () async {
      final target = await pictureServer(threePixels);
      final server = await redirecting(location(target.port));

      final width = await widthOf(
        loader().image(remoteImage(server.url('/poster'))),
      );

      expect(width, 3);
      expect(target.requests.single.target, '/image');
      expectPlain(server.requests.single);
      expectPlain(target.requests.single);
    });
  }

  test('carries nothing across hosts and back again', () async {
    late final TestServer first;
    final second = await TestServer.start(
      (_, response) => reply(
        response,
        status: 307,
        headers: {
          'location': '${first.url('/back')}',
          'set-cookie': 'other=1',
          'www-authenticate': 'Basic realm="x"',
        },
      ),
    );
    first = await TestServer.start(
      (received, response) => received.target == '/poster'
          ? reply(
              response,
              status: 302,
              headers: {
                'location': 'http://localhost:${second.port}/over',
                'set-cookie': 'track=1',
              },
            )
          : picture(response, threePixels),
    );

    final width = await widthOf(
      loader().image(remoteImage(first.url('/poster'))),
    );

    expect(width, 3);
    expect(first.requests.map((r) => r.target), ['/poster', '/back']);
    expect(second.requests.map((r) => r.target), ['/over']);
    [...first.requests, ...second.requests].forEach(expectPlain);
  });

  test('takes nothing but a picture from where it is led', () async {
    final target = await TestServer.start(
      (_, response) =>
          reply(response, body: '<html>', contentType: 'image/png'),
    );
    final server = await redirecting('${target.url('/page')}');
    final directory = temporaryDirectory();
    final artwork = cacheIn(directory).loaderFor(
      'radarr-1',
      clientFor(settingsFor(Uri.parse('http://127.0.0.1:1'))),
    );

    await expectLater(
      widthOf(artwork.image(remoteImage(server.url('/poster')))),
      throwsArtworkException,
    );
    expect(target.requests, hasLength(1));
    expect(
      filesIn(directory).keys.where((name) => name.endsWith('.img')),
      isEmpty,
    );
  });

  /// A client for which `localhost` is local and `127.0.0.1` public.
  RemoteClient split({int maximumBytes = 1024}) {
    final client = RemoteClient(
      maximumBytes: maximumBytes,
      isLocal: (host) async => host == 'localhost',
    );
    addTearDown(client.close);
    return client;
  }

  test('is not led from a public host to a local one', () async {
    final local = await RawServer.start();
    final server = await redirecting('http://localhost:${local.port}/admin');

    await expectLater(
      split().get(server.url('/poster'), allowed: () => true),
      throwsA(isA<HttpException>()),
    );
    await pause();
    expect(local.connections, 0);
  });

  test('may be led from a local host to a public and a local one', () async {
    final target = await pictureServer(onePixel);
    final outward = await redirecting('${target.url('/image')}');
    final within = await redirecting('http://localhost:${target.port}/image');

    // The first starts at a local name, the second also ends at one.
    for (final start in [outward, within]) {
      final answer = await split().get(
        Uri.parse('http://localhost:${start.port}/poster'),
        allowed: () => true,
      );

      expect(answer.bytes, onePixel);
    }
  });

  test('looks nothing up once switched off during a redirect', () async {
    var allowed = true;
    final looked = <String>[];
    final server = await TestServer.start((_, response) {
      allowed = false;
      return reply(
        response,
        status: 302,
        headers: {'location': 'http://image.invalid/a'},
      );
    });
    final client = RemoteClient(
      isLocal: (host) async {
        looked.add(host);
        return false;
      },
    );
    addTearDown(client.close);

    await expectLater(
      client.get(server.url('/poster'), allowed: () => allowed),
      throwsA(isA<HttpException>()),
    );
    expect(looked, isEmpty);
  });

  test('gives up on an answer that is too large after a redirect', () async {
    final target = await TestServer.start(
      (_, response) => reply(response, body: 'x' * 2000),
    );
    final server = await redirecting('${target.url('/large')}');

    await expectLater(
      split().get(server.url('/poster'), allowed: () => true),
      throwsA(
        isA<HttpException>().having(
          (e) => e.message,
          'message',
          'Answer too large',
        ),
      ),
    );
    expect(target.requests, hasLength(1));
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

  test('counts the redirects across hosts', () async {
    late final TestServer server;
    server = await TestServer.start((received, response) {
      final host = server.requests.length.isOdd ? 'localhost' : '127.0.0.1';
      return reply(
        response,
        status: 302,
        headers: {'location': 'http://$host:${server.port}/again'},
      );
    });

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
      ('http://a.example/p', 'https://a.example/p'),
      ('https://a.example/p', 'https://b.example/p'),
      ('https://a.example/p', 'https://a.example:8443/p'),
      ('http://a.example/p', 'https://b.example/p'),
      ('http://a.example/p', 'http://b.example:8080/p'),
    ]) {
      test('from $from to $to is followed', () {
        expect(follows(from, to), isTrue);
      });
    }

    for (final (from, to) in [
      ('https://a.example/p', 'http://a.example/p'),
      ('https://a.example/p', 'http://b.example/p'),
      ('http://a.example/p', 'http://user@b.example/p'),
      ('http://a.example/p', 'file:///etc/hosts'),
      ('http://a.example/p', 'ftp://b.example/p'),
    ]) {
      test('from $from to $to is not followed', () {
        expect(follows(from, to), isFalse);
      });
    }
  });

  // Addresses and names that need no name server.
  group('as a host', () {
    for (final host in [
      'localhost',
      'LOCALHOST.',
      'nas.local',
      '0.0.0.0',
      '10.1.2.3',
      '100.64.0.1',
      '127.0.0.1',
      '169.254.1.1',
      '172.16.0.1',
      '172.31.255.255',
      '192.168.1.1',
      '224.0.0.1',
      '255.255.255.255',
      '::',
      '::1',
      'fc00::1',
      'fd12:3456::1',
      'fe80::1%wlan0',
      'ff02::1',
      '::ffff:192.168.1.1',
    ]) {
      test('$host is local', () async {
        expect(await isLocalHost(host), isTrue);
      });
    }

    for (final host in [
      '1.1.1.1',
      '100.63.0.1',
      '100.128.0.1',
      '172.15.0.1',
      '172.32.0.1',
      '192.169.0.1',
      '2606:4700::1111',
      '::ffff:1.1.1.1',
    ]) {
      test('$host is public', () async {
        expect(await isLocalHost(host), isFalse);
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

  test(
    'a redirect answered after it was switched off is not followed',
    () async {
      final asked = Completer<void>();
      final answer = Completer<void>();
      final other = await RawServer.start();
      final server = await TestServer.start((_, response) async {
        asked.complete();
        await answer.future;
        await reply(
          response,
          status: 302,
          headers: {'location': 'http://localhost:${other.port}/moved'},
        );
      });
      var allowed = true;
      final loaded = expectLater(
        widthOf(
          loader(loadRemote: () => allowed)
              .image(remoteImage(server.url('/poster'))),
        ),
        throwsArtworkException,
      );
      await asked.future;
      allowed = false;
      answer.complete();

      await loaded;
      await pause();
      expect(server.requests.map((r) => r.target), ['/poster']);
      expect(other.connections, 0);
    },
  );

  test('what was saved of it is not shown while switched off', () async {
    final server = await pictureServer(twoPixels);
    var allowed = true;
    final artwork = loader(loadRemote: () => allowed);
    final poster = remoteImage(server.url('/poster'));
    final made = artwork.image(poster)!;
    expect(await widthOf(made), 2);
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    allowed = false;

    expect(artwork.image(poster), isNull);
    // Nor by an image made while it was on.
    await expectLater(widthOf(made), throwsArtworkException);

    // It is kept: switched on again, nothing is asked for.
    await pause();
    allowed = true;
    expect(await widthOf(artwork.image(poster)), 2);
    expect(server.requests, hasLength(1));
  });

  test("switched off leaves the instance's own artwork alone", () async {
    final server = await pictureServer(onePixel);
    final artwork = cacheIn(
      temporaryDirectory(),
      loadRemote: () => false,
    ).loaderFor('radarr-1', clientFor(settingsFor(server.url('/'))));

    final width = await widthOf(
      artwork.image(
        instanceImage(
          'poster.png',
          remoteUrl: Uri.parse('https://images.invalid/poster.png'),
        ),
      ),
    );

    expect(width, 1);
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
