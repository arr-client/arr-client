// A Readarr and a cache to run the module's adapters against. The tests go
// through `ReadarrModule().capability<T>`, so they fix what the module does and
// not how it is divided up.
//
// Readarr is retired upstream. The fixtures in `fixtures/0.4.18.2805` were
// recorded from a throwaway of the last linuxserver.io build, the dev stack's,
// with qBittorrent as its download client, a made-up Torznab indexer and
// made-up EPUB and MOBI files; its metadata source was set to a public mirror,
// as the one it ships with no longer resolves. Those in `fixtures/0.4.21.182`
// are from the dev stack's Bookshelf, the API-compatible fork. All passed
// tool/sanitize_fixture.dart. Before that, links and genres were emptied and
// long lists of books, editions, search results and wanted books were cut down.
// So counts do not add up to the statistics.
//
// The server held two authors. Author 1, monitored and tagged, was added with
// every book monitored: books 8, 18 and 29 have an EPUB file, book 10 a MOBI
// file below the profile's cutoff, the others none. Author 2 was made by adding
// one of its books, book 54, and is not monitored. In the queue are a download
// of book 19, one that is being imported and one that no author matches. Book
// 19 had one grab marked as failed. `search.json` was recorded before either
// author was added, `search_existing.json` after.
//
// Titles, names, paths and the metadata source's ids are placeholders, the same
// one for equal values. The sanitizer takes Bookshelf's version for an address,
// so the tests put it back. What the tests need beyond the recordings they
// change here.
//
// The server answers as the recorded one did: embedded authors and books only
// where asked for (`book/{id}` always names its author), no editions on a book,
// 404 for the books or files of an author or book it does not have, an empty
// list for such a book's editions, and 500 for a book that is written back
// without its editions.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:core/testing/allow_list.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readarr/readarr_module.dart';

import '../allow_list.dart';

const instanceId = 'i1';

/// The version of Readarr the fixtures were recorded from.
const recordedVersion = '0.4.18.2805';

/// The version of Bookshelf the other fixtures were recorded from.
const bookshelfVersion = '0.4.21.182';

Object? _decode(String name, String version) =>
    jsonDecode(File('test/fixtures/$version/$name.json').readAsStringSync());

/// A fresh copy of a recorded list.
List<Map<String, Object?>> records(
  String name, [
  String version = recordedVersion,
]) => (_decode(name, version)! as List<Object?>).cast<Map<String, Object?>>();

/// A fresh copy of a recorded object.
Map<String, Object?> record(String name, [String version = recordedVersion]) =>
    _decode(name, version)! as Map<String, Object?>;

/// A fresh copy of the records of a recorded page.
List<Map<String, Object?>> pageRecords(String name) =>
    (record(name)['records']! as List<Object?>).cast<Map<String, Object?>>();

/// The one of [list] with [id].
Map<String, Object?> byId(List<Map<String, Object?>> list, int id) =>
    list.singleWhere((record) => record['id'] == id);

ItemRef authorRef(int id) =>
    ItemRef(instanceId: instanceId, kind: MediaKind.author, remoteId: id);

ItemRef bookRef(int id) =>
    ItemRef(instanceId: instanceId, kind: MediaKind.book, remoteId: id);

MediaTarget author([int id = 1]) => MediaTarget(authorRef(id));

MediaTarget book([int id = 8]) => MediaTarget(bookRef(id));

/// A target that is not Readarr's.
const movie = MediaTarget(
  ItemRef(instanceId: instanceId, kind: MediaKind.movie, remoteId: 1),
);

/// Author 1 of some other instance, whose id names another author here.
const elsewhere = ItemRef(
  instanceId: 'i2',
  kind: MediaKind.author,
  remoteId: 1,
);

/// The authors (`kind` "author") or books ("book") of search results.
List<Map<String, Object?>> found(
  List<Map<String, Object?>> results,
  String kind,
) => [
  for (final result in results)
    if (result[kind] case final Map<String, Object?> record) record,
];

/// The messages the core's client takes from a refusal.
List<String> _messages(String body) {
  final Object? json;
  try {
    json = jsonDecode(body);
  } on FormatException {
    return const [];
  }
  return [
    if (json is List<Object?>)
      for (final entry in json)
        if (entry case {'errorMessage': final String message}) message,
    if (json case {'message': final String message}) message,
  ];
}

