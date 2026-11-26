// Manual import of music: files are matched to an artist, an album and tracks,
// and there is no language correction (story 8, scenario 4).
//
// `activity_manualimport` is what Lidarr said of a download it matched to its
// artist only. `activity_manualimport_reprocess` is its answer once the album
// and tracks were chosen, which has no `name` and no `audioTags`.
//
// What the module sends, as the web UI does:
//   reprocess  POST manualimport [{id, path, artistId, albumId,
//              albumReleaseId?, trackIds, quality, downloadId, ...}]
//   import     POST command {name: ManualImport, importMode, files: [{path,
//              artistId, albumId, albumReleaseId, trackIds, quality, ...}]}
// The server chooses the release of an album: it is sent back only for the
// album it was given for.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

final _downloadId =
    records('activity_manualimport').first['downloadId']! as String;

QueueItem _item([String? downloadId]) => QueueItem(
  id: 1,
  title: 'download',
  status: QueueStatus.completed,
  trackedState: TrackedState.importBlocked,
  severity: QueueSeverity.warning,
  progress: 1,
  sizeLeft: 0,
  protocol: DownloadProtocol.torrent,
  downloadId: downloadId,
);

/// [candidate] as the user corrected it.
ManualImportCandidate _corrected(
  ManualImportCandidate candidate, {
  ItemRef? artist,
  int? albumId = 1,
  List<int> trackIds = const [1],
  Quality? quality,
}) => ManualImportCandidate(
  path: candidate.path,
  size: candidate.size,
  rawJson: candidate.rawJson,
  downloadId: candidate.downloadId,
  matchedRef: artist ?? candidate.matchedRef,
  albumId: albumId,
  trackIds: trackIds,
  quality: quality ?? candidate.quality,
  selected: true,
);

Future<List<ManualImportCandidate>> _candidates(Harness harness) =>
    ok(harness.queue.importCandidates(_item(_downloadId)));

/// The candidates after the server took the chosen album and tracks.
Future<List<ManualImportCandidate>> _reprocessed(Harness harness) async {
  final candidates = await _candidates(harness);
  final answer = await ok(
    harness.queue.reprocess([
      for (final (index, candidate) in candidates.indexed)
        _corrected(candidate, trackIds: [index + 1]),
    ]),
  );
  harness.server.requests.clear();
  return answer;
}

