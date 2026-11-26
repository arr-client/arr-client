// Editing a series and several at once (story 5, scenarios 5, 7 and 8; research
// R13). The shared client's tests cover the merge; these cover what Sonarr is
// asked.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'manage_support.dart';
import 'support.dart';

/// The recorded series 1 with what no version of the app can know about.
Map<String, Object?> _series() => record('manage_series')
  ..['someFutureObject'] = {
    'list': [1, null, 'kept'],
  }
  ..['someFutureNull'] = null;

ManageHarness _harness() => ManageHarness()..sonarr.item = _series();

/// Each field of Sonarr's edit form, and what it writes.
const _fields = <String, (ItemEdit, Map<String, Object?>)>{
  'monitoring': (ItemEdit(monitored: false), {'monitored': false}),
  'the quality profile': (
    ItemEdit(qualityProfileId: 6),
    {'qualityProfileId': 6},
  ),
  'tags': (
    ItemEdit(tagIds: {2}),
    {
      'tags': [2],
    },
  ),
  'no tags': (ItemEdit(tagIds: {}), {'tags': <int>[]}),
  'the series type': (
    ItemEdit(seriesType: SeriesType.anime),
    {'seriesType': 'anime'},
  ),
  'season folders': (ItemEdit(seasonFolder: false), {'seasonFolder': false}),
};

/// Bulk changes, and what each sends beside the ids.
const _bulk = <String, (BulkEdit, Map<String, Object?>)>{
  'monitoring': (BulkEdit(monitored: false), {'monitored': false}),
  'the quality profile': (
    BulkEdit(qualityProfileId: 6),
    {'qualityProfileId': 6},
  ),
  'added tags': (
    BulkEdit(tagIds: {2}),
    {
      'tags': [2],
      'applyTags': 'add',
    },
  ),
  'removed tags': (
    BulkEdit(tagIds: {2}, tagChange: TagChange.remove),
    {
      'tags': [2],
      'applyTags': 'remove',
    },
  ),
  'replaced tags': (
    BulkEdit(tagIds: {}, tagChange: TagChange.replace),
    {'tags': <int>[], 'applyTags': 'replace'},
  ),
};

