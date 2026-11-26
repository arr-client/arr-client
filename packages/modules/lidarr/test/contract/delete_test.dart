// Deleting artists, albums and track files. What is deleted never rests on a
// server default, and the exclusion is `addImportListExclusion`.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// A harness with artist 1, its albums and the tracks of album 2 cached.
Future<Harness> _cached() async {
  final harness = Harness();
  await ok(harness.library.list());
  await ok(harness.library.children(artistRef(1)));
  await ok(harness.library.children(albumRef(2)));
  harness.server.requests.clear();
  return harness;
}

void main() {
  for (final (ref, path) in [
    (artistRef(1), 'artist/1'),
    (albumRef(2), 'album/2'),
  ]) {
    for (final (files, exclusion) in [(false, false), (true, true)]) {
      test('deletes $path, files $files, exclusion $exclusion', () async {
        final harness = Harness();

        await ok(
          harness.library.delete(
            ref,
            deleteFiles: files,
            addImportExclusion: exclusion,
          ),
        );

        expect(harness.asked, [line(HttpMethod.delete, path)]);
        expect(harness.server.requests.single.query, {
          'deleteFiles': ['$files'],
          'addImportListExclusion': ['$exclusion'],
        });
      });
    }
  }

  test('a deleted artist leaves the cache with all under it', () async {
    final harness = await _cached();

    await ok(
      harness.library.delete(
        artistRef(1),
        deleteFiles: false,
        addImportExclusion: false,
      ),
    );

    expect(await harness.cache.entry(MediaKind.artist, 1), isNull);
    expect(await harness.cache.entry(MediaKind.album, 2), isNull);
    expect(await harness.cache.entry(MediaKind.track, 188), isNull);
  });

  test('a deleted album leaves the cache', () async {
    final harness = await _cached();

    await ok(
      harness.library.delete(
        albumRef(2),
        deleteFiles: false,
        addImportExclusion: false,
      ),
    );

    expect(await harness.cache.entry(MediaKind.album, 2), isNull);
    expect(await harness.cache.entry(MediaKind.artist, 1), isNotNull);
  });

  test('one already gone is not found and leaves the cache', () async {
    final harness = await _cached();
    harness.server.writeAnswer = FakeLidarr.body('', status: 404, write: true);

    expect(
      await failureOf(
        harness.library.delete(
          albumRef(2),
          deleteFiles: false,
          addImportExclusion: false,
        ),
      ),
      isA<NotFound>(),
    );
    expect(await harness.cache.entry(MediaKind.album, 2), isNull);
  });

  for (final (name, ref) in [
    ('a track', trackRef(188)),
    ('an artist of another instance', elsewhere),
  ]) {
    test('$name is not deleted', () async {
      final harness = Harness();

      await expectProgrammingError(
        () => harness.library.delete(
          ref,
          deleteFiles: true,
          addImportExclusion: false,
        ),
      );

      expect(harness.server.requests, isEmpty);
    });
  }

  test('deletes one track file', () async {
    final harness = Harness();

    await ok(
      harness.library.deleteFile(
        const MediaFile(id: 13, path: '/redacted/1.mp3', size: 1),
      ),
    );

    expect(harness.asked, [line(HttpMethod.delete, 'trackfile/13')]);
  });

  for (final MapEntry(key: cause, value: (answer, expected))
      in writeFailures.entries) {
    test('$cause is reported, the delete sent once, the cache kept', () async {
      final harness = await _cached();
      harness.server.writeAnswer = answer;

      final failure = await failureOf(
        harness.library.delete(
          artistRef(1),
          deleteFiles: true,
          addImportExclusion: false,
        ),
      );

      expect(failure.runtimeType, expected);
      expect(harness.server.requests, hasLength(1));
      expect(await harness.cache.entry(MediaKind.artist, 1), isNotNull);
    });
  }
}