Result<ServiceResponse, HttpError> _answer(
  int status,
  String body, {
  String contentType = 'application/json; charset=utf-8',
  bool write = false,
}) {
  final response = ServiceResponse(
    statusCode: status,
    headers: {
      'content-type': [contentType],
    },
    bytes: Uint8List.fromList(utf8.encode(body)),
  );
  // As the core's client classifies them.
  final failure = switch (status) {
    >= 200 && < 300 when contentType.startsWith('text/html') =>
      const ProxyInterception(),
    >= 200 && < 300 => null,
    400 || 422 => Validation(_messages(body)),
    401 => const AuthFailed(),
    403 => const Forbidden(),
    404 => const NotFound(),
    409 => const Conflict(),
    502 || 504 when write => const OutcomeUnknown(),
    _ => ServerError(statusCode: status),
  };
  return failure == null
      ? Ok(response)
      : Err(HttpError(failure, response: response));
}

/// The recorded answer to each command.
const commandFixtures = {
  'BookSearch': 'manage_command_search_book',
  'AuthorSearch': 'manage_command_search_author',
  'RefreshAuthor': 'manage_command_refresh_author',
  'RefreshBook': 'manage_command_refresh_book',
  'RescanFolders': 'manage_command_rescan',
  'ManualImport': 'activity_command_manualimport',
};

/// Answers reads from the recorded lists, which a test may change, and takes
/// the module's writes without changing them. As with the core's client,
/// nothing is sent twice.
class FakeReadarr implements ServiceHttpClient {
  final authors = records('author');

  /// As `book?authorId` lists them: without their author and editions.
  final books = [...records('book_author_1'), ...records('book_author_2')];

  /// The editions by book; a book not named here has none.
  final editions = {
    8: records('edition_book_8'),
    10: records('edition_book_10'),
  };
  final bookFiles = records('bookfile_author_1');
  final queue = pageRecords('activity_queue');

  /// Newest first.
  final history = pageRecords('activity_history');

  /// What `history/since` has, in the server's order.
  final historySince = records('activity_history_since');
  final blocklist = pageRecords('activity_blocklist');
  final calendar = records('overview_calendar');
  final wantedMissing = pageRecords('overview_wanted_missing');
  final wantedCutoff = pageRecords('overview_wanted_cutoff');
  final qualityProfiles = records('qualityprofile');
  final metadataProfiles = records('metadataprofile');
  final rootFolders = records('rootfolder');
  final tags = records('tag');
  List<Map<String, Object?>> health = records('overview_health');
  List<Map<String, Object?>> diskSpace = records('overview_diskspace');
  List<Map<String, Object?>> manualImport = records('activity_manualimport');
  List<Map<String, Object?>> reprocessed = records(
    'activity_manualimport_reprocess',
  );

  /// What a search for [searchTerm] finds: authors and books, neither of them
  /// in the library.
  List<Map<String, Object?>> search = records('search');
  static const searchTerm = 'frankenstein';

  /// What `author:<id>` and `work:<id>` can find, beside the search.
  List<Map<String, Object?>> searchById = records('search_existing');

  /// What `GET command/{id}` answers.
  Map<String, Object?> command = record('manage_command_status');

  /// The id given to an author or book that is added.
  static const addedId = 99;

  final requests = <ServiceRequest>[];

  /// If set, every request gets this.
  Result<ServiceResponse, HttpError>? always;

  /// If set, every write gets this.
  Result<ServiceResponse, HttpError>? writeAnswer;

  /// Answers for single paths of reads, below `api/v1/`.
  final overrides = <String, Result<ServiceResponse, HttpError>>{};

  /// No answer from the address, from now on.
  void goOffline() => always = const Err(HttpError(Unreachable()));

  /// The requests that were not reads.
  Iterable<ServiceRequest> get writes =>
      requests.where((request) => request.method != HttpMethod.get);

  /// An answer with [body] as it is; [write] if it answers one.
  static Result<ServiceResponse, HttpError> body(
    String body, {
    int status = 200,
    String contentType = 'application/json; charset=utf-8',
    bool write = false,
  }) => _answer(status, body, contentType: contentType, write: write);

