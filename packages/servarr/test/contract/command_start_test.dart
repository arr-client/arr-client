// Starting a search, refresh or rescan, `POST command` (story 5, scenario 2).
// Each service names its commands and their targets; the client sends what it
// is given and reads the command to follow with `commandStatus`.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'manage_support.dart';
import 'support.dart';

/// Each command of the allow-lists, its target as recorded, and its recording.
final _commands = [
  (
    radarr,
    'MoviesSearch',
    <String, Object?>{
      'movieIds': [2],
    },
    'manage_command_search',
  ),
  (
    radarr,
    'RefreshMovie',
    <String, Object?>{
      'movieIds': [2],
    },
    'manage_command_refresh',
  ),
  (
    radarr,
    'RescanMovie',
    <String, Object?>{'movieId': 2},
    'manage_command_rescan',
  ),
  (
    sonarr,
    'EpisodeSearch',
    <String, Object?>{
      'episodeIds': [2, 3],
    },
    'manage_command_search_episode',
  ),
  (
    sonarr,
    'SeasonSearch',
    <String, Object?>{'seriesId': 2, 'seasonNumber': 1},
    'manage_command_search_season',
  ),
  (
    sonarr,
    'SeriesSearch',
    <String, Object?>{'seriesId': 2},
    'manage_command_search_series',
  ),
  (
    sonarr,
    'RefreshSeries',
    <String, Object?>{
      'seriesIds': [2],
    },
    'manage_command_refresh',
  ),
  (
    sonarr,
    'RescanSeries',
    <String, Object?>{'seriesId': 2},
    'manage_command_rescan',
  ),
];

/// The answer to an accepted command has status 201.
Reply _accepted(Object? body) => Reply.json(body, status: 201);

void main() {
  for (final (service, name, target, fixture) in _commands) {
    group('${service.name} $name', () {
      test('sends the name and the target', () async {
        final server = routes({
          'POST command': _accepted(service.fixture(fixture)),
        });

        await value(service.client(server).startCommand(name, target));

        final request = server.requests.single;
        expect(request.method, HttpMethod.post);
        expect(request.path, 'api/v3/command');
        expect(request.query, isEmpty);
        expect(sentBody(request), {'name': name, ...target});
      });

      test('gives the command the server accepted', () async {
        final record = service.object(fixture);
        final server = routes({'POST command': _accepted(record)});

        final command = await value(
          service.client(server).startCommand(name, target),
        );

        expect(command.id, record['id']);
        expect(command.name, name);
        expect(command.status.name, record['status']);
        expect(command.result, CommandResult.unknown);
        expect(command.outcome, CommandOutcome.pending);
        expect(command.isFinished, isFalse);
      });
    });
  }

  test('sends season 0, the specials', () async {
    final server = routes({
      'POST command': _accepted(sonarr.fixture('manage_command_search_season')),
    });

    await value(
      sonarr.client(server).startCommand('SeasonSearch', const {
        'seriesId': 2,
        'seasonNumber': 0,
      }),
    );

    expect(sentBody(server.requests.single), {
      'name': 'SeasonSearch',
      'seriesId': 2,
      'seasonNumber': 0,
    });
  });

  for (final (without, target) in [
    ('a target', <String, Object?>{}),
    ('ids', <String, Object?>{'movieIds': <int>[]}),
  ]) {
    test('starts nothing without $without', () async {
      final server = routes({
        'POST command': _accepted(radarr.fixture('manage_command_search')),
      });

      expect(
        await failure(
          radarr.client(server).startCommand('MoviesSearch', target),
        ),
        isA<Validation>(),
      );
      expect(server.requests, isEmpty);
    });
  }

  group('a command that fails to start', () {
    final failures = <String, (Answer, Type)>{
      ...writeFailures,
      // As recorded.
      'a name the server does not know': (
        refusal(500, 'Sequence contains no matching element'),
        ServerError,
      ),
      'an answer that breaks off': (
        const Reply(201, '{"id":'),
        MalformedResponse,
      ),
      'an answer without a command': (
        const Reply(201, '{}'),
        MalformedResponse,
      ),
    };

    for (final MapEntry(key: cause, value: (answer, expected))
        in failures.entries) {
      test('reports $cause and is sent once', () async {
        final server = FakeServer.always(answer);

        final result = await failure(
          radarr.client(server).startCommand('MoviesSearch', const {
            'movieIds': [2],
          }),
        );

        expect(result.runtimeType, expected);
        expect(server.requests, hasLength(1));
      });
    }
  });
}
