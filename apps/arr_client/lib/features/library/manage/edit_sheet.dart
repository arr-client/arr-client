/// Editing one item (spec story 5, scenarios 5 and 8). Only what the user has
/// changed from what the server last said is sent, and the module applies it on
/// top of what the server has then. Nothing is sent twice.
library;

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../../app/providers.dart';
import '../../../src/l10n/generated/app_localizations.dart';
import '../../search/add/add_draft.dart';
import '../../search/add/add_form.dart';
import 'manage_calls.dart';
import 'manage_widgets.dart';

class EditSheet extends ConsumerStatefulWidget {
  const EditSheet({
    required this.instance,
    required this.library,
    required this.item,
    super.key,
  });

  final ActiveInstance instance;
  final LibraryProvider library;
  final ItemRef item;

  @override
  ConsumerState<EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends ConsumerState<EditSheet> {
  /// The item and the server's options, as last read.
  LibraryItem? _item;
  List<ServerOption>? _options;
  ServiceFailure? _readFailure;
  var _reading = false;

  // What the user has chosen; null where untouched.
  bool? _monitored;
  int? _qualityProfileId;
  int? _metadataProfileId;
  Set<int>? _tagIds;
  SeriesType? _seriesType;
  bool? _seasonFolder;
  MinimumAvailability? _minimumAvailability;
  String? _monitorOptionId;

  var _sending = false;
  ServiceFailure? _saveFailure;
  var _monitorOptionAccepted = false;

  @override
  void initState() {
    super.initState();
    unawaited(_read());
  }

  Future<void> _read() async {
    setState(() {
      _reading = true;
      _readFailure = null;
    });
    final services = ref.read(appServicesProvider);
    final (item, options) = await (
      readOf(services, () => widget.library.item(widget.item)),
      readOf(services, widget.library.options),
    ).wait;
    if (!mounted) return;
    setState(() {
      _reading = false;
      switch ((item, options)) {
        case (Ok(value: final item), Ok(value: final options)):
          _item = item;
          _options = options;
        case (Err(:final error), _) || (_, Err(:final error)):
          _readFailure = error;
      }
    });
  }

  /// What differs from the item as last read.
  ItemEdit _changes(LibraryItem item) {
    T? changed<T>(T? chosen, T? current) => chosen == current ? null : chosen;
    final tags = _tagIds;
    return ItemEdit(
      monitored: changed(_monitored, item.monitored),
      qualityProfileId: changed(_qualityProfileId, item.qualityProfileId),
      metadataProfileId: changed(_metadataProfileId, _metadataOf(item)),
      tagIds: tags == null || setEquals(tags, item.tagIds) ? null : tags,
      seriesType: item is Series ? changed(_seriesType, item.seriesType) : null,
      seasonFolder: item is Series
          ? changed(_seasonFolder, item.seasonFolder)
          : null,
      minimumAvailability: item is Movie
          ? changed(_minimumAvailability, item.minimumAvailability)
          : null,
    );
  }

  static int? _metadataOf(LibraryItem item) => switch (item) {
    Artist(:final metadataProfileId) ||
    Author(:final metadataProfileId) => metadataProfileId,
    _ => null,
  };

  static bool _isEmpty(ItemEdit edit) =>
      edit.monitored == null &&
      edit.qualityProfileId == null &&
      edit.metadataProfileId == null &&
      edit.tagIds == null &&
      edit.seriesType == null &&
      edit.seasonFolder == null &&
      edit.minimumAvailability == null;

  /// Sends one change and, where the server may have taken it, has the library
  /// read again.
  Future<Result<void, ServiceFailure>> _send(
    ServiceResult<void> Function() change,
  ) async {
    setState(() {
      _sending = true;
      _saveFailure = null;
      _monitorOptionAccepted = false;
    });
    final container = ProviderScope.containerOf(context);
    final result = await sendOnce(
      ref.read(appServicesProvider),
      widget.instance,
      change,
    );
    if (result case Ok() || Err(error: NotFound() || OutcomeUnknown())) {
      reloadLibrary(container, widget.item.kind, widget.item.instanceId);
    }
    if (mounted) {
      setState(() {
        _sending = false;
        if (result case Err(:final error)) _saveFailure = error;
      });
    }
    return result;
  }

  Future<void> _save(LibraryItem item) async {
    if (_sending) return;
    final changes = _changes(item);
    // Taken before the wait, after which the sheet may be gone.
    final strings = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final route = ModalRoute.of(context);
    final name = widget.instance.instance.name;
    final title = itemName(item);

    final result = await _send(() => widget.library.edit(widget.item, changes));
    // The sheet says how it failed while it is there.
    if (mounted) {
      switch (result) {
        case Ok():
          if (route?.isCurrent ?? false) navigator.pop();
        case Err(error: OutcomeUnknown()):
          // Shows what the server now has.
          await _read();
          return;
        case Err():
          return;
      }
    }
    if (!messenger.mounted) return;
    messenger.showSnackBar(switch (result) {
      Ok() => SnackBar(content: Text(strings.editAccepted(name, title))),
      Err(:final error) => SnackBar(
        content: Text(
          strings.itemChangeFailed(
            title,
            name,
            itemFailure(messenger.context, error),
          ),
        ),
        persist: true,
        showCloseIcon: true,
      ),
    });
  }

  Future<void> _applyMonitorOption(String optionId) async {
    if (_sending) return;
    final result = await _send(
      () => widget.library.applyMonitorOption(widget.item, optionId),
    );
    if (!mounted) return;
    if (result is Ok) {
      setState(() {
        _monitorOptionAccepted = true;
        _monitorOptionId = null;
      });
    }
    // It may have changed what is monitored.
    if (result case Ok() || Err(error: OutcomeUnknown())) await _read();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final item = _item;
    final readFailure = _readFailure;
    final saveFailure = _saveFailure;
    final gone = readFailure is NotFound || saveFailure is NotFound;
    // Nothing is changed on the strength of what may be out of date.
    final enabled = !_sending && !_reading && readFailure == null;

    return PopScope(
      // The sheet stays with what it is sending.
      canPop: !_sending,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        item == null
                            ? strings.editItem
                            : strings.editTitle(itemName(item)),
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: MaterialLocalizations.of(context)
                        .closeButtonTooltip,
                    onPressed: _sending ? null : () => Navigator.pop(context),
                  ),
                ],
              ),
              Text(strings.itemOnService(widget.instance.instance.name)),
              const SizedBox(height: 16),
              if (saveFailure != null && !gone) ...[
                Problem(itemFailure(context, saveFailure)),
                const SizedBox(height: 16),
              ],
              if (gone)
                Problem(UiLocalizations.of(context).itemGone)
              else ...[
                if (readFailure != null) ...[
                  Problem(itemFailure(context, readFailure)),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () => unawaited(_read()),
                    child: Text(UiLocalizations.of(context).retry),
                  ),
                  const SizedBox(height: 16),
                ],
                if (_reading) const Waiting(),
                if (item != null) ...[
                  ..._fields(context, item, enabled: enabled),
                  const SizedBox(height: 16),
                  if (_sending) ...[
                    LinearProgressIndicator(semanticsLabel: strings.formSaving),
                    const SizedBox(height: 8),
                  ],
                  FilledButton(
                    onPressed: enabled && !_isEmpty(_changes(item))
                        ? () => unawaited(_save(item))
                        : null,
                    child: Text(strings.editSave),
                  ),
                  if (widget.library.monitorOptions.isNotEmpty)
                    ..._monitorOptions(context, enabled: enabled),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _fields(
    BuildContext context,
    LibraryItem item, {
    required bool enabled,
  }) {
    final strings = AppLocalizations.of(context);
    final options = _options ?? const <ServerOption>[];
    Map<int, String> of(ServerOptionKind kind) => {
      for (final option in options)
        if (option.kind == kind) option.id: option.label,
    };
    final qualities = of(ServerOptionKind.qualityProfile);
    final metadata = of(ServerOptionKind.metadataProfile);
    final tags = of(ServerOptionKind.tag);
    final chosenTags = _tagIds ?? item.tagIds;
    // The item's own are kept although the server no longer lists them.
    final tagIds = {...tags.keys, ...item.tagIds};

    Widget choice<T extends Object>({
      required String label,
      required T? value,
      required Map<T, String> items,
      required void Function(T value) set,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: AddChoice<T>(
        label: label,
        // A value the server does not offer shows as none chosen.
        value: items.containsKey(value) ? value : null,
        items: items,
        onChanged: enabled ? (value) => setState(() => set(value)) : null,
      ),
    );

    Widget toggle(String label, bool value, void Function(bool) set) =>
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(label),
          value: value,
          onChanged: enabled ? (value) => setState(() => set(value)) : null,
        );

    return [
      toggle(
        strings.editMonitored,
        _monitored ?? item.monitored,
        (value) => _monitored = value,
      ),
      const SizedBox(height: 8),
      if (qualities.isNotEmpty)
        choice<int>(
          label: strings.addQualityProfile,
          value: _qualityProfileId ?? item.qualityProfileId,
          items: qualities,
          set: (value) => _qualityProfileId = value,
        ),
      if (metadata.isNotEmpty && (item is Artist || item is Author))
        choice<int>(
          label: strings.addMetadataProfile,
          value: _metadataProfileId ?? _metadataOf(item),
          items: metadata,
          set: (value) => _metadataProfileId = value,
        ),
      if (item is Series) ...[
        choice<SeriesType>(
          label: strings.addSeriesType,
          value: _seriesType ?? item.seriesType,
          items: {
            for (final type in seriesTypeChoices)
              type: switch (type) {
                SeriesType.daily => strings.addSeriesTypeDaily,
                SeriesType.anime => strings.addSeriesTypeAnime,
                SeriesType.standard ||
                SeriesType.unknown => strings.addSeriesTypeStandard,
              },
          },
          set: (value) => _seriesType = value,
        ),
        toggle(
          strings.addSeasonFolders,
          _seasonFolder ?? item.seasonFolder,
          (value) => _seasonFolder = value,
        ),
        const SizedBox(height: 8),
      ],
      if (item is Movie)
        choice<MinimumAvailability>(
          label: strings.addMinimumAvailability,
          value: _minimumAvailability ?? item.minimumAvailability,
          items: {
            for (final value in [
              // Shown where the movie has it, though no longer offered.
              if (item.minimumAvailability == MinimumAvailability.tba)
                MinimumAvailability.tba,
              ...minimumAvailabilityChoices,
            ])
              value: switch (value) {
                MinimumAvailability.tba => strings.editToBeAnnounced,
                MinimumAvailability.announced => strings.addAnnounced,
                MinimumAvailability.inCinemas => strings.addInCinemas,
                MinimumAvailability.released ||
                MinimumAvailability.unknown => strings.addReleased,
              },
          },
          set: (value) => _minimumAvailability = value,
        ),
      if (tagIds.isNotEmpty) ...[
        Text(strings.addTags, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final id in tagIds)
              FilterChip(
                label: Text(tags[id] ?? strings.libraryFilterUnknownTag('$id')),
                selected: chosenTags.contains(id),
                onSelected: enabled
                    ? (chosen) => setState(
                        () => _tagIds = chosen
                            ? {...chosenTags, id}
                            : chosenTags.difference({id}),
                      )
                    : null,
              ),
          ],
        ),
      ],
    ];
  }

  /// Applying a monitoring option is a change of its own, with its own button.
  List<Widget> _monitorOptions(BuildContext context, {required bool enabled}) {
    final strings = AppLocalizations.of(context);
    final chosen = _monitorOptionId;
    return [
      const Divider(height: 32),
      AddChoice<String>(
        label: strings.editMonitorOption,
        value: chosen,
        items: {
          for (final option in widget.library.monitorOptions)
            option.id: option.label(context),
        },
        onChanged: enabled
            ? (value) => setState(() {
                _monitorOptionId = value;
                _monitorOptionAccepted = false;
              })
            : null,
      ),
      const SizedBox(height: 8),
      OutlinedButton(
        onPressed: enabled && chosen != null
            ? () => unawaited(_applyMonitorOption(chosen))
            : null,
        child: Text(strings.editApplyMonitorOption),
      ),
      if (_monitorOptionAccepted) ...[
        const SizedBox(height: 8),
        Semantics(
          liveRegion: true,
          child: Text(
            strings.editMonitorOptionAccepted(widget.instance.instance.name),
          ),
        ),
      ],
    ];
  }
}
