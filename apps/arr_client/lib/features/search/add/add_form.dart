import 'package:core/core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../../src/l10n/generated/app_localizations.dart';
import 'add_draft.dart';

/// The choices of an add, of those the server offers.
class AddForm extends StatelessWidget {
  const AddForm({
    required this.options,
    required this.draft,
    required this.enabled,
    required this.onChanged,
    super.key,
  });

  final AddOptions options;
  final AddDraft draft;

  /// False while the add is being sent.
  final bool enabled;

  final ValueChanged<AddDraft> onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final folders = optionsOf(options, ServerOptionKind.rootFolder);
    final qualities = optionsOf(options, ServerOptionKind.qualityProfile);
    final metadata = optionsOf(options, ServerOptionKind.metadataProfile);
    final tags = optionsOf(options, ServerOptionKind.tag);

    String folder(ServerOption option) => switch (option.freeSpace) {
      final free? => strings.addFolderFree(
        option.label,
        formatBytes(context, free),
      ),
      null => option.label,
    };

    Widget choice<T extends Object>({
      required String label,
      required T? value,
      required Map<T, String> items,
      required AddDraft Function(T value) set,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: AddChoice<T>(
        label: label,
        value: value,
        items: items,
        onChanged: enabled ? (value) => onChanged(set(value)) : null,
      ),
    );

    Widget toggle(String label, bool value, AddDraft Function(bool) set) =>
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(label),
          value: value,
          onChanged: enabled ? (value) => onChanged(set(value)) : null,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (folders.isNotEmpty)
          choice<int>(
            label: strings.addRootFolder,
            value: draft.rootFolderId,
            items: {for (final option in folders) option.id: folder(option)},
            set: draft.withRootFolder,
          ),
        if (qualities.isNotEmpty)
          choice<int>(
            label: strings.addQualityProfile,
            value: draft.qualityProfileId,
            items: {for (final option in qualities) option.id: option.label},
            set: draft.withQualityProfile,
          ),
        if (metadata.isNotEmpty)
          choice<int>(
            label: strings.addMetadataProfile,
            value: draft.metadataProfileId,
            items: {for (final option in metadata) option.id: option.label},
            set: draft.withMetadataProfile,
          ),
        if (options.monitorOptions.isNotEmpty)
          choice<String>(
            label: strings.addMonitor,
            value: draft.monitorOptionId,
            items: {
              for (final option in options.monitorOptions)
                option.id: option.label(context),
            },
            set: draft.withMonitorOption,
          ),
        if (draft.seriesType case final type?)
          choice<SeriesType>(
            label: strings.addSeriesType,
            value: type,
            items: {
              for (final type in seriesTypeChoices)
                type: switch (type) {
                  SeriesType.daily => strings.addSeriesTypeDaily,
                  SeriesType.anime => strings.addSeriesTypeAnime,
                  SeriesType.standard ||
                  SeriesType.unknown => strings.addSeriesTypeStandard,
                },
            },
            set: draft.withSeriesType,
          ),
        if (draft.minimumAvailability case final availability?)
          choice<MinimumAvailability>(
            label: strings.addMinimumAvailability,
            value: availability,
            items: {
              for (final value in minimumAvailabilityChoices)
                value: switch (value) {
                  MinimumAvailability.announced => strings.addAnnounced,
                  MinimumAvailability.inCinemas => strings.addInCinemas,
                  MinimumAvailability.released ||
                  MinimumAvailability.tba ||
                  MinimumAvailability.unknown => strings.addReleased,
                },
            },
            set: draft.withMinimumAvailability,
          ),
        if (draft.seasonFolder case final seasonFolder?)
          toggle(
            strings.addSeasonFolders,
            seasonFolder,
            draft.withSeasonFolder,
          ),
        toggle(strings.addSearchNow, draft.searchNow, draft.withSearchNow),
        if (tags.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(strings.addTags, style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in tags)
                FilterChip(
                  label: Text(tag.label),
                  selected: draft.tagIds.contains(tag.id),
                  onSelected: enabled
                      ? (chosen) =>
                            onChanged(draft.withTag(tag.id, chosen: chosen))
                      : null,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// One choice of several, under its label. Long names wrap, also at large text
/// sizes.
class AddChoice<T extends Object> extends StatelessWidget {
  const AddChoice({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    super.key,
  });

  final String label;
  final T? value;

  /// The name of each value.
  final Map<T, String> items;

  /// Null while nothing can be changed.
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) => InputDecorator(
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      // The button below is already as tall as a touch target.
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      enabled: onChanged != null,
    ),
    isEmpty: value == null,
    child: DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        value: value,
        isExpanded: true,
        isDense: false,
        itemHeight: null,
        items: [
          for (final MapEntry(key: item, value: name) in items.entries)
            DropdownMenuItem(
              value: item,
              // Room between names that wrap.
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(name),
              ),
            ),
        ],
        onChanged: switch (onChanged) {
          final changed? => (value) {
            if (value != null) changed(value);
          },
          null => null,
        },
      ),
    ),
  );
}
