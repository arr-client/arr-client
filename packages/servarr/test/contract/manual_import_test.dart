// Manual import: `GET manualimport`, the correction choices, the reprocessing of
// corrected candidates and the import itself.
//
// Candidates are read with `downloadId` and `filterExistingFiles=true`. An entry
// without a download id has none, and nothing is asked: without one the server
// lists a folder instead.
//
// Mapping of a record to `ManualImportCandidate`:
//   path, downloadId     as sent
//   size                 as sent
//   matchedRef, episodeIds  from `mapping.match`
//   quality              quality.quality id and name
//   languages            id and name of each
//   rejections           reason of each
//   rawJson              the record
//
// Choices: the `quality` of each of `qualitydefinition`, and of `language` those
// with an id of 0 or more ('Any' and 'Original' are not languages of a file).
//
// What is sent for a candidate, here "its entry":
//   path, downloadId        from the candidate
//   quality                 the record's `quality` as it is, or when the id of
//                           the candidate's differs, the whole `quality`
//                           object of that id in `qualitydefinition` with the
//                           record's `revision`
//   languages               id and name of each of the candidate's
//   releaseGroup, indexerFlags, releaseType
//                           from rawJson, those it has
//   and the fields of `mapping.ids`
// and nothing else of the record, but that
//   `POST manualimport` (a list) has also `id`, from rawJson;
//   `POST command` has also `folderName`, from rawJson, if it has one.
//
// The command is `{name: ManualImport, importMode: auto, files: [...]}` and is
// answered with the command, which `commandStatus` follows. Every candidate
// passed is imported; choosing is the caller's.
//
// The server takes source, resolution and modifier from what is sent, not from
// the id, so a corrected quality is never sent as its id and name only. Where a
// candidate's quality differs, `qualitydefinition` is read before the write; if
// that fails, its failure is returned, and an id it does not have is NotFound.
// Either way nothing is written. Without a correction it is not read.
//
// The answer of `POST manualimport` has no size and no folder name, and names
// the match as `mapping.match` reads it. Each of its records becomes the
// candidate of the same path: path, size, downloadId and selected as they were;
// the match, quality, languages and rejections from the answer; rawJson the old
// record with the answer's fields over it.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servarr/servarr.dart';

import 'activity_support.dart';
import 'support.dart';

Future<List<ManualImportCandidate>> _candidates(
  Service service,
  List<Object?> records,
) => value(
  service
      .client(only('manualimport', Reply.json(records)))
      .importCandidates(waiting(), mapping: mapping(service)),
);

/// The recorded candidates of a download of two files.
Future<List<ManualImportCandidate>> _recorded(Service service) =>
    _candidates(service, service.list('manualimport'));

/// [candidate] with the user's corrections.
ManualImportCandidate _corrected(
  ManualImportCandidate candidate, {
  ItemRef? matchedRef,
  List<int>? episodeIds,
  Quality? quality,
  List<Language>? languages,
  bool? selected,
}) => ManualImportCandidate(
  path: candidate.path,
  size: candidate.size,
  rawJson: candidate.rawJson,
  downloadId: candidate.downloadId,
  matchedRef: matchedRef ?? candidate.matchedRef,
  episodeIds: episodeIds ?? candidate.episodeIds,
  quality: quality ?? candidate.quality,
  languages: languages ?? candidate.languages,
  rejections: candidate.rejections,
  selected: selected ?? candidate.selected,
);

/// A quality the first recorded file of the service does not have.
Quality _otherQuality(Service service) => service == radarr
    ? const Quality(id: 3, name: 'WEBDL-1080p')
    : const Quality(id: 7, name: 'Bluray-1080p');

/// The corrections the recorded reprocessing was made with.
List<ManualImportCandidate> _corrections(
  Service service,
  List<ManualImportCandidate> candidates,
) => [
  _corrected(
    candidates.first,
    episodeIds: service == radarr ? null : [20],
    quality: _otherQuality(service),
    languages: const [Language(id: 4, name: 'German')],
    selected: true,
  ),
  candidates.last,
];

