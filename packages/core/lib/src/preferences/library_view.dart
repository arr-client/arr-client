import 'instance_option_id.dart';
import 'library_filters.dart';
import 'library_layout.dart';
import 'library_sort.dart';

/// How the user left one library of one profile.
final class LibraryView {
  /// Creates a [LibraryView].
  const LibraryView({
    this.layout = LibraryLayout.grid,
    this.sort = const LibrarySort(),
    this.filters = const LibraryFilters(),
    this.instanceScope,
  });

  /// Grid or list.
  final LibraryLayout layout;

  /// The order.
  final LibrarySort sort;

  /// What is hidden.
  final LibraryFilters filters;

  /// The one instance shown, or null for all.
  final String? instanceScope;

  /// This view with every instance id replaced by what [replace] returns for
  /// it. Where it returns null, the scope becomes all instances and the filter
  /// ids of that instance are dropped.
  LibraryView mapInstances(String? Function(String instanceId) replace) {
    Set<InstanceOptionId> mapped(Set<InstanceOptionId> ids) => {
      for (final id in ids)
        if (replace(id.instanceId) case final instanceId?)
          InstanceOptionId(instanceId, id.optionId),
    };

    final scope = instanceScope;
    return LibraryView(
      layout: layout,
      sort: sort,
      filters: LibraryFilters(
        text: filters.text,
        states: filters.states,
        monitored: filters.monitored,
        qualityProfiles: mapped(filters.qualityProfiles),
        tags: mapped(filters.tags),
      ),
      instanceScope: scope == null ? null : replace(scope),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LibraryView &&
      other.layout == layout &&
      other.sort == sort &&
      other.filters == filters &&
      other.instanceScope == instanceScope;

  @override
  int get hashCode => Object.hash(layout, sort, filters, instanceScope);
}
