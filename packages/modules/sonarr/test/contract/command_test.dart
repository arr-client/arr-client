// Searching, refreshing and rescanning (story 5, scenario 2). Some of these
// commands act on the whole library without their target.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonarr/sonarr_module.dart';

import 'manage_support.dart';
import 'support.dart';

/// Each command the user can start, and what it sends.
final _commands =
    <String, (ServiceResult<Command> Function(CommandProvider), Object)>{
      'a search for an episode': (
        (commands) => commands.search([episode()]),
        {
          'name': 'EpisodeSearch',
          'episodeIds': [31],
        },
      ),
      'a search for several episodes': (
        (commands) => commands.search([episode(), episode(37)]),
        {
          'name': 'EpisodeSearch',
          'episodeIds': [31, 37],
        },
      ),
      'a search for a season': (
        (commands) => commands.search([season(1)]),
        {'name': 'SeasonSearch', 'seriesId': 1, 'seasonNumber': 1},
      ),
      'a search for the specials': (
        (commands) => commands.search([season(0)]),
        {'name': 'SeasonSearch', 'seriesId': 1, 'seasonNumber': 0},
      ),
      'a search for a series': (
        (commands) => commands.search([series()]),
        {'name': 'SeriesSearch', 'seriesId': 1},
      ),
      'a refresh of a series': (
        (commands) => commands.refresh(series()),
        {
          'name': 'RefreshSeries',
          'seriesIds': [1],
        },
      ),
      'a rescan of a series': (
        (commands) => commands.rescan(series()),
        {'name': 'RescanSeries', 'seriesId': 1},
      ),
    };

/// What cannot be started.
final _unsupported = <String, ServiceResult<Command> Function(CommandProvider)>{
  'a refresh of a season': (commands) => commands.refresh(season(1)),
  'a refresh of an episode': (commands) => commands.refresh(episode()),
  'a refresh of a movie': (commands) => commands.refresh(movie),
  'a rescan of a season': (commands) => commands.rescan(season(1)),
  'a rescan of an episode': (commands) => commands.rescan(episode()),
  'a rescan of a movie': (commands) => commands.rescan(movie),
  'a search for a movie': (commands) => commands.search([movie]),
  'a search for a series of another instance': (commands) =>
      commands.search([const MediaTarget(elsewhere)]),
  'a refresh of a series of another instance': (commands) =>
      commands.refresh(const MediaTarget(elsewhere)),
  'a rescan of a series of another instance': (commands) =>
      commands.rescan(const MediaTarget(elsewhere)),
  'a search for an episode of a season': (commands) =>
      commands.search([MediaTarget(episodeRef(31), seasonNumber: 1)]),
  // One command names one series or season.
  'a search for two series': (commands) =>
      commands.search([series(), series(2)]),
  'a search for two seasons': (commands) =>
      commands.search([season(1), season(2)]),
  'a search for an episode and a series': (commands) =>
      commands.search([episode(), series()]),
  'a search for episodes and a movie': (commands) =>
      commands.search([episode(), movie]),
};

void main() {
  test('the module offers commands', () {
    expect(
      SonarrModule().capabilitiesFor(
        const ProbeResult(
          product: 'Sonarr',
          version: '4.0.20.3014',
          newerThanTested: false,
        ),
        null,
      ),
      contains(CapabilityKind.command),
    );
  });

  test('says what it supports without asking the server', () {
    final harness = ManageHarness();
    final commands = harness.commands;
    final supported = {
      series(): CommandAction.values.toSet(),
      season(1): {CommandAction.search},
      season(0): {CommandAction.search},
      episode(): {CommandAction.search},
      movie: <CommandAction>{},
      MediaTarget(episodeRef(31), seasonNumber: 1): <CommandAction>{},
    };

    for (final MapEntry(key: target, value: actions) in supported.entries) {
      for (final action in CommandAction.values) {
        expect(
          commands.supports(action, target),
          actions.contains(action),
          reason:
              '${action.name} of ${target.item.kind.name} '
              '${target.seasonNumber}',
        );
      }
    }
    expect(harness.sonarr.requests, isEmpty);
  });

  for (final MapEntry(key: name, value: (start, body)) in _commands.entries) {
    test('starts $name, naming its target', () async {
      final harness = ManageHarness();

      final command = await ok(start(harness.commands));

      final request = harness.sonarr.requests.single;
      expect(request.method, HttpMethod.post);
      expect(request.path, 'api/v3/command');
      expect(request.query, isEmpty);
      expect(sentBody(request), body);
      final accepted = record(
        commandFixtures[(body as Map<String, Object?>)['name']]!,
      );
      expect(command.id, accepted['id']);
      expect(command.name, body['name']);
      expect(command.isFinished, isFalse);
    });
  }

  test('searches for nothing when nothing is named', () async {
    final harness = ManageHarness();

    expect(await failureOf(harness.commands.search([])), isA<Validation>());
    expect(harness.sonarr.requests, isEmpty);
  });

  for (final MapEntry(key: name, value: start) in _unsupported.entries) {
    test('does not start $name', () async {
      final harness = ManageHarness();

      await expectProgrammingError(() => start(harness.commands));

      expect(harness.sonarr.requests, isEmpty);
    });
  }

  for (final MapEntry(key: cause, value: (answer, expected)) in {
    ...writeFailures,
    // The server accepted it, so the command may well be running.
    'an answer that breaks off': (
      FakeSonarr.body('{"id":', status: 201),
      OutcomeUnknown,
    ),
  }.entries) {
    for (final MapEntry(key: name, value: (start, _)) in _commands.entries) {
      test('$name reports $cause and is sent once', () async {
        final harness = ManageHarness()..sonarr.writeAnswer = answer;

        final failure = await failureOf(start(harness.commands));

        expect(failure.runtimeType, expected);
        expect(harness.asked, [line(HttpMethod.post, 'command')]);
      });
    }
  }

  test('follows a command to its outcome', () async {
    final harness = ManageHarness();
    final id = harness.sonarr.command['id']! as int;

    final command = await ok(harness.commands.commandStatus(id));

    expect(harness.asked, [line(HttpMethod.get, 'command/$id')]);
    expect(command.id, id);
    expect(command.status, CommandStatus.completed);
    expect(command.outcome, CommandOutcome.succeeded);
  });

  test('reports a command the server does not have', () async {
    final harness = ManageHarness();

    expect(
      await failureOf(harness.commands.commandStatus(999999)),
      isA<NotFound>(),
    );
  });
}
