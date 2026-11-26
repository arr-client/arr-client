// The indexers with their status (story 11 scenario 3), read only, and the
// categories to filter a search by (scenario 1).

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Matcher _moment(Object? wire) => isA<DateTime>().having(
  (time) => time.isAtSameMomentAs(DateTime.parse(wire! as String)),
  'is the recorded moment',
  isTrue,
);

void main() {
  group('indexers', () {
    test('reads the indexers and their status', () async {
      final harness = Harness();

      await succeed(harness.indexers.indexers());

      expect(
        harness.server.sent,
        unorderedEquals(['GET indexer', 'GET indexerstatus']),
      );
      for (final request in harness.server.requests) {
        expect(request.query, isEmpty);
        expect(request.body, isNull);
      }
    });

    test('lists them as the server does, with recent failures', () async {
      final wire = records(fixture('indexer'));
      final status = records(fixture('indexerstatus')).single;
      expect(status['indexerId'], 2);

      final found = await succeed(Harness().indexers.indexers());

      expect(found.map((indexer) => indexer.id), [2, 1]);
      expect(
        found.map((indexer) => indexer.name),
        wire.map((record) => record['name']),
      );
      expect(found.map((indexer) => indexer.protocol), [
        DownloadProtocol.usenet,
        DownloadProtocol.torrent,
      ]);
      expect(found.map((indexer) => indexer.enabled), [true, true]);
      expect(found[0].failureUntil, _moment(status['disabledTill']));
      expect(found[0].lastFailure, _moment(status['mostRecentFailure']));
      // The server has a status only for what failed.
      expect(found[1].failureUntil, isNull);
      expect(found[1].lastFailure, isNull);
    });

    test('shows a disabled one, and a protocol it does not know', () async {
      final wire = records(fixture('indexer'));
      wire[0]['enable'] = false;
      wire[1]['protocol'] = 'carrierPigeon';
      final harness = Harness()
        ..server.routes['GET indexer'] = jsonAnswer(wire);

      final found = await succeed(harness.indexers.indexers());

      expect(found[0].enabled, isFalse);
      expect(found[1].protocol, DownloadProtocol.unknown);
    });

    test('copes with a status without times, or of no indexer', () async {
      final harness = Harness()
        ..server.routes['GET indexerstatus'] = jsonAnswer([
          {'indexerId': 2},
          {'indexerId': 99, 'disabledTill': '2026-11-26T00:00:00Z'},
        ]);

      final found = await succeed(harness.indexers.indexers());

      expect(found, hasLength(2));
      for (final indexer in found) {
        expect(indexer.failureUntil, isNull);
        expect(indexer.lastFailure, isNull);
      }
    });

    test('lists none where there is none', () async {
      final harness = Harness()
        ..server.routes['GET indexer'] = jsonAnswer(<Object>[])
        ..server.routes['GET indexerstatus'] = jsonAnswer(<Object>[]);

      expect(await succeed(harness.indexers.indexers()), isEmpty);
    });

    for (final route in ['GET indexer', 'GET indexerstatus']) {
      test('passes on a failure of $route', () async {
        const failure = ServerError(statusCode: 500);
        final harness = Harness()
          ..server.routes[route] = failedAnswer(failure, status: 500);

        expect(await failureOf(harness.indexers.indexers()), same(failure));
        expect(harness.server.sent.where((sent) => sent == route), [route]);
      });

      test('cannot understand an answer to $route that is no list', () async {
        final harness = Harness()
          ..server.routes[route] = jsonAnswer(<String, Object?>{});

        expect(
          await failureOf(harness.indexers.indexers()),
          isA<MalformedResponse>(),
        );
      });
    }

    for (final field in ['id', 'name']) {
      test('cannot understand an indexer without its $field', () async {
        final wire = records(fixture('indexer'));
        wire.first.remove(field);
        final harness = Harness()
          ..server.routes['GET indexer'] = jsonAnswer(wire);

        expect(
          await failureOf(harness.indexers.indexers()),
          isA<MalformedResponse>(),
        );
      });
    }
  });

  group('categories', () {
    test('lists every category, each followed by its subcategories', () async {
      final harness = Harness();

      final found = await succeed(harness.indexers.categories());

      final wire = [
        for (final parent in records(fixture('indexer_categories'))) ...[
          parent,
          ...records(parent['subCategories']),
        ],
      ];
      expect(
        found.map((category) => (category.id, category.name)),
        wire.map((record) => (record['id'], record['name'])),
      );
      expect(found.map((c) => (c.id, c.name)), contains((2000, 'Movies')));
      expect(found.map((c) => (c.id, c.name)), contains((2040, 'Movies/HD')));
      final request = harness.server.requests.single;
      expect(asked(request), 'GET indexer/categories');
      expect(request.query, isEmpty);
      expect(request.body, isNull);
    });

    test('passes on a failure, asking once', () async {
      const failure = Unreachable();
      final harness = Harness()..server.down = failedAnswer(failure);

      expect(await failureOf(harness.indexers.categories()), same(failure));
      expect(harness.server.requests, hasLength(1));
    });

    test('cannot understand an answer that is no list', () async {
      final harness = Harness()
        ..server.routes['GET indexer/categories'] = textAnswer('{"id":');

      expect(
        await failureOf(harness.indexers.categories()),
        isA<MalformedResponse>(),
      );
    });
  });
}
