// DownloadProgressProvider against recorded torrent lists (FR-030, spec story 7,
// data-model.md DownloadProgress).

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qbittorrent/qbittorrent_module.dart';

import 'support.dart';

// The sanitizer numbers the hashes it replaces.
String _hash(int n) => 'abcdef${'$n'.padLeft(34, '0')}';

Future<Result<List<DownloadProgress>, ServiceFailure>> _progress(
  FakeHttp http, {
  AuthKind authKind = AuthKind.userPassword,
}) => QbittorrentModule()
    .capability<DownloadProgressProvider>(context(http, authKind: authKind))!
    .progress();

/// A server whose torrent list is [answer].
FakeHttp _listing(Answer answer) =>
    FakeHttp.server('5.3.1', torrentList: answer);

/// The progress of the first recorded torrent with [changes] to its fields and
/// without the fields in [without].
Future<DownloadProgress> _one(
  Map<String, Object?> changes, {
  Set<String> without = const {},
}) async {
  final torrent = {...torrents('5.3.1').first, ...changes}
    ..removeWhere((key, _) => without.contains(key));
  return valueOf(await _progress(_listing(json([torrent])))).single;
}

Future<ServiceFailure> _failure(
  Answer answer, {
  AuthKind authKind = AuthKind.userPassword,
}) async => failureOf(await _progress(_listing(answer), authKind: authKind));

