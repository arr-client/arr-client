import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../src/l10n/generated/app_localizations.dart';
import 'library_controller.dart';
import 'library_source.dart';
import 'library_state.dart';
import 'state_appearance.dart';

/// Opens the filters of the library of [kind]. Each choice applies at once.
Future<void> showLibraryFilters(BuildContext context, MediaKind kind) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      // Over the bottom bar too, for the room.
      useRootNavigator: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => _FilterSheet(kind),
    );

/// How many filters, besides the text, narrow what is shown.
int activeFilterCount(LibraryState state) {
  final filters = state.view?.filters;
  if (filters == null) return 0;
  final shown = {for (final source in state.shown) source.id};
  bool applies(InstanceOptionId id) => shown.contains(id.instanceId);
  return [
    filters.states.isNotEmpty,
    filters.monitored != null,
    filters.qualityProfiles.any(applies),
    filters.tags.any(applies),
  ].where((on) => on).length;
}

class _FilterSheet extends ConsumerWidget {
  const _FilterSheet(this.kind);

  final MediaKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(libraryProvider(kind));
    final view = state.view;
    // The profile is being switched under the sheet.
    if (view == null) return const SizedBox.shrink();
    final controller = ref.read(libraryProvider(kind).notifier);
    final filters = view.filters;
    final strings = AppLocalizations.of(context);
    final theme = Theme.of(context);

    void apply({
      Set<ItemState>? states,
      bool? Function()? monitored,
      Set<InstanceOptionId>? qualityProfiles,
      Set<InstanceOptionId>? tags,
    }) => controller.setFilters(
      LibraryFilters(
        text: filters.text,
        states: states ?? filters.states,
        monitored: monitored == null ? filters.monitored : monitored(),
        qualityProfiles: qualityProfiles ?? filters.qualityProfiles,
        tags: tags ?? filters.tags,
      ),
    );

    Set<T> toggled<T>(Set<T> set, T value, bool on) =>
        on ? {...set, value} : set.difference({value});

    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Semantics(
        header: true,
        child: Text(text, style: theme.textTheme.titleSmall),
      ),
    );

    /// The chips of one kind of server option, by instance where several are
    /// shown. A chosen id whose name is not known can still be taken off.
    List<Widget> options({
      required String title,
      required ServerOptionKind optionKind,
      required Set<InstanceOptionId> chosen,
      required String Function(String id) unknown,
      required ValueChanged<Set<InstanceOptionId>> onChanged,
    }) {
      List<(InstanceOptionId, String)> choices(LibrarySource source) {
        final known = [
          for (final option in source.options ?? const <ServerOption>[])
            if (option.kind == optionKind)
              (InstanceOptionId(source.id, option.id), option.label),
        ];
        final ids = {for (final (id, _) in known) id};
        return [
          ...known,
          for (final id in chosen)
            if (id.instanceId == source.id && !ids.contains(id))
              (id, unknown('${id.optionId}')),
        ];
      }

      final groups = [
        for (final source in state.shown)
          if (choices(source) case final found when found.isNotEmpty)
            (source, found),
      ];
      if (groups.isEmpty) return const [];
      return [
        heading(title),
        for (final (source, found) in groups) ...[
          if (state.shown.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(source.name, style: theme.textTheme.labelMedium),
            ),
          Wrap(
            spacing: 8,
            children: [
              for (final (id, label) in found)
                FilterChip(
                  label: Text(label),
                  selected: chosen.contains(id),
                  onSelected: (on) => onChanged(toggled(chosen, id, on)),
                ),
            ],
          ),
        ],
      ];
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final margin = screenMargin(constraints.maxWidth);
        return SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              margin,
              0,
              margin,
              16 + MediaQuery.viewPaddingOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    strings.libraryFilters,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                heading(strings.libraryFilterState),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final itemState in ItemState.values)
                      // Only what holds several files can have some of them.
                      if (itemState != ItemState.partial ||
                          kind != MediaKind.movie ||
                          filters.states.contains(itemState))
                        FilterChip(
                          label: Text(itemState.label(strings)),
                          selected: filters.states.contains(itemState),
                          onSelected: (on) => apply(
                            states: toggled(filters.states, itemState, on),
                          ),
                        ),
                  ],
                ),
                heading(strings.libraryFilterMonitoring),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final (value, label) in [
                      (null, strings.libraryFilterAnyMonitoring),
                      (true, strings.libraryFilterMonitored),
                      (false, strings.libraryFilterUnmonitored),
                    ])
                      ChoiceChip(
                        label: Text(label),
                        selected: filters.monitored == value,
                        onSelected: (_) => apply(monitored: () => value),
                      ),
                  ],
                ),
                ...options(
                  title: strings.libraryFilterQuality,
                  optionKind: ServerOptionKind.qualityProfile,
                  chosen: filters.qualityProfiles,
                  unknown: strings.libraryFilterUnknownProfile,
                  onChanged: (ids) => apply(qualityProfiles: ids),
                ),
                ...options(
                  title: strings.libraryFilterTags,
                  optionKind: ServerOptionKind.tag,
                  chosen: filters.tags,
                  unknown: strings.libraryFilterUnknownTag,
                  onChanged: (ids) => apply(tags: ids),
                ),
                for (final source in state.shown)
                  if (source.optionsFailed && source.options == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(strings.libraryOptionsFailed(source.name)),
                    ),
                const SizedBox(height: 24),
                OverflowBar(
                  alignment: MainAxisAlignment.end,
                  spacing: 8,
                  overflowAlignment: OverflowBarAlignment.end,
                  children: [
                    TextButton(
                      onPressed: filters == const LibraryFilters()
                          ? null
                          : controller.clearFilters,
                      child: Text(strings.libraryClearFilters),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        strings.libraryShowResults(state.visible.length),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
