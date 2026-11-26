// LookupProvider.addOptions and add against recorded answers (spec story 3).

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'library_support.dart';
import 'lookup_support.dart';

/// What the choices decide in the posted movie.
const _chosen = {
  'qualityProfileId',
  'rootFolderPath',
  'tags',
  'minimumAvailability',
  'monitored',
  'addOptions',
};

AddChoices _choices({
  int rootFolderId = 2,
  String monitorOptionId = 'movieOnly',
  bool searchNow = true,
  MinimumAvailability? minimumAvailability = MinimumAvailability.inCinemas,
  Set<int> tagIds = const {1, 2},
}) => AddChoices(
  rootFolderId: rootFolderId,
  qualityProfileId: 4,
  monitorOptionId: monitorOptionId,
  searchNow: searchNow,
  minimumAvailability: minimumAvailability,
  tagIds: tagIds,
);

/// The search result a user would pick, from this instance.
Future<AddCandidate> _candidate(LookupHarness harness) async {
  final found = (await succeed(harness.lookup.lookup('bunny'))).single;
  harness.radarr.requests.clear();
  return found;
}

/// A result that only the instance `i2` produced.
AddCandidate _fromElsewhere({
  ExternalIds externalIds = const ExternalIds(tmdbId: bunnyTmdbId),
}) => AddCandidate(
  kind: MediaKind.movie,
  title: 'Elsewhere',
  externalIds: externalIds,
  existingRefs: const [
    ItemRef(instanceId: 'i2', kind: MediaKind.movie, remoteId: 40),
  ],
  sourceByInstance: const {
    'i2': {
      'title': 'Elsewhere',
      'tmdbId': bunnyTmdbId,
      'id': 40,
      'path': '/elsewhere/movie',
      'onlyOnTheOtherServer': true,
    },
  },
);

/// Adds and returns what was posted.
Future<Map<String, Object?>> _posted(
  LookupHarness harness,
  AddChoices choices,
) async {
  await succeed(harness.lookup.add(await _candidate(harness), choices));
  return harness.radarr.posted.single;
}

List<ServiceRequest> _writes(LookupHarness harness) => [
  for (final request in harness.radarr.requests)
    if (request.method != HttpMethod.get) request,
];

