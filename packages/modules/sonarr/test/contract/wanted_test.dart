// Sonarr's wanted lists. Paging is the shared Servarr client's, tested in
// packages/servarr; here is what Sonarr is asked and what its records become.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'overview_support.dart';
import 'support.dart';

/// One of the two lists: where it is read and what was recorded in it.
typedef _List = ({
  String name,
  String path,
  List<int> ids,
  ItemState state,
  ServiceResult<ResultPage<LibraryItem>> Function(WantedProvider, int page)
  read,
});

final _lists = <_List>[
  (
    name: 'missing',
    path: 'wanted/missing',
    ids: [86, 85, 84],
    state: ItemState.missing,
    read: (wanted, page) => wanted.missing(page: page),
  ),
  (
    name: 'cutoff unmet',
    path: 'wanted/cutoff',
    ids: [40, 41, 42, 43, 44],
    // An episode with its file, whatever its quality.
    state: ItemState.downloaded,
    read: (wanted, page) => wanted.cutoffUnmet(page: page),
  ),
];

List<Map<String, Object?>> _records(FakeOverview server, _List list) =>
    list.path == 'wanted/missing' ? server.missing : server.cutoff;

void main() {
  for (final list in _lists) {
    group(list.name, () {
      Future<ResultPage<LibraryItem>> read(
        FakeOverview server, [
        int page = 1,
      ]) => ok(list.read(Harness(server: server).wanted, page));

      test('asks for monitored episodes and their series', () async {
        final server = FakeOverview();

        await read(server);

        final request = server.asked(list.path).single;
        expect(request.method, HttpMethod.get);
        expect(request.query['includeSeries'], ['true']);
        expect(request.query['monitored'], ['true']);
        expect(request.query['page'], ['1']);
        // Latest aired first, as in Sonarr's web UI and the recordings.
        expect(request.query['sortKey'], ['episodes.airDateUtc']);
        expect(request.query['sortDirection'], ['descending']);
        // Only a list of episodes with files has files to ask for.
        expect(
          request.query['includeEpisodeFile'],
          list.state == ItemState.downloaded ? ['true'] : null,
        );
        // Besides it, only the queue is needed, for the state.
        expect(server.requests.map((r) => r.path).toSet(), {
          'api/v3/${list.path}',
          'api/v3/queue',
        });
        expect(server.writes, isEmpty);
      });

      test('marks a queued episode as downloading', () async {
        final server = FakeOverview()..enqueue(list.ids.first);

        final page = await read(server);

        expect(page.items.first.state, ItemState.downloading);
        expect(page.items.last.state, list.state);
      });

      // As for the library: a queued episode would otherwise show as missing.
      for (final path in ['queue', list.path]) {
        test('fails when $path cannot be read', () async {
          final server = FakeOverview()..breaks(path);

          expect(
            await failureOf(list.read(Harness(server: server).wanted, 1)),
            isA<ServerError>(),
          );
          expect(server.asked(path), hasLength(1));
        });
      }

      test('takes a queue that is not found for a server error', () async {
        final server = FakeOverview()..breaks('queue', status: 404);

        expect(
          await failureOf(list.read(Harness(server: server).wanted, 1)),
          isA<ServerError>(),
        );
      });

      // One page is not the library.
      test('does not write to the cache', () async {
        final harness = Harness(server: FakeOverview());

        await ok(list.read(harness.wanted, 1));

        expect(
          await harness.cache.entry(MediaKind.episode, list.ids.first),
          isNull,
        );
      });

      test("lists episodes in the server's order", () async {
        final page = await read(FakeOverview());

        expect(page.items.map((item) => item.ref), [
          for (final id in list.ids) episodeRef(id),
        ]);
        expect(page.items, everyElement(isA<Episode>()));
        expect(page.items.map((item) => item.state).toSet(), {list.state});
        expect(page.page, 1);
        expect(page.hasMore, isFalse);
      });

      test('an item is the episode, under its series', () async {
        final server = FakeOverview();
        final record = _records(server, list).first;
        record['title'] = 'Signals';
        record['series'] = {
          ...record['series']! as Map<String, Object?>,
          'title': 'Slow Horses',
        };

        final episode = (await read(server)).items.first as Episode;

        // The series is the parent's title, not part of the episode's.
        expect(episode.title, 'Signals');
        expect(episode.parentTitle, 'Slow Horses');
        expect(episode.parent, seriesRef(record['seriesId']! as int));
        expect(episode.seasonNumber, record['seasonNumber']);
        expect(episode.episodeNumber, record['episodeNumber']);
        expect(
          episode.airDateUtc,
          DateTime.parse(record['airDateUtc']! as String),
        );
        expect(episode.monitored, isTrue);
        expect(episode.hasFile, record['hasFile']);
      });

      test('has further pages when the server has more', () async {
        final server = FakeOverview();
        final records = _records(server, list);
        final one = records.first;
        records
          ..clear()
          ..addAll([
            for (var id = 1; id <= 120; id++) {...one, 'id': id},
          ]);

        final first = await read(server);
        final size = first.items.length;
        final last = await read(server, (120 / size).ceil());

        expect(first.hasMore, isTrue);
        expect(last.hasMore, isFalse);
        expect(last.items.last.ref, episodeRef(120));
      });

      test('is empty when nothing is wanted', () async {
        final server = FakeOverview();
        _records(server, list).clear();

        final page = await read(server);

        expect(page.items, isEmpty);
        expect(page.hasMore, isFalse);
      });

      test('lists an episode whose series the record lacks', () async {
        final server = FakeOverview();
        final record = _records(server, list).first..remove('series');

        final episode = (await read(server)).items.first as Episode;

        expect(episode.parent, seriesRef(record['seriesId']! as int));
        expect(episode.parentTitle, isNull);
      });

      for (final field in ['id', 'seriesId', 'seasonNumber', 'episodeNumber']) {
        test('cannot understand an episode without $field', () async {
          final server = FakeOverview();
          _records(server, list).first.remove(field);

          expect(
            await failureOf(list.read(Harness(server: server).wanted, 1)),
            isA<MalformedResponse>(),
          );
        });
      }

      test('passes a failure on, asking once', () async {
        final server = FakeOverview()..goOffline();

        expect(
          await failureOf(list.read(Harness(server: server).wanted, 1)),
          isA<Unreachable>(),
        );
        expect(server.requests, hasLength(1));
      });
    });
  }
}
