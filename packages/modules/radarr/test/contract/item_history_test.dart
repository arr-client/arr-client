// The history of one movie against recorded answers (spec story 2). The overall
// history and the history actions are not covered here.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'library_support.dart';

Future<ResultPage<HistoryEvent>> _history(Harness harness, int movieId) =>
    succeed(harness.history.history(target: MediaTarget(movieRef(movieId))));

void main() {
  test('asks for the history of the movie', () async {
    final harness = Harness();

    await _history(harness, 1);

    final request = harness.server.requests.single;
    expect(request.method, HttpMethod.get);
    expect(request.path, 'api/v3/history/movie');
    expect(request.query['movieId'], ['1']);
  });

  test('is one page, as the server does not page it', () async {
    final page = await _history(Harness(), 1);

    expect(page.page, 1);
    expect(page.hasMore, isFalse);
    expect(page.items.map((e) => e.id), [5, 4, 3, 2, 1]);
  });

  test('is newest first whatever order the server sends', () async {
    final harness = Harness();
    harness.server.answers['api/v3/history/movie'] = jsonAnswer(
      records(fixture('history_movie_4')).reversed.toList(),
    );

    final page = await _history(harness, 4);

    expect(page.items.map((e) => e.id), [10, 9]);
  });

  test('has nothing after its one page, and asks no server', () async {
    final harness = Harness();

    final page = await succeed(
      harness.history.history(target: MediaTarget(movieRef(1)), page: 2),
    );

    expect(page.page, 2);
    expect(page.items, isEmpty);
    expect(page.hasMore, isFalse);
    expect(harness.server.requests, isEmpty);
  });

  test('maps the events of a movie', () async {
    final wire = records(fixture('history_movie_1'));

    final items = (await _history(Harness(), 1)).items;

    expect(items.map((e) => e.eventType), [
      HistoryEventType.renamed,
      HistoryEventType.imported,
      HistoryEventType.deleted,
      HistoryEventType.imported,
      HistoryEventType.deleted,
    ]);
    for (final (index, event) in items.indexed) {
      expect(event.itemRef, movieRef(1));
      expect(event.sourceTitle, wire[index]['sourceTitle']);
      expect(
        event.date.toUtc(),
        DateTime.parse(wire[index]['date']! as String),
      );
      expect(event.downloadId, isNull);
    }
    expect(items[2].details, containsPair('reason', 'Upgrade'));
    expect(items[2].details, containsPair('size', '11524858'));
  });

  test('keeps the download of a grab and of its failure', () async {
    final items = (await _history(Harness(), 4)).items;

    expect(items.map((e) => e.eventType), [
      HistoryEventType.failed,
      HistoryEventType.grabbed,
    ]);
    for (final event in items) {
      expect(event.itemRef, movieRef(4));
      expect(event.downloadId, 'ABCDEF0000000000000000000000000000000001');
    }
  });

  test('maps the other event types', () async {
    for (final (wire, expected) in [
      ('movieFolderImported', HistoryEventType.imported),
      ('downloadIgnored', HistoryEventType.other),
      ('unknown', HistoryEventType.other),
      ('someFutureEvent', HistoryEventType.other),
    ]) {
      final harness = Harness();
      harness.server.answers['api/v3/history/movie'] = jsonAnswer([
        {...records(fixture('history_movie_1')).first, 'eventType': wire},
      ]);

      final event = (await _history(harness, 1)).items.single;

      expect(event.eventType, expected, reason: wire);
    }
  });

  test('is empty for a movie without events', () async {
    final page = await _history(Harness(), 3);

    expect(page.items, isEmpty);
    expect(page.hasMore, isFalse);
  });

  test('passes on a failure', () async {
    const failure = AuthFailed();
    final harness = Harness()..server.down = failedAnswer(failure);

    expect(
      await failureOf(
        harness.history.history(target: MediaTarget(movieRef(1))),
      ),
      same(failure),
    );
  });

  test('cannot understand a body of another shape', () async {
    final harness = Harness()..server.down = textAnswer('{}');

    expect(
      await failureOf(
        harness.history.history(target: MediaTarget(movieRef(1))),
      ),
      isA<MalformedResponse>(),
    );
  });
}
