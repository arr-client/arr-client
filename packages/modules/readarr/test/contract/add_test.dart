// Adding an author or a book with quality and metadata profile, root folder and
// monitoring choice (story 8, scenario 3).
//
// What Readarr's own web UI posts: the record of the search with the choices set
// in it. A book brings its editions and its author along: an author the server
// does not have is made with the choices, one it has is left as it is. The
// refusals were recorded; a book the server has is only refused by its database.

import 'dart:convert';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

AddChoices _choices({
  int rootFolderId = 1,
  String monitor = 'all',
  bool searchNow = false,
  Set<int> tags = const {1},
}) => AddChoices(
  rootFolderId: rootFolderId,
  qualityProfileId: 2,
  metadataProfileId: 2,
  monitorOptionId: monitor,
  searchNow: searchNow,
  tagIds: tags,
);

/// The candidate this instance's search makes of [source].
AddCandidate _candidate(MediaKind kind, Map<String, Object?> source) =>
    AddCandidate(
      kind: kind,
      title: 'New',
      externalIds: ExternalIds(
        foreignId:
            source[kind == MediaKind.author
                    ? 'foreignAuthorId'
                    : 'foreignBookId']
                as String?,
      ),
      sourceByInstance: {instanceId: source},
    );

/// An author the server does not have.
Map<String, Object?> _newAuthor() => found(records('search'), 'author').last;

/// A book of [_newAuthor].
Map<String, Object?> _newBook() => found(records('search'), 'book').last;

Map<String, Object?> _posted(Harness harness) =>
    sentBody(harness.server.writes.single)! as Map<String, Object?>;

