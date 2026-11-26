// Radarr's wanted lists (spec story 6 scenario 2, FR-023): monitored movies,
// a server page at a time, sorted by title.
//
// The order is asked for, since Radarr's own is by title descending.
// `movieMetadata.sortTitle` is the title key Radarr's API sorts movies by.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../allow_list.dart';
import 'library_support.dart';
import 'overview_support.dart';

typedef _Read = ServiceResult<ResultPage<LibraryItem>> Function(
  Harness harness,
  int? page,
);

ServiceResult<ResultPage<LibraryItem>> _missing(Harness harness, int? page) =>
    page == null
    ? harness.wanted.missing()
    : harness.wanted.missing(page: page);

ServiceResult<ResultPage<LibraryItem>> _cutoff(Harness harness, int? page) =>
    page == null
    ? harness.wanted.cutoffUnmet()
    : harness.wanted.cutoffUnmet(page: page);

void main() {
  for (final (name, path, file, read, ids, state)
      in <(String, String, String, _Read, List<int>, ItemState)>[
        (
          'missing',
          'wanted/missing',
          'overview_wanted_missing',
          _missing,
          [5, 3, 2],
          ItemState.missing,
        ),
        (
          'cutoff unmet',
          'wanted/cutoff',
          'overview_wanted_cutoff',
          _cutoff,
          [6, 1],
          // It has a file, if not one good enough.
          ItemState.downloaded,
        ),
      ]) {
    group(name, () {
      List<Map<String, Object?>> movies() => records(object(file)['records']);

      Harness serving([
        List<Map<String, Object?>>? list,
        Map<String, Object?> changes = const {},
      ]) => Harness()
        ..serve(path, {
          ...object(file),
          if (list != null) ...{'records': list, 'totalRecords': list.length},
          ...changes,
        });

      Future<List<Movie>> items(Harness harness) async => [
        for (final item in (await succeed(read(harness, null))).items)
          item as Movie,
      ];

      for (final page in [null, 2]) {
        test('asks for page ${page ?? 1} of monitored, by title', () async {
          final harness = serving();

          await succeed(read(harness, page));

          final request = harness.asked(path).single;
          expect(request.method, HttpMethod.get);
          expect(request.body, isNull);
          expect(request.query['page'], ['${page ?? 1}']);
          expect(int.parse(request.query['pageSize']!.single), greaterThan(0));
          // The server's default is monitored only.
          expect(request.query['monitored'] ?? ['true'], ['true']);
          expect(request.query['sortKey'], ['movieMetadata.sortTitle']);
          expect(request.query['sortDirection'], ['ascending']);
          // Besides it, only the queue is needed, for the state.
          expect(
            harness.server.requests.map((r) => r.path).toSet(),
            everyElement(anyOf('api/v3/$path', 'api/v3/queue')),
          );
          expect(harness.server.requests.map((r) => r.method).toSet(), {
            HttpMethod.get,
          });
        });
      }

      test('maps the recorded movies in server order', () async {
        final found = await items(serving());

        expect(found.map((movie) => movie.ref), ids.map(movieRef));
        for (final (index, wire) in movies().indexed) {
          final movie = found[index];
          expect(movie.title, wire['title']);
          expect(movie.sortTitle, wire['sortTitle']);
          expect(movie.year, wire['year']);
          expect(movie.overview, wire['overview']);
          expect(movie.runtime, Duration(minutes: wire['runtime']! as int));
          expect(movie.qualityProfileId, wire['qualityProfileId']);
          expect(movie.sizeOnDisk, wire['sizeOnDisk']);
          expect(movie.monitored, isTrue);
          expect(movie.state, state);
        }
      });

      test('gives images the app may load', () async {
        for (final movie in await items(serving())) {
          expect(movie.images, isNotEmpty);
          for (final image in movie.images) {
            final uri = Uri.parse(image.instancePath!);
            expect(
              allowList.permits(
                ServiceRequest(
                  HttpMethod.get,
                  uri.path,
                  query: uri.queryParametersAll,
                ),
              ),
              isTrue,
              reason: image.instancePath,
            );
          }
        }
      });

      test('marks a queued movie as downloading', () async {
        final harness = serving()..enqueue(ids.first);

        final found = await items(harness);

        expect(found.first.state, ItemState.downloading);
        expect(found.last.state, state);
      });

      test('follows what the server says about a release', () async {
        final harness = serving([
          {...movies().first, 'hasFile': false, 'isAvailable': false},
        ]);

        expect((await items(harness)).single.state, ItemState.unreleased);
      });

      test('says whether the server has more', () async {
        final recordedPage = await succeed(read(serving(), null));
        expect(recordedPage.page, 1);
        expect(recordedPage.hasMore, isFalse);

        for (final (page, more) in [(1, true), (2, true), (3, false)]) {
          final harness = serving(null, {
            'page': page,
            'pageSize': 50,
            'totalRecords': 120,
          });

          final result = await succeed(read(harness, page));

          expect(result.page, page);
          expect(result.hasMore, more, reason: 'page $page');
        }
      });

      test('is empty when nothing is wanted', () async {
        final result = await succeed(read(serving([]), null));

        expect(result.items, isEmpty);
        expect(result.hasMore, isFalse);
      });

      // One page is not the library.
      test('does not replace the cached library', () async {
        final harness = serving();

        await succeed(read(harness, null));

        expect(await succeed(harness.library.cachedList()), isNull);
      });

      test('passes a failure on', () async {
        final harness = serving()
          ..server.down = failedAnswer(const AuthFailed(), status: 401);

        expect(await failureOf(read(harness, null)), isA<AuthFailed>());
        expect(harness.asked(path).length, lessThanOrEqualTo(1));
      });

      // As for the library: a queued movie would otherwise show as missing.
      test('fails when the queue cannot be read', () async {
        final harness = serving()
          ..server.answers['api/v3/queue'] = failedAnswer(
            const ServerError(statusCode: 500),
            status: 500,
          );

        expect(await failureOf(read(harness, null)), isA<ServerError>());
      });

      for (final field in ['id', 'title']) {
        test('cannot understand a movie without its $field', () async {
          final harness = serving([movies().first..remove(field)]);

          expect(
            await failureOf(read(harness, null)),
            isA<MalformedResponse>(),
          );
        });
      }
    });
  }
}
