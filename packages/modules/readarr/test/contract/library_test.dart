// Browsing the book library (story 8, scenario 2): authors, their books, series
// membership and edition and file state, with details and artwork.
//
// A book's editions are not in its record: `edition` gives them. `book?authorId`
// does not name the author of a book either.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../allow_list.dart';
import 'support.dart';

Future<Map<int, Author>> _list(Harness harness) async => {
  for (final item in await ok(harness.library.list()))
    item.ref.remoteId: item as Author,
};

Future<Map<int, Book>> _books(Harness harness, [int author = 1]) async => {
  for (final item in await ok(harness.library.children(authorRef(author))))
    item.ref.remoteId: item as Book,
};

/// Whether the allow-list lets the artwork loader ask for [instancePath].
bool _permitted(String instancePath) {
  final uri = Uri.parse(instancePath);
  return allowList.permits(
    ServiceRequest(HttpMethod.get, uri.path, query: uri.queryParametersAll),
  );
}

/// The query of the address of the [type] image of [raw].
String _coverQuery(Map<String, Object?> raw, String type) {
  final image = (raw['images']! as List<Object?>)
      .cast<Map<String, Object?>>()
      .singleWhere((image) => image['coverType'] == type);
  return Uri.parse(image['url']! as String).query;
}

void main() {
  test('the library is of authors', () {
    expect(Harness().library.itemKind, MediaKind.author);
  });

  group('authors', () {
    test('every author, keyed to this instance', () async {
      final items = await ok(Harness().library.list());

      expect(items, everyElement(isA<Author>()));
      expect(
        items.map((item) => item.ref),
        unorderedEquals([authorRef(1), authorRef(2)]),
      );
    });

    test('maps the fields of an author', () async {
      final harness = Harness();
      final raw = byId(harness.server.authors, 1);

      final found = (await _list(harness))[1]!;

      expect(found.title, raw['authorName']);
      expect(found.sortTitle, anyOf(raw['sortName'], raw['sortNameLastFirst']));
      expect(found.monitored, isTrue);
      expect(found.metadataProfileId, raw['metadataProfileId']);
      expect(found.qualityProfileId, raw['qualityProfileId']);
      expect(found.tagIds, {1});
      expect(found.path, raw['path']);
      expect(
        found.sizeOnDisk,
        (raw['statistics']! as Map<String, Object?>)['sizeOnDisk'],
      );
      expect(found.addedAt, DateTime.parse(raw['added']! as String));
      expect(found.parent, isNull);
    });

    test('reads the authors and the queue, nothing else', () async {
      final harness = Harness();

      await ok(harness.library.list());

      expect(harness.server.requests.map((request) => request.path).toSet(), {
        'api/v1/author',
        'api/v1/queue',
      });
    });

    // Author 1 wants more books than it has; author 2 wants none.
    test('derives the state from the statistics and the queue', () async {
      final queued = await _list(Harness());
      final idle = await _list(Harness()..server.queue.clear());

      expect(queued[1]!.state, ItemState.downloading);
      expect(idle[1]!.state, ItemState.partial);
      expect(idle[2]!.state, ItemState.unmonitored);
    });

    test('one with every wanted book is downloaded', () async {
      final harness = Harness()..server.queue.clear();
      final raw = byId(harness.server.authors, 1);
      raw['statistics'] = {
        ...raw['statistics']! as Map<String, Object?>,
        'bookCount': 4,
        'bookFileCount': 4,
      };

      expect((await _list(harness))[1]!.state, ItemState.downloaded);
    });

    test('a stored poster is read from the API, keeping its query', () async {
      final harness = Harness();
      final raw = byId(harness.server.authors, 1);

      final found = (await _list(harness))[1]!;

      final poster = found.images.singleWhere(
        (image) => image.type == MediaImageType.poster,
      );
      expect(
        poster.instancePath,
        'api/v1/mediacover/author/1/poster.jpg?${_coverQuery(raw, 'poster')}',
      );
      expect(_permitted(poster.instancePath!), isTrue);
    });
  });

  group('books', () {
    test('of an author, with their series, date and author', () async {
      final harness = Harness()..server.queue.clear();
      final authorName = byId(harness.server.authors, 1)['authorName'];
      final raw = byId(harness.server.books, 8);

      final books = await _books(harness);

      expect(books.keys, unorderedEquals([1, 8, 9, 10, 11, 18, 19, 21, 29]));
      final found = books[8]!;
      expect(found.ref, bookRef(8));
      expect(found.title, raw['title']);
      expect(found.seriesTitle, raw['seriesTitle']);
      expect(found.year, 1907);
      expect(found.monitored, isTrue);
      expect(found.parent, authorRef(1));
      expect(found.parentTitle, authorName);
      expect(found.sizeOnDisk, 201186);
    });

    // The server sends an empty text.
    test('one of no series names none', () async {
      final books = await _books(Harness());

      expect(books[1]!.seriesTitle, isNull);
    });

    test('derive their state from the statistics and the queue', () async {
      final queued = await _books(Harness());
      final idle = await _books(Harness()..server.queue.clear());

      expect(queued[19]!.state, ItemState.downloading);
      expect(idle[19]!.state, ItemState.missing);
      expect(idle[8]!.state, ItemState.downloaded);
      // A file below the cutoff is a file.
      expect(idle[10]!.state, ItemState.downloaded);
      expect(idle[1]!.state, ItemState.missing);
    });

    test('one not monitored and without a file is unmonitored', () async {
      final books = await _books(Harness(), 2);

      expect(books[54]!.monitored, isFalse);
      expect(books[54]!.state, ItemState.unmonitored);
    });

    test('one not released yet is unreleased', () async {
      final harness = Harness()..server.queue.clear();
      byId(harness.server.books, 1)['releaseDate'] = '2999-01-01T00:00:00Z';

      expect((await _books(harness))[1]!.state, ItemState.unreleased);
    });

    test('a cover is read from the API, keeping its query', () async {
      final harness = Harness();
      final raw = byId(harness.server.books, 8);

      final found = (await _books(harness))[8]!;

      final cover = found.images.singleWhere(
        (image) => image.type == MediaImageType.cover,
      );
      expect(
        cover.instancePath,
        'api/v1/mediacover/book/8/cover.jpg?${_coverQuery(raw, 'cover')}',
      );
      expect(_permitted(cover.instancePath!), isTrue);
    });

    // One the server has not downloaded yet has no query.
    test('a cover address without a query is read too', () async {
      final found = (await _books(Harness(), 2))[54]!;

      final cover = found.images.singleWhere(
        (image) => image.type == MediaImageType.cover,
      );
      expect(cover.instancePath, 'api/v1/mediacover/book/54/cover.jpg');
      expect(_permitted(cover.instancePath!), isTrue);
    });

    test('of an author the server does not have are not found', () async {
      expect(
        await failureOf(Harness().library.children(authorRef(99))),
        isA<NotFound>(),
      );
    });
  });

  group('one item', () {
    test('an author', () async {
      final harness = Harness();

      final item = await ok(harness.library.item(authorRef(1)));

      expect(item, isA<Author>());
      expect(item.ref, authorRef(1));
      expect(item.title, byId(harness.server.authors, 1)['authorName']);
    });

    test('a book, with its author', () async {
      final harness = Harness();

      final item = await ok(harness.library.item(bookRef(8)));

      expect(item, isA<Book>());
      expect(item.ref, bookRef(8));
      expect(item.parent, authorRef(1));
      expect(item.parentTitle, byId(harness.server.authors, 1)['authorName']);
      expect(harness.asked, contains(line(HttpMethod.get, 'edition')));
    });

    test('a book, with the state of its editions', () async {
      final harness = Harness();
      final raw = harness.server.editions[8]!;

      final item = await ok(harness.library.item(bookRef(8))) as Book;

      expect(
        harness.server.requests
            .singleWhere((request) => request.path == 'api/v1/edition')
            .query,
        {
          'bookId': ['8'],
        },
      );
      expect(item.editions, hasLength(raw.length));
      expect(
        item.editions.map((edition) => edition.monitored),
        unorderedEquals([for (final edition in raw) edition['monitored']]),
      );
      final printed = raw.firstWhere((edition) => edition['isbn13'] != null);
      final edition = item.editions.singleWhere(
        (edition) => edition.isbn == printed['isbn13'],
      );
      expect(edition.title, printed['title']);
      expect(edition.format, printed['format']);
      expect(edition.pageCount, printed['pageCount']);
      expect(
        edition.releaseDate,
        DateTime.parse(printed['releaseDate']! as String),
      );
      expect(edition.monitored, printed['monitored']);
    });

    // The server sends 0 for a number of pages it does not know.
    test('an edition of unknown length has none', () async {
      final item = await ok(Harness().library.item(bookRef(8))) as Book;

      expect(
        item.editions.singleWhere((edition) => edition.monitored).pageCount,
        isNull,
      );
    });

    test('a book fails without its editions', () async {
      final harness = Harness();
      harness.server.overrides['edition'] = FakeReadarr.body('', status: 500);

      expect(
        await failureOf(harness.library.item(bookRef(8))),
        isA<ServerError>(),
      );
    });

    for (final ref in [authorRef(99), bookRef(99)]) {
      test('a ${ref.kind.name} that is gone leaves the cache', () async {
        final harness = Harness();
        await ok(harness.library.list());
        await harness.cache.put(
          CacheEntry(
            instanceId: instanceId,
            kind: ref.kind,
            remoteId: 99,
            parentRemoteId: ref.kind == MediaKind.book ? 1 : null,
            sortTitle: 'gone',
            state: ItemState.missing,
            monitored: true,
            tagIds: const [],
            rawJson: '{}',
            fetchedAt: DateTime.now().toUtc(),
          ),
        );

        expect(await failureOf(harness.library.item(ref)), isA<NotFound>());
        expect(await harness.cache.entry(ref.kind, 99), isNull);
      });
    }
  });

  group('cache', () {
    test('has nothing before a fetch', () async {
      final harness = Harness();

      expect(await ok(harness.library.cachedList()), isNull);
      expect(await ok(harness.library.cachedItem(authorRef(1))), isNull);
      expect(await ok(harness.library.cachedChildren(authorRef(1))), isNull);
      expect(harness.server.requests, isEmpty);
    });

    test('keeps authors and books for offline use', () async {
      final harness = Harness();
      final authors = await ok(harness.library.list());
      final books = await ok(harness.library.children(authorRef(1)));
      harness.server
        ..requests.clear()
        ..goOffline();

      final cachedAuthors = await ok(harness.library.cachedList());
      final cachedBooks = await ok(
        harness.library.cachedChildren(authorRef(1)),
      );
      final cachedBook = await ok(harness.library.cachedItem(bookRef(8)));

      List<(ItemRef, String, ItemState, String?)> summary(
        List<LibraryItem> items,
      ) => [
        for (final item in items)
          (item.ref, item.title, item.state, item.parentTitle),
      ];
      expect(summary(cachedAuthors!.value), unorderedEquals(summary(authors)));
      expect(summary(cachedBooks!.value), unorderedEquals(summary(books)));
      expect(cachedBook!.value, isA<Book>());
      expect(cachedBook.value.parent, authorRef(1));
      expect(harness.server.requests, isEmpty);
    });

    test('keeps the editions of a book that was opened', () async {
      final harness = Harness();
      final item = await ok(harness.library.item(bookRef(8))) as Book;
      harness.server
        ..requests.clear()
        ..goOffline();

      final cached = await ok(harness.library.cachedItem(bookRef(8)));

      expect(
        (cached!.value as Book).editions.map((edition) => edition.title),
        item.editions.map((edition) => edition.title),
      );
      expect(harness.server.requests, isEmpty);
    });

    test('is left as it was when the queue cannot be read', () async {
      final harness = Harness();
      harness.server.overrides['queue'] = FakeReadarr.body('', status: 500);

      expect(await failureOf(harness.library.list()), isA<ServerError>());
      expect(await ok(harness.library.cachedList()), isNull);
    });
  });

  group('files', () {
    test('of a book', () async {
      final harness = Harness();
      final raw = byId(harness.server.bookFiles, 1);

      final files = await ok(harness.library.files(bookRef(8)));

      expect(harness.asked, [line(HttpMethod.get, 'bookfile')]);
      expect(harness.server.requests.single.query, {
        'bookId': ['8'],
      });
      final file = files.single;
      expect(file.id, 1);
      expect(file.path, raw['path']);
      expect(file.size, raw['size']);
      expect(file.quality?.name, 'EPUB');
      expect(file.audio, isNull);
      expect(file.video, isNull);
    });

    test('of an author', () async {
      final harness = Harness();

      final files = await ok(harness.library.files(authorRef(1)));

      expect(harness.server.requests.single.query, {
        'authorId': ['1'],
      });
      expect(files, hasLength(harness.server.bookFiles.length));
    });

    test('of a book that is gone are not found', () async {
      expect(
        await failureOf(Harness().library.files(bookRef(99))),
        isA<NotFound>(),
      );
    });
  });

  test('there are no credits, and nothing is asked', () async {
    final harness = Harness();

    expect(await ok(harness.library.credits(authorRef(1))), isEmpty);
    expect(harness.server.requests, isEmpty);
  });

  test('a record it cannot understand is malformed', () async {
    final harness = Harness();
    byId(harness.server.authors, 1).remove('id');

    expect(await failureOf(harness.library.list()), isA<MalformedResponse>());
  });
}