/// The entry of [candidate] as both writes have it, for the record it was read
/// from.
Map<String, Object?> _entry(Service service, JsonObject record) => {
  'path': record['path'],
  'downloadId': record['downloadId'],
  'quality': record['quality'],
  'languages': record['languages'],
  'releaseGroup': record['releaseGroup'],
  'indexerFlags': record['indexerFlags'],
  if (service == radarr)
    'movieId': (record['movie']! as JsonObject)['id']
  else ...{
    'releaseType': record['releaseType'],
    'seriesId': (record['series']! as JsonObject)['id'],
    'seasonNumber': record['seasonNumber'],
    'episodeIds': [
      for (final episode in record['episodes']! as List<Object?>)
        (episode! as JsonObject)['id'],
    ],
  },
};

/// The whole quality object the server defines for [id].
Object? _defined(Service service, int id) => service
    .list('qualitydefinition')
    .map((definition) => definition['quality']! as JsonObject)
    .singleWhere((quality) => quality['id'] == id);

/// Answers [path] with [reply] and `qualitydefinition` with [definitions], by
/// default as recorded.
FakeServer _writeServer(
  Service service,
  String path,
  Reply reply, {
  Reply? definitions,
}) => FakeServer(
  (request) => switch (request.path) {
    'api/v3/qualitydefinition' =>
      definitions ?? Reply.json(service.fixture('qualitydefinition')),
    final asked when asked == 'api/v3/$path' => reply,
    _ => const Reply(404, ''),
  },
);

/// The write of [server], before which only the definitions were read.
ServiceRequest _write(FakeServer server, String path) {
  expect(
    server.requests.map(
      (request) =>
          '${request.method.name} '
          '${request.path}',
    ),
    [
      '${HttpMethod.get.name} api/v3/qualitydefinition',
      '${HttpMethod.post.name} api/v3/$path',
    ],
  );
  expect(server.requests.first.query, isEmpty);
  return server.requests.last;
}

/// The entries of [_corrections].
List<Map<String, Object?>> _correctedEntries(Service service) {
  final records = service.list('manualimport');
  final revision = (records.first['quality']! as JsonObject)['revision'];
  return [
    {
      ..._entry(service, records.first),
      'quality': {
        'quality': _defined(service, _otherQuality(service).id),
        'revision': revision,
      },
      'languages': [
        {'id': 4, 'name': 'German'},
      ],
      if (service == sonarr) 'episodeIds': [20],
    },
    _entry(service, records.last),
  ];
}

Object? _sent(ServiceRequest request) => (request.body! as JsonBody).value;

