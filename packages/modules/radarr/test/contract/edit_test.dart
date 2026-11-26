// Monitoring, edits and bulk edits of movies (story 5, scenarios 1, 5, 7 and 8).
// An edit reads the movie and writes the whole of it back, so that what the user
// did not change stays as the server has it (research R13).

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'library_support.dart';
import 'manage_support.dart';

/// The recorded movie with what no version of the app can know about.
Map<String, Object?> _movie() => manageObject('manage_movie')
  ..['someFutureFlag'] = true
  ..['someFutureObject'] = {
    'list': [
      1,
      null,
      {'deep': 'kept'},
    ],
  }
  // Left out is not the same to every server as null.
  ..['someFutureNull'] = null;

/// A Radarr that has [movie] and takes a write of it, as recorded: with 202.
ManageHarness _harness([Map<String, Object?>? movie]) {
  final harness = ManageHarness();
  harness.radarr.routes['GET movie/1'] = replyJson(movie ?? _movie());
  harness.radarr.routes['PUT movie/1'] = replyJson(
    movie ?? _movie(),
    status: 202,
  );
  return harness;
}

/// Asserts that the movie was read and then written back with [changed] and
/// nothing else.
void _expectWritten(
  ManageHarness harness,
  Map<String, Object?> changed, [
  Map<String, Object?>? movie,
]) {
  expect(harness.sent, ['GET movie/1', 'PUT movie/1']);
  final [read, write] = harness.server.requests;
  expect(read.query, isEmpty);
  // `moveFiles` among others is never asked for.
  expect(write.query, isEmpty);
  expect(sentBody(write), {...movie ?? _movie(), ...changed});
}

/// Each way to change one movie.
final _changes = <String, ServiceResult<void> Function(ManageHarness, ItemRef)>{
  'monitoring': (harness, ref) =>
      harness.library.setMonitored(MediaTarget(ref), false),
  'an edit': (harness, ref) =>
      harness.library.edit(ref, const ItemEdit(qualityProfileId: 6)),
};

ServiceResult<void> _bulk(
  ManageHarness harness,
  BulkEdit changes, [
  List<ItemRef>? refs,
]) => harness.library.bulkEdit(refs ?? [movieRef(2), movieRef(3)], changes);

/// A Radarr whose editor answers, as recorded, with the movies.
ManageHarness _editor() {
  final harness = ManageHarness();
  harness.radarr.routes['PUT movie/editor'] = replyJson([_movie()]);
  return harness;
}

/// What a bulk edit of movies 2 and 3 sends.
Future<Object?> _edited(BulkEdit changes) async {
  final harness = _editor();
  await succeed(_bulk(harness, changes));
  expect(harness.sent, ['PUT movie/editor']);
  expect(harness.server.requests.single.query, isEmpty);
  return sentBody(harness.server.requests.single);
}

