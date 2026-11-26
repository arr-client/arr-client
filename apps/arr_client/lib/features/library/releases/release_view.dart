/// The order and filters of the releases shown.
library;

import 'package:core/core.dart';

import '../../activity/history/server_text.dart';

/// Whether the user confirms before [release] is grabbed: the server would not
/// grab it by itself, or could not match it.
bool needsConfirmation(Release release) =>
    release.rejections.isNotEmpty || !release.downloadAllowed;

/// What releases can be ordered by.
enum ReleaseSort {
  /// As the server ranked them.
  server(ascendingFirst: true),
  score(ascendingFirst: false),
  seeders(ascendingFirst: false),
  size(ascendingFirst: false),

  /// Ascending is newest first.
  age(ascendingFirst: true),
  title(ascendingFirst: true);

  const ReleaseSort({required this.ascendingFirst});

  /// The direction chosen with the field.
  final bool ascendingFirst;
}

/// The names a release can be filtered by, as they are shown.
String? indexerName(Release release) => serverText(release.indexer);

/// The name of the quality, if it has one.
String? qualityName(Release release) => serverText(release.quality?.name);

/// The names of the languages.
List<String> languageNames(Release release) => [
  for (final language in release.languages) ?serverText(language.name),
];

/// How the releases are ordered and which are shown. A set that is empty
/// filters nothing.
final class ReleaseView {
  const ReleaseView({
    this.sort = ReleaseSort.server,
    this.ascending = true,
    this.text = '',
    this.protocols = const {},
    this.indexers = const {},
    this.qualities = const {},
    this.languages = const {},
    this.hideRejected = false,
  });

  final ReleaseSort sort;
  final bool ascending;

  /// Matched against the title and the indexer.
  final String text;

  final Set<DownloadProtocol> protocols;
  final Set<String> indexers;
  final Set<String> qualities;
  final Set<String> languages;

  /// Hides what [needsConfirmation].
  final bool hideRejected;

  /// How many filters, besides the text, are on.
  int get activeFilters => [
    protocols.isNotEmpty,
    indexers.isNotEmpty,
    qualities.isNotEmpty,
    languages.isNotEmpty,
    hideRejected,
  ].where((on) => on).length;

  ReleaseView copyWith({
    ReleaseSort? sort,
    bool? ascending,
    String? text,
    Set<DownloadProtocol>? protocols,
    Set<String>? indexers,
    Set<String>? qualities,
    Set<String>? languages,
    bool? hideRejected,
  }) => ReleaseView(
    sort: sort ?? this.sort,
    ascending: ascending ?? this.ascending,
    text: text ?? this.text,
    protocols: protocols ?? this.protocols,
    indexers: indexers ?? this.indexers,
    qualities: qualities ?? this.qualities,
    languages: languages ?? this.languages,
    hideRejected: hideRejected ?? this.hideRejected,
  );

  /// The same order without any filter.
  ReleaseView withoutFilters() => ReleaseView(sort: sort, ascending: ascending);

  /// What of [releases] is shown, in order. Releases without the value ordered
  /// by come last, and equal ones keep the server's order.
  List<Release> apply(List<Release> releases) {
    final wanted = text.trim().toLowerCase();
    final shown = [
      for (final release in releases)
        if (_matches(release, wanted)) release,
    ];
    if (sort == ReleaseSort.server) return shown;
    final sign = ascending ? 1 : -1;
    // `List.sort` is not stable, so the place as given breaks ties.
    final places = List.generate(shown.length, (place) => place)
      ..sort((a, b) {
        final left = _value(shown[a]);
        final right = _value(shown[b]);
        final order = switch ((left, right)) {
          (null, null) => 0,
          (null, _) => 1,
          (_, null) => -1,
          (final left?, final right?) => sign * Comparable.compare(left, right),
        };
        return order != 0 ? order : a.compareTo(b);
      });
    return [for (final place in places) shown[place]];
  }

  bool _matches(Release release, String wanted) =>
      (wanted.isEmpty ||
          (serverText(release.title) ?? '').toLowerCase().contains(wanted) ||
          (indexerName(release) ?? '').toLowerCase().contains(wanted)) &&
      (protocols.isEmpty || protocols.contains(release.protocol)) &&
      (indexers.isEmpty || indexers.contains(indexerName(release))) &&
      (qualities.isEmpty || qualities.contains(qualityName(release))) &&
      (languages.isEmpty || languageNames(release).any(languages.contains)) &&
      !(hideRejected && needsConfirmation(release));

  Comparable<Object>? _value(Release release) => switch (sort) {
    ReleaseSort.server => null,
    ReleaseSort.score => release.score,
    ReleaseSort.seeders => release.seeders,
    // A size the server does not give is read as 0.
    ReleaseSort.size => release.size > 0 ? release.size : null,
    ReleaseSort.age => release.ageHours,
    ReleaseSort.title => serverText(release.title)?.toLowerCase(),
  };
}
