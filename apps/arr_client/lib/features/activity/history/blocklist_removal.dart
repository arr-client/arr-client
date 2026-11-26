import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../../src/l10n/generated/app_localizations.dart';
import 'activity_feed.dart';
import 'server_changes.dart';
import 'server_text.dart';

/// An entry of an instance's blocklist.
typedef BlocklistKey = ({String instanceId, int id});

/// Asks whether [selected] should leave the blocklist and, once confirmed,
/// removes them, sending one request to each instance, once.
///
/// Returns once every instance has answered, whatever it said: each answer is
/// shown, and the blocklist is read again. [onSent] is called as soon as the
/// user has confirmed. [context] must outlive the entries' rows.
Future<void> removeBlocklistEntries(
  BuildContext context,
  WidgetRef ref,
  Set<BlocklistKey> selected, {
  VoidCallback? onSent,
}) async {
  final strings = AppLocalizations.of(context);
  final changes = ref.read(serverChangesProvider.notifier);
  final feed = ref.read(blocklistFeedProvider);
  // What is confirmed: the entries as they are now.
  final batches = <ActiveInstance, List<BlocklistEntry>>{};
  for (final (:source, item: entry) in feed.rows) {
    if (selected.contains((instanceId: source.id, id: entry.id))) {
      (batches[source.instance] ??= []).add(entry);
    }
  }
  final count = batches.values.fold(0, (sum, entries) => sum + entries.length);
  if (count == 0) return;

  final several = feed.sources.length > 1;
  final confirmed = await showConfirmDialog(
    context,
    title: strings.blocklistRemoveTitle(count),
    target: [
      for (final MapEntry(key: instance, value: entries) in batches.entries)
        for (final entry in entries)
          switch (serverText(entry.sourceTitle) ?? strings.historyUntitled) {
            final title when several => strings.queueTitleOnInstance(
              title,
              instance.instance.name,
            ),
            final title => title,
          },
    ].join('\n'),
    consequence: strings.blocklistRemoveConsequence(count),
    confirmLabel: strings.blocklistRemoveConfirm(count),
  );
  if (!confirmed || !context.mounted) return;
  onSent?.call();

  final messenger = ScaffoldMessenger.of(context);
  final actions = <Future<void>>[];
  for (final MapEntry(key: instance, value: entries) in batches.entries) {
    final name = instance.instance.name;
    if (!instance.isCurrent) {
      messenger.showSnackBar(
        SnackBar(content: Text(strings.queueServiceChanged(name))),
      );
      continue;
    }
    final ids = [for (final entry in entries) entry.id];
    actions.add(
      runAction<void>(
        context,
        action: () => changes.unblock(instance, ids),
        acceptedMessage: strings.queueRemoveAccepted(name),
        describeFailure: (message) => strings.queueFailureOn(name, message),
        // Every answer has the blocklist read again.
        onRefresh: () {},
      ),
    );
  }
  await Future.wait(actions);
}
