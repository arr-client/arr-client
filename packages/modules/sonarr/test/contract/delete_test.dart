// Deleting a series and an episode file (story 5, scenario 6). Both destroy
// data, so each request is exactly what the user chose.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'manage_support.dart';
import 'support.dart';

ServiceResult<void> _delete(
  ManageHarness harness, {
  ItemRef? ref,
  bool deleteFiles = true,
  bool addImportExclusion = true,
}) => harness.library.delete(
  ref ?? seriesRef(1),
  deleteFiles: deleteFiles,
  addImportExclusion: addImportExclusion,
);

/// A harness whose cache holds the library and the episodes of series 1.
Future<ManageHarness> _loaded() async {
  final harness = ManageHarness();
  await ok(harness.library.list());
  await ok(harness.library.children(seriesRef(1)));
  harness.sonarr.requests.clear();
  return harness;
}

/// The episode file of series 1, with the harness's requests cleared.
Future<MediaFile> _file(ManageHarness harness) async {
  final file = (await ok(harness.library.files(seriesRef(1)))).single;
  harness.sonarr.requests.clear();
  return file;
}

void main() {
  group('delete', () {
    for (final deleteFiles in [true, false]) {
      for (final exclude in [true, false]) {
        test('states deleteFiles=$deleteFiles and '
            'addImportListExclusion=$exclude', () async {
          final harness = ManageHarness();

          await ok(
            _delete(
              harness,
              deleteFiles: deleteFiles,
              addImportExclusion: exclude,
            ),
          );

          // One request: no file is deleted on its own first.
          final request = harness.sonarr.requests.single;
          expect(request.method, HttpMethod.delete);
          expect(request.path, 'api/v3/series/1');
          expect(request.query, {
            'deleteFiles': ['$deleteFiles'],
            'addImportListExclusion': ['$exclude'],
          });
          expect(request.body, isNull);
        });
      }
    }

    test('removes the series and its episodes from the cache', () async {
      final harness = await _loaded();
      expect(await harness.cachedSeries(), contains(1));

      await ok(_delete(harness));

      expect(await harness.cachedSeries(), isNot(contains(1)));
      expect(await harness.cachedSeries(), contains(4));
      expect(await ok(harness.library.cachedChildren(seriesRef(1))), isNull);
    });

    // An episode's id would name some other series.
    for (final (name, ref) in [
      ('an episode', episodeRef(1)),
      ('a movie', movie.item),
    ]) {
      test('does not take $name for a series', () async {
        final harness = ManageHarness();

        await expectProgrammingError(() => _delete(harness, ref: ref));

        expect(harness.sonarr.requests, isEmpty);
      });
    }

    for (final MapEntry(key: cause, value: (answer, expected))
        in writeFailures.entries) {
      test('reports $cause, is sent once and keeps the cache', () async {
        final harness = await _loaded();
        harness.sonarr.writeAnswer = answer;

        final failure = await failureOf(_delete(harness));

        expect(failure.runtimeType, expected);
        expect(harness.asked, [line(HttpMethod.delete, 'series/1')]);
        expect(await harness.cachedSeries(), contains(1));
      });
    }

    for (final (name, answer) in [
      (
        'as recorded',
        FakeSonarr.body(
          '{"message":"$noSuchSeries"}',
          status: 500,
          write: true,
        ),
      ),
      ('with 404', FakeSonarr.body('', status: 404)),
    ]) {
      test('of a series that is gone, $name, says so and forgets it', () async {
        final harness = await _loaded();
        harness.sonarr.writeAnswer = answer;

        expect(await failureOf(_delete(harness)), isA<NotFound>());

        expect(harness.asked, [line(HttpMethod.delete, 'series/1')]);
        expect(await harness.cachedSeries(), isNot(contains(1)));
      });
    }
  });

  group('file delete', () {
    test('deletes that file alone', () async {
      final harness = ManageHarness();
      final file = await _file(harness);

      await ok(harness.library.deleteFile(file));

      final request = harness.sonarr.requests.single;
      expect(request.method, HttpMethod.delete);
      expect(request.path, 'api/v3/episodefile/${file.id}');
      expect(request.query, isEmpty);
      expect(request.body, isNull);
    });

    for (final MapEntry(key: cause, value: (answer, expected)) in {
      ...writeFailures,
      // As recorded for a file already deleted.
      'a file that is gone': (
        FakeSonarr.body(
          '{"message":"EpisodeFile with ID 2 does not exist"}',
          status: 404,
          write: true,
        ),
        NotFound,
      ),
    }.entries) {
      test('reports $cause and is sent once', () async {
        final harness = ManageHarness();
        final file = await _file(harness);
        harness.sonarr.writeAnswer = answer;

        final failure = await failureOf(harness.library.deleteFile(file));

        expect(failure.runtimeType, expected);
        expect(harness.asked, [
          line(HttpMethod.delete, 'episodefile/${file.id}'),
        ]);
      });
    }
  });
}
