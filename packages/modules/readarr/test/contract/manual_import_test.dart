// Manual import of books: files are matched to an author, a book and one of its
// editions, and there is no language correction (story 8, scenario 4).
//
// `activity_manualimport` is what Readarr said of a download it could match to
// nothing. `activity_manualimport_reprocess` is its answer for the same file
// once author 1 and book 29 were chosen. `activity_manualimport_matched` is a
// download it matched by itself.
//
// What the module sends, as the web UI does:
//   reprocess  POST manualimport [{id, path, authorId, bookId,
//              foreignEditionId?, quality, downloadId, ...}]
//   import     POST command {name: ManualImport, importMode, files: [{path,
//              authorId, bookId, foreignEditionId, quality, downloadId, ...}]}
// The server chooses the edition of a book: it is sent back only for the book
// it was given for.

import 'dart:convert';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

final _downloadId =
    records('activity_manualimport').single['downloadId']! as String;

/// The edition the server chose for book 29.
final _editionId =
    records('activity_manualimport_reprocess').single['foreignEditionId']!
        as String;

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
  ItemRef? author,
  int? bookId = 29,
  Quality? quality,
}) => ManualImportCandidate(
  path: candidate.path,
  size: candidate.size,
  rawJson: candidate.rawJson,
  downloadId: candidate.downloadId,
  matchedRef: author ?? candidate.matchedRef ?? authorRef(1),
  bookId: bookId,
  quality: quality ?? candidate.quality,
  selected: true,
);

Future<ManualImportCandidate> _candidate(Harness harness) async =>
    (await ok(harness.queue.importCandidates(_item(_downloadId)))).single;

/// The candidate after the server took the chosen author and book.
Future<ManualImportCandidate> _reprocessed(Harness harness) async {
  final candidate = await _candidate(harness);
  final answer = await ok(harness.queue.reprocess([_corrected(candidate)]));
  harness.server.requests.clear();
  return answer.single;
}

Map<String, Object?> _sentCandidate(Harness harness) =>
    (sentBody(harness.server.writes.single)! as List<Object?>).single!
        as Map<String, Object?>;

List<Map<String, Object?>> _sentFiles(Harness harness) {
  final body = sentBody(harness.server.writes.single)! as Map<String, Object?>;
  return (body['files']! as List<Object?>).cast<Map<String, Object?>>();
}

