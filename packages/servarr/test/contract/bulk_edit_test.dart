// Changing several items at once through the editor, `PUT movie/editor` and
// `series/editor` (research R13; story 5, scenario 7). Only what changes is
// sent, so the server keeps the rest of each item. Radarr 7.0.3 answers with
// 200 and Sonarr 4.0.20 with 202, both with the items.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servarr/servarr.dart';

import 'manage_support.dart';
import 'support.dart';

String _path(Service service) =>
    service == radarr ? 'movie/editor' : 'series/editor';

String _idsField(Service service) =>
    service == radarr ? 'movieIds' : 'seriesIds';

Reply _accepted(Service service) => Reply(service == radarr ? 200 : 202, '[]');

ServiceResult<void> _edit(
  Service service,
  ServarrClient client,
  BulkEdit changes, {
  List<int> ids = const [1, 2],
}) => client.bulkEdit(
  _path(service),
  idsField: _idsField(service),
  ids: ids,
  changes: changes,
);

/// Each change the user can make, and what it sends beside the ids.
final _changes = <String, (BulkEdit, Map<String, Object?>)>{
  'monitoring on': (const BulkEdit(monitored: true), {'monitored': true}),
  'monitoring off': (const BulkEdit(monitored: false), {'monitored': false}),
  'the quality profile': (
    const BulkEdit(qualityProfileId: 4),
    {'qualityProfileId': 4},
  ),
  'added tags': (
    const BulkEdit(tagIds: {2}),
    {
      'tags': [2],
      'applyTags': 'add',
    },
  ),
  'removed tags': (
    const BulkEdit(tagIds: {2}, tagChange: TagChange.remove),
    {
      'tags': [2],
      'applyTags': 'remove',
    },
  ),
  'replaced tags': (
    const BulkEdit(tagIds: {1}, tagChange: TagChange.replace),
    {
      'tags': [1],
      'applyTags': 'replace',
    },
  ),
  // As recorded: it takes every tag off.
  'tags replaced by none': (
    const BulkEdit(tagIds: {}, tagChange: TagChange.replace),
    {'tags': <int>[], 'applyTags': 'replace'},
  ),
  'several fields': (
    const BulkEdit(monitored: true, qualityProfileId: 4, tagIds: {2}),
    {
      'monitored': true,
      'qualityProfileId': 4,
      'tags': [2],
      'applyTags': 'add',
    },
  ),
  // `tagChange` says nothing without tags.
  'monitoring with a tag change and no tags': (
    const BulkEdit(monitored: true, tagChange: TagChange.replace),
    {'monitored': true},
  ),
  'monitoring with no tag to add': (
    const BulkEdit(monitored: true, tagIds: {}),
    {'monitored': true},
  ),
};

/// Changes that change nothing.
const _empty = {
  'no change': BulkEdit(),
  'no tag to add': BulkEdit(tagIds: {}),
  'no tag to remove': BulkEdit(tagIds: {}, tagChange: TagChange.remove),
  'a tag change without tags': BulkEdit(tagChange: TagChange.replace),
};

void main() {
  for (final service in services) {
    group('${service.name} bulk edit', () {
      for (final MapEntry(key: name, value: (changes, sent))
          in _changes.entries) {
        test('sends $name and nothing else', () async {
          final server = routes({'PUT ${_path(service)}': _accepted(service)});

          await value(_edit(service, service.client(server), changes));

          // The items are not read: the editor changes only what it is given.
          final request = server.requests.single;
          expect(request.method, HttpMethod.put);
          expect(request.path, 'api/v3/${_path(service)}');
          expect(request.query, isEmpty);
          expect(sentBody(request), {
            _idsField(service): [1, 2],
            ...sent,
          });
        });
      }

      test('sends one item through the editor too', () async {
        final server = routes({'PUT ${_path(service)}': _accepted(service)});

        await value(
          _edit(
            service,
            service.client(server),
            const BulkEdit(monitored: false),
            ids: [7],
          ),
        );

        expect(sentBody(server.requests.single), {
          _idsField(service): [7],
          'monitored': false,
        });
      });

      test('sends nothing for no items', () async {
        final server = routes({'PUT ${_path(service)}': _accepted(service)});

        await value(
          _edit(
            service,
            service.client(server),
            const BulkEdit(monitored: false),
            ids: [],
          ),
        );

        expect(server.requests, isEmpty);
      });

      for (final MapEntry(key: name, value: changes) in _empty.entries) {
        test('sends nothing for $name', () async {
          final server = routes({'PUT ${_path(service)}': _accepted(service)});

          await value(_edit(service, service.client(server), changes));

          expect(server.requests, isEmpty);
        });
      }

      final failures = <String, (Answer, Type)>{
        ...writeFailures,
        // As recorded; no item of the request was changed.
        'an item that is gone': (
          refusal(500, 'Expected query to return 2 rows but returned 1'),
          ServerError,
        ),
        // As recorded.
        'a quality profile that does not exist': (
          Reply.json([
            {
              'propertyName': 'QualityProfileId',
              'errorMessage': 'Quality Profile does not exist',
            },
          ], status: 400),
          Validation,
        ),
      };
      for (final MapEntry(key: cause, value: (answer, expected))
          in failures.entries) {
        test('reports $cause and is sent once', () async {
          final server = FakeServer.always(answer);

          final result = await failure(
            _edit(
              service,
              service.client(server),
              const BulkEdit(qualityProfileId: 999),
            ),
          );

          expect(result.runtimeType, expected);
          expect(server.requests, hasLength(1));
        });
      }
    });
  }
}