  @override
  Future<Result<ServiceResponse, HttpError>> send(
    ServiceRequest request,
  ) async {
    requests.add(request);
    expect(request.path, startsWith('api/v1/'));
    final path = request.path.substring('api/v1/'.length);
    if (request.method != HttpMethod.get) {
      return always ?? writeAnswer ?? _written(request, path);
    }
    return always ?? overrides[path] ?? _read(path, request.query);
  }

  Result<ServiceResponse, HttpError> _written(
    ServiceRequest request,
    String path,
  ) {
    Result<ServiceResponse, HttpError> ok(String body, [int status = 200]) =>
        _answer(status, body, write: true);

    switch ((request.method, path)) {
      case (HttpMethod.post, 'author'):
        final sent = sentBody(request)! as Map<String, Object?>;
        if (_holds(authors, 'foreignAuthorId', sent)) {
          return ok(jsonEncode(records('author_add_exists')), 400);
        }
        return ok(
          jsonEncode({
            ...record('author_add'),
            'foreignAuthorId': sent['foreignAuthorId'],
            'id': addedId,
          }),
          201,
        );
      case (HttpMethod.post, 'book'):
        final sent = sentBody(request)! as Map<String, Object?>;
        // The server has no check of its own: its database refuses.
        if (_holds(books, 'foreignBookId', sent)) {
          return ok(jsonEncode(record('book_add_exists')), 409);
        }
        return ok(
          jsonEncode({
            ...record('book_add'),
            'foreignBookId': sent['foreignBookId'],
            'id': addedId,
          }),
          201,
        );
      case (HttpMethod.post, 'command'):
        final name = (sentBody(request)! as Map<String, Object?>)['name'];
        return ok(jsonEncode(record(commandFixtures[name]!)), 201);
      case (HttpMethod.post, 'release'):
        return ok(jsonEncode(sentBody(request)));
      case (HttpMethod.post, 'manualimport'):
        // Only the files that were sent.
        final paths = {
          for (final file in sentBody(request)! as List<Object?>)
            (file! as Map<String, Object?>)['path'],
        };
        return ok(
          jsonEncode([
            for (final file in reprocessed)
              if (paths.contains(file['path'])) file,
          ]),
          202,
        );
      case (HttpMethod.post, 'bookshelf'):
        return ok(jsonEncode(sentBody(request)), 202);
      case (HttpMethod.put, 'book/monitor' || 'author/editor'):
        return ok('[]', 202);
      case (HttpMethod.delete, 'queue/bulk' || 'blocklist/bulk'):
        return ok('{}');
    }
    final known = switch (request.method) {
      HttpMethod.put => RegExp(r'^(author|book)/\d+$'),
      HttpMethod.delete => RegExp(
        r'^(author|book|bookfile|queue|blocklist)/\d+$',
      ),
      HttpMethod.post => RegExp(r'^(queue/grab|history/failed)/\d+$'),
      _ => null,
    };
    if (known == null || !known.hasMatch(path)) {
      fail('not a write of the module: ${request.method.name} $path');
    }
    if (request.method == HttpMethod.put &&
        path.startsWith('book/') &&
        (sentBody(request)! as Map<String, Object?>)['editions'] == null) {
      return ok(jsonEncode(record('book_put_without_editions')), 500);
    }
    return ok('', request.method == HttpMethod.put ? 202 : 200);
  }

  bool _holds(
    List<Map<String, Object?>> held,
    String field,
    Map<String, Object?> sent,
  ) => held.any((item) => item[field] == sent[field]);

