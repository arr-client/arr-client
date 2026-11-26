// Radarr's manual import against recorded answers (spec story 4): the movie a
// file is matched to, what is sent back of it, and the refusal of a file without
// a movie. See activity_support.dart.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'activity_support.dart';
import 'library_support.dart';

const _webdl = Quality(id: 3, name: 'WEBDL-1080p');
const _german = Language(id: 4, name: 'German');

/// The recorded candidates of the download of two files.
Future<List<ManualImportCandidate>> _matched(Activity activity) =>
    succeed(activity.queue.importCandidates(waiting(matchedDownload)));

/// The recorded file the server cannot match.
Future<ManualImportCandidate> _unmatched(Activity activity) async =>
    (await succeed(activity.queue.importCandidates(waiting(unmatchedDownload))))
        .single;

/// [candidate] with the user's corrections; [movie] replaces its match, which
/// may be with none.
ManualImportCandidate _corrected(
  ManualImportCandidate candidate, {
  ItemRef? Function()? movie,
  Quality? quality,
  List<Language>? languages,
}) => ManualImportCandidate(
  path: candidate.path,
  size: candidate.size,
  rawJson: candidate.rawJson,
  downloadId: candidate.downloadId,
  matchedRef: movie == null ? candidate.matchedRef : movie(),
  quality: quality ?? candidate.quality,
  languages: languages ?? candidate.languages,
  rejections: candidate.rejections,
  selected: true,
);

/// The corrections the recorded reprocessing was made with.
List<ManualImportCandidate> _corrections(List<ManualImportCandidate> read) => [
  _corrected(read.first, quality: _webdl, languages: const [_german]),
  read.last,
];

/// What both writes send of the candidate that was read from [record].
Map<String, Object?> _entry(Map<String, Object?> record) => {
  'path': record['path'],
  'downloadId': record['downloadId'],
  'quality': record['quality'],
  'languages': record['languages'],
  'releaseGroup': record['releaseGroup'],
  'indexerFlags': record['indexerFlags'],
  'movieId': 1,
};

/// The entries of [_corrections].
List<Map<String, Object?>> _correctedEntries() {
  final wire = records(fixture('manualimport'));
  final defined = records(fixture('qualitydefinition'))
      .map((definition) => definition['quality']! as Map<String, Object?>)
      .singleWhere((quality) => quality['id'] == _webdl.id);
  return [
    {
      ..._entry(wire.first),
      'quality': {
        'quality': defined,
        'revision': (wire.first['quality']! as Map)['revision'],
      },
      'languages': [
        {'id': 4, 'name': 'German'},
      ],
    },
    _entry(wire.last),
  ];
}

