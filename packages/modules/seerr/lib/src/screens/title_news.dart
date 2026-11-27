/// How the screens that are open learn of what another one did or read.
library;

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'seerr_source.dart';

/// The title last read on its own, with the status of its requests, which a
/// list of titles does not have.
final readTitleProvider = NotifierProvider.autoDispose
    .family<ReadTitle, DiscoveryTitle?, SeerrSource>((_) => ReadTitle());

/// Holds the title of [readTitleProvider].
final class ReadTitle extends Notifier<DiscoveryTitle?> {
  @override
  DiscoveryTitle? build() => null;

  /// Tells whoever lists titles of [title].
  void publish(DiscoveryTitle title) => state = title;
}

/// Counts the changes sent about one title of one instance.
final titleChangesProvider = NotifierProvider.autoDispose
    .family<TitleChanges, int, (SeerrSource, DiscoveryRef)>(
      (_) => TitleChanges(),
    );

/// Holds the count of [titleChangesProvider].
final class TitleChanges extends Notifier<int> {
  @override
  int build() => 0;

  /// Has whoever shows the title read it again.
  void changed() => state++;
}
