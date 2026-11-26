/// The order of a list of releases.
library;

import 'package:core/core.dart';

import '../format/server_text.dart';
import 'release_text.dart';

/// What releases can be ordered by.
enum ReleaseSort {
  /// As the server ranked them.
  server(ascendingFirst: true),

  /// The custom format score.
  score(ascendingFirst: false),

  /// Torrent seeders.
  seeders(ascendingFirst: false),

  /// Bytes.
  size(ascendingFirst: false),

  /// Ascending is newest first.
  age(ascendingFirst: true),

  /// The title.
  title(ascendingFirst: true),

  /// The indexer's name.
  indexer(ascendingFirst: true);

  const ReleaseSort({required this.ascendingFirst});

  /// The direction chosen with the field.
  final bool ascendingFirst;
}

/// [releases] ordered by [sort]. Releases without the value ordered by come
/// last, and equal ones keep the order they had.
List<Release> sortReleases(
  List<Release> releases,
  ReleaseSort sort, {
  required bool ascending,
}) {
  if (sort == ReleaseSort.server) return releases;
  Comparable<Object>? value(Release release) => switch (sort) {
    ReleaseSort.server => null,
    ReleaseSort.score => release.score,
    ReleaseSort.seeders => release.seeders,
    // A size the server does not give is read as 0.
    ReleaseSort.size => release.size > 0 ? release.size : null,
    ReleaseSort.age => release.ageHours,
    ReleaseSort.title => serverText(release.title)?.toLowerCase(),
    ReleaseSort.indexer => releaseIndexerName(release)?.toLowerCase(),
  };
  final sign = ascending ? 1 : -1;
  // `List.sort` is not stable, so the place as given breaks ties.
  final places = List.generate(releases.length, (place) => place)
    ..sort((a, b) {
      final order = switch ((value(releases[a]), value(releases[b]))) {
        (null, null) => 0,
        (null, _) => 1,
        (_, null) => -1,
        (final left?, final right?) => sign * Comparable.compare(left, right),
      };
      return order != 0 ? order : a.compareTo(b);
    });
  return [for (final place in places) releases[place]];
}
