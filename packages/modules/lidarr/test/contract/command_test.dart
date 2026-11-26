// Searching, refreshing and rescanning (story 8, scenario 4, as story 5). Some
// of these commands act on the whole library without their target.
//
// Lidarr has no command to rescan one artist: its disk scan takes folders, so
// the artist is read for its folder. Left to its defaults that scan also adds
// every artist it finds.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Each command that needs no read first, and what it sends.
final _commands =
    <String, (ServiceResult<Command> Function(CommandProvider), Object)>{
      'a search for an album': (
        (commands) => commands.search([album()]),
        {
          'name': 'AlbumSearch',
          'albumIds': [1],
        },
      ),
      'a search for several albums': (
        (commands) => commands.search([album(), album(3)]),
        {
          'name': 'AlbumSearch',
          'albumIds': [1, 3],
        },
      ),
      'a search for an artist': (
        (commands) => commands.search([artist()]),
        {'name': 'ArtistSearch', 'artistId': 1},
      ),
      'a refresh of an artist': (
        (commands) => commands.refresh(artist()),
        {
          'name': 'RefreshArtist',
          'artistIds': [1],
        },
      ),
      'a refresh of an album': (
        (commands) => commands.refresh(album()),
        {'name': 'RefreshAlbum', 'albumId': 1},
      ),
    };

final _unsupported = <String, ServiceResult<Command> Function(CommandProvider)>{
  'a search for a track': (commands) => commands.search([track()]),
  'a search for a movie': (commands) => commands.search([movie]),
  'a search for two artists': (commands) =>
      commands.search([artist(), artist(2)]),
  'a search for an album and an artist': (commands) =>
      commands.search([album(), artist()]),
  'a rescan of an album': (commands) => commands.rescan(album()),
  'a rescan of a movie': (commands) => commands.rescan(movie),
  'a refresh of a track': (commands) => commands.refresh(track()),
  'a refresh of an artist of another instance': (commands) =>
      commands.refresh(const MediaTarget(elsewhere)),
  'a rescan of an artist of another instance': (commands) =>
      commands.rescan(const MediaTarget(elsewhere)),
};

void main() {
  test('says what it supports without asking the server', () {
    final harness = Harness();
    final supported = {
      artist(): CommandAction.values.toSet(),
      album(): {CommandAction.search, CommandAction.refresh},
      track(): <CommandAction>{},
      movie: <CommandAction>{},
      const MediaTarget(elsewhere): <CommandAction>{},
    };

    for (final MapEntry(key: target, value: actions) in supported.entries) {
      for (final action in CommandAction.values) {
        expect(
          harness.commands.supports(action, target),
          actions.contains(action),
          reason: '${action.name} of ${target.item.kind.name}',
        );
      }
    }
    expect(harness.server.requests, isEmpty);
  });

  for (final MapEntry(key: name, value: (start, body)) in _commands.entries) {
    test('starts $name, naming its target', () async {
      final harness = Harness();

      final command = await ok(start(harness.commands));

      final request = harness.server.requests.single;
      expect(request.method, HttpMethod.post);
      expect(request.path, 'api/v1/command');
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

  group('rescan', () {
    test('scans the folder of the artist and adds nothing', () async {
      final harness = Harness();
      final path = byId(harness.server.artists, 1)['path'];

      final command = await ok(harness.commands.rescan(artist()));

      expect(harness.asked, [
        line(HttpMethod.get, 'artist/1'),
        line(HttpMethod.post, 'command'),
      ]);
      final body =
          sentBody(harness.server.writes.single)! as Map<String, Object?>;
      expect(body['name'], 'RescanFolders');
      expect(body['folders'], [path]);
      expect(body['artistIds'], [1]);
      expect(body['addNewArtists'], isFalse);
      expect(command.name, 'RescanFolders');
    });

    test('of an artist without a folder sends no command', () async {
      final harness = Harness();
      byId(harness.server.artists, 1).remove('path');

      await failureOf(harness.commands.rescan(artist()));

      expect(harness.server.writes, isEmpty);
    });

    test('of an artist the server does not have is not found', () async {
      final harness = Harness();

      expect(
        await failureOf(harness.commands.rescan(artist(99))),
        isA<NotFound>(),
      );
      expect(harness.server.writes, isEmpty);
    });
  });

  test('searches for nothing when nothing is named', () async {
    final harness = Harness();

    expect(await failureOf(harness.commands.search([])), isA<Validation>());
    expect(harness.server.requests, isEmpty);
  });

  for (final MapEntry(key: name, value: start) in _unsupported.entries) {
    test('does not start $name', () async {
      final harness = Harness();

      await expectProgrammingError(() => start(harness.commands));

      expect(harness.server.requests, isEmpty);
    });
  }

  for (final MapEntry(key: cause, value: (answer, expected)) in {
    ...writeFailures,
    // The server accepted it, so the command may well be running.
    'an answer that breaks off': (
      FakeLidarr.body('{"id":', status: 201),
      OutcomeUnknown,
    ),
  }.entries) {
    test('$cause is reported and the command is sent once', () async {
      final harness = Harness()..server.writeAnswer = answer;

      final failure = await failureOf(harness.commands.search([album()]));

      expect(failure.runtimeType, expected);
      expect(harness.server.requests, hasLength(1));
    });
  }

  test('follows a command to its outcome', () async {
    final harness = Harness();
    final id = harness.server.command['id']! as int;

    final command = await ok(harness.commands.commandStatus(id));

    expect(harness.asked, [line(HttpMethod.get, 'command/$id')]);
    expect(command.status, CommandStatus.completed);
    expect(command.outcome, CommandOutcome.succeeded);
  });

  test('reports a command the server does not have', () async {
    expect(
      await failureOf(Harness().commands.commandStatus(999999)),
      isA<NotFound>(),
    );
  });
}