  Result<ServiceResponse, HttpError> _read(
    String path,
    Map<String, List<String>> query,
  ) {
    String? one(String name) => query[name]?.single;
    int? number(String name) => switch (one(name)) {
      final value? => int.parse(value),
      null => null,
    };
    // A list may be repeated or comma separated.
    Set<int>? numbers(String name) =>
        query[name]?.expand((value) => value.split(',')).map(int.parse).toSet();
    // Embedded objects are sent only when asked for.
    List<Map<String, Object?>> asked(Iterable<Map<String, Object?>> list) => [
      for (final record in list)
        {
          for (final MapEntry(:key, :value) in record.entries)
            if (!const {'author', 'book'}.contains(key) ||
                one(key == 'author' ? 'includeAuthor' : 'includeBook') ==
                    'true')
              key: value,
        },
    ];
    bool has(List<Map<String, Object?>> list, int? id) =>
        list.any((item) => item['id'] == id);
    final missing = _json({'message': 'NotFound'}, 404);

    List<Map<String, Object?>> events(List<Map<String, Object?>> all) {
      final types = numbers('eventType');
      return [
        for (final event in all)
          if (types == null || types.contains(eventNumber(event['eventType'])))
            event,
      ];
    }

    switch (path) {
      case 'author':
        return _json(authors);
      case 'book':
        final ids = numbers('bookIds');
        final authorId = number('authorId');
        if (authorId != null && !has(authors, authorId)) return missing;
        return _json([
          for (final book in books)
            if ((authorId == null || book['authorId'] == authorId) &&
                (ids == null || ids.contains(book['id'])))
              book,
        ]);
      case 'edition':
        return _json(editions[number('bookId')] ?? const []);
      case 'bookfile':
        final ids = numbers('bookFileIds');
        final bookId = number('bookId');
        final authorId = number('authorId');
        if (bookId != null && !has(books, bookId)) return missing;
        if (authorId != null && !has(authors, authorId)) return missing;
        return _json([
          for (final file in bookFiles)
            if ((bookId == null || file['bookId'] == bookId) &&
                (authorId == null || file['authorId'] == authorId) &&
                (ids == null || ids.contains(file['id'])))
              file,
        ]);
      case 'search':
        return _search(one('term')!);
      case 'queue':
        return _page(
          asked(
            queue.where(
              (item) =>
                  one('includeUnknownAuthorItems') == 'true' ||
                  item['authorId'] != null,
            ),
          ),
          query,
        );
      case 'queue/details':
        final ids = numbers('bookIds');
        final authorId = number('authorId');
        return _json(
          asked(
            queue.where(
              (item) =>
                  (authorId == null || item['authorId'] == authorId) &&
                  (ids == null || ids.contains(item['bookId'])),
            ),
          ),
        );
      case 'history':
        final bookId = number('bookId');
        final matches = asked(
          events(history).where((e) => bookId == null || e['bookId'] == bookId),
        );
        return _page(
          one('sortDirection') == 'ascending'
              ? matches.reversed.toList()
              : matches,
          query,
        );
      case 'history/since':
        final since = DateTime.parse(one('date')!);
        return _json(
          asked(
            events(historySince).where(
              (e) => !DateTime.parse(e['date']! as String).isBefore(since),
            ),
          ),
        );
      case 'history/author':
        final authorId = number('authorId');
        final bookId = number('bookId');
        if (!has(authors, authorId)) return missing;
        return _json(
          asked(
            history.where(
              (e) =>
                  e['authorId'] == authorId &&
                  (bookId == null || e['bookId'] == bookId),
            ),
          ),
        );
      case 'blocklist':
        return _page(blocklist, query);
      case 'calendar':
        return _json(
          asked(
            calendar.where(
              (b) => one('unmonitored') == 'true' || b['monitored'] == true,
            ),
          ),
        );
      case 'wanted/missing':
        return _page(asked(wantedMissing), query);
      case 'wanted/cutoff':
        return _page(asked(wantedCutoff), query);
      case 'release':
        return _json(
          records(
            query.containsKey('bookId')
                ? 'manage_releases_book'
                : 'manage_releases',
          ),
        );
      case 'manualimport':
        return _json(manualImport);
      case 'qualitydefinition':
        return _json(records('qualitydefinition'));
      case 'qualityprofile':
        return _json(qualityProfiles);
      case 'metadataprofile':
        return _json(metadataProfiles);
      case 'rootfolder':
        return _json(rootFolders);
      case 'tag':
        return _json(tags);
      case 'health':
        return _json(health);
      case 'diskspace':
        return _json(diskSpace);
      case 'system/status':
        return _json(record('system_status'));
    }
    if (path == 'command/${command['id']}') return _json(command);
    if (RegExp(r'^(author|book)/(\d+)$').firstMatch(path) case final match?) {
      final isAuthor = match[1] == 'author';
      final held = isAuthor ? authors : books;
      final matches = held.where((item) => item['id'] == int.parse(match[2]!));
      if (matches.isEmpty) return missing;
      final item = matches.single;
      return _json(
        isAuthor
            ? item
            : {...item, 'author': byId(authors, item['authorId']! as int)},
      );
    }
    return missing;
  }