void main() {
  group('setMonitored', () {
    for (final monitored in [true, false]) {
      test('turns monitoring ${monitored ? 'on' : 'off'}', () async {
        final movie = _movie()..['monitored'] = !monitored;
        final harness = _harness(movie);

        await succeed(
          harness.library.setMonitored(MediaTarget(movieRef(1)), monitored),
        );

        _expectWritten(harness, {'monitored': monitored}, movie);
      });
    }

    for (final MapEntry(key: name, value: target) in foreignTargets.entries) {
      test('changes nothing for $name', () async {
        final harness = _harness();

        expect(
          await failureOf(harness.library.setMonitored(target, false)),
          isA<Validation>(),
        );
        expect(harness.sent, isEmpty);
      });
    }
  });

  group('applyMonitorOption', () {
    test('has no option to apply', () async {
      final harness = _harness();

      expect(harness.library.monitorOptions, isEmpty);
      expect(
        await failureOf(
          harness.library.applyMonitorOption(movieRef(1), 'movieOnly'),
        ),
        isA<Validation>(),
      );
      expect(harness.sent, isEmpty);
    });
  });

  group('edit', () {
    for (final (name, changes, changed) in [
      (
        'the quality profile',
        const ItemEdit(qualityProfileId: 6),
        <String, Object?>{'qualityProfileId': 6},
      ),
      (
        'tags',
        const ItemEdit(tagIds: {2}),
        <String, Object?>{
          'tags': [2],
        },
      ),
      (
        'no tags',
        const ItemEdit(tagIds: {}),
        <String, Object?>{'tags': <int>[]},
      ),
      (
        'the minimum availability',
        const ItemEdit(minimumAvailability: MinimumAvailability.inCinemas),
        <String, Object?>{'minimumAvailability': 'inCinemas'},
      ),
      (
        'several fields',
        const ItemEdit(monitored: false, qualityProfileId: 6),
        <String, Object?>{'monitored': false, 'qualityProfileId': 6},
      ),
    ]) {
      test('of $name keeps every other field', () async {
        final harness = _harness();

        await succeed(harness.library.edit(movieRef(1), changes));

        _expectWritten(harness, changed);
      });
    }

    test('applies to the movie as the server has it now', () async {
      // The app showed, and cached, an earlier state.
      final now = _movie()
        ..['monitored'] = false
        ..['tags'] = [1, 2]
        ..['path'] = '/redacted/moved';
      final harness = _harness(now);
      await harness.cache.put(_entry(1));

      await succeed(
        harness.library.edit(movieRef(1), const ItemEdit(qualityProfileId: 6)),
      );

      _expectWritten(harness, {'qualityProfileId': 6}, now);
    });

    test('sends nothing without a change', () async {
      final harness = _harness();

      await succeed(harness.library.edit(movieRef(1), const ItemEdit()));

      expect(harness.sent, isEmpty);
    });

    for (final MapEntry(key: name, value: ref) in foreignRefs.entries) {
      test('changes nothing for $name', () async {
        final harness = _harness();

        expect(
          await failureOf(
            harness.library.edit(ref, const ItemEdit(monitored: false)),
          ),
          isA<Validation>(),
        );
        expect(harness.sent, isEmpty);
      });
    }
  });

  for (final MapEntry(key: name, value: change) in _changes.entries) {
    group('$name that fails', () {
      test('writes nothing if the movie is gone', () async {
        const failure = NotFound();
        final harness = _harness();
        harness.radarr.routes['GET movie/1'] = failedAnswer(
          failure,
          status: 404,
        );

        expect(await failureOf(change(harness, movieRef(1))), same(failure));
        expect(harness.sent, everyElement('GET movie/1'));
      });

      for (final body in ['{"id":', '[]']) {
        test('writes nothing over a movie it cannot read: $body', () async {
          final harness = _harness();
          harness.radarr.routes['GET movie/1'] = reply(body);

          expect(
            await failureOf(change(harness, movieRef(1))),
            isA<MalformedResponse>(),
          );
          expect(harness.sent, everyElement('GET movie/1'));
        });
      }

      for (final (failure, status) in writeFailures) {
        test('passes on ${failure.runtimeType} and writes once', () async {
          final harness = _harness();
          harness.radarr.routes['PUT movie/1'] = failedAnswer(
            failure,
            status: status,
          );

          expect(await failureOf(change(harness, movieRef(1))), same(failure));
          expect(harness.sent, ['GET movie/1', 'PUT movie/1']);
        });
      }
    });
  }

  group('bulkEdit', () {
    test('changes monitoring and the quality profile', () async {
      expect(
        await _edited(const BulkEdit(monitored: false, qualityProfileId: 6)),
        {
          'movieIds': [2, 3],
          'monitored': false,
          'qualityProfileId': 6,
        },
      );
    });

    // The body is all there is: no file, folder or exclusion is touched.
    test('changes only what was asked', () async {
      expect(await _edited(const BulkEdit(monitored: true)), {
        'movieIds': [2, 3],
        'monitored': true,
      });
    });

    for (final change in TagChange.values) {
      test('says to ${change.name} the tags', () async {
        expect(await _edited(BulkEdit(tagIds: const {2}, tagChange: change)), {
          'movieIds': [2, 3],
          'tags': [2],
          'applyTags': change.name,
        });
      });
    }

    for (final (name, refs, changes) in [
      ('movies', <ItemRef>[], const BulkEdit(monitored: false)),
      ('a change', null, const BulkEdit()),
    ]) {
      test('sends nothing without $name', () async {
        final harness = _editor();

        await succeed(_bulk(harness, changes, refs));

        expect(harness.sent, isEmpty);
      });
    }

    for (final MapEntry(key: name, value: ref) in foreignRefs.entries) {
      test('changes none of a list with $name', () async {
        final harness = _editor();

        expect(
          await failureOf(
            _bulk(harness, const BulkEdit(monitored: false), [
              movieRef(2),
              ref,
            ]),
          ),
          isA<Validation>(),
        );
        expect(harness.sent, isEmpty);
      });
    }

    for (final (failure, status) in writeFailures) {
      test('passes on ${failure.runtimeType} and is sent once', () async {
        final harness = _editor();
        harness.radarr.routes['PUT movie/editor'] = failedAnswer(
          failure,
          status: status,
        );

        expect(
          await failureOf(_bulk(harness, const BulkEdit(monitored: false))),
          same(failure),
        );
        expect(harness.sent, ['PUT movie/editor']);
      });
    }
  });
}

CacheEntry _entry(int id) => CacheEntry(
  instanceId: instanceId,
  kind: MediaKind.movie,
  remoteId: id,
  sortTitle: 'old',
  state: ItemState.missing,
  monitored: true,
  qualityProfileId: 1,
  tagIds: const [],
  addedAt: DateTime.utc(2026),
  rawJson: '{"id": $id, "title": "Old", "monitored": true}',
  fetchedAt: DateTime.utc(2026),
);
