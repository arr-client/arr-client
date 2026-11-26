// Automatic search, refresh and rescan of movies (story 5, scenario 2). Some of
// these commands act on the whole library when no movie is named, so every one
// must name its movies.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radarr/radarr_module.dart';

import 'library_support.dart';
import 'manage_support.dart';

/// Each command of one movie: what starts it, what is posted and the recording.
final _commands =
    <
      String,
      (
        ServiceResult<Command> Function(CommandProvider, MediaTarget),
        Map<String, Object?>,
        String,
      )
    >{
      'search': (
        (commands, target) => commands.search([target]),
        {
          'name': 'MoviesSearch',
          'movieIds': [2],
        },
        'manage_command_search',
      ),
      'refresh': (
        (commands, target) => commands.refresh(target),
        {
          'name': 'RefreshMovie',
          'movieIds': [2],
        },
        'manage_command_refresh',
      ),
      'rescan': (
        (commands, target) => commands.rescan(target),
        {'name': 'RescanMovie', 'movieId': 2},
        'manage_command_rescan',
      ),
    };

/// A Radarr that accepts a command and answers with the recording [name].
ManageHarness _accepting(String name) {
  final harness = ManageHarness();
  harness.radarr.routes['POST command'] = replyJson(
    manageObject(name),
    status: 201,
  );
  return harness;
}

void main() {
  test('is offered, and asks nothing by itself', () {
    final harness = ManageHarness();

    expect(
      RadarrModule().capabilitiesFor(
        const ProbeResult(product: 'Radarr', version: '7.0.3.10918'),
        null,
      ),
      contains(CapabilityKind.command),
    );
    harness.commands;
    expect(harness.sent, isEmpty);
  });

  test('offers all three for a movie, and for nothing else', () {
    final harness = ManageHarness();

    for (final action in CommandAction.values) {
      expect(
        harness.commands.supports(action, MediaTarget(movieRef(1))),
        isTrue,
        reason: action.name,
      );
      for (final MapEntry(key: name, value: target) in foreignTargets.entries) {
        expect(
          harness.commands.supports(action, target),
          isFalse,
          reason: '${action.name} of $name',
        );
      }
    }
    expect(harness.sent, isEmpty);
  });

  for (final MapEntry(key: action, value: (start, body, recording))
      in _commands.entries) {
    group(action, () {
      test('names the movie, and sends nothing else', () async {
        final harness = _accepting(recording);

        await succeed(start(harness.commands, MediaTarget(movieRef(2))));

        final request = harness.server.requests.single;
        expect(asked(request), 'POST command');
        expect(request.query, isEmpty);
        expect(sentBody(request), body);
      });

      test('gives the command to follow', () async {
        final wire = manageObject(recording);
        final harness = _accepting(recording);

        final command = await succeed(
          start(harness.commands, MediaTarget(movieRef(2))),
        );

        expect(command.id, wire['id']);
        expect(command.name, body['name']);
        expect(command.status.name, wire['status']);
        expect(command.outcome, CommandOutcome.pending);
      });

      for (final MapEntry(key: name, value: target) in foreignTargets.entries) {
        test('starts nothing for $name', () async {
          final harness = _accepting(recording);

          expect(
            await failureOf(start(harness.commands, target)),
            isA<Validation>(),
          );
          expect(harness.sent, isEmpty);
        });
      }

      for (final (failure, status) in writeFailures) {
        test('passes on ${failure.runtimeType} and is sent once', () async {
          final harness = ManageHarness();
          harness.radarr.routes['POST command'] = failedAnswer(
            failure,
            status: status,
          );

          expect(
            await failureOf(start(harness.commands, MediaTarget(movieRef(2)))),
            same(failure),
          );
          expect(harness.sent, ['POST command']);
        });
      }

      // The server accepted it, so the command may well be running.
      test('cannot tell the outcome of an answer it cannot read', () async {
        final harness = ManageHarness();
        harness.radarr.routes['POST command'] = reply('{}', status: 201);

        expect(
          await failureOf(start(harness.commands, MediaTarget(movieRef(2)))),
          isA<OutcomeUnknown>(),
        );
        expect(harness.sent, ['POST command']);
      });
    });
  }

  test('searches for several movies with one command', () async {
    final harness = _accepting('manage_command_search');

    await succeed(
      harness.commands.search([
        MediaTarget(movieRef(2)),
        MediaTarget(movieRef(3)),
      ]),
    );

    expect(sentBody(harness.server.requests.single), {
      'name': 'MoviesSearch',
      'movieIds': [2, 3],
    });
  });

  test('searches for nothing without a movie', () async {
    final harness = _accepting('manage_command_search');

    expect(await failureOf(harness.commands.search([])), isA<Validation>());
    expect(harness.sent, isEmpty);
  });

  // Leaving it out would search less than was asked.
  for (final MapEntry(key: name, value: target) in foreignTargets.entries) {
    test('searches for none of a list with $name', () async {
      final harness = _accepting('manage_command_search');

      expect(
        await failureOf(
          harness.commands.search([MediaTarget(movieRef(2)), target]),
        ),
        isA<Validation>(),
      );
      expect(harness.sent, isEmpty);
    });
  }

  group('commandStatus', () {
    test('reads the command', () async {
      final harness = ManageHarness();
      harness.radarr.routes['GET command/9'] = replyJson(
        manageObject('manage_command_status'),
      );

      final command = await succeed(harness.commands.commandStatus(9));

      expect(harness.sent, ['GET command/9']);
      expect(harness.server.requests.single.query, isEmpty);
      expect(command.id, 9);
      expect(command.name, 'MoviesSearch');
      expect(command.status, CommandStatus.completed);
      expect(command.result, CommandResult.successful);
      expect(command.outcome, CommandOutcome.succeeded);
      expect(command.message, manageObject('manage_command_status')['message']);
    });

    test('passes on a failure', () async {
      const failure = NotFound();
      final harness = ManageHarness()
        ..radarr.down = failedAnswer(failure, status: 404);

      expect(await failureOf(harness.commands.commandStatus(9)), same(failure));
    });
  });
}