void main() {
  group('capability', () {
    final module = QbittorrentModule();

    test('offers download progress and nothing else', () {
      const probe = ProbeResult(product: 'qBittorrent', version: '5.3.1');

      expect(module.capabilitiesFor(probe, null), {
        CapabilityKind.downloadProgress,
      });
      expect(module.routes(), isEmpty);
    });

    test('is built without a request', () {
      final http = FakeHttp.server('5.3.1');
      final instance = context(http);

      expect(module.capability<DownloadProgressProvider>(instance), isNotNull);
      expect(module.capability<QueueProvider>(instance), isNull);
      expect(module.capability<LibraryProvider>(instance), isNull);
      expect(http.requests, isEmpty);
    });
  });

  group('request', () {
    for (final authKind in [AuthKind.apiKey, AuthKind.userPassword]) {
      test('is one read of every torrent, with ${authKind.name}', () async {
        final http = FakeHttp.server('5.3.1');

        valueOf(await _progress(http, authKind: authKind));

        final request = http.requests.single;
        expect(request.method, HttpMethod.get);
        expect(request.path, 'api/v2/torrents/info');
        expect(request.query, isEmpty);
        expect(request.headers, isEmpty);
        expect(request.body, isNull);
        expectNoOrigin(request);
      });
    }
  });

  group('recorded lists', () {
    for (final version in versions) {
      for (final name in ['torrents_info.json', 'torrents_info_queued.json']) {
        test('reads $version/$name', () async {
          final recorded = torrents(version, name);

          final result = valueOf(
            await _progress(
              _listing(ok(fixture(version, name), type: 'application/json')),
            ),
          );

          expect(
            result.map((torrent) => torrent.hash),
            recorded.map((torrent) => torrent['hash']),
          );
          for (final torrent in result) {
            expect(torrent.instanceId, 'i1');
            expect(torrent.progress, inInclusiveRange(0, 1));
            expect(torrent.downSpeed, 0);
            // All were recorded with 8640000, which means no estimate.
            expect(torrent.eta, isNull);
            expect(torrent.state, isNot(DownloadState.unknown));
          }
        });
      }
    }

    test('maps the states 4.4 recorded', () async {
      final result = valueOf(await _progress(FakeHttp.server('4.4.5')));
      final states = {for (final t in result) t.hash: t.state};

      expect(states[_hash(1)], DownloadState.stalled);
      expect(states[_hash(3)], DownloadState.paused);
      expect(states[_hash(5)], DownloadState.seeding);
    });

    test('maps the states 5.3 recorded', () async {
      final result = valueOf(
        await _progress(
          _listing(
            ok(
              fixture('5.3.1', 'torrents_info_queued.json'),
              type: 'application/json',
            ),
          ),
        ),
      );
      final states = {for (final t in result) t.hash: t.state};

      expect(states[_hash(1)], DownloadState.queued);
      expect(states[_hash(2)], DownloadState.paused);
      expect(states[_hash(3)], DownloadState.seeding);
      expect(states[_hash(4)], DownloadState.downloading);
    });
  });

  group('hashes', () {
    // A version 1 torrent has the same value in both fields.
    test('names one hash once', () async {
      final result = valueOf(await _progress(FakeHttp.server('5.3.1')));
      final first = result.first;

      expect(first.hash, _hash(1));
      expect(first.infohashV1, isNull);
    });

    // A hybrid torrent is listed under its version 2 hash; a library service
    // may know it by the version 1 hash.
    final hybrids = {'4.4.5': (6, 7), '5.3.1': (5, 6)};
    for (final MapEntry(key: version, value: (hash, v1)) in hybrids.entries) {
      test('keeps both hashes of a hybrid torrent on $version', () async {
        final result = valueOf(await _progress(FakeHttp.server(version)));

        final hybrid = result.singleWhere((t) => t.hash == _hash(hash));
        expect(hybrid.infohashV1, _hash(v1));
      });
    }

    test('has no version 1 hash for a version 2 torrent', () async {
      final torrent = await _one({'infohash_v1': ''});

      expect(torrent.infohashV1, isNull);
    });

    test('does without the version 1 field', () async {
      final torrent = await _one({}, without: {'infohash_v1'});

      expect(torrent.hash, _hash(1));
      expect(torrent.infohashV1, isNull);
    });
  });

  group('figures', () {
    // The recorded servers had no peers, so these are made up.
    test('reads the progress, speed and time remaining', () async {
      final torrent = await _one({
        'progress': 0.5273,
        'dlspeed': 1048576,
        'eta': 300,
        'state': 'downloading',
      });

      expect(torrent.progress, 0.5273);
      expect(torrent.downSpeed, 1048576);
      expect(torrent.eta, const Duration(seconds: 300));
      expect(torrent.state, DownloadState.downloading);
    });

    test('reads a whole number of progress', () async {
      expect((await _one({'progress': 1})).progress, 1.0);
    });

    test('keeps the progress within 0 to 1', () async {
      expect((await _one({'progress': 1.0000001})).progress, 1.0);
      expect((await _one({'progress': -0.1})).progress, 0.0);
    });

    test('has no estimate without the field', () async {
      expect((await _one({}, without: {'eta'})).eta, isNull);
    });

    // For a finished torrent, qBittorrent's eta is the time until it reaches
    // its seeding limit.
    test('has no estimate for a finished torrent', () async {
      final torrent = await _one({
        'progress': 1,
        'state': 'stalledUP',
        'eta': 3600,
      });

      expect(torrent.eta, isNull);
    });

    test('ignores fields it does not know', () async {
      final torrent = await _one({
        'someFutureField': {'a': 1},
      });

      expect(torrent.hash, _hash(1));
    });
  });

  group('states', () {
    // 5.0 renamed the paused states to stopped.
    final states = <String, Object>{
      'downloading': DownloadState.downloading,
      'forcedDL': DownloadState.downloading,
      'metaDL': anyOf(DownloadState.downloading, DownloadState.processing),
      'forcedMetaDL': anyOf(
        DownloadState.downloading,
        DownloadState.processing,
      ),
      'stalledDL': DownloadState.stalled,
      'queuedDL': DownloadState.queued,
      // Complete, and waiting for its turn to upload.
      'queuedUP': anyOf(DownloadState.queued, DownloadState.completed),
      'pausedDL': DownloadState.paused,
      'stoppedDL': DownloadState.paused,
      'pausedUP': DownloadState.completed,
      'stoppedUP': DownloadState.completed,
      'uploading': DownloadState.seeding,
      'forcedUP': DownloadState.seeding,
      'stalledUP': DownloadState.seeding,
      'checkingDL': DownloadState.checking,
      'checkingUP': DownloadState.checking,
      'checkingResumeData': DownloadState.checking,
      'allocating': DownloadState.processing,
      'moving': DownloadState.processing,
      'error': DownloadState.error,
      'missingFiles': DownloadState.error,
      'unknown': DownloadState.unknown,
      'someFutureState': DownloadState.unknown,
    };
    for (final MapEntry(key: wire, value: state) in states.entries) {
      test('maps $wire', () async {
        expect((await _one({'state': wire})).state, state);
      });
    }

    test('does not know a torrent without a state', () async {
      final torrent = await _one({}, without: {'state'});

      expect(torrent.state, DownloadState.unknown);
    });
  });

  group('answers', () {
    test('reads a client with no torrents', () async {
      final result = await _progress(_listing(json(<Object>[])));

      expect(valueOf(result), isEmpty);
    });

    final unreadable = {
      'an object': '{}',
      'a text': '"Ok."',
      'JSON that breaks off': '[{"hash":"abc',
      'a list of other things': '[1, 2]',
    };
    for (final MapEntry(key: name, value: body) in unreadable.entries) {
      test('cannot understand $name', () async {
        expect(
          await _failure(ok(body, type: 'application/json')),
          isA<MalformedResponse>(),
        );
      });
    }

    test('recognises a login page without a content type', () async {
      expect(
        await _failure(ok(loginPage, type: null)),
        isA<ProxyInterception>(),
      );
    });
  });

  group('failures', () {
    test('reports a rejected API key', () async {
      final failure = await _failure(
        error(const Forbidden(), status: 403, body: 'Forbidden'),
        authKind: AuthKind.apiKey,
      );

      expect(failure, isA<AuthFailed>());
    });

    test('names what a 401 may mean', () async {
      final failure = await _failure(
        error(const AuthFailed(), status: 401, body: 'Unauthorized'),
        authKind: AuthKind.apiKey,
      );

      expect(failure, isUnauthorized);
    });

    test('passes on a refusal of a signed-in account', () async {
      final failure = await _failure(
        error(const Forbidden(), status: 403, body: 'Forbidden'),
      );

      expect(failure, isA<Forbidden>());
    });

    for (final failure in <ServiceFailure>[
      const Unreachable(),
      const ServerError(statusCode: 500),
    ]) {
      test('passes on ${failure.runtimeType}', () async {
        expect(await _failure(error(failure)), same(failure));
      });
    }
  });
}
