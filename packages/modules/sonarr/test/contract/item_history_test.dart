// The history of a series, a season and an episode, and Sonarr's mapping of its
// events. Paging itself is the shared Servarr client's.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Future<ResultPage<HistoryEvent>> _history(
  Harness harness,
  MediaTarget target, {
  int page = 1,
}) => ok(harness.history.history(target: target, page: page));

final _series = MediaTarget(seriesRef(1));

void main() {
  test('of a series, newest first', () async {
    final harness = Harness();

    final page = await _history(harness, _series);

    expect(page.items.map((e) => e.id), [9, 8, 7, 6, 5, 4, 3, 2, 1]);
    expect(page.page, 1);
    expect(page.hasMore, isFalse);
  });

  test('maps the event types', () async {
    final page = await _history(Harness(), _series);

    expect(
      {for (final event in page.items) event.id: event.eventType},
      {
        9: HistoryEventType.failed,
        8: HistoryEventType.renamed,
        7: HistoryEventType.deleted,
        6: HistoryEventType.imported,
        5: HistoryEventType.grabbed,
        4: HistoryEventType.grabbed,
        3: HistoryEventType.grabbed,
        2: HistoryEventType.grabbed,
        1: HistoryEventType.grabbed,
      },
    );
  });

  // The rest of Sonarr's event types, which the recording does not hold.
  for (final (name, type) in [
    ('seriesFolderImported', HistoryEventType.imported),
    ('downloadIgnored', HistoryEventType.other),
    ('unknown', HistoryEventType.other),
    ('somethingNew', HistoryEventType.other),
  ]) {
    test('$name is ${type.name}', () async {
      final harness = Harness();
      harness.server.history.first['eventType'] = name;

      final page = await _history(harness, _series);

      expect(page.items.first.eventType, type);
    });
  }

  test('maps the fields of an event', () async {
    final harness = Harness();
    final raw = byId(harness.server.history, 5);
    final data = raw['data']! as Map<String, Object?>;

    final page = await _history(harness, _series);

    final event = page.items.singleWhere((e) => e.id == 5);
    expect(event.date, DateTime.utc(2026, 11, 26, 12, 53, 5));
    expect(event.date.isUtc, isTrue);
    expect(event.itemRef, episodeRef(19));
    expect(event.downloadId, raw['downloadId']);
    expect(event.sourceTitle, raw['sourceTitle']);
    expect(event.details, containsPair('indexer', data['indexer']));
    expect(
      event.details,
      containsPair('downloadClient', data['downloadClient']),
    );
    expect(event.details, containsPair('size', '1468006400'));
  });

  test('an event without a download', () async {
    final page = await _history(Harness(), _series);

    expect(page.items.singleWhere((e) => e.id == 7).downloadId, isNull);
  });

  test('of a season', () async {
    final harness = Harness();
    final special = Map.of(byId(harness.server.history, 1));
    special['id'] = 10;
    special['episodeId'] = 1;
    harness.server.history.insert(0, special);

    final season = await _history(
      harness,
      MediaTarget(seriesRef(1), seasonNumber: 1),
    );
    final specials = await _history(
      harness,
      MediaTarget(seriesRef(1), seasonNumber: 0),
    );

    expect(season.items.map((e) => e.id), [9, 8, 7, 6, 5, 4, 3, 2, 1]);
    expect(specials.items.map((e) => e.id), [10]);
  });

  test('of an episode', () async {
    final page = await _history(Harness(), MediaTarget(episodeRef(17)));

    expect(page.items.map((e) => e.id), [6, 3]);
    expect(page.items.map((e) => e.itemRef).toSet(), {episodeRef(17)});
    expect(page.hasMore, isFalse);
  });

  test('a later page of an episode is asked of the server', () async {
    final harness = Harness();

    final page = await _history(harness, MediaTarget(episodeRef(17)), page: 2);

    expect(page.page, 2);
    expect(page.items, isEmpty);
    expect(page.hasMore, isFalse);
  });

  // Sonarr gives a series' history whole.
  test('a series has no second page', () async {
    final page = await _history(Harness(), _series, page: 2);

    expect(page.items, isEmpty);
    expect(page.hasMore, isFalse);
  });

  test('nothing yet', () async {
    final harness = Harness();
    harness.server.history.clear();

    expect((await _history(harness, _series)).items, isEmpty);
  });

  test('of a deleted series is not found', () async {
    expect(
      await failureOf(
        Harness().history.history(target: MediaTarget(seriesRef(999))),
      ),
      isA<NotFound>(),
    );
  });

  test('an unreachable server is a failure', () async {
    final harness = Harness()..server.goOffline();

    expect(
      await failureOf(harness.history.history(target: _series)),
      isA<Unreachable>(),
    );
  });
}
