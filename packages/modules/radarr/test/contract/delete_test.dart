// Deleting a movie or its file (story 5, scenario 6). Both destroy something, so
// each is one request that says exactly what the user chose, sent once.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'library_support.dart';
import 'manage_support.dart';

/// A Radarr that has the movies 1 and 2 and the file 1, all cached, and
/// answers a delete as recorded: with 200 and nothing.
Future<ManageHarness> _harness() async {
  final harness = ManageHarness();
  for (final path in ['movie/1', 'moviefile/1']) {
    harness.radarr.routes['DELETE $path'] = reply('');
  }
  for (final id in [1, 2]) {
    await harness.cache.put(
      CacheEntry(
        instanceId: instanceId,
        kind: MediaKind.movie,
        remoteId: id,
        sortTitle: 'movie $id',
        state: ItemState.downloaded,
        monitored: true,
        qualityProfileId: 1,
        tagIds: const [],
        addedAt: DateTime.utc(2026),
        rawJson: '{"id": $id, "title": "Movie $id"}',
        fetchedAt: DateTime.utc(2026),
      ),
    );
  }
  return harness;
}

Iterable<int> _cached(ManageHarness harness) =>
    harness.cache.entries.values.map((entry) => entry.remoteId);

ServiceResult<void> _delete(
  ManageHarness harness, {
  ItemRef? ref,
  bool deleteFiles = false,
  bool addImportExclusion = false,
}) => harness.library.delete(
  ref ?? movieRef(1),
  deleteFiles: deleteFiles,
  addImportExclusion: addImportExclusion,
);

/// The recorded movie's file.
MediaFile _file() {
  final wire =
      manageObject('manage_movie')['movieFile']! as Map<String, Object?>;
  return MediaFile(
    id: wire['id']! as int,
    path: wire['path']! as String,
    size: wire['size']! as int,
  );
}

void main() {
  group('delete', () {
    for (final deleteFiles in [false, true]) {
      for (final addImportExclusion in [false, true]) {
        test('states deleteFiles=$deleteFiles and '
            'addImportExclusion=$addImportExclusion', () async {
          final harness = await _harness();

          await succeed(
            _delete(
              harness,
              deleteFiles: deleteFiles,
              addImportExclusion: addImportExclusion,
            ),
          );

          final request = harness.server.requests.single;
          expect(asked(request), 'DELETE movie/1');
          expect(request.query, {
            'deleteFiles': ['$deleteFiles'],
            'addImportExclusion': ['$addImportExclusion'],
          });
          expect(request.body, isNull);
        });
      }
    }

    test('takes the movie, and no other, out of the cache', () async {
      final harness = await _harness();

      await succeed(_delete(harness));

      expect(_cached(harness), [2]);
    });

    for (final (failure, status) in writeFailures) {
      test('passes on ${failure.runtimeType} and is sent once', () async {
        final harness = await _harness();
        harness.radarr.routes['DELETE movie/1'] = failedAnswer(
          failure,
          status: status,
        );

        expect(
          await failureOf(_delete(harness, deleteFiles: true)),
          same(failure),
        );
        expect(harness.sent, ['DELETE movie/1']);
        // A movie already gone may leave the cache or stay.
        if (failure is! NotFound) expect(_cached(harness), [1, 2]);
      });
    }

    for (final MapEntry(key: name, value: ref) in foreignRefs.entries) {
      test('deletes nothing for $name', () async {
        final harness = await _harness();

        expect(
          await failureOf(_delete(harness, ref: ref, deleteFiles: true)),
          isA<Validation>(),
        );
        expect(harness.sent, isEmpty);
        expect(_cached(harness), [1, 2]);
      });
    }
  });

  group('a movie found to be gone', () {
    final writes = <String, ServiceResult<void> Function(ManageHarness)>{
      'a delete': _delete,
      'an edit': (harness) =>
          harness.library.edit(movieRef(1), const ItemEdit(monitored: false)),
      'a monitoring change': (harness) =>
          harness.library.setMonitored(MediaTarget(movieRef(1)), false),
    };

    // What is not routed is answered with a 404.
    for (final MapEntry(key: name, value: write) in writes.entries) {
      test('by $name leaves the cache', () async {
        final harness = await _harness();
        harness.radarr.routes.clear();

        expect(await failureOf(write(harness)), isA<NotFound>());

        expect(_cached(harness), [2]);
      });
    }
  });

  group('deleteFile', () {
    test('deletes that file and nothing else', () async {
      final harness = await _harness();

      await succeed(harness.library.deleteFile(_file()));

      final request = harness.server.requests.single;
      expect(asked(request), 'DELETE moviefile/1');
      expect(request.query, isEmpty);
      expect(request.body, isNull);
      // The movie stays.
      expect(_cached(harness), [1, 2]);
    });

    for (final (failure, status) in writeFailures) {
      test('passes on ${failure.runtimeType} and is sent once', () async {
        final harness = await _harness();
        harness.radarr.routes['DELETE moviefile/1'] = failedAnswer(
          failure,
          status: status,
        );

        expect(
          await failureOf(harness.library.deleteFile(_file())),
          same(failure),
        );
        expect(harness.sent, ['DELETE moviefile/1']);
      });
    }
  });
}
