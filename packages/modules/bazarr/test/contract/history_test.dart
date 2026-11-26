// Subtitle history (FR-050, spec story 10 scenario 1; data-model.md
// SubtitleHistoryEvent), against recorded answers.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// The server gives no machine-readable time: its relative text and its local
/// date and time are shown as they are. What happened is told in its words.
void _expectEvent(SubtitleHistoryEvent event, Map<String, Object?> record) {
  expect(event.whenText, contains(record['timestamp']! as String));
  expect(event.whenText, contains(record['parsed_timestamp']! as String));
  expect(tag(event.language), wireTag(record['language']));
  expect(event.provider, record['provider']);
  expect(event.score, record['score']);
  expect(event.action, record['description']);
}

void main() {
  for (final version in versions) {
    group('Bazarr $version', () {
      test('lists movie history in the server order', () async {
        final harness = Harness(version);

        final page = await succeed(
          harness.subtitles.history(SubtitleMediaType.movie),
        );

        final wire = records('movies_history', version);
        expect(page.items, hasLength(wire.length));
        for (final (index, event) in page.items.indexed) {
          final record = wire[index];
          _expectEvent(event, record);
          expect(
            event.mediaRef,
            SubtitleMedia.movie(record['radarrId']! as int),
          );
          expect(event.title, record['title']);
        }
        expect(page.page, 1);
        expect(page.hasMore, isFalse);
        final request = harness.server.requests.single;
        expect(asked(request), 'GET movies/history');
        expect(queryOf(request).keys, unorderedEquals(['start', 'length']));
        expect(queryOf(request)['start'], '0');
        expect(int.parse(queryOf(request)['length']!), greaterThan(0));
      });

      test('lists episode history in the server order', () async {
        final harness = Harness(version);

        final page = await succeed(
          harness.subtitles.history(SubtitleMediaType.episode),
        );

        final wire = records('episodes_history', version);
        expect(page.items, hasLength(wire.length));
        for (final (index, event) in page.items.indexed) {
          final record = wire[index];
          _expectEvent(event, record);
          expect(
            event.mediaRef,
            SubtitleMedia.episode(
              seriesId: record['sonarrSeriesId']! as int,
              episodeId: record['sonarrEpisodeId']! as int,
            ),
          );
          for (final part in [
            'seriesTitle',
            'episode_number',
            'episodeTitle',
          ]) {
            expect(event.title, contains(record[part]! as String));
          }
        }
        expect(asked(harness.server.requests.single), 'GET episodes/history');
      });
    });
  }

  // A deletion has neither provider nor score.
  test('shows an event without a provider or a score', () async {
    final index = records('movies_history')
        .indexWhere((record) => record['action'] == 0);

    final page = await succeed(
      Harness().subtitles.history(SubtitleMediaType.movie),
    );

    expect(page.items[index].provider, isNull);
    expect(page.items[index].score, isNull);
  });

  test('shows an action it does not know', () async {
    final record = records('movies_history').first
      ..['action'] = 99
      ..['description'] = 'Something new.';
    final harness = Harness();
    harness.server.routes['GET movies/history'] = jsonAnswer({
      'data': [record],
      'total': 1,
    });

    final page = await succeed(
      harness.subtitles.history(SubtitleMediaType.movie),
    );

    expect(page.items.single.action, 'Something new.');
  });

  for (final type in SubtitleMediaType.values) {
    final name = '${type.name}s';

    test('asks for the next page of ${type.name} history', () async {
      final harness = Harness();
      harness.server.routes['GET $name/history'] = jsonAnswer({
        ...fixture('${name}_history'),
        'total': 10000,
      });

      await succeed(harness.subtitles.history(type));
      final second = await succeed(harness.subtitles.history(type, page: 2));

      final [one, two] = harness.server.requests.map(queryOf).toList();
      expect(two['start'], one['length']);
      expect(two['length'], one['length']);
      expect(second.page, 2);
      expect(second.hasMore, isTrue);
    });

    test('cannot understand ${type.name} history that breaks off', () async {
      final harness = Harness()..server.down = textAnswer('{"data":[{');

      expect(
        await failureOf(harness.subtitles.history(type)),
        isA<MalformedResponse>(),
      );
    });

    test('passes on a failure for ${type.name} history', () async {
      const failure = AuthFailed();
      final harness = Harness()..server.down = failedAnswer(failure);

      expect(await failureOf(harness.subtitles.history(type)), same(failure));
    });
  }
}
