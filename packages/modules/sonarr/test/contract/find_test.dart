// LookupProvider.find against recorded answers: what one instance has for a
// candidate (spec story 3).

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _notHeld = 79257;

AddCandidate _candidate({int? tvdbId = _notHeld}) => AddCandidate(
  kind: MediaKind.series,
  title: 'Elsewhere',
  externalIds: ExternalIds(tvdbId: tvdbId),
  sourceByInstance: const {
    instanceId: {'title': 'As searched', 'tvdbId': _notHeld},
    'i2': {'title': 'Elsewhere', 'tvdbId': _notHeld, 'id': 9},
  },
);

void main() {
  test('asks the instance by TVDB id, even with a record of its own', () async {
    final harness = Harness();

    final found = await ok(harness.lookup.find(_candidate()));

    final request = harness.server.requests.single;
    expect(request.path, 'api/v3/series/lookup');
    expect(request.query, {
      'term': ['tvdb:$_notHeld'],
    });
    expect(found.externalIds.tvdbId, _notHeld);
    expect(found.existingRefs, isEmpty);
    expect(found.sourceByInstance.keys, [instanceId]);
    expect(
      found.sourceByInstance[instanceId]!['title'],
      harness.server.tvdbLookup.single['title'],
    );
    expect(harness.server.writes, isEmpty);
  });

  test('says where the instance has the series by now', () async {
    final harness = Harness();
    harness.server.tvdbLookup.single['id'] = 9;

    final found = await ok(harness.lookup.find(_candidate()));

    expect(found.existingRefs.single, seriesRef(9));
  });

  test('is not found if the lookup gives nothing', () async {
    final harness = Harness();
    harness.server.overrides['series/lookup'] = FakeSonarr.body('[]');

    expect(await failureOf(harness.lookup.find(_candidate())), isA<NotFound>());
  });

  test('is not found without a TVDB id, without asking', () async {
    final harness = Harness();

    expect(
      await failureOf(harness.lookup.find(_candidate(tvdbId: null))),
      isA<NotFound>(),
    );
    expect(harness.server.requests, isEmpty);
  });

  test('passes on a failure of the lookup', () async {
    final harness = Harness();
    harness.server.overrides['series/lookup'] = FakeSonarr.body(
      '{}',
      status: 500,
    );

    expect(
      await failureOf(harness.lookup.find(_candidate())),
      isA<ServerError>(),
    );
  });
}
