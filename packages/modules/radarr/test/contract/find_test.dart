// LookupProvider.find against recorded answers: what one instance has for a
// candidate (spec story 3).

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'library_support.dart';
import 'lookup_support.dart';

AddCandidate _candidate({int? tmdbId = bunnyTmdbId}) => AddCandidate(
  kind: MediaKind.movie,
  title: 'Elsewhere',
  externalIds: ExternalIds(tmdbId: tmdbId),
  sourceByInstance: const {
    'i1': {'title': 'As searched', 'tmdbId': bunnyTmdbId},
    'i2': {'title': 'Elsewhere', 'tmdbId': bunnyTmdbId, 'id': 40},
  },
);

void main() {
  test('asks the instance by TMDB id, even with a record of its own', () async {
    final harness = LookupHarness();

    final found = await succeed(harness.lookup.find(_candidate()));

    expect(harness.radarr.terms, ['tmdb:$bunnyTmdbId']);
    expect(harness.radarr.posted, isEmpty);
    expect(found.externalIds.tmdbId, bunnyTmdbId);
    expect(found.existingRefs, isEmpty);
    // Its own record alone, which `add` posts without looking up again.
    expect(found.sourceByInstance.keys, ['i1']);
    expect(found.sourceByInstance['i1']!['title'], isNot('As searched'));
  });

  test('says where the instance has the movie by now', () async {
    final harness = LookupHarness();
    harness.radarr.held.add(bunnyTmdbId);

    final found = await succeed(harness.lookup.find(_candidate()));

    expect(found.existingRefs.single.kind, MediaKind.movie);
    expect(found.existingRefs.single.instanceId, 'i1');
    expect(
      found.existingRefs.single.remoteId,
      records(fixture('lookup_existing')).single['id'],
    );
  });

  test('is not found if the lookup gives another movie only', () async {
    final harness = LookupHarness();

    expect(
      await failureOf(harness.lookup.find(_candidate(tmdbId: 1))),
      isA<NotFound>(),
    );
  });

  test('is not found without a TMDB id, without asking', () async {
    final harness = LookupHarness();

    expect(
      await failureOf(harness.lookup.find(_candidate(tmdbId: null))),
      isA<NotFound>(),
    );
    expect(harness.radarr.requests, isEmpty);
  });

  test('passes on a failure of the lookup', () async {
    final harness = LookupHarness();
    harness.radarr.down = failedAnswer(const Unreachable());

    expect(
      await failureOf(harness.lookup.find(_candidate())),
      isA<Unreachable>(),
    );
  });
}
