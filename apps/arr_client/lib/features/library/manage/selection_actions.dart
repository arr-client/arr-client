/// What can be done to the items selected in the library, all of one instance.
library;

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../../app/providers.dart';
import '../../../src/l10n/generated/app_localizations.dart';
import '../library_source.dart';
import 'bulk_edit_sheet.dart';
import 'manage_calls.dart';
import 'manage_widgets.dart';
import 'search_tasks.dart';

/// Asks what to change about [items] of [source] and, once confirmed, changes
/// them in one request, sent once.
///
/// [onSending] is called when it is sent and then [onSent] with whether the
/// server accepted it. A failure is shown with the titles it concerns.
Future<void> editSelection(
  BuildContext context,
  WidgetRef ref,
  LibrarySource source,
  List<LibraryItem> items, {
  required VoidCallback onSending,
  required void Function(bool accepted) onSent,
}) async {
  final instance = source.active;
  final library = instance.capability(CapabilityKind.library);
  // One instance's only, whatever the caller selected.
  final own = [
    for (final item in items)
      if (item.ref.instanceId == instance.instance.id) item,
  ];
  if (library == null || own.isEmpty) return;
  final name = instance.instance.name;
  final titles = [for (final item in own) itemName(item)];
  // Taken before the waits, after which the screen may be gone.
  final strings = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  final container = ProviderScope.containerOf(context);
  final services = ref.read(appServicesProvider);

  final changes = await showBulkEditSheet(
    context,
    instanceName: name,
    titles: titles,
    options: source.options,
  );
  if (changes == null) return;
  if (!instance.isCurrent) {
    if (messenger.mounted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(strings.titleProblem(name, strings.bulkNotSent)),
        ),
      );
    }
    return;
  }
  onSending();
  final result = await sendOnce(
    services,
    instance,
    () => library.bulkEdit([for (final item in own) item.ref], changes),
  );
  reloadLibrary(container, library.itemKind, instance.instance.id);
  onSent(result is Ok);

  switch (result) {
    case Ok():
      if (!messenger.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(strings.bulkAccepted(name, own.length))),
      );
    case Err(:final error):
      if (!navigator.mounted) return;
      await showDialog<void>(
        context: navigator.context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text(
            error is OutcomeUnknown
                ? strings.bulkUnknownTitle(own.length)
                : strings.bulkFailedTitle(own.length),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The server answers for all of them at once.
              Problem(
                strings.titleProblem(name, failureMessage(context, error)),
              ),
              const SizedBox(height: 16),
              Text(titles.join('\n')),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(MaterialLocalizations.of(context).closeButtonLabel),
            ),
          ],
        ),
      );
  }
}

/// Names [items] of [instance] and, once confirmed, has it search for them.
/// Calls [onStarted] when the searches have been asked for; the library shows
/// their progress.
Future<void> searchSelection(
  BuildContext context,
  WidgetRef ref,
  ActiveInstance instance,
  List<LibraryItem> items, {
  required VoidCallback onStarted,
}) async {
  final commands = instance.capability(CapabilityKind.command);
  final own = [
    for (final item in items)
      if (item.ref.instanceId == instance.instance.id &&
          (commands?.supports(CommandAction.search, MediaTarget(item.ref)) ??
              false))
        item,
  ];
  if (commands == null || own.isEmpty) return;
  final strings = AppLocalizations.of(context);
  final tasks = ref.read(searchTasksProvider.notifier);
  final confirmed = await showConfirmDialog(
    context,
    title: strings.bulkSearchConfirmTitle(own.length),
    target: [for (final item in own) itemName(item)].join('\n'),
    consequence: strings.bulkSearchConsequence(instance.instance.name),
    confirmLabel: strings.bulkSearchConfirm(own.length),
    destructive: false,
  );
  if (!confirmed) return;
  onStarted();
  unawaited(
    tasks.start(instance, commands, [
      for (final item in own) (item: item.ref, title: itemName(item)),
    ]),
  );
}