void main() {
  group('candidates', () {
    test('of a download, matched to the artist', () async {
      final harness = Harness();
      final raw = records('activity_manualimport').first;

      final candidates = await _candidates(harness);

      expect(harness.asked, [line(HttpMethod.get, 'manualimport')]);
      final query = harness.server.requests.single.query;
      expect(query['downloadId'], [_downloadId]);
      expect(query['filterExistingFiles'], ['true']);
      expect(candidates, hasLength(records('activity_manualimport').length));
      final first = candidates.first;
      expect(first.path, raw['path']);
      expect(first.size, raw['size']);
      expect(first.downloadId, _downloadId);
      expect(first.matchedRef, artistRef(1));
      expect(first.albumId, isNull);
      expect(first.trackIds, isEmpty);
      expect(first.episodeIds, isEmpty);
      expect(first.quality?.name, 'MP3-320');
      expect(first.languages, isEmpty);
      expect(first.rejections, [
        for (final rejection in raw['rejections']! as List<Object?>)
          (rejection! as Map<String, Object?>)['reason'],
      ]);
      expect(first.rawJson, raw);
    });

    test('names the album and tracks where the server has them', () async {
      final harness = Harness();
      harness.server.manualImport = records('activity_manualimport_reprocess');

      final first = (await _candidates(harness)).first;

      final raw = records('activity_manualimport_reprocess').first;
      expect(first.matchedRef, artistRef(1));
      expect(first.albumId, 1);
      expect(first.trackIds, [
        for (final track in raw['tracks']! as List<Object?>)
          (track! as Map<String, Object?>)['id'],
      ]);
    });

    test('none for an entry without a download', () async {
      final harness = Harness();

      expect(await ok(harness.queue.importCandidates(_item())), isEmpty);
      expect(harness.server.requests, isEmpty);
    });
  });

  test('qualities can be corrected, languages cannot', () async {
    final harness = Harness();

    final choices = await ok(harness.queue.importChoices());

    expect(choices.qualities.map((quality) => quality.id), [
      for (final definition in records('qualitydefinition'))
        (definition['quality']! as Map<String, Object?>)['id'],
    ]);
    expect(choices.languages, isEmpty);
  });

  group('reprocess', () {
    test('sends the chosen artist, album and tracks', () async {
      final harness = Harness();
      final candidate = (await _candidates(harness)).first;
      harness.server.requests.clear();
      final raw = candidate.rawJson;

      await ok(harness.queue.reprocess([_corrected(candidate)]));

      final write = harness.server.writes.single;
      expect(write.path, 'api/v1/manualimport');
      final sent =
          (sentBody(write)! as List<Object?>).single! as Map<String, Object?>;
      expect(sent['id'], raw['id']);
      expect(sent['path'], candidate.path);
      expect(sent['artistId'], 1);
      expect(sent['albumId'], 1);
      expect(sent['trackIds'], [1]);
      expect(sent['downloadId'], _downloadId);
      expect(sent['quality'], raw['quality']);
      // 0 in the record: the server has not chosen one.
      expect(sent['albumReleaseId'], isNull);
      expect(sent.containsKey('episodeIds'), isFalse);
    });

    test('takes the match and release of the answer', () async {
      final harness = Harness();
      final candidates = await _candidates(harness);

      final answer = await ok(
        harness.queue.reprocess([
          for (final (index, candidate) in candidates.indexed)
            _corrected(candidate, trackIds: [index + 1]),
        ]),
      );

      expect(answer.map((c) => c.path), candidates.map((c) => c.path));
      expect(answer.map((c) => c.size), candidates.map((c) => c.size));
      expect(answer.map((c) => c.albumId), everyElement(1));
      expect(answer.map((c) => c.trackIds), [
        [1],
        [2],
        [3],
      ]);
      expect(answer.first.rawJson['albumReleaseId'], 1);
    });

    // A release of the album chosen before is not one of this album.
    test('drops the release when another album is chosen', () async {
      final harness = Harness();
      final candidate = (await _reprocessed(harness)).first;

      await ok(
        harness.queue.reprocess([
          _corrected(candidate, albumId: 3, trackIds: const []),
        ]),
      );

      final sent =
          (sentBody(harness.server.writes.single)! as List<Object?>).single!
              as Map<String, Object?>;
      expect(sent['albumId'], 3);
      expect(sent['albumReleaseId'], isNull);
    });

    test('a file without an artist is refused, with nothing sent', () async {
      final harness = Harness();
      final raw = records('activity_manualimport').first;

      expect(
        await failureOf(
          harness.queue.reprocess([
            ManualImportCandidate(
              path: raw['path']! as String,
              size: 1,
              rawJson: raw,
              downloadId: _downloadId,
              albumId: 1,
            ),
          ]),
        ),
        isA<Validation>(),
      );
      expect(harness.server.requests, isEmpty);
    });
  });

  group('import', () {
    test('starts the import of the chosen files', () async {
      final harness = Harness();
      final candidates = await _reprocessed(harness);

      final command = await ok(harness.queue.importFiles(candidates));

      expect(command.name, 'ManualImport');
      expect(command.id, record('activity_command_manualimport')['id']);
      final write = harness.server.writes.single;
      expect(write.path, 'api/v1/command');
      final body = sentBody(write)! as Map<String, Object?>;
      expect(body['name'], 'ManualImport');
      expect(body['importMode'], 'auto');
      // Never on its own: it deletes the files the album has.
      expect(body['replaceExistingFiles'], isNot(true));
      final files = (body['files']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(files, hasLength(candidates.length));
      for (final (index, file) in files.indexed) {
        expect(file['path'], candidates[index].path);
        expect(file['artistId'], 1);
        expect(file['albumId'], 1);
        expect(file['albumReleaseId'], 1);
        expect(file['trackIds'], [index + 1]);
        expect(file['downloadId'], _downloadId);
        expect(file['quality'], candidates[index].rawJson['quality']);
        expect(file.containsKey('languages'), isFalse);
        expect(file.containsKey('episodeIds'), isFalse);
      }
    });

    test('sends a corrected quality as the server defines it', () async {
      final harness = Harness();
      final candidate = (await _reprocessed(harness)).first;

      await ok(
        harness.queue.importFiles([
          _corrected(
            candidate,
            trackIds: candidate.trackIds,
            quality: const Quality(id: 6, name: 'FLAC'),
          ),
        ]),
      );

      final body =
          sentBody(harness.server.writes.single)! as Map<String, Object?>;
      final file =
          (body['files']! as List<Object?>).single! as Map<String, Object?>;
      final quality = file['quality']! as Map<String, Object?>;
      expect(
        quality['quality'],
        records('qualitydefinition')
            .map((d) => d['quality']! as Map<String, Object?>)
            .singleWhere((q) => q['id'] == 6),
      );
    });

    test('of nothing is refused, with nothing sent', () async {
      final harness = Harness();

      expect(await failureOf(harness.queue.importFiles([])), isA<Validation>());
      expect(harness.server.requests, isEmpty);
    });

    for (final (name, change) in [
      ('an album', (ManualImportCandidate c) => _corrected(c, albumId: null)),
      (
        'tracks',
        (ManualImportCandidate c) => _corrected(c, trackIds: const []),
      ),
      // Only the server can choose the release: it takes a reprocessing.
      (
        'a release of its album',
        (ManualImportCandidate c) =>
            _corrected(c, albumId: 3, trackIds: const [415]),
      ),
    ]) {
      test('of a file without $name is refused, nothing written', () async {
        final harness = Harness();
        final candidate = (await _reprocessed(harness)).first;

        expect(
          await failureOf(harness.queue.importFiles([change(candidate)])),
          isA<Validation>(),
        );
        expect(harness.server.writes, isEmpty);
      });
    }

    test('an accepted import that breaks off has an unknown outcome', () async {
      final harness = Harness();
      final candidates = await _reprocessed(harness);
      harness.server.writeAnswer = FakeLidarr.body('{"id":', status: 201);

      expect(
        await failureOf(harness.queue.importFiles(candidates)),
        anyOf(isA<OutcomeUnknown>(), isA<MalformedResponse>()),
      );
      expect(harness.server.writes, hasLength(1));
    });
  });
}
