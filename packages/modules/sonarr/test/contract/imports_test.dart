// "Downloaded today" and "recently added" of Sonarr (spec story 6 scenario 5,
// FR-024, FR-026). Grouping, order and the bounds of a day are the shared
// Servarr calendar's, tested in packages/servarr; here is what Sonarr is asked
// and what its records become, season packs included: each episode of a pack is
// an item of its own, which opens that episode.
//
// The days are built from the device's zone and hold in any; run them with
// several values of TZ.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'overview_support.dart';
import 'support.dart';

/// The recorded imports as listed, newest first, each episode once: the upgraded
/// one, the two of one file, then the three of a season pack. Imports of one
/// second go by their ids.
const _episodes = [81, 44, 43, 42, 41, 40];

/// The local day of the recordings, which were made within one quarter minute.
final DateTime _recordedDay = () {
  final local = DateTime.utc(2026, 11, 26, 14, 33).toLocal();
  return DateTime(local.year, local.month, local.day);
}();

/// A recorded import, the one with [id], changed.
Map<String, Object?> _import(
  int id, {
  DateTime? at,
  int? newId,
  int? episodeId,
}) => {
  ...byId(records('overview_history_since'), id),
  if (at != null) 'date': at.toUtc().toIso8601String(),
  'id': ?newId,
  'episodeId': ?episodeId,
};

FakeOverview _serving(List<Map<String, Object?>> imports) => FakeOverview()
  ..imports.clear()
  ..imports.addAll(imports);

/// The two reads of imports.
final _reads =
    <String, ServiceResult<List<ImportedItem>> Function(CalendarProvider)>{
      'imported on a day': (calendar) => calendar.importedOn(_recordedDay),
      'recently added': (calendar) => calendar.recentlyAdded(),
    };

