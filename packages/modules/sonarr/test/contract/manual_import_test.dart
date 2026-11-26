// Sonarr's mapping of manual import: which series and episodes a file is
// matched to, what is sent back, and what is never sent. activity_support.dart
// states the mapping. Which other fields of a record are sent, and how a
// corrected quality is, is the shared Servarr client's.

import 'dart:convert';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'activity_support.dart';
import 'support.dart';

const _german = Language(id: 4, name: 'German');
const _bluray = Quality(id: 7, name: 'Bluray-1080p');

/// The queue entry of [download], as the module reads it.
Future<QueueItem> _item(ActivityHarness harness, String download) async {
  final queue = await ok(harness.queue.queue());
  return queue.firstWhere((item) => item.downloadId == download);
}

/// The candidates of [download], after which no request is remembered.
Future<List<ManualImportCandidate>> _candidates(
  ActivityHarness harness,
  String download,
) async {
  final item = await _item(harness, download);
  final candidates = await ok(harness.queue.importCandidates(item));
  harness.activity.requests.clear();
  return candidates;
}

Future<ManualImportCandidate> _one(
  ActivityHarness harness,
  String download,
) async => (await _candidates(harness, download)).single;

/// [candidate] as the user left it. A null [matchedRef] keeps the series
/// unless [noSeries].
ManualImportCandidate _corrected(
  ManualImportCandidate candidate, {
  ItemRef? matchedRef,
  bool noSeries = false,
  List<int>? episodeIds,
  Quality? quality,
  List<Language>? languages,
}) => ManualImportCandidate(
  path: candidate.path,
  size: candidate.size,
  rawJson: candidate.rawJson,
  downloadId: candidate.downloadId,
  matchedRef: noSeries ? null : matchedRef ?? candidate.matchedRef,
  episodeIds: episodeIds ?? candidate.episodeIds,
  quality: quality ?? candidate.quality,
  languages: languages ?? candidate.languages,
  rejections: candidate.rejections,
  selected: true,
);

/// The files of the one import command.
List<Map<String, Object?>> _files(ActivityHarness harness) {
  final request = harness.activity.writes.single;
  expect(request.path, 'api/v3/command');
  final body = sentBody(request)! as Map<String, Object?>;
  expect(body['name'], 'ManualImport');
  expect(body['importMode'], 'auto');
  return (body['files']! as List<Object?>).cast<Map<String, Object?>>();
}

/// The entries of the one reprocessing.
List<Map<String, Object?>> _reprocessed(ActivityHarness harness) {
  final request = harness.activity.writes.single;
  expect(request.path, 'api/v3/manualimport');
  return (sentBody(request)! as List<Object?>).cast<Map<String, Object?>>();
}

