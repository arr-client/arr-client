/// What to change about several items of one instance. It sends nothing: it
/// answers with the change the user has confirmed.
library;

import 'package:core/core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../../src/l10n/generated/app_localizations.dart';
import '../../search/add/add_form.dart';

/// Asks what to change about the items called [titles], names them again for
/// the user to confirm, and returns the change; null if the user did not.
///
/// [options] are those of the instance called [instanceName]; without them only
/// monitoring can be changed.
Future<BulkEdit?> showBulkEditSheet(
  BuildContext context, {
  required String instanceName,
  required List<String> titles,
  required List<ServerOption>? options,
}) => showModalBottomSheet<BulkEdit>(
  context: context,
  isScrollControlled: true,
  // Over the bottom bar too, for the room.
  useRootNavigator: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (context) => _BulkEditSheet(
    instanceName: instanceName,
    titles: titles,
    options: options,
  ),
);

class _BulkEditSheet extends StatefulWidget {
  const _BulkEditSheet({
    required this.instanceName,
    required this.titles,
    required this.options,
  });

  final String instanceName;
  final List<String> titles;
  final List<ServerOption>? options;

  @override
  State<_BulkEditSheet> createState() => _BulkEditSheetState();
}

/// A choice that may be to change nothing.
enum _Monitoring { keep, on, off }

class _BulkEditSheetState extends State<_BulkEditSheet> {
  var _monitoring = _Monitoring.keep;

  /// Zero keeps each item's own.
  var _qualityProfileId = 0;

  /// Null keeps each item's tags.
  TagChange? _tagChange;
  final _tagIds = <int>{};

  bool get _changesTags => switch (_tagChange) {
    null => false,
    TagChange.replace => true,
    TagChange.add || TagChange.remove => _tagIds.isNotEmpty,
  };

  bool get _changesSomething =>
      _monitoring != _Monitoring.keep || _qualityProfileId != 0 || _changesTags;

  Map<int, String> _of(ServerOptionKind kind) => {
    for (final option in widget.options ?? const <ServerOption>[])
      if (option.kind == kind) option.id: option.label,
  };

  Future<void> _confirm() async {
    final strings = AppLocalizations.of(context);
    final count = widget.titles.length;
    final qualities = _of(ServerOptionKind.qualityProfile);
    final tags = _of(ServerOptionKind.tag);
    final names = [for (final id in _tagIds) tags[id] ?? '$id'].join(', ');
    final tagChange = _changesTags ? _tagChange : null;
    final change = BulkEdit(
      monitored: switch (_monitoring) {
        _Monitoring.keep => null,
        _Monitoring.on => true,
        _Monitoring.off => false,
      },
      qualityProfileId: _qualityProfileId == 0 ? null : _qualityProfileId,
      tagIds: tagChange == null ? null : Set.unmodifiable(_tagIds),
      tagChange: tagChange ?? TagChange.add,
    );
    final summary = [
      if (change.monitored case final monitored?)
        monitored ? strings.bulkWillMonitor : strings.bulkWillNotMonitor,
      if (qualities[change.qualityProfileId] case final name?)
        strings.bulkWillUseProfile(name),
      if (tagChange != null)
        switch (tagChange) {
          TagChange.add => strings.bulkWillAddTags(names),
          TagChange.remove => strings.bulkWillRemoveTags(names),
          TagChange.replace when _tagIds.isEmpty => strings.bulkWillClearTags,
          TagChange.replace => strings.bulkWillReplaceTags(names),
        },
    ].join('\n');

    final confirmed = await showConfirmDialog(
      context,
      title: strings.bulkConfirmTitle(count, widget.instanceName),
      target: widget.titles.join('\n'),
      consequence: summary,
      confirmLabel: strings.bulkConfirm(count),
      destructive: false,
    );
    if (confirmed && mounted) Navigator.pop(context, change);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final qualities = _of(ServerOptionKind.qualityProfile);
    final tags = _of(ServerOptionKind.tag);

    Widget choice<T extends Object>({
      required String label,
      required T value,
      required Map<T, String> items,
      required void Function(T value) set,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: AddChoice<T>(
        label: label,
        value: value,
        items: items,
        onChanged: (value) => setState(() => set(value)),
      ),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              strings.bulkTitle(widget.titles.length, widget.instanceName),
              style: theme.textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: 16),
          if (widget.options == null) ...[
            Text(strings.libraryOptionsFailed(widget.instanceName)),
            const SizedBox(height: 16),
          ],
          choice<_Monitoring>(
            label: strings.libraryFilterMonitoring,
            value: _monitoring,
            items: {
              _Monitoring.keep: strings.bulkNoChange,
              _Monitoring.on: strings.bulkMonitor,
              _Monitoring.off: strings.bulkUnmonitor,
            },
            set: (value) => _monitoring = value,
          ),
          if (qualities.isNotEmpty)
            choice<int>(
              label: strings.addQualityProfile,
              value: _qualityProfileId,
              items: {0: strings.bulkNoChange, ...qualities},
              set: (value) => _qualityProfileId = value,
            ),
          if (tags.isNotEmpty) ...[
            choice<int>(
              label: strings.addTags,
              value: switch (_tagChange) {
                null => 0,
                final change => change.index + 1,
              },
              items: {
                0: strings.bulkNoChange,
                TagChange.add.index + 1: strings.bulkAddTags,
                TagChange.remove.index + 1: strings.bulkRemoveTags,
                TagChange.replace.index + 1: strings.bulkReplaceTags,
              },
              set: (value) =>
                  _tagChange = value == 0 ? null : TagChange.values[value - 1],
            ),
            if (_tagChange != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final MapEntry(key: id, value: label) in tags.entries)
                      FilterChip(
                        label: Text(label),
                        selected: _tagIds.contains(id),
                        onSelected: (chosen) => setState(
                          () => chosen ? _tagIds.add(id) : _tagIds.remove(id),
                        ),
                      ),
                  ],
                ),
              ),
          ],
          FilledButton(
            onPressed: _changesSomething ? _confirm : null,
            child: Text(strings.bulkReview),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(UiLocalizations.of(context).cancel),
          ),
        ],
      ),
    );
  }
}