void main() {
  test('a day asks for the imports with their series and episodes', () async {
    final server = FakeOverview();

    await ok(Harness(server: server).calendar.importedOn(_recordedDay));

    final request = server.requests.single;
    expect(request.method, HttpMethod.get);
    expect(request.path, 'api/v3/history/since');
    expect(request.query['includeSeries'], ['true']);
    expect(request.query['includeEpisode'], ['true']);
    expect(
      request.query['eventType']!.single,
      anyOf('3', 'downloadFolderImported'),
    );
    final date = request.query['date']!.single;
    expect(date, endsWith('Z'));
    expect(DateTime.parse(date).isBefore(_recordedDay), isTrue);
  });

  test('recently added asks for the newest imports, named', () async {
    final server = FakeOverview();

    await ok(Harness(server: server).calendar.recentlyAdded());

    final request = server.requests.single;
    expect(request.method, HttpMethod.get);
    expect(request.path, 'api/v3/history');
    expect(request.query['includeSeries'], ['true']);
    expect(request.query['includeEpisode'], ['true']);
    expect(request.query['eventType'], ['3']);
    expect(request.query['sortKey'], ['date']);
    expect(request.query['sortDirection'], ['descending']);
  });

  for (final MapEntry(key: name, value: read) in _reads.entries) {
    group(name, () {
      Future<List<ImportedItem>> imports(FakeOverview server) =>
          ok(read(Harness(server: server).calendar));

      test('lists each episode, of a pack and of one file too', () async {
        final listed = await imports(FakeOverview());

        expect(listed.map((item) => item.itemRef), [
          for (final id in _episodes) episodeRef(id),
        ]);
      });

      test('gives the time and quality of the latest import', () async {
        final upgraded = (await imports(FakeOverview())).first;

        expect(upgraded.importedAt, DateTime.utc(2026, 11, 26, 14, 33, 12));
        expect(upgraded.importedAt.isUtc, isTrue);
        expect(upgraded.quality?.id, 7);
        expect(upgraded.quality?.name, 'Bluray-1080p');
      });

      test('names the series, number and episode', () async {
        final record = _import(8);
        rename(record, 'Slow Horses', 'Signals');

        final listed = await imports(_serving([record]));

        expect(listed.single.title, titled('Slow Horses', 'S06E01', 'Signals'));
      });

      test('tells the episodes of a pack apart', () async {
        final server = _serving([_import(2), _import(3), _import(4)]);
        for (final record in server.imports) {
          rename(record, 'The Bear', 'Pilot');
        }

        final listed = await imports(server);

        expect(listed.map((item) => item.title), [
          titled('The Bear', 'S05E03', 'Pilot'),
          titled('The Bear', 'S05E02', 'Pilot'),
          titled('The Bear', 'S05E01', 'Pilot'),
        ]);
      });

      test('falls back to the release name for a bare record', () async {
        final record = _import(8)
          ..remove('series')
          ..remove('episode')
          ..['sourceTitle'] = 'Slow.Horses.S06E01.1080p';

        final listed = await imports(_serving([record]));

        expect(listed.single.title, 'Slow.Horses.S06E01.1080p');
        expect(listed.single.itemRef, episodeRef(81));
      });

      test('passes a failure on, asking once', () async {
        final server = FakeOverview()..goOffline();

        expect(
          await failureOf(read(Harness(server: server).calendar)),
          isA<Unreachable>(),
        );
        expect(server.requests, hasLength(1));
      });

      test('cannot understand an import without a date', () async {
        final record = _import(8)..remove('date');

        expect(
          await failureOf(read(Harness(server: _serving([record])).calendar)),
          isA<MalformedResponse>(),
        );
      });
    });
  }

  test('every episode of a long season pack is listed', () async {
    // More than one page of any list, all of one download.
    final server = _serving([
      for (var id = 1; id <= 60; id++)
        {
          ..._import(2, newId: id, episodeId: 1000 + id),
          'downloadId': '0123456789ABCDEF0123456789ABCDEF01234567',
        },
    ]);

    final listed = await ok(
      Harness(server: server).calendar.importedOn(_recordedDay),
    );

    expect(listed.map((item) => item.itemRef), [
      for (var id = 60; id >= 1; id--) episodeRef(1000 + id),
    ]);
  });

  group('downloaded today', () {
    const second = Duration(seconds: 1);

    // Days on which clocks change in some zones, and an ordinary one.
    for (final day in [
      DateTime(2026, 3, 8),
      DateTime(2026, 3, 29),
      DateTime(2026, 4, 5),
      DateTime(2026, 9, 6),
      DateTime(2026, 9, 27),
      DateTime(2026, 10, 25),
      DateTime(2026, 11, 1),
      DateTime(2026, 11, 26),
    ]) {
      final name = '${day.year}-${day.month}-${day.day}';
      test('on $name runs from local midnight to the next', () async {
        final next = DateTime(day.year, day.month, day.day + 1);
        final server = _serving([
          for (final (id, at) in [
            (1, day.subtract(second)),
            (2, day),
            (3, next.subtract(second)),
            (4, next),
          ])
            _import(2, at: at, newId: id, episodeId: id),
        ]);

        // The time of day asked with does not matter.
        final listed = await ok(
          Harness(server: server).calendar
              .importedOn(DateTime(day.year, day.month, day.day, 23, 30)),
        );

        expect(listed.map((item) => item.itemRef), [
          episodeRef(3),
          episodeRef(2),
        ]);
      });
    }

    test('steps back to an earlier day', () async {
      final server = _serving([
        _import(2, at: DateTime(2026, 11, 25, 22), episodeId: 7),
        _import(3, at: DateTime(2026, 11, 26, 1), episodeId: 8),
      ]);

      final listed = await ok(
        Harness(server: server).calendar.importedOn(DateTime(2026, 11, 25)),
      );

      expect(listed.single.itemRef, episodeRef(7));
    });

    test('is by when it was imported, not when it aired', () async {
      final record = _import(2, at: DateTime(2026, 11, 26, 12));
      record['episode'] = {
        ...record['episode']! as Map<String, Object?>,
        'airDateUtc': '2022-06-23T04:00:00Z',
      };

      final listed = await ok(
        Harness(server: _serving([record])).calendar
            .importedOn(DateTime(2026, 11, 26)),
      );

      expect(listed, hasLength(1));
    });
  });
}
