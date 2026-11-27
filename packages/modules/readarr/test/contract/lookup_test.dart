// Searching for authors and books, finding one again and the choices for adding
// it (story 8, scenario 3).
//
// `search` is the one read that gives a book with its author and editions,
// which adding it takes; `book/lookup` gives neither. It is what the web UI
// asks, with `author:<id>` or `work:<id>` for one by the metadata source's id.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

List<Map<String, Object?>> _authors([String fixture = 'search']) =>
    found(records(fixture), 'author');

List<Map<String, Object?>> _books([String fixture = 'search']) =>
    found(records(fixture), 'book');

String _foreignId(Map<String, Object?> record, MediaKind kind) =>
    record[kind == MediaKind.author ? 'foreignAuthorId' : 'foreignBookId']!
        as String;

AddCandidate _candidate(MediaKind kind, String? foreignId) => AddCandidate(
  kind: kind,
  title: 'Found elsewhere',
  externalIds: ExternalIds(foreignId: foreignId),
);

Future<List<AddCandidate>> _lookup(Harness harness, MediaKind kind) async => [
  for (final candidate in await ok(
    harness.lookup.lookup(FakeReadarr.searchTerm),
  ))
    if (candidate.kind == kind) candidate,
];

void main() {
  test('adds authors and books', () {
    expect(Harness().lookup.itemKinds, {MediaKind.author, MediaKind.book});
  });

  group('lookup', () {
    test('searches once for authors and books', () async {
      final harness = Harness();

      final candidates = await ok(
        harness.lookup.lookup(FakeReadarr.searchTerm),
      );

      expect(harness.asked, [line(HttpMethod.get, 'search')]);
      expect(harness.server.requests.single.query, {
        'term': [FakeReadarr.searchTerm],
      });
      expect(
        candidates.where((candidate) => candidate.kind == MediaKind.author),
        hasLength(_authors().length),
      );
      expect(
        candidates.where((candidate) => candidate.kind == MediaKind.book),
        hasLength(_books().length),
      );
    });

    test('maps an author', () async {
      final raw = _authors().first;

      final candidate = (await _lookup(Harness(), MediaKind.author)).first;

      expect(candidate.title, raw['authorName']);
      expect(candidate.parentTitle, isNull);
      expect(candidate.externalIds.foreignId, raw['foreignAuthorId']);
      expect(candidate.existingRefs, isEmpty);
      expect(candidate.sourceByInstance, {instanceId: raw});
    });

    test('maps a book and names its author', () async {
      final raw = _books()[1];
      final author = raw['author']! as Map<String, Object?>;

      final candidate = (await _lookup(Harness(), MediaKind.book))[1];

      expect(candidate.title, raw['title']);
      expect(candidate.parentTitle, author['authorName']);
      expect(candidate.externalIds.foreignId, raw['foreignBookId']);
      expect(
        candidate.year,
        DateTime.parse(raw['releaseDate']! as String).year,
      );
      expect(candidate.existingRefs, isEmpty);
      expect(candidate.sourceByInstance, {instanceId: raw});
    });

    // The proxied address is behind the web UI's sign-in.
    test('shows the public cover of what the library does not have', () async {
      final candidates = await ok(
        Harness().lookup.lookup(FakeReadarr.searchTerm),
      );

      for (final candidate in candidates) {
        expect(candidate.images, isNotEmpty);
        for (final image in candidate.images) {
          expect(image.instancePath, isNull);
          expect(image.remoteUrl, isNotNull);
        }
      }
    });

    test('names the library item of what the server has', () async {
      final harness = Harness()..server.search = records('search_existing');

      final candidates = await ok(
        harness.lookup.lookup(FakeReadarr.searchTerm),
      );

      expect(
        candidates
            .singleWhere((candidate) => candidate.kind == MediaKind.author)
            .existingRefs,
        [authorRef(1)],
      );
      expect(
        candidates
            .singleWhere((candidate) => candidate.kind == MediaKind.book)
            .existingRefs,
        [bookRef(18)],
      );
    });

    for (final term in ['', '   ']) {
      test('sends nothing for "$term"', () async {
        final harness = Harness();

        expect(await ok(harness.lookup.lookup(term)), isEmpty);
        expect(harness.server.requests, isEmpty);
      });
    }

    test('fails when the search does', () async {
      final harness = Harness();
      harness.server.overrides['search'] = FakeReadarr.body('', status: 503);

      expect(
        await failureOf(harness.lookup.lookup(FakeReadarr.searchTerm)),
        isA<ServerError>(),
      );
    });

    test('a result it cannot understand is malformed', () async {
      final harness = Harness();
      (harness.server.search.first['author']! as Map<String, Object?>).remove(
        'authorName',
      );

      expect(
        await failureOf(harness.lookup.lookup(FakeReadarr.searchTerm)),
        isA<MalformedResponse>(),
      );
    });
  });

  group('find', () {
    for (final (kind, prefix) in [
      (MediaKind.author, 'author'),
      (MediaKind.book, 'work'),
    ]) {
      test('a ${kind.name} by the id of the metadata source', () async {
        final harness = Harness();
        final raw = (kind == MediaKind.author ? _authors() : _books()).last;
        final id = _foreignId(raw, kind);

        final candidate = await ok(harness.lookup.find(_candidate(kind, id)));

        expect(harness.asked, [line(HttpMethod.get, 'search')]);
        expect(harness.server.requests.single.query, {
          'term': ['$prefix:$id'],
        });
        expect(candidate.kind, kind);
        expect(candidate.sourceByInstance, {instanceId: raw});
        expect(candidate.existingRefs, isEmpty);
      });

      test('says that the instance has the ${kind.name}', () async {
        final raw =
            (kind == MediaKind.author
                    ? _authors('search_existing')
                    : _books('search_existing'))
                .single;

        final candidate = await ok(
          Harness().lookup.find(_candidate(kind, _foreignId(raw, kind))),
        );

        expect(candidate.existingRefs, [
          kind == MediaKind.author ? authorRef(1) : bookRef(18),
        ]);
      });
    }

    test('one the search does not give is not found', () async {
      expect(
        await failureOf(
          Harness().lookup.find(_candidate(MediaKind.author, 'unknown')),
        ),
        isA<NotFound>(),
      );
    });

    test('one without an id is not found, and nothing is asked', () async {
      final harness = Harness();

      expect(
        await failureOf(harness.lookup.find(_candidate(MediaKind.book, null))),
        isA<NotFound>(),
      );
      expect(harness.server.requests, isEmpty);
    });
  });

  group('add options', () {
    for (final kind in [MediaKind.author, MediaKind.book]) {
      test('of a ${kind.name} have both profiles and the choices', () async {
        final options = await ok(Harness().lookup.addOptions(kind));

        expect(
          options.serverOptions.map((option) => option.kind).toSet(),
          ServerOptionKind.values.toSet(),
        );
        expect(options.monitorOptions.map((option) => option.id), [
          'all',
          'future',
          'missing',
          'existing',
          'first',
          'latest',
          'none',
        ]);
      });
    }

    test('are not of anything else', () async {
      final harness = Harness();

      await expectProgrammingError(
        () => harness.lookup.addOptions(MediaKind.movie),
      );

      expect(harness.server.requests, isEmpty);
    });
  });
}
