// The choices for adding a series, and adding it.

import 'dart:convert';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

// Results of the recorded search, by TVDB id.
const _notHeld = 79257;
const _other = 83779;

/// What `addOptions.monitor` may be offered as: the choices of Sonarr's own
/// form for adding.
const _offerable = {
  'all',
  'future',
  'missing',
  'existing',
  'recent',
  'pilot',
  'firstSeason',
  'lastSeason',
  'monitorSpecials',
  'unmonitorSpecials',
  'none',
};

int _rootFolderId(Harness harness) =>
    harness.server.rootFolders.first['id']! as int;

int _profileId(Harness harness) =>
    harness.server.qualityProfiles.last['id']! as int;

AddChoices _choices(
  Harness harness, {
  int? rootFolderId,
  int? qualityProfileId,
  String monitor = 'all',
  bool searchNow = false,
  SeriesType? seriesType = SeriesType.standard,
  bool? seasonFolder = true,
  Set<int> tagIds = const {},
}) => AddChoices(
  rootFolderId: rootFolderId ?? _rootFolderId(harness),
  qualityProfileId: qualityProfileId ?? _profileId(harness),
  monitorOptionId: monitor,
  searchNow: searchNow,
  seriesType: seriesType,
  seasonFolder: seasonFolder,
  tagIds: tagIds,
);

/// The recorded search's result [tvdbId]. Forgets the requests made for it.
Future<AddCandidate> _found(Harness harness, [int tvdbId = _notHeld]) async {
  final candidates = await ok(harness.lookup.lookup(FakeSonarr.searchTerm));
  harness.server.requests.clear();
  return candidates.singleWhere((c) => c.externalIds.tvdbId == tvdbId);
}

/// [candidate] as another instance's search would have given it.
AddCandidate _fromElsewhere(AddCandidate candidate, {int? tvdbId = _notHeld}) =>
    AddCandidate(
      kind: candidate.kind,
      title: candidate.title,
      externalIds: ExternalIds(tvdbId: tvdbId, tmdbId: 1044),
      existingRefs: const [
        ItemRef(instanceId: 'i2', kind: MediaKind.series, remoteId: 9),
      ],
      sourceByInstance: {
        'i2': {
          ...candidate.sourceByInstance[instanceId]!,
          'title': 'As the other instance has it',
          'id': 9,
          'path': '/elsewhere/series',
        },
      },
    );

/// What was posted, as the server received it.
Map<String, Object?> _posted(Harness harness) {
  final request = harness.server.writes.single;
  expect(request.method, HttpMethod.post);
  expect(request.path, 'api/v3/series');
  return jsonDecode(jsonEncode((request.body! as JsonBody).value))
      as Map<String, Object?>;
}

Map<String, Object?> _addOptions(Harness harness) =>
    _posted(harness)['addOptions']! as Map<String, Object?>;

