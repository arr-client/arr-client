/// Ordering and narrowing a library. Pure, so that it can be tested and kept
/// out of `build`.
library;

import 'package:core/core.dart';

import 'library_entry.dart';

/// What a library can be ordered by. Names are persisted as `LibrarySort.field`.
enum LibrarySortField {
  title,
  added,
  year,
  size;

  /// The field saved as [name]; [title] for one this version does not know.
  static LibrarySortField of(String name) => values.asNameMap()[name] ?? title;

  /// The direction a newly chosen field starts in: names from A, and the
  /// newest and largest first.
  bool get ascendingFirst => this == title;
}

/// [entries] in the order of [sort]. Items without the value come last in both
/// directions; equal values are ordered by title, then as given.
List<LibraryEntry> sortEntries(List<LibraryEntry> entries, LibrarySort sort) {
  final field = LibrarySortField.of(sort.field);
  final sign = sort.ascending ? 1 : -1;
  int values(LibraryEntry a, LibraryEntry b) {
    final Comparable<Object>? left;
    final Comparable<Object>? right;
    switch (field) {
      case LibrarySortField.title:
        return sign * a.sortKey.compareTo(b.sortKey);
      case LibrarySortField.added:
        left = a.item.addedAt?.microsecondsSinceEpoch;
        right = b.item.addedAt?.microsecondsSinceEpoch;
      case LibrarySortField.year:
        left = a.item.year;
        right = b.item.year;
      case LibrarySortField.size:
        left = a.item.sizeOnDisk;
        right = b.item.sizeOnDisk;
    }
    if (left == null || right == null) {
      if (left == right) return 0;
      return left == null ? 1 : -1;
    }
    return sign * Comparable.compare(left, right);
  }

  // `List.sort` is not stable, so the place as given breaks the last ties.
  final order = List<int>.generate(entries.length, (index) => index)
    ..sort((a, b) {
      var result = values(entries[a], entries[b]);
      if (result == 0) {
        result = entries[a].sortKey.compareTo(entries[b].sortKey);
      }
      return result != 0 ? result : a.compareTo(b);
    });
  return [for (final index in order) entries[index]];
}

/// Those of [entries] that [filters] let through, in their order.
///
/// Within one filter any of the chosen values will do; different filters all
/// have to hold. A quality profile or tag belongs to its instance, and one of
/// an instance that is not in [shownInstances] is not applied: it could only
/// hide everything, and its choice is not on screen.
List<LibraryEntry> filterEntries(
  List<LibraryEntry> entries,
  LibraryFilters filters,
  Set<String> shownInstances,
) {
  final text = filters.text.trim().toLowerCase();
  Set<InstanceOptionId> shown(Set<InstanceOptionId> ids) => {
    for (final id in ids)
      if (shownInstances.contains(id.instanceId)) id,
  };
  final profiles = shown(filters.qualityProfiles);
  final tags = shown(filters.tags);
  final states = filters.states;
  final monitored = filters.monitored;
  if (text.isEmpty &&
      states.isEmpty &&
      monitored == null &&
      profiles.isEmpty &&
      tags.isEmpty) {
    return entries;
  }
  bool passes(LibraryEntry entry) {
    final item = entry.item;
    if (text.isNotEmpty && !entry.titleKey.contains(text)) return false;
    if (states.isNotEmpty && !states.contains(item.state)) return false;
    if (monitored != null && item.monitored != monitored) return false;
    if (profiles.isNotEmpty) {
      final profile = item.qualityProfileId;
      if (profile == null ||
          !profiles.contains(InstanceOptionId(entry.instanceId, profile))) {
        return false;
      }
    }
    return tags.isEmpty ||
        item.tagIds.any(
          (tag) => tags.contains(InstanceOptionId(entry.instanceId, tag)),
        );
  }

  return [
    for (final entry in entries)
      if (passes(entry)) entry,
  ];
}