void main() {
  group('an author', () {
    test('is posted as found, with the choices', () async {
      final harness = Harness();
      final source = _newAuthor();

      final added = await ok(
        harness.lookup.add(
          _candidate(MediaKind.author, source),
          _choices(monitor: 'future', searchNow: true),
        ),
      );

      expect(added, authorRef(FakeReadarr.addedId));
      final write = harness.server.writes.single;
      expect(write.method, HttpMethod.post);
      expect(write.path, 'api/v1/author');
      expect(write.query, isEmpty);
      final body = _posted(harness);
      expect(body['foreignAuthorId'], source['foreignAuthorId']);
      expect(body['authorName'], source['authorName']);
      expect(body['images'], source['images']);
      expect(body['rootFolderPath'], records('rootfolder').single['path']);
      expect(body['qualityProfileId'], 2);
      expect(body['metadataProfileId'], 2);
      expect(body['tags'], [1]);
      expect(body['monitored'], isTrue);
      expect(body['addOptions'], {
        'monitor': 'future',
        'searchForMissingBooks': true,
      });
    });

    test('does not change the candidate', () async {
      final source = _newAuthor();
      final before = jsonEncode(source);

      await ok(
        Harness().lookup.add(_candidate(MediaKind.author, source), _choices()),
      );

      expect(jsonEncode(source), before);
    });

    test('from another instance is first looked up here', () async {
      final harness = Harness();
      final id = _newAuthor()['foreignAuthorId']! as String;

      await ok(
        harness.lookup.add(
          AddCandidate(
            kind: MediaKind.author,
            title: 'New',
            externalIds: ExternalIds(foreignId: id),
            sourceByInstance: const {
              'i2': {'foreignAuthorId': 'theirs', 'id': 9},
            },
          ),
          _choices(),
        ),
      );

      expect(harness.asked, contains(line(HttpMethod.get, 'search')));
      expect(_posted(harness)['foreignAuthorId'], id);
    });

    test('that the server has is a conflict, with nothing sent', () async {
      final harness = Harness();

      expect(
        await failureOf(
          harness.lookup.add(
            _candidate(
              MediaKind.author,
              found(records('search_existing'), 'author').single,
            ),
            _choices(),
          ),
        ),
        isA<Conflict>(),
      );
      expect(harness.server.writes, isEmpty);
    });

    // Added since it was searched for.
    test('refused as already added is a conflict', () async {
      final harness = Harness();
      final source = _newAuthor();
      harness.server.authors.add({...source, 'id': 7});

      expect(
        await failureOf(
          harness.lookup.add(_candidate(MediaKind.author, source), _choices()),
        ),
        isA<Conflict>(),
      );
      expect(harness.server.writes, hasLength(1));
    });

    for (final fixture in ['author_add_bad_root', 'author_add_bad_profile']) {
      test('keeps the server\'s refusal, as $fixture', () async {
        final harness = Harness()
          ..server.writeAnswer = FakeReadarr.body(
            jsonEncode(records(fixture)),
            status: 400,
            write: true,
          );

        expect(
          await failureOf(
            harness.lookup.add(
              _candidate(MediaKind.author, _newAuthor()),
              _choices(),
            ),
          ),
          isA<Validation>().having((failure) => failure.messages, 'messages', [
            for (final refusal in records(fixture)) refusal['errorMessage'],
          ]),
        );
      });
    }

    test('without its root folder is refused, with nothing sent', () async {
      final harness = Harness();

      expect(
        await failureOf(
          harness.lookup.add(
            _candidate(MediaKind.author, _newAuthor()),
            _choices(rootFolderId: 99),
          ),
        ),
        isA<Validation>(),
      );
      expect(harness.server.writes, isEmpty);
    });
  });

  group('a book', () {
    test('of a new author makes the author with the choices', () async {
      final harness = Harness();
      final source = _newBook();
      final author = source['author']! as Map<String, Object?>;

      final added = await ok(
        harness.lookup.add(
          _candidate(MediaKind.book, source),
          _choices(monitor: 'none', searchNow: true),
        ),
      );

      expect(added, bookRef(FakeReadarr.addedId));
      final write = harness.server.writes.single;
      expect(write.method, HttpMethod.post);
      expect(write.path, 'api/v1/book');
      final body = _posted(harness);
      expect(body['foreignBookId'], source['foreignBookId']);
      expect(body['foreignEditionId'], source['foreignEditionId']);
      // The server takes the edition marked among them.
      expect(body['editions'], source['editions']);
      expect(body['monitored'], isTrue);
      expect(body['addOptions'], {'searchForNewBook': true});
      final sent = body['author']! as Map<String, Object?>;
      expect(sent['foreignAuthorId'], author['foreignAuthorId']);
      expect(sent['rootFolderPath'], records('rootfolder').single['path']);
      expect(sent['qualityProfileId'], 2);
      expect(sent['metadataProfileId'], 2);
      expect(sent['tags'], [1]);
      expect(sent['monitored'], isTrue);
      // The server would otherwise search for the whole author.
      expect(sent['addOptions'], {
        'monitor': 'none',
        'searchForMissingBooks': false,
      });
    });

    test('of an author the server has leaves the author as it is', () async {
      final harness = Harness();
      final source = _newBook();
      final author = {
        ...source['author']! as Map<String, Object?>,
        'id': 2,
        'qualityProfileId': 1,
        'metadataProfileId': 1,
        'path': '/redacted/held',
      };
      source['author'] = author;

      await ok(
        harness.lookup.add(_candidate(MediaKind.book, source), _choices()),
      );

      expect(_posted(harness)['author'], author);
    });

    test('that the server has is a conflict, with nothing sent', () async {
      final harness = Harness();

      expect(
        await failureOf(
          harness.lookup.add(
            _candidate(
              MediaKind.book,
              found(records('search_existing'), 'book').single,
            ),
            _choices(),
          ),
        ),
        isA<Conflict>(),
      );
      expect(harness.server.writes, isEmpty);
    });

    // The search was made before the library had it.
    test('refused as already added is a conflict', () async {
      final harness = Harness();

      expect(
        await failureOf(
          harness.lookup.add(
            _candidate(MediaKind.book, found(records('search'), 'book').first),
            _choices(),
          ),
        ),
        isA<Conflict>(),
      );
      expect(harness.server.writes, hasLength(1));
    });
  });

  group('failures', () {
    for (final MapEntry(key: cause, value: (answer, expected))
        in writeFailures.entries) {
      test('$cause is reported and the add is sent once', () async {
        final harness = Harness()..server.writeAnswer = answer;

        final failure = await failureOf(
          harness.lookup.add(
            _candidate(MediaKind.author, _newAuthor()),
            _choices(),
          ),
        );

        expect(failure.runtimeType, expected);
        expect(harness.server.writes, hasLength(1));
      });
    }

    test('an accepted add that names nothing has an unknown outcome', () async {
      final harness = Harness()
        ..server.writeAnswer = FakeReadarr.body('{', status: 201);

      expect(
        await failureOf(
          harness.lookup.add(
            _candidate(MediaKind.author, _newAuthor()),
            _choices(),
          ),
        ),
        isA<OutcomeUnknown>(),
      );
    });

    test('nothing else can be added', () async {
      final harness = Harness();

      await expectProgrammingError(
        () => harness.lookup.add(
          _candidate(MediaKind.movie, _newAuthor()),
          _choices(),
        ),
      );

      expect(harness.server.requests, isEmpty);
    });
  });
}
