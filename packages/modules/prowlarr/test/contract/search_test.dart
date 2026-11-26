// Free-text search with category and indexer filters (story 11 scenario 1).

import 'dart:convert';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  group('request', () {
    test('asks for the term alone when nothing is filtered', () async {
      final harness = Harness();

      await succeed(harness.indexers.search('big buck bunny & friends'));

      final request = harness.server.requests.single;
      expect(asked(request), 'GET search');
      expect(request.query.keys, isNot(contains('categories')));
      expect(request.query.keys, isNot(contains('indexerIds')));
      // The client encodes it.
      expect(request.query['query'], ['big buck bunny & friends']);
      expect(request.body, isNull);
      // The server asks its indexers while the request is open.
      expect(request.timeout, const Duration(minutes: 2));
    });

    test('names each category and indexer on its own', () async {
      final harness = Harness();

      await succeed(
        harness.indexers.search(
          'sintel',
          categoryIds: {2000, 5000},
          indexerIds: {1, 2},
        ),
      );

      final query = harness.server.requests.single.query;
      expect(query['query'], ['sintel']);
      expect(query['categories'], unorderedEquals(['2000', '5000']));
      expect(query['indexerIds'], unorderedEquals(['1', '2']));
    });

    // The server would answer with its indexers' feeds.
    for (final term in ['', '   ']) {
      test('asks nothing for the blank term "$term"', () async {
        final harness = Harness();

        expect(
          await failureOf(harness.indexers.search(term, indexerIds: {1})),
          isA<Validation>(),
        );
        expect(harness.server.requests, isEmpty);
      });
    }
  });

  group('results', () {
    test('carry what the list shows and sorts by', () async {
      final wire = records(fixture('search'));

      final found = await succeed(Harness().indexers.search('sintel'));

      expect(found, hasLength(wire.length));
      for (final (index, release) in found.indexed) {
        final record = wire[index];
        expect(release.guid, record['guid']);
        expect(release.indexerId, record['indexerId']);
        expect(release.indexer, record['indexer']);
        expect(release.title, record['title']);
        expect(release.protocol.name, record['protocol']);
        expect(release.size, record['size']);
        expect(release.ageHours, record['ageHours']);
        expect(release.seeders, record['seeders']);
        expect(release.leechers, record['leechers']);
        // Prowlarr judges nothing and matches nothing.
        expect(release.quality, isNull);
        expect(release.rejections, isEmpty);
        expect(release.downloadAllowed, isTrue);
        expect(release.searchTarget, isEmpty);
        // Unknown fields are kept (module contract rule 6). Addresses are not
        // asked for here, as they carry keys.
        for (final field in ['sortTitle', 'indexerFlags', 'fileName']) {
          expect(release.rawJson[field], record[field], reason: field);
        }
      }
      expect(found.map((release) => release.protocol), [
        DownloadProtocol.torrent,
        DownloadProtocol.torrent,
        DownloadProtocol.usenet,
      ]);
      // Usenet has no peers.
      expect(found.last.seeders, isNull);
      expect(found.last.leechers, isNull);
    });

    test('may be none', () async {
      final harness = Harness()
        ..server.routes['GET search'] = jsonAnswer(<Object>[]);

      expect(await succeed(harness.indexers.search('nothing')), isEmpty);
    });

    test('need only a guid and an indexer', () async {
      final harness = Harness()
        ..server.routes['GET search'] = jsonAnswer([
          {'guid': 'g', 'indexerId': 1, 'protocol': 'carrierPigeon'},
        ]);

      final release = (await succeed(harness.indexers.search('a'))).single;

      expect(release.indexer, '');
      expect(release.title, '');
      expect(release.protocol, DownloadProtocol.unknown);
      expect(release.size, 0);
      expect(release.ageHours, 0);
      expect(release.seeders, isNull);
    });
  });

  group('failures', () {
    // What the server answers when every indexer asked for is unavailable.
    test('passes on the refusal, asking once', () async {
      const failure = Validation(['unavailable']);
      final harness = Harness()
        ..server.routes['GET search'] = failedAnswer(
          failure,
          status: 400,
          body: jsonEncode(fixture('search_unavailable')),
        );

      expect(await failureOf(harness.indexers.search('a')), same(failure));
      expect(harness.server.requests, hasLength(1));
    });

    for (final failure in <ServiceFailure>[
      const Unreachable(),
      const AuthFailed(),
      const ServerError(statusCode: 500),
    ]) {
      test('passes on ${failure.runtimeType}', () async {
        final harness = Harness()..server.down = failedAnswer(failure);

        expect(await failureOf(harness.indexers.search('a')), same(failure));
        expect(harness.server.requests, hasLength(1));
      });
    }

    final unreadable = <String, String>{
      'JSON that breaks off': '[{"guid":',
      'an object': '{}',
      'a release that is no object': '[1]',
      'a release without a guid': '[{"indexerId":1}]',
      'a release without an indexer': '[{"guid":"g"}]',
    };
    for (final MapEntry(key: name, value: body) in unreadable.entries) {
      test('cannot understand $name', () async {
        final harness = Harness()
          ..server.routes['GET search'] = textAnswer(body);

        expect(
          await failureOf(harness.indexers.search('a')),
          isA<MalformedResponse>(),
        );
      });
    }
  });
}
