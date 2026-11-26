/// How results of several sources are put together (spec story 3, scenarios 1
/// and 6).
library;

import 'package:arr_client/features/search/search_hit.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

SearchHit found(
  String instance, {
  MediaKind kind = MediaKind.movie,
  String title = 'Alien',
  int? tmdb,
  int? tvdb,
  String? musicBrainz,
  String? foreign,
  String? overview,
  int? heldAs,
  List<MediaImage> images = const [],
}) => SearchHit.fromLookup(
  instance,
  AddCandidate(
    kind: kind,
    title: title,
    externalIds: ExternalIds(
      tmdbId: tmdb,
      tvdbId: tvdb,
      musicBrainzId: musicBrainz,
      foreignId: foreign,
    ),
    overview: overview,
    images: images,
    existingRefs: [
      if (heldAs != null)
        ItemRef(instanceId: instance, kind: kind, remoteId: heldAs),
    ],
    sourceByInstance: {
      instance: {'from': instance},
    },
  ),
);

SearchHit requested({
  DiscoveryMediaType type = DiscoveryMediaType.movie,
  int tmdb = 1,
  int? tvdb,
}) => SearchHit.fromDiscovery(
  'seerr',
  DiscoveryTitle(
    tmdbId: tmdb,
    tvdbId: tvdb,
    mediaType: type,
    title: 'Alien',
    availability: Availability.unknown,
    availability4k: Availability.unknown,
  ),
);

void main() {
  test('one title of two instances is one hit with both records', () {
    const poster = MediaImage(
      type: MediaImageType.poster,
      instancePath: 'api/v3/mediacover/3/poster.jpg',
    );

    final hits = mergeHits(
      [found('a', tmdb: 1)],
      [
        found(
          'b',
          tmdb: 1,
          title: 'Alien, again',
          heldAs: 3,
          overview: 'In space.',
          images: [poster],
        ),
      ],
    );

    final hit = hits.single;
    expect(hit.title, 'Alien');
    expect(hit.overview, 'In space.');
    expect(hit.candidate.sourceByInstance.keys, unorderedEquals(['a', 'b']));
    expect(hit.existingRefs.map((ref) => ref.instanceId), ['b']);
    // A path among the images is under the address of the instance it is from.
    expect(hit.images, [poster]);
    expect(hit.artworkInstanceId, 'b');
  });

  test('without a shared identifier results stay apart', () {
    expect(mergeHits([], [found('a'), found('b')]), hasLength(2));
    expect(
      mergeHits([], [found('a', tmdb: 1), found('b', tmdb: 2)]),
      hasLength(2),
    );
    // The same number in another namespace.
    expect(
      mergeHits([], [
        found('a', tmdb: 1),
        found('b', kind: MediaKind.series, tmdb: 1),
      ]),
      hasLength(2),
    );
    // Servers may take their book ids from different sources.
    expect(
      mergeHits([], [
        found('a', kind: MediaKind.book, foreign: '12'),
        found('b', kind: MediaKind.book, foreign: '12'),
      ]),
      hasLength(2),
    );
  });

  test('series match by TVDB id, and by TMDB id only without two of it', () {
    SearchHit series(String instance, {int? tvdb, int? tmdb}) =>
        found(instance, kind: MediaKind.series, tvdb: tvdb, tmdb: tmdb);

    expect(
      mergeHits([], [series('a', tvdb: 7), series('b', tvdb: 7, tmdb: 1)]),
      hasLength(1),
    );
    expect(
      mergeHits([], [
        series('a', tvdb: 7, tmdb: 1),
        series('b', tvdb: 8, tmdb: 1),
      ]),
      hasLength(2),
    );
    expect(
      mergeHits(
        [series('a', tvdb: 7, tmdb: 1)],
        [requested(type: DiscoveryMediaType.series)],
      ),
      hasLength(1),
    );
  });

  test('a request service title merges by identifier', () {
    final hits = mergeHits([found('a', tmdb: 1)], [requested()]);

    expect(hits.single.canAdd, isTrue);
    expect(hits.single.discovered.keys, ['seerr']);
    expect(requested().canAdd, isFalse);
  });

  test('music matches by MusicBrainz id', () {
    SearchHit artist(String instance) =>
        found(instance, kind: MediaKind.artist, musicBrainz: 'abc');

    expect(mergeHits([], [artist('a'), artist('b')]), hasLength(1));
  });

  test('what is shown keeps its place; the new follows', () {
    final shown = [found('a', title: 'One', tmdb: 1), found('a', tmdb: 2)];

    final hits = mergeHits(shown, [
      found('b', title: 'Three', tmdb: 3),
      found('b', tmdb: 2),
      found('b', title: 'Uno', tmdb: 1),
    ]);

    expect(hits.map((hit) => hit.externalIds.tmdbId), [1, 2, 3]);
    expect(hits.first.title, 'One');
  });
}
