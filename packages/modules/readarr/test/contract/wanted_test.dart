// The wanted lists of books (story 8, scenario 4, as story 6).

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

typedef _Read = ServiceResult<ResultPage<LibraryItem>> Function(
  WantedProvider wanted, {
  int page,
});

final _lists = <String, (_Read, String)>{
  'missing': (
    (wanted, {page = 1}) => wanted.missing(page: page),
    'overview_wanted_missing',
  ),
  'cutoff': (
    (wanted, {page = 1}) => wanted.cutoffUnmet(page: page),
    'overview_wanted_cutoff',
  ),
};

void main() {
  for (final MapEntry(key: path, value: (read, fixture)) in _lists.entries) {
    group(path, () {
      test('monitored books, a page at a time, in the order given', () async {
        final harness = Harness();

        final page = await ok(read(harness.wanted));

        final request = harness.server.requests.singleWhere(
          (request) => request.path == 'api/v1/wanted/$path',
        );
        expect(request.query['page'], ['1']);
        expect(request.query['monitored'], ['true']);
        expect(request.query['includeAuthor'], ['true']);
        expect(page.page, 1);
        expect(page.hasMore, isFalse);
        expect(page.items, everyElement(isA<Book>()));
        expect(page.items.map((item) => item.ref), [
          for (final r in pageRecords(fixture)) bookRef(r['id']! as int),
        ]);
      });

      test('names the author of each book', () async {
        final raw = pageRecords(fixture).first;
        final author = raw['author']! as Map<String, Object?>;

        final item = (await ok(read(Harness().wanted))).items.first;

        expect(item.title, raw['title']);
        expect(item.parent, authorRef(raw['authorId']! as int));
        expect(item.parentTitle, author['authorName']);
      });

      test('caches nothing', () async {
        final harness = Harness();

        await ok(read(harness.wanted));

        expect(await harness.cache.read(MediaKind.book), isNull);
      });
    });
  }

  test('the states of missing and cutoff books', () async {
    final harness = Harness()..server.queue.clear();

    final missing = (await ok(harness.wanted.missing())).items;
    final cutoff = (await ok(harness.wanted.cutoffUnmet())).items;

    expect(
      {for (final item in missing) item.ref.remoteId: item.state},
      {1: ItemState.missing, 19: ItemState.missing},
    );
    expect(
      {for (final item in cutoff) item.ref.remoteId: item.state},
      {10: ItemState.downloaded},
    );
  });

  test('a queued book shows as downloading', () async {
    final missing = (await ok(Harness().wanted.missing())).items;

    expect(
      {for (final item in missing) item.ref.remoteId: item.state},
      {1: ItemState.missing, 19: ItemState.downloading},
    );
  });

  test('fails when the queue cannot be read', () async {
    final harness = Harness();
    harness.server.overrides['queue'] = FakeReadarr.body('', status: 500);

    expect(await failureOf(harness.wanted.missing()), isA<ServerError>());
  });
}
