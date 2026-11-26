import 'package:flutter/foundation.dart';

import '../models/item_state.dart';
import '../models/server_option.dart';
import '../models/server_option_kind.dart';
import 'instance_option_id.dart';

/// What narrows a library down. An empty or null filter lets everything through.
final class LibraryFilters {
  /// Creates a [LibraryFilters].
  const LibraryFilters({
    this.text = '',
    this.states = const {},
    this.monitored,
    this.qualityProfiles = const {},
    this.tags = const {},
  });

  /// What was typed in the filter box.
  final String text;

  /// The states to show.
  final Set<ItemState> states;

  /// Only monitored or only unmonitored items.
  final bool? monitored;

  /// The quality profiles to show.
  final Set<InstanceOptionId> qualityProfiles;

  /// The tags to show.
  final Set<InstanceOptionId> tags;

  /// These filters without the quality profiles and tags that the servers no
  /// longer have.
  ///
  /// [options] holds what each instance offers, by instance id. The ids of an
  /// instance that is not in it, for example an unreachable one, are kept.
  LibraryFilters withoutUnresolved(Map<String, List<ServerOption>> options) {
    Set<InstanceOptionId> resolved(
      Set<InstanceOptionId> ids,
      ServerOptionKind kind,
    ) => {
      for (final id in ids)
        if (options[id.instanceId]?.any(
              (option) => option.kind == kind && option.id == id.optionId,
            ) ??
            true)
          id,
    };

    return LibraryFilters(
      text: text,
      states: states,
      monitored: monitored,
      qualityProfiles: resolved(
        qualityProfiles,
        ServerOptionKind.qualityProfile,
      ),
      tags: resolved(tags, ServerOptionKind.tag),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LibraryFilters &&
      other.text == text &&
      setEquals(other.states, states) &&
      other.monitored == monitored &&
      setEquals(other.qualityProfiles, qualityProfiles) &&
      setEquals(other.tags, tags);

  @override
  int get hashCode => Object.hash(
    text,
    Object.hashAllUnordered(states),
    monitored,
    Object.hashAllUnordered(qualityProfiles),
    Object.hashAllUnordered(tags),
  );
}
