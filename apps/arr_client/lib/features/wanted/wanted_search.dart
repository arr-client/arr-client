/// Searching for wanted items: confirmation, sending and saying how it went.
///
/// A search may start downloads. Every command names its items, so that none
/// can mean a whole library, and none is ever sent a second time.
library;

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../app/providers.dart';
import '../../src/l10n/generated/app_localizations.dart';
import 'wanted_controller.dart';
import 'wanted_tile.dart';

/// The most items that selecting them searches without asking again.
const searchWithoutAsking = 10;

/// The instances a search is being sent to.
final wantedSearchesProvider = NotifierProvider<WantedSearches, Set<String>>(
  WantedSearches.new,
);

/// Sends searches, one at a time for each instance. It outlives the screen, so
/// that a search under way cannot be sent again from a screen opened anew.
class WantedSearches extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  /// Sends one search for [items] of [instance]. Null, with nothing sent, if
  /// one is already under way for it.
  Future<Result<Command, ServiceFailure>>? send(
    ActiveInstance instance,
    List<LibraryItem> items,
  ) {
    final id = instance.instance.id;
    if (state.contains(id)) return null;
    state = {...state, id};
    return _send(instance, items);
  }

  Future<Result<Command, ServiceFailure>> _send(
    ActiveInstance instance,
    List<LibraryItem> items,
  ) async {
    final log = ref.read(appServicesProvider).log;
    try {
      final commands = instance.capability(CapabilityKind.command);
      // Nothing is sent for what has been edited, removed or switched away
      // from.
      if (!instance.isCurrent || commands == null) {
        return const Err(Unreachable());
      }
      return await commands.search([
        for (final item in items) MediaTarget(item.ref),
      ]);
    } catch (error) {
      // The type only: the text of an error may quote an address or a secret.
      log.log(LogLevel.error, 'A search failed (${error.runtimeType})');
      return const Err(OutcomeUnknown());
    } finally {
      state = {...state}..remove(instance.instance.id);
    }
  }
}

/// Which of [items] [instance] can search for.
List<LibraryItem> searchable(
  ActiveInstance instance,
  Iterable<LibraryItem> items,
) {
  final commands = instance.capability(CapabilityKind.command);
  if (commands == null) return const [];
  return [
    for (final item in items)
      if (commands.supports(CommandAction.search, MediaTarget(item.ref))) item,
  ];
}

/// The items to search for on one instance.
typedef SearchBatch = ({ActiveInstance instance, List<LibraryItem> items});

/// Searches for [batches], once confirmed where they are more than
/// [searchWithoutAsking] items. [onSent] is called when they are about to be
/// sent. [onRefresh] reads an instance's list again.
///
/// [context] must outlive the items' rows.
Future<void> searchWanted(
  BuildContext context,
  WidgetRef ref,
  List<SearchBatch> batches, {
  required void Function(String instanceId) onRefresh,
  VoidCallback? onSent,
}) async {
  final strings = AppLocalizations.of(context);
  final items = [for (final batch in batches) ...batch.items];
  if (items.isEmpty) return;
  if (items.length > searchWithoutAsking) {
    final confirmed = await showConfirmDialog(
      context,
      title: strings.wantedSearchSelectedTitle(items.length),
      target: [
        for (final (:instance, items: own) in batches)
          strings.wantedItemsOn(own.length, instance.instance.name),
      ].join('\n'),
      consequence: _consequence(strings, items),
      confirmLabel: strings.wantedSearchConfirm(items.length),
      destructive: false,
    );
    if (!confirmed || !context.mounted) return;
  }
  onSent?.call();
  await Future.wait([
    for (final batch in batches) _sendBatch(context, ref, batch, onRefresh),
  ]);
}

