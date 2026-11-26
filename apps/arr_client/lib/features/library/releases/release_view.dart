/// The order and filters of the releases shown.
library;

import 'package:core/core.dart';
import 'package:ui/ui.dart';

/// Whether the user confirms before [release] is grabbed: the server would not
/// grab it by itself, or could not match it.
bool needsConfirmation(Release release) =>
    release.rejections.isNotEmpty || !release.downloadAllowed;

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
    return sortReleases(shown, sort, ascending: ascending);
  }

  bool _matches(Release release, String wanted) =>
      (wanted.isEmpty ||
          (serverText(release.title) ?? '').toLowerCase().contains(wanted) ||
          (releaseIndexerName(release) ?? '').toLowerCase().contains(wanted)) &&
      (protocols.isEmpty || protocols.contains(release.protocol)) &&
      (indexers.isEmpty || indexers.contains(releaseIndexerName(release))) &&
      (qualities.isEmpty || qualities.contains(releaseQualityName(release))) &&
      (languages.isEmpty ||
          releaseLanguageNames(release).any(languages.contains)) &&
      !(hideRejected && needsConfirmation(release));
}