void main() {
  for (final service in services) {
    final item = service == radarr
        ? itemRef(MediaKind.movie, 1)
        : itemRef(MediaKind.series, 1);

    group('${service.name} import candidates', () {
      test('asks for the files of the download', () async {
        final server = only(
          'manualimport',
          Reply.json(service.list('manualimport')),
        );

        await value(
          service
              .client(server)
              .importCandidates(waiting(), mapping: mapping(service)),
        );

        final request = server.requests.single;
        expect(request.method, HttpMethod.get);
        expect(request.path, 'api/v3/manualimport');
        expect(request.query, {
          'downloadId': ['ABCDEF01'],
          'filterExistingFiles': ['true'],
        });
        expect(request.body, isNull);
      });

      test('asks nothing for an entry without a download', () async {
        final server = only('manualimport', Reply.json(<Object?>[]));

        final candidates = await value(
          service
              .client(server)
              .importCandidates(
                waiting(downloadId: null),
                mapping: mapping(service),
              ),
        );

        expect(candidates, isEmpty);
        expect(server.requests, isEmpty);
      });

      test('maps the matched files and why they were rejected', () async {
        final records = service.list('manualimport');

        final candidates = await _recorded(service);

        expect(candidates, hasLength(2));
        for (final (index, candidate) in candidates.indexed) {
          final record = records[index];
          expect(candidate.path, record['path']);
          expect(candidate.size, 2097152);
          expect(candidate.downloadId, record['downloadId']);
          expect(candidate.matchedRef, item);
          expect(candidate.episodeIds, service == radarr ? isEmpty : [19]);
          expect(candidate.quality?.id, service == radarr ? 7 : 3);
          expect(
            candidate.quality?.name,
            service == radarr ? 'Bluray-1080p' : 'WEBDL-1080p',
          );
          expect(candidate.languages.single.id, 1);
          expect(candidate.languages.single.name, 'English');
          expect(candidate.rejections, [
            ((record['rejections']! as List<Object?>).single!
                as JsonObject)['reason'],
          ]);
          expect(candidate.rawJson, record);
        }
      });

      test('maps a file the server cannot match', () async {
        final candidate = (await _candidates(
          service,
          service.list('manualimport_unmatched'),
        )).single;

        expect(candidate.matchedRef, isNull);
        expect(candidate.episodeIds, isEmpty);
        expect(candidate.size, 2097152);
        expect(candidate.quality?.id, service == radarr ? 5 : 4);
        expect(candidate.languages.single.id, 0);
        expect(candidate.rejections, hasLength(1));
      });

      test('accepts a record with only its path', () async {
        final candidate = (await _candidates(service, [
          {'path': '/redacted/1.mkv'},
        ])).single;

        expect(candidate.path, '/redacted/1.mkv');
        expect(candidate.size, 0);
        expect(candidate.matchedRef, isNull);
        expect(candidate.quality, isNull);
        expect(candidate.languages, isEmpty);
        expect(candidate.rejections, isEmpty);
      });

      test('cannot understand a record without a path', () async {
        final records = service.list('manualimport');
        records[1].remove('path');

        expect(
          await failure(
            service
                .client(only('manualimport', Reply.json(records)))
                .importCandidates(waiting(), mapping: mapping(service)),
          ),
          isA<MalformedResponse>(),
        );
      });
    });

    group('${service.name} import choices', () {
      FakeServer server() => FakeServer.paths({
        'qualitydefinition': service.fixture('qualitydefinition'),
        'language': service.fixture('language'),
      });

      test('reads the quality definitions and languages', () async {
        final fake = server();

        await value(service.client(fake).importChoices());

        expect(fake.requests.map((request) => request.path).toSet(), {
          'api/v3/qualitydefinition',
          'api/v3/language',
        });
        expect(fake.requests, hasLength(2));
        for (final request in fake.requests) {
          expect(request.method, HttpMethod.get);
          expect(request.query, isEmpty);
          expect(request.body, isNull);
        }
      });

      test('offers every quality, in the server order', () async {
        final definitions = service.list('qualitydefinition');

        final choices = await value(service.client(server()).importChoices());

        expect(
          [for (final quality in choices.qualities) (quality.id, quality.name)],
          [
            for (final definition in definitions)
              if (definition['quality'] case {
                'id': final int id,
                'name': final String name,
              })
                (id, name),
          ],
        );
        expect(choices.qualities, hasLength(definitions.length));
      });

      test('offers the languages a file can have', () async {
        final languages = service.list('language');
        expect(languages.map((language) => language['id']), contains(-2));

        final choices = await value(service.client(server()).importChoices());

        expect(
          [for (final language in choices.languages) language.id],
          [
            for (final language in languages)
              if (language['id']! as int >= 0) language['id'],
          ],
        );
        expect(choices.languages.first.id, 0);
        expect(choices.languages.first.name, 'Unknown');
      });

      for (final missing in ['qualitydefinition', 'language']) {
        test('gives no choices when $missing cannot be read', () async {
          final fake = FakeServer.paths({
            for (final path in ['qualitydefinition', 'language'])
              if (path != missing) path: service.fixture(path),
          });

          expect(
            await failure(service.client(fake).importChoices()),
            isA<NotFound>(),
          );
        });
      }
    });

    group('${service.name} reprocess', () {
      FakeServer server([Object? answer]) => _writeServer(
        service,
        'manualimport',
        Reply.json(answer ?? service.list('manualimport_reprocess')),
      );

      test('sends the corrected candidates', () async {
        final candidates = _corrections(service, await _recorded(service));
        final fake = server();

        await value(
          service.client(fake).reprocess(candidates, mapping: mapping(service)),
        );

        final request = _write(fake, 'manualimport');
        expect(request.query, isEmpty);
        final entries = _correctedEntries(service);
        final records = service.list('manualimport');
        expect(_sent(request), [
          for (final (index, entry) in entries.indexed)
            {'id': records[index]['id'], ...entry},
        ]);
      });

      test('gives what the server now says of them', () async {
        final before = _corrections(service, await _recorded(service));
        final answer = service.list('manualimport_reprocess');

        final after = await value(
          service.client(server()).reprocess(before, mapping: mapping(service)),
        );

        expect(after, hasLength(2));
        final first = after.first;
        expect(first.path, before.first.path);
        expect(first.size, 2097152);
        expect(first.downloadId, before.first.downloadId);
        expect(first.selected, isTrue);
        expect(first.matchedRef, item);
        expect(first.episodeIds, service == radarr ? isEmpty : [20]);
        expect(first.quality?.id, _otherQuality(service).id);
        expect(first.quality?.name, _otherQuality(service).name);
        // Sent whole, the quality keeps its source and resolution.
        expect(
          (first.rawJson['quality']! as JsonObject)['quality'],
          _defined(service, _otherQuality(service).id),
        );
        expect(first.languages.single.id, 4);
        expect(first.rejections, [
          for (final rejection in answer.first['rejections']! as List<Object?>)
            (rejection! as JsonObject)['reason'],
        ]);
        expect(first.rejections, hasLength(1));
        // What the import needs and the answer leaves out is still there.
        expect(first.rawJson['folderName'], before.first.rawJson['folderName']);
        expect(first.rawJson['quality'], answer.first['quality']);
        expect(after.last.selected, isFalse);
        expect(after.last.quality?.id, service == radarr ? 7 : 3);
      });

      test('takes over a match and rejections that are gone', () async {
        final before = (await _recorded(service)).first;
        final answer = service.list('manualimport_reprocess').first
          ..['rejections'] = <Object?>[]
          ..remove('movie')
          ..remove('movieId')
          ..remove('seriesId')
          ..remove('episodes');

        final after = (await value(
          service.client(server([answer])).reprocess([
            before,
          ], mapping: mapping(service)),
        )).single;

        expect(after.matchedRef, isNull);
        expect(after.episodeIds, isEmpty);
        expect(after.rejections, isEmpty);
      });

      test('cannot understand a candidate it did not send', () async {
        final before = await _recorded(service);
        final answer = service.list('manualimport_reprocess');
        answer.first['path'] = '/redacted/other.mkv';

        expect(
          await failure(
            service
                .client(server(answer))
                .reprocess(before, mapping: mapping(service)),
          ),
          isA<MalformedResponse>(),
        );
      });

      test('asks nothing for no candidates', () async {
        final fake = server();

        expect(
          await value(
            service.client(fake).reprocess([], mapping: mapping(service)),
          ),
          isEmpty,
        );
        expect(fake.requests, isEmpty);
      });
    });

    group('${service.name} corrected quality', () {
      final writes =
          <
            String,
            (
              String,
              Reply,
              ServiceResult<Object?> Function(
                ServarrClient,
                List<ManualImportCandidate>,
              ),
            )
          >{
            'reprocess': (
              'manualimport',
              Reply.json(service.list('manualimport_reprocess')),
              (client, candidates) =>
                  client.reprocess(candidates, mapping: mapping(service)),
            ),
            'importFiles': (
              'command',
              Reply.json(service.object('command_manualimport'), status: 201),
              (client, candidates) =>
                  client.importFiles(candidates, mapping: mapping(service)),
            ),
          };
      final unusable = <String, (Reply, Matcher)>{
        'the definitions cannot be read': (
          Reply.json({'message': 'Example'}, status: 500),
          isA<ServerError>(),
        ),
        'the definitions cannot be understood': (
          Reply.json([
            {'id': 1},
          ]),
          isA<MalformedResponse>(),
        ),
        'the quality is not defined': (
          Reply.json(<Object?>[]),
          isA<NotFound>(),
        ),
      };

      for (final MapEntry(key: name, value: (path, answer, write))
          in writes.entries) {
        for (final MapEntry(key: cause, value: (definitions, expected))
            in unusable.entries) {
          test('$name writes nothing when $cause', () async {
            final candidates = _corrections(service, await _recorded(service));
            final fake = _writeServer(
              service,
              path,
              answer,
              definitions: definitions,
            );

            expect(
              await failure(write(service.client(fake), candidates)),
              expected,
            );

            expect(fake.requests.single.method, HttpMethod.get);
            expect(fake.requests.single.path, 'api/v3/qualitydefinition');
          });
        }

        test('$name keeps the record quality of the same id', () async {
          final recorded = await _recorded(service);
          final first = recorded.first;
          final renamed = _corrected(
            first,
            quality: Quality(id: first.quality!.id, name: 'Renamed'),
          );
          final fake = _writeServer(service, path, answer);

          await value(write(service.client(fake), [renamed, recorded.last]));

          final sent = _sent(fake.requests.single);
          final entries = sent is List<Object?>
              ? sent
              : (sent! as JsonObject)['files']! as List<Object?>;
          expect(
            (entries.first! as JsonObject)['quality'],
            first.rawJson['quality'],
          );
        });
      }
    });

    group('${service.name} import', () {
      FakeServer server() => _writeServer(
        service,
        'command',
        Reply.json(service.object('command_manualimport'), status: 201),
      );

      test('sends the files as one command', () async {
        final candidates = _corrections(service, await _recorded(service));
        final records = service.list('manualimport');
        final fake = server();

        await value(
          service
              .client(fake)
              .importFiles(candidates, mapping: mapping(service)),
        );

        final request = _write(fake, 'command');
        expect(request.query, isEmpty);
        // The second candidate is not marked selected and is imported too.
        expect(candidates.last.selected, isFalse);
        expect(_sent(request), {
          'name': 'ManualImport',
          'importMode': 'auto',
          'files': [
            for (final (index, entry) in _correctedEntries(service).indexed)
              {...entry, 'folderName': records[index]['folderName']},
          ],
        });
      });

      test('sends a file that is not in a folder', () async {
        final candidate = (await _candidates(
          service,
          service.list('manualimport_unmatched'),
        )).single;
        final fake = server();

        await value(
          service.client(fake).importFiles([
            _corrected(candidate, matchedRef: item),
          ], mapping: mapping(service)),
        );

        final body = _sent(fake.requests.single)! as JsonObject;
        final file = (body['files']! as List<Object?>).single! as JsonObject;
        expect(file, isNot(contains('folderName')));
        expect(file[service == radarr ? 'movieId' : 'seriesId'], isNotNull);
        expect(file['quality'], candidate.rawJson['quality']);
      });

      test('gives the command to follow', () async {
        final command = await value(
          service
              .client(server())
              .importFiles(await _recorded(service), mapping: mapping(service)),
        );

        expect(command.id, service == radarr ? 29 : 15);
        expect(command.name, 'ManualImport');
        expect(
          command.status,
          service == radarr ? CommandStatus.queued : CommandStatus.started,
        );
        // `unknown` until the command has ended.
        expect(command.result, CommandResult.unknown);
        expect(command.outcome, CommandOutcome.pending);
      });

      test('asks nothing to import nothing', () async {
        final fake = server();

        await failure(
          service.client(fake).importFiles([], mapping: mapping(service)),
        );

        expect(fake.requests, isEmpty);
      });

      test('cannot understand an answer without the command', () async {
        final fake = only('command', const Reply(201, '{}'));

        expect(
          await failure(
            service
                .client(fake)
                .importFiles(
                  await _recorded(service),
                  mapping: mapping(service),
                ),
          ),
          isA<MalformedResponse>(),
        );
        expect(fake.requests, hasLength(1));
      });
    });
  }
}
