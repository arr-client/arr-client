// The QueueProvider read against recorded answers. Reading, paging and mapping
// the records is shared Servarr behaviour and is tested there; here is what
// Radarr binds: its movies and its include-unknown flag.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radarr/radarr_module.dart';

import 'library_support.dart';

QueueProvider _queue(Harness harness) =>
    RadarrModule().capability<QueueProvider>(harness.context)!;

void main() {
  test('asks for the queue with the unmatched downloads', () async {
    final harness = Harness();

    expect(await succeed(_queue(harness).queue()), isEmpty);

    final request = harness.server.requests.single;
    expect(request.method, HttpMethod.get);
    expect(request.path, 'api/v3/queue');
    expect(request.query['includeUnknownMovieItems'], ['true']);
  });

  test('names the movie of each download, where there is one', () async {
    final wire = FakeRadarr.recordedQueue();
    final harness = Harness()..server.queue = FakeRadarr.recordedQueue();

    final items = await succeed(_queue(harness).queue());

    expect(items.map((item) => item.id), wire.map((record) => record['id']));
    expect(items.map((item) => item.itemRef), [
      movieRef(2),
      // The download that matches no movie.
      null,
      movieRef(6),
      movieRef(3),
    ]);
    expect(items.map((item) => item.parent), everyElement(isNull));
  });

  test('passes on a failure', () async {
    const failure = AuthFailed();
    final harness = Harness()..server.down = failedAnswer(failure);

    expect(await failureOf(_queue(harness).queue()), same(failure));
  });
}