void main() {
  group('candidates', () {
    test('are asked by the download of the entry', () async {
      final harness = ActivityHarness();
      final item = await _item(harness, pairDownload);
      harness.activity.requests.clear();

      await ok(harness.queue.importCandidates(item));

      final request = harness.activity.requests.single;
      expect(request.method, HttpMethod.get);
      expect(request.path, 'api/v3/manualimport');
      expect(request.query, {
        'downloadId': [pairDownload],
        'filterExistingFiles': ['true'],
      });
    });

    test('name their series and episodes', () async {
      final harness = ActivityHarness();
      final raw = records('activity_manualimport');

      final candidates = await _candidates(harness, pairDownload);

      expect(candidates, hasLength(2));
      expect(candidates.map((c) => c.matchedRef), [seriesRef(1), seriesRef(1)]);
      expect(candidates.map((c) => c.episodeIds), [
        [19],
        [20],
      ]);
      for (final (index, candidate) in candidates.indexed) {
        expect(candidate.path, raw[index]['path']);
        expect(candidate.size, 2097152);
        expect(candidate.downloadId, pairDownload);
        expect(candidate.quality?.id, 3);
        expect(candidate.languages.single.id, 1);
        expect(candidate.rejections, hasLength(1));
        expect(candidate.rawJson, raw[index]);
      }
    });

    test('name every episode of a file', () async {
      final harness = ActivityHarness();
      final raw = records('activity_manualimport').first;
      final episode =
          (raw['episodes']! as List<Object?>).single! as Map<String, Object?>;
      raw['episodes'] = [
        episode,
        {...episode, 'id': 20},
      ];
      harness.activity.overrides['manualimport'] = FakeSonarr.body(
        jsonEncode([raw]),
      );

      final candidate = await _one(harness, pairDownload);

      expect(candidate.episodeIds, [19, 20]);
    });

    test('may have a series and no episodes', () async {
      final harness = ActivityHarness();
      final item = await _item(harness, noEpisodesDownload);
      // The queue knows the series of this one too, but no episode.
      expect(item.parent, seriesRef(1));
      expect(item.itemRef, isNull);

      final candidate = (await ok(harness.queue.importCandidates(item))).single;

      expect(candidate.rawJson, isNot(contains('episodes')));
      expect(candidate.matchedRef, seriesRef(1));
      expect(candidate.episodeIds, isEmpty);
    });

    test('may have neither', () async {
      final candidate = await _one(ActivityHarness(), unmatchedDownload);

      expect(candidate.matchedRef, isNull);
      expect(candidate.episodeIds, isEmpty);
      expect(candidate.languages.single.id, 0);
    });

    test('are none for an entry without a download', () async {
      final harness = ActivityHarness();
      const item = QueueItem(
        id: 1,
        title: 'Some.Release-GRP',
        status: QueueStatus.delayed,
        trackedState: TrackedState.unknown,
        severity: QueueSeverity.ok,
        progress: 0,
        sizeLeft: 0,
        protocol: DownloadProtocol.torrent,
        needsManualImport: false,
      );

      expect(await ok(harness.queue.importCandidates(item)), isEmpty);
      expect(harness.activity.requests, isEmpty);
    });
  });

  test('offers the qualities and languages of the server', () async {
    final harness = ActivityHarness();

    final choices = await ok(harness.queue.importChoices());

    expect(harness.asked, hasLength(2));
    expect(harness.asked.toSet(), {
      line(HttpMethod.get, 'qualitydefinition'),
      line(HttpMethod.get, 'language'),
    });
    expect(
      choices.qualities,
      hasLength(records('activity_qualitydefinition').length),
    );
    expect(choices.languages.map((language) => language.id), contains(4));
    expect(
      choices.languages.map((language) => language.id),
      everyElement(greaterThanOrEqualTo(0)),
    );
  });

  group('reprocess', () {
    Future<List<ManualImportCandidate>> corrections(
      ActivityHarness harness,
    ) async {
      final candidates = await _candidates(harness, pairDownload);
      return [
        _corrected(
          candidates.first,
          episodeIds: [21],
          quality: _bluray,
          languages: const [_german],
        ),
        candidates.last,
      ];
    }

    test('sends the series, season and episodes of each file', () async {
      final harness = ActivityHarness();
      final sent = await corrections(harness);

      await ok(harness.queue.reprocess(sent));

      expect(harness.asked, [
        line(HttpMethod.get, 'qualitydefinition'),
        line(HttpMethod.post, 'manualimport'),
      ]);
      final entries = _reprocessed(harness);
      expect(entries, hasLength(2));
      for (final (index, entry) in entries.indexed) {
        expect(entry['id'], sent[index].rawJson['id']);
        expect(entry['path'], sent[index].path);
        expect(entry['downloadId'], pairDownload);
        expect(entry['seriesId'], 1);
        expect(entry['seasonNumber'], 1);
        expect(entry['releaseType'], 'multiEpisode');
        expect(entry, isNot(contains('series')));
        expect(entry, isNot(contains('episodes')));
      }
      expect(entries.first['episodeIds'], [21]);
      expect(entries.last['episodeIds'], [20]);
      expect(entries.first['languages'], [
        {'id': 4, 'name': 'German'},
      ]);
      expect(
        (entries.first['quality']! as Map<String, Object?>)['quality'],
        records('activity_qualitydefinition')
            .map((d) => d['quality']! as Map<String, Object?>)
            .singleWhere((quality) => quality['id'] == 7),
      );
    });

    // The answer names the series by `seriesId` alone.
    test('gives what the server now says of each file', () async {
      final harness = ActivityHarness();

      final after = await ok(
        harness.queue.reprocess(await corrections(harness)),
      );

      expect(after.map((c) => c.matchedRef), [seriesRef(1), seriesRef(1)]);
      expect(after.map((c) => c.episodeIds), [
        [21],
        [20],
      ]);
      expect(after.first.quality?.id, 7);
      expect(after.first.languages.single.id, 4);
      expect(after.first.rejections, hasLength(2));
      expect(after.first.size, 2097152);
    });

    test('whose files can then be imported', () async {
      final harness = ActivityHarness();
      final after = await ok(
        harness.queue.reprocess(await corrections(harness)),
      );
      harness.activity.requests.clear();

      await ok(harness.queue.importFiles(after));

      // The quality is now the record's own, so no definition is read.
      expect(harness.asked, [line(HttpMethod.post, 'command')]);
      final first = _files(harness).first;
      expect(first['seriesId'], 1);
      expect(first['seasonNumber'], 1);
      expect(first['episodeIds'], [21]);
      expect(first['folderName'], after.first.rawJson['folderName']);
      expect(first['folderName'], isNotNull);
    });

    test('of nothing asks nothing', () async {
      final harness = ActivityHarness();

      expect(await ok(harness.queue.reprocess(const [])), isEmpty);
      expect(harness.activity.requests, isEmpty);
    });
  });

  group('import', () {
    test('sends the files as one command and gives it', () async {
      final harness = ActivityHarness();
      final candidates = await _candidates(harness, pairDownload);

      final command = await ok(harness.queue.importFiles(candidates));

      expect(harness.asked, [line(HttpMethod.post, 'command')]);
      expect(command.id, 25);
      expect(command.name, 'ManualImport');
      expect(command.status, CommandStatus.started);
      final files = _files(harness);
      expect(files.map((file) => file['path']), candidates.map((c) => c.path));
      expect(files.map((file) => file['seriesId']), [1, 1]);
      expect(files.map((file) => file['episodeIds']), [
        [19],
        [20],
      ]);
    });

    test('sends the series and episodes the user chose', () async {
      final harness = ActivityHarness();
      final candidate = (await _candidates(harness, pairDownload)).first;

      await ok(
        harness.queue.importFiles([
          _corrected(candidate, matchedRef: seriesRef(2), episodeIds: [7, 8]),
        ]),
      );

      final file = _files(harness).single;
      expect(file['seriesId'], 2);
      expect(file['episodeIds'], [7, 8]);
    });

    test('takes a file once the user has matched it', () async {
      final harness = ActivityHarness();
      final candidate = await _one(harness, unmatchedDownload);

      await ok(
        harness.queue.importFiles([
          _corrected(candidate, matchedRef: seriesRef(1), episodeIds: [22]),
        ]),
      );

      final file = _files(harness).single;
      expect(file['seriesId'], 1);
      expect(file['episodeIds'], [22]);
      expect(file, isNot(contains('seasonNumber')));
      expect(file, isNot(contains('folderName')));
    });

    test('of nothing is refused and asks nothing', () async {
      final harness = ActivityHarness();

      expect(
        await failureOf(harness.queue.importFiles(const [])),
        isA<Validation>(),
      );
      expect(harness.activity.requests, isEmpty);
    });

    test('an unknown outcome is reported and not retried', () async {
      final harness = ActivityHarness();
      final candidates = await _candidates(harness, pairDownload);
      harness.activity.writeAnswer = FakeSonarr.body(
        '',
        status: 504,
        write: true,
      );

      expect(
        await failureOf(harness.queue.importFiles(candidates)),
        isA<OutcomeUnknown>(),
      );
      expect(harness.activity.requests, hasLength(1));
    });
  });

  // The server throws on these, or reports success and imports nothing.
  group('a file without a series or episodes', () {
    final incomplete =
        <String, Future<ManualImportCandidate> Function(ActivityHarness)>{
          'neither, as the server sent it': (harness) =>
              _one(harness, unmatchedDownload),
          'no episodes, as the server sent it': (harness) =>
              _one(harness, noEpisodesDownload),
          'a series chosen but no episodes': (harness) async => _corrected(
            await _one(harness, unmatchedDownload),
            matchedRef: seriesRef(1),
          ),
          'episodes but no series': (harness) async => _corrected(
            (await _candidates(harness, pairDownload)).first,
            noSeries: true,
          ),
          'every episode taken away': (harness) async => _corrected(
            (await _candidates(harness, pairDownload)).first,
            episodeIds: const [],
          ),
        };
    final writes =
        <
          String,
          ServiceResult<Object?> Function(
            QueueProvider,
            List<ManualImportCandidate>,
          )
        >{
          'reprocess': (queue, candidates) => queue.reprocess(candidates),
          'importFiles': (queue, candidates) => queue.importFiles(candidates),
        };

    for (final MapEntry(key: call, value: write) in writes.entries) {
      for (final MapEntry(key: name, value: make) in incomplete.entries) {
        test('$call refuses one with $name', () async {
          final harness = ActivityHarness();
          final candidate = await make(harness);
          harness.activity.requests.clear();

          expect(
            await failureOf(write(harness.queue, [candidate])),
            isA<Validation>(),
          );
          expect(harness.activity.writes, isEmpty);
        });
      }

      // A complete file, with a corrected quality, goes with none of them.
      test('$call writes nothing when one of several is so', () async {
        final harness = ActivityHarness();
        final complete = _corrected(
          (await _candidates(harness, pairDownload)).first,
          quality: _bluray,
        );
        final other = await _one(harness, noEpisodesDownload);
        harness.activity.requests.clear();

        expect(
          await failureOf(write(harness.queue, [complete, other])),
          isA<Validation>(),
        );
        expect(harness.activity.writes, isEmpty);
      });
    }
  });
}
