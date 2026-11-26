// What Radarr imported: "Downloaded today" and earlier days (spec story 6
// scenario 5, FR-026), and "Recently added" (FR-024).
//
// The day is the device's local day. These tests build their times from local
// ones, so they hold in any zone; run them under zones on both sides of UTC to
// tell a local day from a UTC one.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'library_support.dart';
import 'overview_support.dart';

/// The recorded imports, oldest first, as `history/since` answers.
List<Map<String, Object?>> _since() =>
    records(fixture('overview_history_since'));

Map<String, Object?> _import(int id) =>
    _since().singleWhere((record) => record['id'] == id);

Harness _harness([List<Map<String, Object?>>? since]) => Harness()
  ..serve('history', fixture('overview_history_imports'))
  ..serve('history/since', since ?? _since());

/// The local day of the recording. Its imports are seconds apart, and no zone's
/// midnight falls among them.
final _recordedDay = DateTime.parse(_since().first['date']! as String)
    .toLocal();

/// The recorded imports, each movie once with its latest, newest first: the
/// movie, the record and the quality.
const _latest = [
  (4, 6, 7, 'Bluray-1080p'),
  (7, 4, 7, 'Bluray-1080p'),
  (6, 3, 4, 'HDTV-720p'),
  (1, 2, 5, 'WEBDL-720p'),
];

void _expectRecorded(List<ImportedItem> items) {
  expect(items.map((item) => item.itemRef), [
    for (final (movie, _, _, _) in _latest) movieRef(movie),
  ]);
  for (final (index, (_, id, quality, name)) in _latest.indexed) {
    final record = _import(id);
    final item = items[index];
    expect(item.title, (record['movie']! as Map<String, Object?>)['title']);
    expect(
      item.importedAt.isAtSameMomentAs(
        DateTime.parse(record['date']! as String),
      ),
      isTrue,
    );
    expect(item.quality?.id, quality);
    expect(item.quality?.name, name);
  }
}

typedef _Read = ServiceResult<List<ImportedItem>> Function(Harness harness);

ServiceResult<List<ImportedItem>> _today(Harness harness) =>
    harness.calendar.importedOn(_recordedDay);

ServiceResult<List<ImportedItem>> _recent(Harness harness) =>
    harness.calendar.recentlyAdded();

void main() {
  group('imported on a day', () {
    test('asks for the imports since that day, with their movies', () async {
      final harness = _harness();
      final day = DateTime(2026, 11, 26, 15, 30);

      await succeed(harness.calendar.importedOn(day));

      final request = harness.server.requests.single;
      expect(request.method, HttpMethod.get);
      expect(request.path, 'api/v3/history/since');
      expect(request.body, isNull);
      expect(request.query['includeMovie'], ['true']);
      expect(
        request.query['eventType']!.single,
        anyOf('3', 'downloadFolderImported'),
      );
      final date = request.query['date']!.single;
      // Radarr reads a date with an offset wrongly.
      expect(date, endsWith('Z'));
      expect(DateTime.parse(date).isAfter(DateTime(2026, 11, 26)), isFalse);
    });

    test('lists each movie once, newest first, with its quality', () async {
      _expectRecorded(await succeed(_today(_harness())));
    });

    test('holds the local day from midnight to midnight', () async {
      final day = DateTime(2026, 11, 26);
      final next = DateTime(2026, 11, 27);
      const second = Duration(seconds: 1);
      final harness = _harness([
        for (final (movie, at) in [
          (1, day.subtract(second)),
          (2, day),
          (3, next.subtract(second)),
          (4, next),
        ])
          {
            ..._import(2),
            'id': movie,
            'movieId': movie,
            'date': at.toUtc().toIso8601String(),
          },
      ]);

      final items = await succeed(harness.calendar.importedOn(day));

      expect(items.map((item) => item.itemRef?.remoteId), [3, 2]);
    });

    test('is empty on the days around the imports', () async {
      for (final offset in [-1, 1]) {
        final day = DateTime(
          _recordedDay.year,
          _recordedDay.month,
          _recordedDay.day + offset,
        );

        expect(
          await succeed(_harness().calendar.importedOn(day)),
          isEmpty,
          reason: '$day',
        );
      }
    });
  });

  group('recently added', () {
    test('asks for the latest imports, with their movies', () async {
      final harness = _harness();

      await succeed(_recent(harness));

      final request = harness.server.requests.single;
      expect(request.method, HttpMethod.get);
      expect(request.path, 'api/v3/history');
      expect(request.body, isNull);
      expect(request.query['includeMovie'], ['true']);
      expect(request.query['eventType'], ['3']);
      expect(request.query['page'], ['1']);
      expect(int.parse(request.query['pageSize']!.single), greaterThan(0));
      expect(request.query['sortKey'], ['date']);
      expect(request.query['sortDirection'], ['descending']);
    });

    test('lists each movie once, newest first, with its quality', () async {
      _expectRecorded(await succeed(_recent(_harness())));
    });
  });

  for (final (name, path, read, answer) in <(String, String, _Read, Object?)>[
    ('imported on a day', 'history/since', _today, _since()),
    ('recently added', 'history', _recent, fixture('overview_history_imports')),
  ]) {
    group(name, () {
      /// Serves [imports] in the shape of this read.
      Harness serving(List<Map<String, Object?>> imports) => Harness()
        ..serve(
          path,
          path == 'history'
              ? {
                  ...answer! as Map<String, Object?>,
                  'totalRecords': imports.length,
                  'records': imports,
                }
              : imports,
        );

      test('keeps an import the server cannot match to a movie', () async {
        final record = _import(2)
          ..['movieId'] = 0
          ..remove('movie');

        final items = await succeed(read(serving([record])));

        expect(items.single.itemRef, isNull);
        expect(items.single.title, record['sourceTitle']);
      });

      // An import has no state, so a queue that fails must not hide it.
      test('does not depend on the queue', () async {
        final harness = _harness()
          ..server.answers['api/v3/queue'] = failedAnswer(
            const ServerError(statusCode: 500),
            status: 500,
          );

        _expectRecorded(await succeed(read(harness)));
      });

      test('is empty when nothing was imported', () async {
        expect(await succeed(read(serving([]))), isEmpty);
      });

      test('passes a failure on, asking once', () async {
        final harness = _harness()
          ..server.down = failedAnswer(const AuthFailed(), status: 401);

        expect(await failureOf(read(harness)), isA<AuthFailed>());
        expect(harness.server.requests, hasLength(1));
      });

      test('cannot understand an import without a date', () async {
        final record = _import(2)..remove('date');

        expect(
          await failureOf(read(serving([record]))),
          isA<MalformedResponse>(),
        );
      });
    });
  }
}
