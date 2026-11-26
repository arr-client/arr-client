// A movie with a download in the queue is `downloading`, before every other
// state (data-model.md LibraryItem.state). Reading and paging the queue is
// shared Servarr behaviour and is tested there.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'library_support.dart';

Harness _queued() => Harness()..server.queue = FakeRadarr.recordedQueue();

Future<Map<int, ItemState>> _states(Harness harness) async => {
  for (final movie in await succeed(harness.library.list()))
    movie.ref.remoteId: movie.state,
};

void main() {
  test('marks the queued movies of a list as downloading', () async {
    expect(await _states(_queued()), {
      1: ItemState.downloaded,
      // Not monitored and with a file: the queue still comes first.
      2: ItemState.downloading,
      3: ItemState.downloading,
      4: ItemState.unmonitored,
      5: ItemState.unreleased,
      6: ItemState.downloading,
      7: ItemState.missing,
    });
  });

  test('puts downloading before unreleased', () async {
    final harness = Harness();
    harness.server.queue = [
      {...FakeRadarr.recordedQueue().first, 'movieId': 5},
    ];

    expect((await _states(harness))[5], ItemState.downloading);
  });

  test('marks one movie that is queued', () async {
    final movie = await succeed(_queued().library.item(movieRef(3)));

    expect(movie.state, ItemState.downloading);
  });

  test('does not mark one movie for the downloads of others', () async {
    final movie = await succeed(_queued().library.item(movieRef(1)));

    expect(movie.state, ItemState.downloaded);
  });

  test('keeps the state for the cache', () async {
    final harness = _queued();
    await succeed(harness.library.list());
    harness.server.requests.clear();

    final cached = await succeed(harness.library.cachedList());
    final one = await succeed(harness.library.cachedItem(movieRef(3)));

    expect(harness.server.requests, isEmpty);
    expect(byId(cached!.value)[3]!.state, ItemState.downloading);
    expect(one!.value.state, ItemState.downloading);
    expect(
      harness.cache.entries[(MediaKind.movie, 3)]!.state,
      ItemState.downloading,
    );
  });

  // The state cannot be told without the queue, so the read fails and the
  // cache keeps what it had.
  group('when only the queue cannot be read', () {
    const failure = ServerError(statusCode: 500);

    Future<Harness> broken([
      ServiceFailure cause = failure,
      int status = 500,
    ]) async {
      final harness = _queued();
      await succeed(harness.library.list());
      harness.server
        ..queue = []
        ..answers['api/v3/queue'] = failedAnswer(cause, status: status);
      return harness;
    }

    test('a list fails and the cache is left alone', () async {
      final harness = await broken();

      expect(await failureOf(harness.library.list()), same(failure));
      expect(harness.cache.entries, hasLength(7));
      expect(
        harness.cache.entries[(MediaKind.movie, 3)]!.state,
        ItemState.downloading,
      );
    });

    test('one movie fails and the cache is left alone', () async {
      final harness = await broken();

      expect(await failureOf(harness.library.item(movieRef(3))), same(failure));
      expect(
        harness.cache.entries[(MediaKind.movie, 3)]!.state,
        ItemState.downloading,
      );
    });

    test('a queue that is not found does not say the movie is gone', () async {
      final harness = await broken(const NotFound(), 404);

      expect(
        await failureOf(harness.library.item(movieRef(3))),
        isA<ServerError>(),
      );
      expect(harness.cache.entries, contains((MediaKind.movie, 3)));
    });
  });

  test('follows the queue on the next read', () async {
    final harness = _queued();
    await succeed(harness.library.list());
    harness.server.queue = [];

    expect((await _states(harness))[3], ItemState.missing);
  });
}
