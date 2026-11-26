/// Removing and grabbing: confirmation, sending and saying how it went. Neither
/// is ever sent a second time.
library;

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../../src/l10n/generated/app_localizations.dart';
import 'queue_controller.dart';
import 'queue_labels.dart';
import 'remove_choices.dart';
import 'waiting_release.dart';

/// An entry of an instance's queue.
typedef QueueKey = ({String instanceId, int id});

/// Asks how to remove [selected] and, once confirmed, removes them.
///
/// Returns once every instance has answered, whatever it said: each answer is
/// shown. [onSent] is called as soon as the user has confirmed.
///
/// [context] must outlive the entries' rows, as they can go at any time.
Future<void> removeQueueEntries(
  BuildContext context,
  WidgetRef ref,
  Set<QueueKey> selected, {
  VoidCallback? onSent,
}) async {
  final strings = AppLocalizations.of(context);
  final controller = ref.read(queueProvider.notifier);
  final state = ref.read(queueProvider);
  // What is confirmed: the entries as they are now.
  final batches = [
    for (final queue in state.queues)
      if ([
            for (final item in queue.items ?? const <QueueItem>[])
              if (selected.contains((
                instanceId: queue.instance.instance.id,
                id: item.id,
              )))
                item,
          ]
          case final items when items.isNotEmpty)
        (queue: queue, items: items),
  ];
  if (batches.isEmpty) return;

  final entries = [for (final batch in batches) ...batch.items];
  // The entries that go too, though not selected.
  var sharingDownload = 0;
  var sharingRelease = 0;
  for (final batch in batches) {
    final selectedIds = {for (final item in batch.items) item.id};
    final downloads = <int>{};
    final releases = <int>{};
    for (final item in batch.items) {
      (isWaitingRelease(item) ? releases : downloads).addAll([
        for (final other in batch.queue.goingWith(item)) other.id,
      ]);
    }
    sharingDownload += downloads.difference(selectedIds).length;
    sharingRelease += releases.difference(selectedIds).length;
  }
  final named = state.queues.length > 1;
  final titles = [
    for (final batch in batches)
      for (final item in batch.items)
        named
            ? strings.queueTitleOnInstance(
                queueTitle(strings, item),
                batch.queue.instance.instance.name,
              )
            : queueTitle(strings, item),
  ];
  final hasDownload = !entries.every(isWaitingRelease);
  var options = const RemoveOptions(
    removeFromClient: true,
    blocklist: false,
    searchReplacement: true,
  );

  // Several titles would push the choices out of sight, so they follow them.
  final several = titles.length > 1;
  final choices = RemoveChoices(
    initial: options,
    onChanged: (value) => options = value,
    hasDownload: hasDownload,
    hasWaiting: entries.any(isWaitingRelease),
  );

  final confirmed = await showConfirmDialog(
    context,
    title: strings.queueRemoveTitle(entries.length),
    target: several ? strings.queueRemoveListed(titles.length) : titles.single,
    consequence: [
      hasDownload
          ? strings.queueRemoveConsequence(entries.length)
          : strings.queueRemoveWaitingConsequence(entries.length),
      if (sharingDownload > 0) strings.queueRemoveShared(sharingDownload),
      if (sharingRelease > 0) strings.queueRemoveSharedRelease(sharingRelease),
    ].join('\n\n'),
    confirmLabel: strings.queueRemoveConfirm(entries.length),
    options: several
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              choices,
              const SizedBox(height: 16),
              Text(titles.join('\n')),
            ],
          )
        : choices,
  );
  if (!confirmed || !context.mounted) return;
  onSent?.call();

  final sent = RemoveOptions(
    removeFromClient: hasDownload && options.removeFromClient,
    blocklist: options.blocklist,
    searchReplacement:
        hasDownload && options.blocklist && options.searchReplacement,
  );
  final messenger = ScaffoldMessenger.of(context);
  final actions = <Future<void>>[];
  for (final batch in batches) {
    final instance = batch.queue.instance;
    final id = instance.instance.id;
    final name = instance.instance.name;
    final now = ref.read(queueProvider).queue(id);
    // Gone while the dialog was open. A server refuses a removal that names an
    // entry it no longer has.
    final present = [
      for (final item in batch.items)
        if (now?.item(item.id) != null) item,
    ];
    if (!instance.isCurrent || present.isEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            instance.isCurrent
                ? strings.queueAlreadyGone(name)
                : strings.queueServiceChanged(name),
          ),
        ),
      );
      continue;
    }
    // One entry names a waiting release: the server drops all of its entries
    // with it, and fails on the next one it is then asked for.
    final namedReleases = <Object>{};
    final ids = [
      for (final item in present)
        if (!isWaitingRelease(item) || namedReleases.add(queueGroup(item)))
          item.id,
    ];
    final affected = {
      for (final item in present)
        for (final queue in [batch.queue, ?now])
          for (final other in queue.goingWith(item)) other.id,
    };
    actions.add(
      runAction<void>(
        context,
        action: () =>
            controller.remove(instance, ids, sent, affected: affected),
        acceptedMessage: strings.queueRemoveAccepted(name),
        describeFailure: (message) => strings.queueFailureOn(name, message),
        onRefresh: () => controller.refresh(id),
        onGone: () => controller.refresh(id),
      ),
    );
  }
  await Future.wait(actions);
}

/// Grabs a delayed entry at once.
Future<void> grabQueueEntry(
  BuildContext context,
  WidgetRef ref,
  InstanceQueue queue,
  QueueItem item,
) async {
  final strings = AppLocalizations.of(context);
  final controller = ref.read(queueProvider.notifier);
  final id = queue.instance.instance.id;
  final name = queue.instance.instance.name;
  await runAction<void>(
    context,
    action: () => controller.grabNow(
      queue.instance,
      item.id,
      affected: {for (final other in queue.goingWith(item)) other.id},
    ),
    acceptedMessage: strings.queueGrabAccepted(name),
    describeFailure: (message) => strings.queueFailureOn(name, message),
    onRefresh: () => controller.refresh(id),
    onGone: () => controller.refresh(id),
  );
}