void main() {
  group('candidates', () {
    test('are the files of the download', () async {
      final activity = Activity();

      await _matched(activity);

      final request = activity.server.requests.single;
      expect(request.method, HttpMethod.get);
      expect(request.path, 'api/v3/manualimport');
      expect(request.query, {
        'downloadId': [matchedDownload],
        'filterExistingFiles': ['true'],
      });
    });

    test('name their movie, quality, languages and rejections', () async {
      final wire = records(fixture('manualimport'));

      final candidates = await _matched(Activity());

      expect(candidates, hasLength(2));
      for (final (index, candidate) in candidates.indexed) {
        final record = wire[index];
        expect(candidate.path, record['path']);
        expect(candidate.size, record['size']);
        expect(candidate.downloadId, matchedDownload);
        expect(candidate.matchedRef, movieRef(1));
        expect(candidate.episodeIds, isEmpty);
        expect(candidate.quality?.id, 7);
        expect(candidate.quality?.name, 'Bluray-1080p');
        expect(candidate.languages.single.id, 1);
        expect(candidate.languages.single.name, 'English');
        expect(candidate.rejections, [
          for (final rejection in record['rejections']! as List<Object?>)
            (rejection! as Map)['reason'],
        ]);
        expect(candidate.rawJson, record);
      }
    });

    test('have no movie where the server cannot match the file', () async {
      final candidate = await _unmatched(Activity());

      expect(candidate.matchedRef, isNull);
      expect(candidate.quality?.id, 5);
      expect(candidate.rejections, hasLength(1));
    });

    test('are none for an entry without a download', () async {
      final activity = Activity();

      expect(
        await succeed(activity.queue.importCandidates(waiting(null))),
        isEmpty,
      );
      expect(activity.server.requests, isEmpty);
    });
  });

  test('offers the qualities and languages of the server', () async {
    final activity = Activity();

    final choices = await succeed(activity.queue.importChoices());

    expect(activity.server.requests.map((request) => request.path).toSet(), {
      'api/v3/qualitydefinition',
      'api/v3/language',
    });
    expect(choices.qualities.map((quality) => quality.id), [
      for (final definition in records(fixture('qualitydefinition')))
        (definition['quality']! as Map)['id'],
    ]);
    // 'Any' and 'Original' are below 0.
    expect(choices.languages.map((language) => language.id), [
      for (final language in records(fixture('language')))
        if (language['id']! as int >= 0) language['id'],
    ]);
  });

  group('reprocess', () {
    test('sends the corrected candidates with their movie', () async {
      final activity = Activity();
      final candidates = _corrections(await _matched(activity));

      await succeed(activity.queue.reprocess(candidates));

      final request = activity.server.writes.single;
      expect(request.method, HttpMethod.post);
      expect(request.path, 'api/v3/manualimport');
      final wire = records(fixture('manualimport'));
      expect(sent(request), [
        for (final (index, entry) in _correctedEntries().indexed)
          {'id': wire[index]['id'], ...entry},
      ]);
    });

    test('sends the movie the user chose', () async {
      final activity = Activity();
      final first = (await _matched(activity)).first;
      activity.server.answers['api/v3/manualimport'] = jsonAnswer([
        {...records(fixture('manualimport_reprocess')).first}..remove('movie'),
      ]);

      await succeed(
        activity.queue.reprocess([_corrected(first, movie: () => movieRef(4))]),
      );

      final entries = sent(activity.server.writes.single)! as List<Object?>;
      expect((entries.single! as Map)['movieId'], 4);
    });

    test('gives what the server now says of them', () async {
      final activity = Activity();
      final before = _corrections(await _matched(activity));

      final after = await succeed(activity.queue.reprocess(before));

      expect(after, hasLength(2));
      expect(after.map((candidate) => candidate.matchedRef), [
        movieRef(1),
        movieRef(1),
      ]);
      expect(after.first.path, before.first.path);
      expect(after.first.size, before.first.size);
      expect(after.first.selected, isTrue);
      expect(after.first.quality?.id, _webdl.id);
      expect(after.first.languages.single.id, _german.id);
      expect(after.first.rejections, hasLength(2));
      expect(
        after.first.rawJson['folderName'],
        before.first.rawJson['folderName'],
      );
    });
  });

  group('import', () {
    test('sends the files with their movie as one command', () async {
      final activity = Activity();
      final candidates = _corrections(await _matched(activity));

      await succeed(activity.queue.importFiles(candidates));

      final request = activity.server.writes.single;
      expect(request.method, HttpMethod.post);
      expect(request.path, 'api/v3/command');
      final wire = records(fixture('manualimport'));
      expect(sent(request), {
        'name': 'ManualImport',
        'importMode': 'auto',
        'files': [
          for (final (index, entry) in _correctedEntries().indexed)
            {...entry, 'folderName': wire[index]['folderName']},
        ],
      });
    });

    test('sends an unmatched file once it has a movie', () async {
      final activity = Activity();
      final candidate = await _unmatched(activity);

      await succeed(
        activity.queue.importFiles([
          _corrected(candidate, movie: () => movieRef(4)),
        ]),
      );

      final body = sent(activity.server.writes.single)! as Map;
      final file = (body['files'] as List<Object?>).single! as Map;
      expect(file['movieId'], 4);
      expect(file['path'], candidate.path);
      expect(file, isNot(contains('folderName')));
    });

    test('gives the command to follow', () async {
      final activity = Activity();

      final command = await succeed(
        activity.queue.importFiles(await _matched(activity)),
      );

      expect(command.id, 17);
      expect(command.name, 'ManualImport');
      expect(command.status, CommandStatus.queued);
      expect(command.outcome, CommandOutcome.pending);
    });

    test('asks nothing to import nothing', () async {
      final activity = Activity();

      expect(
        await failureOf(activity.queue.importFiles(const [])),
        isA<Validation>(),
      );
      expect(activity.server.requests, isEmpty);
    });
  });

  // The server throws for these, so none of them may reach it.
  group('a candidate without a movie', () {
    final lists =
        <String, Future<List<ManualImportCandidate>> Function(Activity)>{
          'the server could not match': (activity) async => [
            await _unmatched(activity),
          ],
          'is among matched ones': (activity) async => [
            ...await _matched(activity),
            await _unmatched(activity),
          ],
          'had its match taken away': (activity) async => [
            _corrected((await _matched(activity)).first, movie: () => null),
          ],
          'also has a corrected quality': (activity) async => [
            _corrected(await _unmatched(activity), quality: _webdl),
          ],
        };
    final writes =
        <
          String,
          ServiceResult<Object?> Function(Activity, List<ManualImportCandidate>)
        >{
          'reprocess': (activity, candidates) =>
              activity.queue.reprocess(candidates),
          'importFiles': (activity, candidates) =>
              activity.queue.importFiles(candidates),
        };

    for (final MapEntry(key: name, value: write) in writes.entries) {
      for (final MapEntry(key: cause, value: list) in lists.entries) {
        test('$name is refused when one $cause', () async {
          final activity = Activity();
          final candidates = await list(activity);

          expect(
            await failureOf(write(activity, candidates)),
            isA<Validation>(),
          );
          expect(activity.server.writes, isEmpty);
        });
      }
    }
  });

  for (final MapEntry(key: name, value: write)
      in <
            String,
            ServiceResult<Object?> Function(
              Activity,
              List<ManualImportCandidate>,
            )
          >{
            'reprocess': (activity, candidates) =>
                activity.queue.reprocess(candidates),
            'importFiles': (activity, candidates) =>
                activity.queue.importFiles(candidates),
          }
          .entries) {
    test('$name is sent once and its failure passed on', () async {
      const failure = OutcomeUnknown();
      final activity = Activity();
      final candidates = await _matched(activity);
      activity.server.writesFail = failedAnswer(failure);

      expect(await failureOf(write(activity, candidates)), same(failure));
      expect(activity.server.writes, hasLength(1));
    });
  }
}