void main() {
  group('add options', () {
    test('the root folders, quality profiles and tags', () async {
      final harness = Harness();

      final options = (await ok(harness.lookup.addOptions(MediaKind.series)))
          .serverOptions;

      Iterable<ServerOption> of(ServerOptionKind kind) =>
          options.where((option) => option.kind == kind);
      final folder = of(ServerOptionKind.rootFolder).single;
      expect(folder.id, _rootFolderId(harness));
      expect(folder.label, harness.server.rootFolders.first['path']);
      expect(folder.freeSpace, harness.server.rootFolders.first['freeSpace']);
      expect(
        of(ServerOptionKind.qualityProfile).map((o) => o.id),
        harness.server.qualityProfiles.map((p) => p['id']),
      );
      expect(
        of(ServerOptionKind.tag).map((o) => o.label),
        harness.server.tags.map((t) => t['label']),
      );
      expect(of(ServerOptionKind.metadataProfile), isEmpty);
    });

    test('what Sonarr can monitor of a series being added', () async {
      final options = await ok(Harness().lookup.addOptions(MediaKind.series));

      final ids = options.monitorOptions.map((option) => option.id).toList();
      expect(ids.toSet(), hasLength(ids.length), reason: 'each once');
      expect(
        ids,
        containsAll([
          'all',
          'future',
          'missing',
          'existing',
          'firstSeason',
          'pilot',
          'none',
        ]),
      );
      expect(_offerable, containsAll(ids));
    });

    test('are read only', () async {
      final harness = Harness();

      await ok(harness.lookup.addOptions(MediaKind.series));

      expect(harness.server.writes, isEmpty);
    });

    for (final path in ['rootfolder', 'qualityprofile', 'tag']) {
      test('fail if $path cannot be read', () async {
        final harness = Harness();
        harness.server.overrides[path] = FakeSonarr.body('{}', status: 500);

        expect(
          await failureOf(harness.lookup.addOptions(MediaKind.series)),
          isA<ServerError>(),
        );
      });
    }

    test('are for series only', () {
      expect(
        () => Harness().lookup.addOptions(MediaKind.movie),
        throwsArgumentError,
      );
    });
  });

  group('add', () {
    test('returns the new series', () async {
      final harness = Harness();
      final candidate = await _found(harness);

      final ref = await ok(harness.lookup.add(candidate, _choices(harness)));

      expect(ref, seriesRef(FakeSonarr.addedId));
    });

    test('posts back the record found, with the choices', () async {
      final harness = Harness();
      harness.server.lookupResults.first['somethingNew'] = {'a': 1};
      final candidate = await _found(harness);
      final source = candidate.sourceByInstance[instanceId]!;

      await ok(
        harness.lookup.add(
          candidate,
          _choices(
            harness,
            monitor: 'firstSeason',
            searchNow: true,
            seriesType: SeriesType.anime,
            seasonFolder: false,
            tagIds: {1},
          ),
        ),
      );

      final posted = _posted(harness);
      expect(
        posted['rootFolderPath'],
        harness.server.rootFolders.first['path'],
      );
      expect(posted['qualityProfileId'], _profileId(harness));
      expect(posted['seriesType'], 'anime');
      expect(posted['seasonFolder'], isFalse);
      expect(posted['tags'], [1]);
      expect(posted['monitored'], isTrue);
      expect(posted['addOptions'], containsPair('monitor', 'firstSeason'));
      expect(
        posted['addOptions'],
        containsPair('searchForMissingEpisodes', true),
      );
      // Everything else, what the app does not know included.
      const chosen = {
        'rootFolderPath',
        'qualityProfileId',
        'seriesType',
        'seasonFolder',
        'tags',
        'monitored',
        'monitorNewItems',
        'addOptions',
      };
      for (final MapEntry(:key, :value) in source.entries) {
        if (!chosen.contains(key)) expect(posted[key], value, reason: key);
      }
    });

    test('searches only when asked to', () async {
      final harness = Harness();

      await ok(harness.lookup.add(await _found(harness), _choices(harness)));

      expect(
        _addOptions(harness),
        containsPair('searchForMissingEpisodes', false),
      );
      expect(_addOptions(harness)['searchForCutoffUnmetEpisodes'], isNot(true));
      // The search is part of the add, not a command of its own.
      expect(harness.server.writes, hasLength(1));
    });

    for (final type in [SeriesType.standard, SeriesType.daily]) {
      test('sends the series type ${type.name}', () async {
        final harness = Harness();

        await ok(
          harness.lookup.add(
            await _found(harness),
            _choices(harness, seriesType: type),
          ),
        );

        expect(_posted(harness)['seriesType'], type.name);
      });
    }

    for (final type in [null, SeriesType.unknown]) {
      test('without a series type to send ($type), keeps that of the '
          'record', () async {
        final harness = Harness();

        await ok(
          harness.lookup.add(
            await _found(harness),
            _choices(harness, seriesType: type),
          ),
        );

        expect(_posted(harness)['seriesType'], 'standard');
      });
    }

    test('sends every monitoring option it offers', () async {
      final offered = await ok(Harness().lookup.addOptions(MediaKind.series));

      for (final option in offered.monitorOptions) {
        final harness = Harness();

        await ok(
          harness.lookup.add(
            await _found(harness),
            _choices(harness, monitor: option.id),
          ),
        );

        expect(_addOptions(harness)['monitor'], option.id);
      }
    });

    test('takes the path of the chosen root folder', () async {
      final harness = Harness();
      harness.server.rootFolders.add({
        'id': 7,
        'path': '/redacted/second',
        'freeSpace': 1,
      });

      await ok(
        harness.lookup.add(
          await _found(harness),
          _choices(harness, rootFolderId: 7),
        ),
      );

      expect(_posted(harness)['rootFolderPath'], '/redacted/second');
    });

    test('without tags, sends none', () async {
      final harness = Harness();

      await ok(harness.lookup.add(await _found(harness), _choices(harness)));

      expect(_posted(harness)['tags'], isEmpty);
    });

    // The search's own record says false.
    test('without a choice of season folders, uses them', () async {
      final harness = Harness();
      final candidate = await _found(harness);
      expect(candidate.sourceByInstance[instanceId]!['seasonFolder'], isFalse);

      await ok(
        harness.lookup.add(candidate, _choices(harness, seasonFolder: null)),
      );

      expect(_posted(harness)['seasonFolder'], isTrue);
    });

    test('sends nothing for a result the search showed as held', () async {
      final harness = Harness();
      final candidate = await _found(harness, 318408);

      expect(
        await failureOf(harness.lookup.add(candidate, _choices(harness))),
        isA<Conflict>(),
      );
      expect(harness.server.writes, isEmpty);
    });

    test('leaves the candidate as it was', () async {
      final harness = Harness();
      final candidate = await _found(harness);
      final before = jsonEncode(candidate.sourceByInstance);

      await ok(harness.lookup.add(candidate, _choices(harness, tagIds: {1})));

      expect(jsonEncode(candidate.sourceByInstance), before);
    });

    test('is for series only', () {
      final harness = Harness();

      expect(
        () => harness.lookup.add(
          const AddCandidate(
            kind: MediaKind.movie,
            title: 'A movie',
            externalIds: ExternalIds(tmdbId: 1),
          ),
          _choices(harness),
        ),
        throwsArgumentError,
      );
      expect(harness.server.writes, isEmpty);
    });

    test('with a root folder the server no longer has, sends '
        'nothing', () async {
      final harness = Harness();
      final candidate = await _found(harness);

      expect(
        await failureOf(
          harness.lookup.add(candidate, _choices(harness, rootFolderId: 99)),
        ),
        isA<Validation>(),
      );
      expect(harness.server.writes, isEmpty);
    });

    test('sends nothing if the root folders cannot be read', () async {
      final harness = Harness();
      final candidate = await _found(harness);
      harness.server.overrides['rootfolder'] = FakeSonarr.body(
        '{}',
        status: 500,
      );

      expect(
        await failureOf(harness.lookup.add(candidate, _choices(harness))),
        isA<ServerError>(),
      );
      expect(harness.server.writes, isEmpty);
    });
  });

  group('add to an instance whose search did not give the result', () {
    test('looks it up there by its TVDB id and posts that record', () async {
      final harness = Harness();
      final candidate = _fromElsewhere(await _found(harness));

      await ok(harness.lookup.add(candidate, _choices(harness)));

      final lookup = harness.server.requests.singleWhere(
        (request) => request.path == 'api/v3/series/lookup',
      );
      expect(lookup.query, {
        'term': ['tvdb:$_notHeld'],
      });
      final posted = _posted(harness);
      expect(posted['title'], harness.server.tvdbLookup.single['title']);
      expect(posted['id'], anyOf(isNull, 0));
      expect(posted['path'], isNull);
    });

    for (final (name, answer) in [
      ('nothing', '[]'),
      ('another series only', '[{"title": "Other", "tvdbId": $_other}]'),
    ]) {
      test('is not found if that finds $name', () async {
        final harness = Harness();
        final candidate = _fromElsewhere(await _found(harness));
        harness.server.overrides['series/lookup'] = FakeSonarr.body(answer);

        expect(
          await failureOf(harness.lookup.add(candidate, _choices(harness))),
          isA<NotFound>(),
        );
        expect(harness.server.writes, isEmpty);
      });
    }

    test('is not found without a TVDB id to look up', () async {
      final harness = Harness();
      final candidate = _fromElsewhere(await _found(harness), tvdbId: null);

      expect(
        await failureOf(harness.lookup.add(candidate, _choices(harness))),
        isA<NotFound>(),
      );
      expect(harness.server.writes, isEmpty);
    });

    test('sends nothing if the lookup fails', () async {
      final harness = Harness();
      final candidate = _fromElsewhere(await _found(harness));
      harness.server.overrides['series/lookup'] = FakeSonarr.body(
        '{}',
        status: 500,
      );

      expect(
        await failureOf(harness.lookup.add(candidate, _choices(harness))),
        isA<ServerError>(),
      );
      expect(harness.server.writes, isEmpty);
    });
  });

  group('add of a series the instance has by now', () {
    // Added by someone else after the search.
    test('is a conflict', () async {
      final harness = Harness();
      final candidate = await _found(harness);
      harness.server.series.add({
        ...harness.server.series.first,
        'id': 9,
        'tvdbId': _notHeld,
      });

      expect(
        await failureOf(harness.lookup.add(candidate, _choices(harness))),
        isA<Conflict>(),
      );
      expect(harness.server.writes, hasLength(1));
    });

    test('is a conflict when the lookup there already says so', () async {
      final harness = Harness();
      final candidate = _fromElsewhere(await _found(harness));
      harness.server.series.add({
        ...harness.server.series.first,
        'id': 9,
        'tvdbId': _notHeld,
      });
      harness.server.tvdbLookup.single['id'] = 9;

      expect(
        await failureOf(harness.lookup.add(candidate, _choices(harness))),
        isA<Conflict>(),
      );
      expect(harness.server.writes.length, lessThanOrEqualTo(1));
    });
  });

  group('add that the server refuses', () {
    test('for the root folder carries its messages', () async {
      final harness = Harness();
      final candidate = await _found(harness);
      final refusal = records('series_add_bad_root');
      harness.server.addAnswer = FakeSonarr.body(
        jsonEncode(refusal),
        status: 400,
        write: true,
      );

      final failure = await failureOf(
        harness.lookup.add(candidate, _choices(harness)),
      );

      expect(failure, isA<Validation>());
      expect((failure as Validation).messages, [
        refusal.single['errorMessage'],
      ]);
      expect(harness.server.writes, hasLength(1));
    });

    for (final (name, codes, failure) in [
      (
        'because its folder is taken',
        ['SeriesPathValidator'],
        isA<Validation>(),
      ),
      (
        'for several reasons, one that it exists',
        ['QualityProfileExistsValidator', 'SeriesExistsValidator'],
        isA<Conflict>(),
      ),
    ]) {
      test(name, () async {
        final harness = Harness();
        final candidate = await _found(harness);
        harness.server.addAnswer = FakeSonarr.body(
          jsonEncode([
            for (final code in codes) {'errorMessage': 'No', 'errorCode': code},
          ]),
          status: 400,
          write: true,
        );

        expect(
          await failureOf(harness.lookup.add(candidate, _choices(harness))),
          failure,
        );
        expect(harness.server.writes, hasLength(1));
      });
    }

    test('for the quality profile is a validation failure', () async {
      final harness = Harness();

      expect(
        await failureOf(
          harness.lookup.add(
            await _found(harness),
            _choices(harness, qualityProfileId: 999),
          ),
        ),
        isA<Validation>(),
      );
      expect(harness.server.writes, hasLength(1));
    });

    test('for a value it cannot read is a validation failure', () async {
      final harness = Harness();

      expect(
        await failureOf(
          harness.lookup.add(
            await _found(harness),
            _choices(harness, monitor: 'somethingElse'),
          ),
        ),
        isA<Validation>(),
      );
      expect(harness.server.writes.length, lessThanOrEqualTo(1));
    });
  });

  group('add is sent once', () {
    for (final (name, answer, failure) in [
      (
        'a lost connection',
        const Err<ServiceResponse, HttpError>(HttpError(OutcomeUnknown())),
        isA<OutcomeUnknown>(),
      ),
      (
        'a 502 from a gateway',
        FakeSonarr.body('', status: 502, write: true),
        isA<OutcomeUnknown>(),
      ),
      (
        'a 504 from a gateway',
        FakeSonarr.body('', status: 504, write: true),
        isA<OutcomeUnknown>(),
      ),
      (
        'a server error',
        FakeSonarr.body('{}', status: 500, write: true),
        isA<ServerError>(),
      ),
      (
        'a rejected key',
        FakeSonarr.body('{}', status: 401, write: true),
        isA<AuthFailed>(),
      ),
      (
        'a refusal',
        FakeSonarr.body('{}', status: 403, write: true),
        isA<Forbidden>(),
      ),
      (
        'a sign-in page',
        FakeSonarr.body('<html>', contentType: 'text/html', write: true),
        isA<ProxyInterception>(),
      ),
      (
        'no connection',
        const Err<ServiceResponse, HttpError>(HttpError(Unreachable())),
        isA<Unreachable>(),
      ),
    ]) {
      test('after $name', () async {
        final harness = Harness();
        final candidate = await _found(harness);
        harness.server.addAnswer = answer;

        expect(
          await failureOf(harness.lookup.add(candidate, _choices(harness))),
          failure,
        );
        expect(harness.server.writes, hasLength(1));
      });
    }

    // Accepted, so it may well be there; which series it is cannot be told.
    for (final body in ['', '{"id":', '{}', '{"id": 0}']) {
      test('when it is accepted with the answer "$body"', () async {
        final harness = Harness();
        final candidate = await _found(harness);
        harness.server.addAnswer = FakeSonarr.body(
          body,
          status: 201,
          write: true,
        );

        expect(
          await failureOf(harness.lookup.add(candidate, _choices(harness))),
          isA<OutcomeUnknown>(),
        );
        expect(harness.server.writes, hasLength(1));
      });
    }
  });
}
