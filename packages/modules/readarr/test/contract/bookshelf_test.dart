// The same reads against what Bookshelf answered (spec, Supported Services:
// best effort). Its version 1 API is Readarr's; what differs is where its
// metadata comes from and how it reports that source failing.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

List<Map<String, Object?>> _recorded(String name) =>
    records(name, bookshelfVersion);

/// A harness whose server holds what Bookshelf listed.
Harness _bookshelf() {
  final harness = Harness();
  harness.server
    ..authors.clear()
    ..authors.addAll(_recorded('author'))
    ..books.clear()
    ..books.addAll(_recorded('book_author_1'))
    ..editions.clear()
    ..editions[8] = _recorded('edition_book_8')
    ..search = _recorded('search')
    ..queue.clear();
  return harness;
}

void main() {
  test('lists its authors and their books', () async {
    final harness = _bookshelf();

    final authors = await ok(harness.library.list());
    final books = await ok(harness.library.children(authorRef(1)));

    expect(authors, everyElement(isA<Author>()));
    expect(authors, hasLength(_recorded('author').length));
    expect(
      books.map((item) => item.ref.remoteId),
      unorderedEquals([for (final r in _recorded('book_author_1')) r['id']]),
    );
    expect(books.map((item) => item.title), everyElement(isNotEmpty));
  });

  test('shows a book with its editions', () async {
    final item = await ok(_bookshelf().library.item(bookRef(8))) as Book;

    expect(item.editions, hasLength(_recorded('edition_book_8').length));
    expect(item.parent, authorRef(1));
  });

  test('searches it', () async {
    final harness = _bookshelf();

    final candidates = await ok(harness.lookup.lookup(FakeReadarr.searchTerm));

    expect(
      candidates.map((candidate) => candidate.title),
      unorderedEquals([
        for (final author in found(_recorded('search'), 'author'))
          author['authorName'],
        for (final book in found(_recorded('search'), 'book')) book['title'],
      ]),
    );
  });

  // Bookshelf says when its metadata source fails; Readarr's search does not,
  // and only finds nothing.
  test('reports a metadata source that fails', () async {
    final harness = Harness();
    harness.server.overrides['search'] = FakeReadarr.body(
      '{"message":"Example"}',
      status: 503,
    );

    expect(
      await failureOf(harness.lookup.lookup('dracula')),
      isA<ServerError>(),
    );
    expect(record('search_metadata_down', bookshelfVersion), isNotEmpty);
  });

  test('finds nothing where Readarr has no metadata source', () async {
    final harness = Harness();
    harness.server.overrides['search'] = FakeReadarr.body('[]');
    expect(records('search_metadata_down'), isEmpty);

    expect(await ok(harness.lookup.lookup('dracula')), isEmpty);
  });
}
