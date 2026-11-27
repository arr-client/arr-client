// Deleting authors, books and book files. What is deleted never rests on a
// server default, and the exclusion is `addImportListExclusion`.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// A harness with author 1 and its books cached.
Future<Harness> _cached() async {
  final harness = Harness();
  await ok(harness.library.list());
  await ok(harness.library.children(authorRef(1)));
  harness.server.requests.clear();
  return harness;
}

void main() {
  for (final (ref, path) in [
    (authorRef(1), 'author/1'),
    (bookRef(8), 'book/8'),
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

  test('a deleted author leaves the cache with its books', () async {
    final harness = await _cached();

    await ok(
      harness.library.delete(
        authorRef(1),
        deleteFiles: false,
        addImportExclusion: false,
      ),
    );

    expect(await harness.cache.entry(MediaKind.author, 1), isNull);
    expect(await harness.cache.entry(MediaKind.book, 8), isNull);
  });

  test('a deleted book leaves the cache', () async {
    final harness = await _cached();

    await ok(
      harness.library.delete(
        bookRef(8),
        deleteFiles: false,
        addImportExclusion: false,
      ),
    );

    expect(await harness.cache.entry(MediaKind.book, 8), isNull);
    expect(await harness.cache.entry(MediaKind.author, 1), isNotNull);
  });

  test('one already gone is not found and leaves the cache', () async {
    final harness = await _cached();
    harness.server.writeAnswer = FakeReadarr.body('', status: 404, write: true);

    expect(
      await failureOf(
        harness.library.delete(
          bookRef(8),
          deleteFiles: false,
          addImportExclusion: false,
        ),
      ),
      isA<NotFound>(),
    );
    expect(await harness.cache.entry(MediaKind.book, 8), isNull);
  });

  test('an author of another instance is not deleted', () async {
    final harness = Harness();

    await expectProgrammingError(
      () => harness.library.delete(
        elsewhere,
        deleteFiles: true,
        addImportExclusion: false,
      ),
    );

    expect(harness.server.requests, isEmpty);
  });

  test('deletes one book file', () async {
    final harness = Harness();

    await ok(
      harness.library.deleteFile(
        const MediaFile(id: 3, path: '/redacted/1.epub', size: 1),
      ),
    );

    expect(harness.asked, [line(HttpMethod.delete, 'bookfile/3')]);
  });

  for (final MapEntry(key: cause, value: (answer, expected))
      in writeFailures.entries) {
    test('$cause is reported, the delete sent once, the cache kept', () async {
      final harness = await _cached();
      harness.server.writeAnswer = answer;

      final failure = await failureOf(
        harness.library.delete(
          authorRef(1),
          deleteFiles: true,
          addImportExclusion: false,
        ),
      );

      expect(failure.runtimeType, expected);
      expect(harness.server.requests, hasLength(1));
      expect(await harness.cache.entry(MediaKind.author, 1), isNotNull);
    });
  }
}
