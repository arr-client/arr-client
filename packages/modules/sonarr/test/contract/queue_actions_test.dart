// Removing queue entries and grabbing a delayed one. Reading the queue is in
// queue_test.dart; manual import is in manual_import_test.dart.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'activity_support.dart';
import 'support.dart';

const _entry = 1245736911;
const _other = 1013386014;

// Each choice, and the flags that say it.
const _removals = [
  (
    'from the client only',
    RemoveOptions(removeFromClient: true, blocklist: false),
    {
      'removeFromClient': ['true'],
      'blocklist': ['false'],
    },
  ),
  (
    'from the queue only, whatever the replacement choice says',
    RemoveOptions(
      removeFromClient: false,
      blocklist: false,
      searchReplacement: true,
    ),
    {
      'removeFromClient': ['false'],
      'blocklist': ['false'],
    },
  ),
  (
    'blocking, with a replacement search',
    RemoveOptions(
      removeFromClient: true,
      blocklist: true,
      searchReplacement: true,
    ),
    {
      'removeFromClient': ['true'],
      'blocklist': ['true'],
      'skipRedownload': ['false'],
    },
  ),
  (
    'blocking, without a replacement search',
    RemoveOptions(removeFromClient: false, blocklist: true),
    {
      'removeFromClient': ['false'],
      'blocklist': ['true'],
      'skipRedownload': ['true'],
    },
  ),
];

void main() {
  for (final (name, options, query) in _removals) {
    test('removes an entry $name', () async {
      final harness = ActivityHarness();

      await ok(harness.queue.remove(_entry, options));

      final request = harness.activity.requests.single;
      expect(request.method, HttpMethod.delete);
      expect(request.path, 'api/v3/queue/$_entry');
      expect(request.query, query);
      expect(request.body, isNull);
    });

    test('removes several entries $name', () async {
      final harness = ActivityHarness();

      await ok(harness.queue.removeMany([_entry, _other], options));

      final request = harness.activity.requests.single;
      expect(request.method, HttpMethod.delete);
      expect(request.path, 'api/v3/queue/bulk');
      expect(request.query, query);
      expect(sentBody(request), {
        'ids': [_entry, _other],
      });
    });
  }

  test('removing nothing asks nothing', () async {
    final harness = ActivityHarness();

    await ok(
      harness.queue.removeMany(
        const [],
        const RemoveOptions(removeFromClient: true, blocklist: false),
      ),
    );

    expect(harness.activity.requests, isEmpty);
  });

  test('grabs a delayed entry at once', () async {
    final harness = ActivityHarness();

    await ok(harness.queue.grabNow(_entry));

    final request = harness.activity.requests.single;
    expect(request.method, HttpMethod.post);
    expect(request.path, 'api/v3/queue/grab/$_entry');
    expect(request.query, isEmpty);
    expect(request.body, isNull);
  });

  final writes = <String, ServiceResult<void> Function(QueueProvider)>{
    'remove': (queue) => queue.remove(
      _entry,
      const RemoveOptions(removeFromClient: true, blocklist: false),
    ),
    'removeMany': (queue) => queue.removeMany([
      _entry,
    ], const RemoveOptions(removeFromClient: true, blocklist: false)),
    'grabNow': (queue) => queue.grabNow(_entry),
  };
  final answers = <String, (Result<ServiceResponse, HttpError>, Matcher)>{
    'an entry that is gone': (
      FakeSonarr.body('{"message": "NotFound"}', status: 404, write: true),
      isA<NotFound>(),
    ),
    'an unknown outcome': (
      FakeSonarr.body('', status: 504, write: true),
      isA<OutcomeUnknown>(),
    ),
  };
  for (final MapEntry(key: name, value: write) in writes.entries) {
    for (final MapEntry(key: cause, value: (answer, expected))
        in answers.entries) {
      test('$name reports $cause and is sent once', () async {
        final harness = ActivityHarness()..activity.writeAnswer = answer;

        expect(await failureOf(write(harness.queue)), expected);
        expect(harness.activity.requests, hasLength(1));
      });
    }
  }
}