void main() {
  group('candidates', () {
    test('of a download nothing matches', () async {
      final harness = Harness();
      final raw = records('activity_manualimport').single;

      final candidate = await _candidate(harness);

      expect(harness.asked, [line(HttpMethod.get, 'manualimport')]);
      final query = harness.server.requests.single.query;
      expect(query['downloadId'], [_downloadId]);
      expect(query['filterExistingFiles'], ['true']);
      expect(candidate.path, raw['path']);
      expect(candidate.size, raw['size']);
      expect(candidate.downloadId, _downloadId);
      expect(candidate.matchedRef, isNull);
      expect(candidate.bookId, isNull);
      expect(candidate.albumId, isNull);
      expect(candidate.episodeIds, isEmpty);
      expect(candidate.quality?.name, 'EPUB');
      expect(candidate.languages, isEmpty);
      expect(candidate.rejections, [
        for (final rejection in raw['rejections']! as List<Object?>)
          (rejection! as Map<String, Object?>)['reason'],
      ]);
      expect(candidate.rawJson, raw);
    });

    test('names the author and book where the server has them', () async {
      final harness = Harness()
        ..server.manualImport = records('activity_manualimport_matched');

      final candidate = await _candidate(harness);

      expect(candidate.matchedRef, authorRef(1));
      expect(candidate.bookId, 18);
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
    expect(harness.asked, [line(HttpMethod.get, 'qualitydefinition')]);
  });

  group('reprocess', () {
    test('sends the chosen author and book', () async {
      final harness = Harness();
      final candidate = await _candidate(harness);
      harness.server.requests.clear();
      final raw = candidate.rawJson;

      await ok(harness.queue.reprocess([_corrected(candidate)]));

      expect(harness.server.writes.single.path, 'api/v1/manualimport');
      final sent = _sentCandidate(harness);
      expect(sent['id'], raw['id']);
      expect(sent['path'], candidate.path);
      expect(sent['authorId'], 1);
      expect(sent['bookId'], 29);
      expect(sent['foreignEditionId'], isNull);
      expect(sent['downloadId'], _downloadId);
      expect(sent['quality'], raw['quality']);
      expect(sent['replaceExistingFiles'], isNot(true));
      for (final field in ['albumId', 'trackIds', 'episodeIds', 'languages']) {
        expect(sent.containsKey(field), isFalse, reason: field);
      }
    });

    test('takes the match and edition of the answer', () async {
      final harness = Harness();
      final candidate = await _candidate(harness);

      final answer = (await ok(
        harness.queue.reprocess([_corrected(candidate)]),
      )).single;

      expect(answer.path, candidate.path);
      expect(answer.size, candidate.size);
      expect(answer.matchedRef, authorRef(1));
      expect(answer.bookId, 29);
      expect(answer.rawJson['foreignEditionId'], _editionId);
    });

    test('keeps the edition for the same book', () async {
      final harness = Harness();
      final candidate = await _reprocessed(harness);

      await ok(harness.queue.reprocess([_corrected(candidate)]));

      expect(_sentCandidate(harness)['foreignEditionId'], _editionId);
    });

    // An edition of the book chosen before is not one of this book.
    test('drops the edition when another book is chosen', () async {
      final harness = Harness();
      final candidate = await _reprocessed(harness);

      await ok(harness.queue.reprocess([_corrected(candidate, bookId: 9)]));

      final sent = _sentCandidate(harness);
      expect(sent['bookId'], 9);
      expect(sent['foreignEditionId'], isNull);
    });

    // The server leaves out what it has no value for, so the record would
    // otherwise keep the edition of the book chosen before.
    test('keeps no edition of the book before where none is given', () async {
      final harness = Harness();
      final candidate = await _reprocessed(harness);
      final answered = records('activity_manualimport_reprocess').single
        ..remove('foreignEditionId');
      (answered['book']! as Map<String, Object?>)['id'] = 9;
      harness.server.writeAnswer = FakeReadarr.body(
        jsonEncode([answered]),
        status: 202,
      );

      final answer = (await ok(
        harness.queue.reprocess([_corrected(candidate, bookId: 9)]),
      )).single;
      harness.server.requests.clear();

      expect(answer.bookId, 9);
      expect(answer.rawJson.containsKey('foreignEditionId'), isFalse);
      expect(
        await failureOf(harness.queue.importFiles([answer])),
        isA<Validation>(),
      );
      expect(harness.server.requests, isEmpty);
    });

    // Readarr may add to its answer the files the chosen book already has.
    test('leaves out the files it adds of the book', () async {
      final harness = Harness();
      final reprocessed = records('activity_manualimport_reprocess').single;
      harness.server.writeAnswer = FakeReadarr.body(
        jsonEncode([
          reprocessed,
          {
            ...reprocessed,
            'path': '/redacted/held.epub',
            'additionalFile': true,
          },
        ]),
        status: 202,
      );
      final candidate = await _candidate(harness);

      final answer = await ok(harness.queue.reprocess([_corrected(candidate)]));

      expect(answer.map((c) => c.path), [candidate.path]);
    });

    test('a file without an author is refused, with nothing sent', () async {
      final harness = Harness();
      final raw = records('activity_manualimport').single;

      expect(
        await failureOf(
          harness.queue.reprocess([
            ManualImportCandidate(
              path: raw['path']! as String,
              size: 1,
              rawJson: raw,
              downloadId: _downloadId,
              bookId: 29,
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
      final candidate = await _reprocessed(harness);

      final command = await ok(harness.queue.importFiles([candidate]));

      expect(command.name, 'ManualImport');
      expect(command.id, record('activity_command_manualimport')['id']);
      final write = harness.server.writes.single;
      expect(write.path, 'api/v1/command');
      final body = sentBody(write)! as Map<String, Object?>;
      expect(body['name'], 'ManualImport');
      expect(body['importMode'], 'auto');
      // Never on its own: it deletes the files the book has.
      expect(body['replaceExistingFiles'], isNot(true));
      final file = _sentFiles(harness).single;
      expect(file['path'], candidate.path);
      expect(file['authorId'], 1);
      expect(file['bookId'], 29);
      expect(file['foreignEditionId'], _editionId);
      expect(file['downloadId'], _downloadId);
      expect(file['quality'], candidate.rawJson['quality']);
      expect(file.containsKey('languages'), isFalse);
      expect(file.containsKey('episodeIds'), isFalse);
    });

    test('takes a file the server matched by itself', () async {
      final harness = Harness()
        ..server.manualImport = records('activity_manualimport_matched');
      final candidate = await _candidate(harness);
      harness.server.requests.clear();

      await ok(harness.queue.importFiles([candidate]));

      final file = _sentFiles(harness).single;
      expect(file['authorId'], 1);
      expect(file['bookId'], 18);
      expect(file['foreignEditionId'], candidate.rawJson['foreignEditionId']);
    });

    test('sends a corrected quality as the server defines it', () async {
      final harness = Harness();
      final candidate = await _reprocessed(harness);

      await ok(
        harness.queue.importFiles([
          _corrected(candidate, quality: const Quality(id: 2, name: 'MOBI')),
        ]),
      );

      final quality =
          _sentFiles(harness).single['quality']! as Map<String, Object?>;
      expect(
        quality['quality'],
        records('qualitydefinition')
            .map((d) => d['quality']! as Map<String, Object?>)
            .singleWhere((q) => q['id'] == 2),
      );
    });

    test('of nothing is refused, with nothing sent', () async {
      final harness = Harness();

      expect(await failureOf(harness.queue.importFiles([])), isA<Validation>());
      expect(harness.server.requests, isEmpty);
    });

    for (final (name, change) in [
      (
        'without a book',
        (ManualImportCandidate c) {
          return _corrected(c, bookId: null);
        },
      ),
      // Only the server can choose the edition: it takes a reprocessing.
      (
        'without an edition of its book',
        (ManualImportCandidate c) {
          return _corrected(c, bookId: 9);
        },
      ),
      (
        'moved to another author',
        (ManualImportCandidate c) {
          return _corrected(c, author: authorRef(2));
        },
      ),
    ]) {
      test('of a file $name is refused, nothing written', () async {
        final harness = Harness();
        final candidate = await _reprocessed(harness);

        expect(
          await failureOf(harness.queue.importFiles([change(candidate)])),
          isA<Validation>(),
        );
        expect(harness.server.writes, isEmpty);
      });
    }

    test('an accepted import that breaks off has an unknown outcome', () async {
      final harness = Harness();
      final candidate = await _reprocessed(harness);
      harness.server.writeAnswer = FakeReadarr.body('{"id":', status: 201);

      expect(
        await failureOf(harness.queue.importFiles([candidate])),
        anyOf(isA<OutcomeUnknown>(), isA<MalformedResponse>()),
      );
      expect(harness.server.writes, hasLength(1));
    });
  });
}