/// Searches for everything on one list of [instance]: reads the whole of it,
/// asks with the number of items, then names each of them in one command.
Future<void> searchAllWanted(
  BuildContext context,
  WidgetRef ref,
  ActiveInstance instance,
  WantedKind kind, {
  required void Function(String instanceId) onRefresh,
}) async {
  final strings = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final name = instance.instance.name;
  void say(String message) {
    if (messenger.mounted) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  final result = await showDialog<Result<WantedPages, ServiceFailure>>(
    context: context,
    // A tap beside it must not look like an answer.
    barrierDismissible: false,
    builder: (context) => _ReadingAll(instance: instance, kind: kind),
  );
  if (!instance.isCurrent) return say(strings.releaseServiceChanged(name));
  if (!context.mounted) return;
  final List<LibraryItem> items;
  switch (result) {
    // The user gave up.
    case null:
      return;
    case Err(:final error):
      return say(
        strings.wantedReadAllFailed(name, failureMessage(context, error)),
      );
    case Ok(:final value):
      items = searchable(instance, value.items);
  }
  if (items.isEmpty) {
    onRefresh(instance.instance.id);
    return say(strings.wantedNothingToSearch(name));
  }
  final confirmed = await showConfirmDialog(
    context,
    title: switch (kind) {
      WantedKind.missing => strings.wantedSearchAllMissingTitle,
      WantedKind.cutoffUnmet => strings.wantedSearchAllCutoffTitle,
    },
    target: strings.wantedItemsOn(items.length, name),
    consequence: _consequence(strings, items),
    confirmLabel: strings.wantedSearchConfirm(items.length),
    destructive: false,
  );
  if (!confirmed || !context.mounted) return;
  await _sendBatch(context, ref, (instance: instance, items: items), onRefresh);
}

/// What a search leads to, and which of the items the user may not expect.
String _consequence(AppLocalizations strings, List<LibraryItem> items) {
  int count(ItemState state) =>
      items.where((item) => item.state == state).length;
  final unreleased = count(ItemState.unreleased);
  final downloading = count(ItemState.downloading);
  return [
    strings.wantedSearchConsequence,
    if (unreleased > 0) strings.wantedIncludesUnreleased(unreleased),
    if (downloading > 0) strings.wantedIncludesDownloading(downloading),
  ].join('\n\n');
}

Future<void> _sendBatch(
  BuildContext context,
  WidgetRef ref,
  SearchBatch batch,
  void Function(String instanceId) onRefresh,
) async {
  final strings = AppLocalizations.of(context);
  final (:instance, :items) = batch;
  final id = instance.instance.id;
  final name = instance.instance.name;
  if (!instance.isCurrent) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(strings.releaseServiceChanged(name))),
    );
    return;
  }
  // Null if another search of it got in first, which then says how it went.
  final sending = ref
      .read(wantedSearchesProvider.notifier)
      .send(instance, items);
  if (sending == null) return;
  ServiceFailure? failure;
  await runAction<Command>(
    context,
    action: () async {
      final result = await sending;
      if (result case Err(:final error)) failure = error;
      return result;
    },
    acceptedMessage: switch (items) {
      [final item] => strings.wantedSearchAcceptedOne(
        name,
        wantedItemName(strings, item),
      ),
      _ => strings.wantedSearchAccepted(name, items.length),
    },
    describeFailure: (message) => switch (failure) {
      OutcomeUnknown() => strings.wantedSearchUnknown(items.length, name),
      _ => strings.wantedSearchFailed(name, message),
    },
    onRefresh: () => onRefresh(id),
    onGone: () => onRefresh(id),
  );
}

/// Reads a whole list, saying how far it is. Closes with what it read, or with
/// nothing if the user gives up or the instance is no longer the same.
class _ReadingAll extends ConsumerStatefulWidget {
  const _ReadingAll({required this.instance, required this.kind});

  final ActiveInstance instance;
  final WantedKind kind;

  @override
  ConsumerState<_ReadingAll> createState() => _ReadingAllState();
}

class _ReadingAllState extends ConsumerState<_ReadingAll> {
  var _found = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_read());
  }

  Future<void> _read() async {
    final instance = widget.instance;
    final provider = instance.capability(CapabilityKind.wanted);
    final log = ref.read(appServicesProvider).log;
    // There is no dialog to close until it has been built.
    await null;
    final result = instance.instance.authFailed
        ? const Err<WantedPages, ServiceFailure>(AuthFailed())
        : provider == null
        ? null
        : await readWantedPages(
            provider,
            widget.kind,
            log: log,
            proceed: () => mounted && instance.isCurrent,
            onPage: (found) {
              if (mounted) setState(() => _found = found);
            },
          );
    // Not if it is already closing: that would close what is below it.
    if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) {
      Navigator.pop(context, result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return AlertDialog(
      scrollable: true,
      title: Text(strings.wantedReadingAll),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(strings.wantedFoundSoFar(_found)),
          const SizedBox(height: 16),
          LinearProgressIndicator(
            semanticsLabel: UiLocalizations.of(context).loading,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(UiLocalizations.of(context).cancel),
        ),
      ],
    );
  }
}