void main() {
  group('edit', () {
    for (final MapEntry(key: name, value: (changes, changed))
        in _fields.entries) {
      test('of $name writes the series with nothing else changed', () async {
        final harness = _harness();

        await ok(harness.library.edit(seriesRef(1), changes));

        expect(harness.asked, [
          line(HttpMethod.get, 'series/1'),
          line(HttpMethod.put, 'series/1'),
        ]);
        // Never `moveFiles`.
        for (final request in harness.sonarr.requests) {
          expect(request.query, isEmpty);
        }
        expect(sentBody(harness.sonarr.requests.last), {
          ..._series(),
          ...changed,
        });
      });
    }

    test('applies to the series as the server has it now', () async {
      final harness = _harness();
      await ok(harness.library.item(seriesRef(1)));
      // Changed elsewhere since it was displayed.
      harness.sonarr.item
        ..['monitored'] = false
        ..['tags'] = [2];
      harness.sonarr.requests.clear();

      await ok(
        harness.library.edit(seriesRef(1), const ItemEdit(qualityProfileId: 6)),
      );

      expect(sentBody(harness.sonarr.requests.last), {
        ..._series(),
        'monitored': false,
        'tags': [2],
        'qualityProfileId': 6,
      });
    });

    for (final (name, changes) in const [
      ('nothing', ItemEdit()),
      (
        'a series type it does not know',
        ItemEdit(seriesType: SeriesType.unknown),
      ),
      (
        'fields a series does not have',
        ItemEdit(
          minimumAvailability: MinimumAvailability.released,
          metadataProfileId: 1,
        ),
      ),
    ]) {
      test('of $name sends nothing', () async {
        final harness = _harness();

        await ok(harness.library.edit(seriesRef(1), changes));

        expect(harness.sonarr.requests, isEmpty);
      });
    }

    for (final (name, ref) in [
      ('an episode', episodeRef(1)),
      ('a movie', movie.item),
      ('a series of another instance', elsewhere),
    ]) {
      test('of $name sends nothing', () async {
        final harness = _harness();

        await expectProgrammingError(
          () => harness.library.edit(ref, const ItemEdit(monitored: false)),
        );

        expect(harness.sonarr.requests, isEmpty);
      });
    }

    for (final MapEntry(key: cause, value: (answer, expected))
        in writeFailures.entries) {
      test('reports $cause of the write, which is sent once', () async {
        final harness = _harness()..sonarr.writeAnswer = answer;

        final failure = await failureOf(
          harness.library.edit(
            seriesRef(1),
            const ItemEdit(qualityProfileId: 999),
          ),
        );

        expect(failure.runtimeType, expected);
        expect(harness.asked, [
          line(HttpMethod.get, 'series/1'),
          line(HttpMethod.put, 'series/1'),
        ]);
      });
    }

    for (final MapEntry(key: cause, value: (answer, expected))
        in transportFailures.entries) {
      test('writes nothing when the read meets $cause', () async {
        final harness = _harness()..sonarr.always = answer;

        final failure = await failureOf(
          harness.library.edit(seriesRef(1), const ItemEdit(monitored: false)),
        );

        expect(failure.runtimeType, expected);
        expect(harness.asked, [line(HttpMethod.get, 'series/1')]);
      });
    }

    test('of a series that is gone says so and forgets it', () async {
      final harness = _harness();
      await ok(harness.library.list());
      harness.sonarr.requests.clear();
      harness.sonarr.overrides['series/1'] = FakeSonarr.body('', status: 404);

      expect(
        await failureOf(
          harness.library.edit(seriesRef(1), const ItemEdit(monitored: false)),
        ),
        isA<NotFound>(),
      );

      expect(harness.asked, [line(HttpMethod.get, 'series/1')]);
      expect(await harness.cachedSeries(), isNot(contains(1)));
    });
  });

  group('bulk edit', () {
    for (final MapEntry(key: name, value: (changes, sent)) in _bulk.entries) {
      test('of $name sends the ids and that alone', () async {
        final harness = ManageHarness();

        await ok(
          harness.library.bulkEdit([seriesRef(4), seriesRef(1)], changes),
        );

        final request = harness.sonarr.requests.single;
        expect(request.method, HttpMethod.put);
        expect(request.path, 'api/v3/series/editor');
        expect(request.query, isEmpty);
        expect(sentBody(request), {
          'seriesIds': [4, 1],
          ...sent,
        });
      });
    }

    for (final (name, refs, changes) in [
      ('no series', <ItemRef>[], const BulkEdit(monitored: false)),
      ('no change', [seriesRef(1)], const BulkEdit()),
      ('no tag to add', [seriesRef(1)], const BulkEdit(tagIds: {})),
    ]) {
      test('of $name sends nothing', () async {
        final harness = ManageHarness();

        await ok(harness.library.bulkEdit(refs, changes));

        expect(harness.sonarr.requests, isEmpty);
      });
    }

    // An episode's id would name some other series.
    for (final (name, other) in [
      ('an episode', episodeRef(4)),
      ('a movie', movie.item),
      ('a series of another instance', elsewhere),
    ]) {
      test('with $name among the series sends nothing', () async {
        final harness = ManageHarness();

        await expectProgrammingError(
          () => harness.library.bulkEdit([
            seriesRef(1),
            other,
          ], const BulkEdit(monitored: false)),
        );

        expect(harness.sonarr.requests, isEmpty);
      });
    }

    for (final MapEntry(key: cause, value: (answer, expected)) in {
      ...writeFailures,
      // As recorded; no series of the request was changed.
      'a series that is gone': (
        FakeSonarr.body(
          '{"message":"Expected query to return 2 rows but returned 1"}',
          status: 500,
          write: true,
        ),
        ServerError,
      ),
    }.entries) {
      test('reports $cause and is sent once', () async {
        final harness = ManageHarness()..sonarr.writeAnswer = answer;

        final failure = await failureOf(
          harness.library.bulkEdit([
            seriesRef(1),
            seriesRef(4),
          ], const BulkEdit(monitored: false)),
        );

        expect(failure.runtimeType, expected);
        expect(harness.asked, [line(HttpMethod.put, 'series/editor')]);
      });
    }
  });
}
