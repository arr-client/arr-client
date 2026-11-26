// Searching, refreshing and rescanning (story 8, scenario 4, as story 5). Some
// of these commands act on the whole library without their target.
//
// Readarr refreshes one author or one book by `authorId` or `bookId`. It has no
// command to rescan one author: its disk scan takes folders, so the author is
// read for its folder. Left to its defaults that scan also adds every author it
// finds.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Each command that needs no read first, and what it sends.
final _commands =
    <String, (ServiceResult<Command> Function(CommandProvider), Object)>{
      'a search for a book': (
        (commands) => commands.search([book()]),
        {
          'name': 'BookSearch',
          'bookIds': [8],
        },
      ),
      'a search for several books': (
        (commands) => commands.search([book(), book(19)]),
        {
          'name': 'BookSearch',
          'bookIds': [8, 19],
        },
      ),
      'a search for an author': (
        (commands) => commands.search([author()]),
        {'name': 'AuthorSearch', 'authorId': 1},
      ),
      'a refresh of an author': (
        (commands) => commands.refresh(author()),
        {'name': 'RefreshAuthor', 'authorId': 1},
      ),
      'a refresh of a book': (
        (commands) => commands.refresh(book()),
        {'name': 'RefreshBook', 'bookId': 8},
      ),
    };

final _unsupported = <String, ServiceResult<Command> Function(CommandProvider)>{
  'a search for a movie': (commands) => commands.search([movie]),
  'a search for two authors': (commands) =>
      commands.search([author(), author(2)]),
  'a search for a book and an author': (commands) =>
      commands.search([book(), author()]),
  'a rescan of a book': (commands) => commands.rescan(book()),
  'a rescan of a movie': (commands) => commands.rescan(movie),
  'a refresh of a movie': (commands) => commands.refresh(movie),
  'a refresh of an author of another instance': (commands) =>
      commands.refresh(const MediaTarget(elsewhere)),
  'a rescan of an author of another instance': (commands) =>
      commands.rescan(const MediaTarget(elsewhere)),
};

void main() {
  test('says what it supports without asking the server', () {
    final harness = Harness();
    final supported = {
      author(): CommandAction.values.toSet(),
      book(): {CommandAction.search, CommandAction.refresh},
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
    test('scans the folder of the author and adds nothing', () async {
      final harness = Harness();
      final path = byId(harness.server.authors, 1)['path'];

      final command = await ok(harness.commands.rescan(author()));

      expect(harness.asked, [
        line(HttpMethod.get, 'author/1'),
        line(HttpMethod.post, 'command'),
      ]);
      final body =
          sentBody(harness.server.writes.single)! as Map<String, Object?>;
      expect(body['name'], 'RescanFolders');
      expect(body['folders'], [path]);
      expect(body['authorIds'], [1]);
      expect(body['addNewAuthors'], isFalse);
      expect(command.name, 'RescanFolders');
    });

    test('of an author without a folder sends no command', () async {
      final harness = Harness();
      byId(harness.server.authors, 1).remove('path');

      await failureOf(harness.commands.rescan(author()));

      expect(harness.server.writes, isEmpty);
    });

    test('of an author the server does not have is not found', () async {
      final harness = Harness();

      expect(
        await failureOf(harness.commands.rescan(author(99))),
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
      FakeReadarr.body('{"id":', status: 201),
      OutcomeUnknown,
    ),
  }.entries) {
    test('$cause is reported and the command is sent once', () async {
      final harness = Harness()..server.writeAnswer = answer;

      final failure = await failureOf(harness.commands.search([book()]));

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