void main() {
  group('addOptions', () {
    Future<AddOptions> options(LookupHarness harness) =>
        succeed(harness.lookup.addOptions(MediaKind.movie));

    test('reads profiles, root folders and tags', () async {
      final harness = LookupHarness();

      await options(harness);

      expect(
        harness.radarr.requests.map((r) => r.path),
        unorderedEquals([
          'api/v3/qualityprofile',
          'api/v3/rootfolder',
          'api/v3/tag',
        ]),
      );
      expect(_writes(harness), isEmpty);
    });

    test('offers what the server has', () async {
      final result = await options(LookupHarness());

      Iterable<(int, String)> of(ServerOptionKind kind) => result.serverOptions
          .where((option) => option.kind == kind)
          .map((option) => (option.id, option.label));
      expect(
        of(ServerOptionKind.qualityProfile),
        unorderedEquals([
          for (final wire in records(fixture('qualityprofile')))
            (wire['id'], wire['name']),
        ]),
      );
      expect(
        of(ServerOptionKind.rootFolder),
        unorderedEquals([
          (1, records(fixture('rootfolder')).single['path']),
          (2, otherFolder['path']),
        ]),
      );
      expect(
        of(ServerOptionKind.tag),
        unorderedEquals([
          for (final wire in records(fixture('tag')))
            (wire['id'], wire['label']),
        ]),
      );
      expect(of(ServerOptionKind.metadataProfile), isEmpty);
    });

    // The values Radarr 7.0.3 accepted as `addOptions.monitor`.
    test("offers Radarr's monitoring choices", () async {
      final result = await options(LookupHarness());

      expect(
        result.monitorOptions.map((option) => option.id),
        unorderedEquals(['movieOnly', 'movieAndCollection', 'none']),
      );
    });

    test('passes on a failure', () async {
      const failure = Unreachable();
      final harness = LookupHarness()..radarr.down = failedAnswer(failure);

      expect(
        await failureOf(harness.lookup.addOptions(MediaKind.movie)),
        same(failure),
      );
    });
  });

  group('add', () {
    test('posts the movie once and returns the new item', () async {
      final harness = LookupHarness();
      final candidate = await _candidate(harness);

      final added = await succeed(harness.lookup.add(candidate, _choices()));

      expect(added, movieRef(1));
      final write = _writes(harness).single;
      expect(write.method, HttpMethod.post);
      expect(write.path, addPath);
      expect(write.query, isEmpty);
      // It has the record already.
      expect(harness.radarr.terms, isEmpty);
    });

    test('posts back the looked-up record, unknown fields included', () async {
      final harness = LookupHarness();
      harness.radarr.found['bunny'] = [
        {
          ...records(fixture('lookup_new')).single,
          'someFutureField': {'a': 1},
        },
      ];
      final candidate = await _candidate(harness);
      final source = {...candidate.sourceByInstance[instanceId]!};

      await succeed(harness.lookup.add(candidate, _choices()));

      final body = harness.radarr.posted.single;
      for (final MapEntry(:key, :value) in source.entries) {
        if (!_chosen.contains(key)) expect(body[key], value, reason: key);
      }
      // The candidate may be added to another instance after this one.
      expect(candidate.sourceByInstance[instanceId], source);
    });

    test('sends the choices of the user', () async {
      final body = await _posted(LookupHarness(), _choices());

      expect(body['rootFolderPath'], otherFolder['path']);
      expect(body['qualityProfileId'], 4);
      expect(body['tags'], unorderedEquals([1, 2]));
      expect(body['minimumAvailability'], 'inCinemas');
      expect(body['monitored'], isTrue);
      expect(body['addOptions'], containsPair('monitor', 'movieOnly'));
      expect(body['addOptions'], containsPair('searchForMovie', true));
    });

    test('takes the path of the chosen root folder', () async {
      final body = await _posted(LookupHarness(), _choices(rootFolderId: 1));

      expect(
        body['rootFolderPath'],
        records(fixture('rootfolder')).single['path'],
      );
    });

    test('does not search or tag unless asked', () async {
      final body = await _posted(
        LookupHarness(),
        _choices(searchNow: false, tagIds: const {}),
      );

      expect(body['addOptions'], containsPair('searchForMovie', false));
      expect(body['tags'], isEmpty);
    });

    for (final (option, monitored) in [
      ('movieOnly', true),
      ('movieAndCollection', true),
      ('none', false),
    ]) {
      test('monitoring $option sets monitored to $monitored', () async {
        final body = await _posted(
          LookupHarness(),
          _choices(monitorOptionId: option),
        );

        expect(body['addOptions'], containsPair('monitor', option));
        expect(body['monitored'], monitored);
      });
    }

    for (final availability in [
      MinimumAvailability.tba,
      MinimumAvailability.announced,
      MinimumAvailability.inCinemas,
      MinimumAvailability.released,
    ]) {
      test('sends minimum availability ${availability.name}', () async {
        final body = await _posted(
          LookupHarness(),
          _choices(minimumAvailability: availability),
        );

        expect(body['minimumAvailability'], availability.name);
      });
    }

    test('sends nothing meant for another service', () async {
      final body = await _posted(
        LookupHarness(),
        const AddChoices(
          rootFolderId: 2,
          qualityProfileId: 4,
          monitorOptionId: 'movieOnly',
          searchNow: false,
          minimumAvailability: MinimumAvailability.released,
          metadataProfileId: 3,
          seriesType: SeriesType.anime,
          seasonFolder: true,
        ),
      );

      for (final field in ['metadataProfileId', 'seriesType', 'seasonFolder']) {
        expect(body, isNot(contains(field)), reason: field);
      }
    });

    test('fails without posting if the root folder is gone', () async {
      final harness = LookupHarness();
      final candidate = await _candidate(harness);

      final failure = await failureOf(
        harness.lookup.add(candidate, _choices(rootFolderId: 9)),
      );

      expect(failure, isA<Validation>());
      expect(_writes(harness), isEmpty);
    });

    test('does not post if the root folders cannot be read', () async {
      const failure = ServerError(statusCode: 500);
      final harness = LookupHarness();
      final candidate = await _candidate(harness);
      harness.radarr.answers['api/v3/rootfolder'] = failedAnswer(
        failure,
        status: 500,
      );

      expect(
        await failureOf(harness.lookup.add(candidate, _choices())),
        same(failure),
      );
      expect(_writes(harness), isEmpty);
    });
  });

  group('add to an instance whose lookup did not give the result', () {
    test('looks it up there by TMDB id and posts that record', () async {
      final harness = LookupHarness();
      final own = records(fixture('lookup_new')).single;

      final added = await succeed(
        harness.lookup.add(_fromElsewhere(), _choices()),
      );

      expect(added, movieRef(1));
      expect(harness.radarr.terms, ['tmdb:$bunnyTmdbId']);
      final body = harness.radarr.posted.single;
      for (final MapEntry(:key, :value) in own.entries) {
        if (!_chosen.contains(key)) expect(body[key], value, reason: key);
      }
      // Nothing of the other server's record goes to this one.
      for (final field in ['id', 'path', 'onlyOnTheOtherServer']) {
        expect(body, isNot(contains(field)), reason: field);
      }
    });

    test('is a conflict if this instance has it already', () async {
      final harness = LookupHarness()..radarr.held.add(bunnyTmdbId);

      expect(
        await failureOf(harness.lookup.add(_fromElsewhere(), _choices())),
        isA<Conflict>(),
      );
    });

    test('is not found if this instance does not find it', () async {
      final harness = LookupHarness();
      harness.radarr.found['tmdb:$bunnyTmdbId'] = [];

      expect(
        await failureOf(harness.lookup.add(_fromElsewhere(), _choices())),
        isA<NotFound>(),
      );
      expect(_writes(harness), isEmpty);
    });

    test('does not post a result it has no identifier for', () async {
      final harness = LookupHarness();

      await failureOf(
        harness.lookup.add(
          _fromElsewhere(externalIds: const ExternalIds()),
          _choices(),
        ),
      );

      expect(_writes(harness), isEmpty);
    });

    test('does not post if the lookup fails', () async {
      const failure = Unreachable();
      final harness = LookupHarness();
      harness.radarr.answers[lookupPath] = failedAnswer(failure);

      expect(
        await failureOf(harness.lookup.add(_fromElsewhere(), _choices())),
        same(failure),
      );
      expect(_writes(harness), isEmpty);
    });
  });

  group('add refused', () {
    /// Adds to a server that answers [answer], and gives the failure. The
    /// movie must have been posted exactly once.
    Future<ServiceFailure> refusal(
      Result<ServiceResponse, HttpError> answer,
    ) async {
      final harness = LookupHarness();
      final candidate = await _candidate(harness);
      harness.radarr.addAnswer = answer;

      final failure = await failureOf(
        harness.lookup.add(candidate, _choices()),
      );

      expect(_writes(harness), hasLength(1));
      return failure;
    }

    test('because it was added meanwhile is a conflict', () async {
      final harness = LookupHarness();
      final candidate = await _candidate(harness);
      harness.radarr.held.add(bunnyTmdbId);

      expect(
        await failureOf(harness.lookup.add(candidate, _choices())),
        isA<Conflict>(),
      );
      expect(_writes(harness), hasLength(1));
    });

    test('is a conflict when existing is one of several reasons', () async {
      final answer = rejected([
        ...records(fixture('add_invalid')),
        ...records(fixture('add_exists')),
      ]);

      expect(await refusal(answer), isA<Conflict>());
    });

    test("for another reason keeps the server's validation", () async {
      final answer = rejected(fixture('add_invalid'));

      final failure = await refusal(answer);

      expect(
        failure,
        same((answer as Err<ServiceResponse, HttpError>).error.failure),
      );
      expect((failure as Validation).messages, isNotEmpty);
    });

    // A folder in use by another movie does not mean that this one exists.
    test('because its folder is taken is not a conflict', () async {
      final answer = rejected([
        {
          ...records(fixture('add_invalid')).single,
          'propertyName': 'Path',
          'errorCode': 'MoviePathValidator',
        },
      ]);

      expect(await refusal(answer), isA<Validation>());
    });

    for (final body in <Object?>[
      {'message': 'no'},
      ['no'],
      null,
    ]) {
      test('with the body $body stays a validation failure', () async {
        expect(await refusal(rejected(body)), isA<Validation>());
      });
    }

    // Never sent again, whatever the failure.
    for (final failure in const [
      OutcomeUnknown(),
      Unreachable(),
      AuthFailed(),
      Forbidden(),
      WritesRefused(),
      Conflict(),
      ServerError(statusCode: 500),
    ]) {
      test('passes on ${failure.runtimeType}', () async {
        expect(await refusal(failedAnswer(failure)), same(failure));
      });
    }

    // The server accepted it, but did not say which item it made.
    for (final body in ['', 'no', '[]', '{}', '{"id": 0}']) {
      test('is not a success when the answer is "$body"', () async {
        expect(
          await refusal(textAnswer(body)),
          anyOf(isA<MalformedResponse>(), isA<OutcomeUnknown>()),
        );
      });
    }
  });
}
