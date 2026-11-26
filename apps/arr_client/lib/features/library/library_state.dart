import 'package:core/core.dart';

import 'library_entry.dart';
import 'library_source.dart';

/// What the library of one kind shows.
final class LibraryState {
  const LibraryState({
    this.profileId,
    this.view,
    this.sources = const [],
    this.visible = const [],
    this.total = 0,
  });

  /// The profile shown; null while switching.
  final String? profileId;

  /// How the user left this library; null until read.
  final LibraryView? view;

  /// Every instance of the profile that has this library, in their order.
  final List<LibrarySource> sources;

  /// The items to show, filtered and in order.
  final List<LibraryEntry> visible;

  /// How many items the instances in view have, before the filters.
  final int total;

  /// The instance the view is narrowed to; null for all, also when the saved
  /// one is not among [sources].
  String? get scopeId {
    final saved = view?.instanceScope;
    return sources.any((source) => source.id == saved) ? saved : null;
  }

  /// The sources in view.
  List<LibrarySource> get shown {
    final scope = scopeId;
    return scope == null
        ? sources
        : [
            for (final source in sources)
              if (source.id == scope) source,
          ];
  }

  LibrarySource? source(String instanceId) =>
      sources.where((source) => source.id == instanceId).firstOrNull;
}
