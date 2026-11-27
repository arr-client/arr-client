/// Deleting an item (spec story 5, scenario 6). It destroys data for good: both
/// choices start off, the item is named as the server has it now, and the
/// deletion is sent once, whatever the answer.
library;

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../../app/providers.dart';
import '../../../src/l10n/generated/app_localizations.dart';
import 'manage_calls.dart';
import 'manage_widgets.dart';

class DeleteDialog extends ConsumerStatefulWidget {
  const DeleteDialog({
    required this.instance,
    required this.library,
    required this.item,
    super.key,
  });

  final ActiveInstance instance;
  final LibraryProvider library;
  final ItemRef item;

  @override
  ConsumerState<DeleteDialog> createState() => _DeleteDialogState();
}

class _DeleteDialogState extends ConsumerState<DeleteDialog> {
  /// The item to be deleted, as the server has it; null until read.
  LibraryItem? _item;

  /// Why it could not be read.
  ServiceFailure? _readFailure;

  /// Why the deletion did not succeed. It is not offered again here.
  ServiceFailure? _deleteFailure;

  var _deleteFiles = false;
  var _exclude = false;
  var _sending = false;

  @override
  void initState() {
    super.initState();
    unawaited(_read());
  }

  Future<void> _read() async {
    final result = await readOf(
      ref.read(appServicesProvider),
      () => widget.library.item(widget.item),
    );
    if (!mounted) return;
    setState(() {
      switch (result) {
        case Ok(:final value):
          _item = value;
        case Err(:final error):
          _readFailure = error;
      }
    });
  }

  Future<void> _delete(LibraryItem item) async {
    if (_sending) return;
    setState(() => _sending = true);
    // Taken before the wait, after which the dialog may be gone.
    final strings = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final route = ModalRoute.of(context);
    final container = ProviderScope.containerOf(context);
    final name = widget.instance.instance.name;
    final title = itemName(item);

    final result = await sendOnce(
      ref.read(appServicesProvider),
      widget.instance,
      () => widget.library.delete(
        widget.item,
        deleteFiles: _deleteFiles,
        addImportExclusion: _exclude,
      ),
    );
    if (result case Ok() || Err(error: NotFound() || OutcomeUnknown())) {
      // The library lists what holds an album, not the album.
      reloadLibrary(container, widget.library.itemKind, widget.item.instanceId);
    }

    if (mounted) {
      setState(() {
        _sending = false;
        if (result case Err(:final error)) _deleteFailure = error;
      });
      if (result is Ok && (route?.isCurrent ?? false)) navigator.pop();
    }
    if (!messenger.mounted) return;
    switch (result) {
      case Ok():
        messenger.showSnackBar(
          SnackBar(content: Text(strings.deleteAccepted(name, title))),
        );
      // The dialog says it while it is there.
      case Err(:final error) when !mounted:
        messenger.showSnackBar(
          SnackBar(
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
        );
      case Err():
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final item = _item;
    final kind = widget.item.kind.name;
    final name = widget.instance.instance.name;
    final failure = _deleteFailure ?? _readFailure;

    Widget choice({
      required bool value,
      required String title,
      required String effect,
      required void Function(bool value) set,
    }) => CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      value: value,
      title: Text(title),
      subtitle: Text(effect),
      onChanged: _sending
          ? null
          : (value) => setState(() => set(value ?? false)),
    );

    return PopScope(
      // The dialog stays with what it is sending.
      canPop: !_sending,
      child: AlertDialog(
        scrollable: true,
        title: Text(strings.deleteTitle(kind)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item != null) ...[
              Text(itemName(item), style: theme.textTheme.titleMedium),
              Text(strings.itemOnService(name)),
              if (item.sizeOnDisk > 0)
                Text(
                  strings.deleteSizeOnDisk(
                    formatBytes(context, item.sizeOnDisk),
                  ),
                ),
              const SizedBox(height: 8),
            ],
            if (failure != null)
              Problem(itemFailure(context, failure))
            else if (item == null)
              const Waiting()
            else ...[
              Text(strings.deleteConsequence(kind, name)),
              const SizedBox(height: 8),
              choice(
                value: _deleteFiles,
                title: strings.deleteFiles,
                effect: _deleteFiles
                    ? strings.deleteFilesOn(kind)
                    : strings.deleteFilesOff,
                set: (value) => _deleteFiles = value,
              ),
              choice(
                value: _exclude,
                title: strings.deleteExclude,
                effect: _exclude
                    ? strings.deleteExcludeOn
                    : strings.deleteExcludeOff,
                set: (value) => _exclude = value,
              ),
              if (_sending) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(semanticsLabel: strings.deleteSending),
              ],
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: _sending ? null : () => Navigator.pop(context),
            child: Text(
              _deleteFailure == null
                  ? UiLocalizations.of(context).cancel
                  : MaterialLocalizations.of(context).closeButtonLabel,
            ),
          ),
          if (_readFailure != null && _readFailure is! NotFound)
            FilledButton(
              onPressed: () {
                setState(() => _readFailure = null);
                unawaited(_read());
              },
              child: Text(UiLocalizations.of(context).retry),
            ),
          if (item != null && failure == null)
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
              onPressed: _sending ? null : () => unawaited(_delete(item)),
              child: Text(strings.deleteConfirm(kind)),
            ),
        ],
      ),
    );
  }
}
