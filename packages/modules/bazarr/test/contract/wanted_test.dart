// Wanted subtitles (FR-050, spec story 10 scenario 1), against recorded
// answers.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  for (final version in versions) {
    group('Bazarr $version', () {
      test('lists wanted movie subtitles', () async {
        final harness = Harness(version);

        final page = await succeed(
          harness.subtitles.wanted(SubtitleMediaType.movie),
        );

        final wire = records('movies_wanted', version);
        expect(page.page, 1);
        expect(page.hasMore, isFalse);
        expect(page.items, hasLength(wire.length));
        for (final (index, want) in page.items.indexed) {
          final record = wire[index];
          expect(want.media, SubtitleMedia.movie(record['radarrId']! as int));
          expect(want.title, record['title']);
          expect(want.missing.map(tag), wireTags(record['missing_subtitles']));
        }
        final request = harness.server.requests.single;
        expect(asked(request), 'GET movies/wanted');
        expect(queryOf(request).keys, unorderedEquals(['start', 'length']));
        expect(queryOf(request)['start'], '0');
      });

      test('lists wanted episode subtitles', () async {
        final harness = Harness(version);

        final page = await succeed(
          harness.subtitles.wanted(SubtitleMediaType.episode),
        );

        final wire = records('episodes_wanted', version);
        expect(page.items, hasLength(wire.length));
        for (final (index, want) in page.items.indexed) {
          final record = wire[index];
          expect(
            want.media,
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
            expect(want.title, contains(record[part]! as String));
          }
          expect(want.missing.map(tag), wireTags(record['missing_subtitles']));
        }
        expect(asked(harness.server.requests.single), 'GET episodes/wanted');
      });
    });
  }

  // The profile asks for hearing-impaired German and forced Italian.
  test('keeps forced and hearing impaired apart', () async {
    final page = await succeed(
      Harness().subtitles.wanted(SubtitleMediaType.movie),
    );

    expect(page.items.first.missing.map(tag), contains('de:hi'));
    expect(page.items.first.missing.map(tag), contains('it:forced'));
  });

  for (final type in SubtitleMediaType.values) {
    final name = '${type.name}s';

    test('asks for the next page of wanted $name', () async {
      final harness = Harness();
      harness.server.routes['GET $name/wanted'] = jsonAnswer({
        ...fixture('${name}_wanted'),
        'total': 10000,
      });

      await succeed(harness.subtitles.wanted(type));
      final second = await succeed(harness.subtitles.wanted(type, page: 2));

      final [one, two] = harness.server.requests.map(queryOf).toList();
      expect(int.parse(one['length']!), greaterThan(0));
      expect(two['start'], one['length']);
      expect(two['length'], one['length']);
      expect(second.page, 2);
      expect(second.hasMore, isTrue);
    });

    test('cannot understand wanted $name without their ids', () async {
      final harness = Harness();
      harness.server.routes['GET $name/wanted'] = jsonAnswer({
        'data': [
          records('${name}_wanted').first
            ..remove('radarrId')
            ..remove('sonarrEpisodeId'),
        ],
        'total': 1,
      });

      expect(
        await failureOf(harness.subtitles.wanted(type)),
        isA<MalformedResponse>(),
      );
    });

    test('passes on a failure for wanted $name', () async {
      const failure = ServerError(statusCode: 500);
      final harness = Harness()..server.down = failedAnswer(failure);

      expect(await failureOf(harness.subtitles.wanted(type)), same(failure));
    });
  }
}
