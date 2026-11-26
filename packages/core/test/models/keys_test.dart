// The keys are built at run time so that equality, not const identity, is
// tested.
// ignore_for_file: prefer_const_constructors
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

ItemRef _ref({
  String instanceId = 'i1',
  MediaKind kind = MediaKind.movie,
  int remoteId = 1,
}) => ItemRef(instanceId: instanceId, kind: kind, remoteId: remoteId);

void main() {
  test('an item is keyed by instance, kind and remote id', () {
    expect({_ref(), _ref()}, hasLength(1));
    expect({
      _ref(),
      _ref(instanceId: 'i2'),
      _ref(kind: MediaKind.series),
      _ref(remoteId: 2),
    }, hasLength(4));
  });

  test('a season is a different target from its series', () {
    expect(MediaTarget(_ref()), MediaTarget(_ref()));
    expect(MediaTarget(_ref(), seasonNumber: 0), isNot(MediaTarget(_ref())));
  });

  test('a request service title is keyed by type and TMDB id', () {
    DiscoveryRef ref(DiscoveryMediaType type) =>
        DiscoveryRef(mediaType: type, tmdbId: 1);

    expect(ref(DiscoveryMediaType.movie), ref(DiscoveryMediaType.movie));
    expect(
      ref(DiscoveryMediaType.movie),
      isNot(ref(DiscoveryMediaType.series)),
    );
  });

  test('subtitle media of different kinds never match', () {
    expect(SubtitleMedia.movie(1), SubtitleMedia.movie(1));
    expect({
      SubtitleMedia.movie(1),
      SubtitleMedia.series(1),
      SubtitleMedia.episode(seriesId: 1, episodeId: 1),
    }, hasLength(3));
  });
}