  /// A search gives authors and books. `author:<id>` and `work:<id>` name one,
  /// whose entry is given.
  Result<ServiceResponse, HttpError> _search(String term) {
    if (term == searchTerm) return _json(search);
    return _json(
      [
        // First what was recorded after the library had it.
        for (final result in [...searchById, ...search])
          if (result case {'author': {'foreignAuthorId': final Object? id}}
              when term == 'author:$id')
            result
          else if (result case {'book': {'foreignBookId': final Object? id}}
              when term == 'work:$id')
            result,
      ].take(1).toList(),
    );
  }

  Result<ServiceResponse, HttpError> _json(Object? json, [int status = 200]) =>
      _answer(status, jsonEncode(json));

  Result<ServiceResponse, HttpError> _page(
    List<Map<String, Object?>> all,
    Map<String, List<String>> query,
  ) {
    final page = int.parse(query['page']?.single ?? '1');
    final pageSize = int.parse(query['pageSize']?.single ?? '10');
    return _json({
      'page': page,
      'pageSize': pageSize,
      'totalRecords': all.length,
      'records': all.sublist(
        min((page - 1) * pageSize, all.length),
        min(page * pageSize, all.length),
      ),
    });
  }
}

/// The number Readarr's `EntityHistoryEventType` gives the word of a record.
/// It has no number 2.
int eventNumber(Object? word) => const {
  'unknown': 0,
  'grabbed': 1,
  'bookFileImported': 3,
  'downloadFailed': 4,
  'bookFileDeleted': 5,
  'bookFileRenamed': 6,
  'bookImportIncomplete': 7,
  'downloadImported': 8,
  'bookFileRetagged': 9,
  'downloadIgnored': 10,
}[word]!;

/// Behaves as the core's cache of one instance does.
class FakeCache implements CacheScope {
  final _entries = <(MediaKind, int), CacheEntry>{};
  final _fetches = <(MediaKind, int?), DateTime>{};

  static const _children = {MediaKind.author: MediaKind.book};

  @override
  Future<CacheSnapshot?> read(MediaKind kind, {int? parentRemoteId}) async {
    final fetchedAt = _fetches[(kind, parentRemoteId)];
    if (fetchedAt == null) return null;
    final entries =
        [
          for (final entry in _entries.values)
            if (entry.kind == kind &&
                (parentRemoteId == null ||
                    entry.parentRemoteId == parentRemoteId))
              entry,
        ]..sort((a, b) {
          final byTitle = a.sortTitle.compareTo(b.sortTitle);
          return byTitle != 0 ? byTitle : a.remoteId.compareTo(b.remoteId);
        });
    return CacheSnapshot(entries: entries, fetchedAt: fetchedAt);
  }

  @override
  Future<CacheEntry?> entry(MediaKind kind, int remoteId) async =>
      _entries[(kind, remoteId)];

  @override
  Future<void> replace(
    MediaKind kind,
    List<CacheEntry> entries, {
    int? parentRemoteId,
  }) async {
    for (final entry in entries) {
      _check(entry);
      expect(entry.kind, kind);
      if (parentRemoteId != null) {
        expect(entry.parentRemoteId, parentRemoteId);
      }
    }
    final kept = {for (final entry in entries) entry.remoteId};
    final gone = [
      for (final entry in _entries.values)
        if (entry.kind == kind &&
            (parentRemoteId == null ||
                entry.parentRemoteId == parentRemoteId) &&
            !kept.contains(entry.remoteId))
          entry.remoteId,
    ];
    for (final id in gone) {
      _drop(kind, id);
    }
    for (final entry in entries) {
      _entries[(kind, entry.remoteId)] = entry;
    }
    final now = DateTime.now().toUtc();
    if (parentRemoteId == null) {
      _fetches.removeWhere((key, _) => key.$1 == kind);
    }
    _fetches[(kind, parentRemoteId)] = now;
  }

  @override
  Future<void> put(CacheEntry entry) async {
    _check(entry);
    _entries[(entry.kind, entry.remoteId)] = entry;
  }

  @override
  Future<void> remove(MediaKind kind, int remoteId) async {
    _drop(kind, remoteId);
    _removals.add(
      ItemRef(instanceId: instanceId, kind: kind, remoteId: remoteId),
    );
  }

  void _drop(MediaKind kind, int remoteId) {
    _entries.remove((kind, remoteId));
    final child = _children[kind];
    if (child == null) return;
    _fetches.remove((child, remoteId));
    final under = [
      for (final entry in _entries.values)
        if (entry.kind == child && entry.parentRemoteId == remoteId)
          entry.remoteId,
    ];
    for (final id in under) {
      _drop(child, id);
    }
  }

  final _removals = StreamController<ItemRef>.broadcast();

  @override
  Stream<ItemRef> get removals => _removals.stream;

  Cached<List<ServerOption>>? _options;

  @override
  Future<Cached<List<ServerOption>>?> readOptions() async => _options;

  @override
  Future<void> replaceOptions(List<ServerOption> options) async =>
      _options = Cached(options, fetchedAt: DateTime.now().toUtc());

  void _check(CacheEntry entry) => expect(entry.instanceId, instanceId);
}

class _FakeArtwork extends Fake implements ArtworkLoader {}

class _FakeNavigator extends Fake implements AppNavigator {}

class _FakeLogger implements Logger {
  @override
  void log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {}
}

/// The Readarr module's capabilities against [server], through the allow-list.
/// Create inside a test or `setUp`.
class Harness {
  Harness() {
    context = InstanceContext(
      instance: Instance(
        id: instanceId,
        profileId: 'p1',
        name: 'Home',
        serviceType: 'readarr',
        url: Uri.parse('http://server.test/readarr'),
        authKind: AuthKind.apiKey,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
      http: AllowListClient(allowList, server),
      artwork: _FakeArtwork(),
      navigator: _FakeNavigator(),
      cache: cache,
      logger: _FakeLogger(),
    );
  }

  final server = FakeReadarr();
  final cache = FakeCache();

  /// What the module is given for the instance.
  late final InstanceContext context;

  LibraryProvider get library => _capability<LibraryProvider>();

  HistoryProvider get history => _capability<HistoryProvider>();

  LookupProvider get lookup => _capability<LookupProvider>();

  QueueProvider get queue => _capability<QueueProvider>();

  CalendarProvider get calendar => _capability<CalendarProvider>();

  WantedProvider get wanted => _capability<WantedProvider>();

  HealthProvider get health => _capability<HealthProvider>();

  CommandProvider get commands => _capability<CommandProvider>();

  ReleaseProvider get releases => _capability<ReleaseProvider>();

  /// The requests, each as its method and path.
  List<String> get asked => [
    for (final request in server.requests)
      '${request.method.name} ${request.path}',
  ];

  T _capability<T extends Capability>() {
    final found = ReadarrModule().capability<T>(context);
    expect(found, isNotNull, reason: 'Readarr provides $T');
    return found!;
  }
}

/// How a request appears in [Harness.asked].
String line(HttpMethod method, String path) => '${method.name} api/v1/$path';

/// The body of [request] as the server would receive it.
Object? sentBody(ServiceRequest request) =>
    jsonDecode(jsonEncode((request.body! as JsonBody).value));

/// The value of a result that must have succeeded.
Future<T> ok<T>(ServiceResult<T> result) async => switch (await result) {
  Ok(:final value) => value,
  Err(:final error) => fail('failed with ${error.runtimeType}'),
};

/// The failure of a result that must not have succeeded.
Future<ServiceFailure> failureOf<T>(ServiceResult<T> result) async =>
    switch (await result) {
      Ok() => fail('succeeded'),
      Err(:final error) => error,
    };

/// Asserts that [call] is a programming error. Nothing may have been sent,
/// which the caller checks.
Future<void> expectProgrammingError(Future<Object?> Function() call) =>
    expectLater(Future.sync(call), throwsArgumentError);

/// The failures a write can meet.
final writeFailures = <String, (Result<ServiceResponse, HttpError>, Type)>{
  'an unreachable server': (const Err(HttpError(Unreachable())), Unreachable),
  'a rejected key': (FakeReadarr.body('', status: 401), AuthFailed),
  'a refusal': (FakeReadarr.body('', status: 403), Forbidden),
  'a server error': (
    FakeReadarr.body('{"message":"Example"}', status: 500),
    ServerError,
  ),
  'an unknown outcome': (
    const Err(HttpError(OutcomeUnknown())),
    OutcomeUnknown,
  ),
};
