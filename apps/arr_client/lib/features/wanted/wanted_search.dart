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

import '../../app/composition.dart';
import '../../app/providers.dart';
import '../../src/l10n/generated/app_localizations.dart';
import 'wanted_controller.dart';
import 'wanted_tile.dart';

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

/// Searches for [batches], once confirmed where they are more than one item.
/// [onSent] is called when they are about to be sent. [onRefresh] reads an
/// instance's list again.
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
  final removals = _Removals(ref.read(appServicesProvider));
  try {
    if (items.length > 1) {
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
    await _send(context, ref, removals.without(batches), onRefresh);
  } finally {
    removals.close();
  }
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

  // From before the first page: one may go while the others are read.
  final removals = _Removals(ref.read(appServicesProvider));
  try {
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
        items = removals.left(searchable(instance, value.items));
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
    await _send(
      context,
      ref,
      removals.without([(instance: instance, items: items)]),
      onRefresh,
    );
  } finally {
    removals.close();
  }
}

/// The items found to be gone while a search is being prepared, which must
/// then not be named.
class _Removals {
  _Removals(AppServices services) {
    _subscription = services.cache.removals.listen(_gone.add);
  }

  final _gone = <ItemRef>{};
  late final StreamSubscription<ItemRef> _subscription;

  List<LibraryItem> left(List<LibraryItem> items) => [
    for (final item in items)
      if (!isGone(item, _gone)) item,
  ];

  /// A batch with nothing left stays, so that it is said.
  List<SearchBatch> without(List<SearchBatch> batches) => [
    for (final (:instance, :items) in batches)
      (instance: instance, items: left(items)),
  ];

  void close() => unawaited(_subscription.cancel());
}

/// What a search leads to, and which of the items the user may not expect.
String _consequence(AppLocalizations strings, List<LibraryItem> items) {
  int count(ItemState state) =>
      items.where((item) => item.state == state).length;
  final unreleased = count(ItemState.unreleased);
  final downloading = count(ItemState.downloading);
  final warnings = [
    if (unreleased > 0) strings.wantedIncludesUnreleased(unreleased),
    if (downloading > 0) strings.wantedIncludesDownloading(downloading),
  ];
  // What is out of the ordinary first, and close together: large text can put
  // the rest of a dialog out of sight.
  return [
    if (warnings.isNotEmpty) warnings.join('\n'),
    strings.wantedSearchConsequence,
  ].join('\n\n');
}

/// Sends one search for each of [batches] and says in one message how every
/// one of them went, as a later message would replace an earlier one.
Future<void> _send(
  BuildContext context,
  WidgetRef ref,
  List<SearchBatch> batches,
  void Function(String instanceId) onRefresh,
) async {
  final strings = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final searches = ref.read(wantedSearchesProvider.notifier);
  // A null result is of a search that was not sent.
  final sent = <(SearchBatch, Future<Result<Command, ServiceFailure>?>)>[];
  for (final batch in batches) {
    if (!batch.instance.isCurrent || batch.items.isEmpty) {
      sent.add((batch, Future.value()));
    } else if (searches.send(batch.instance, batch.items) case final result?) {
      sent.add((batch, result));
    }
    // Otherwise another search of it got in first, which says how it went.
  }
  if (sent.isEmpty) return;

  String accepted(SearchBatch batch) => switch (batch.items) {
    [final item] => strings.wantedSearchAcceptedOne(
      batch.instance.instance.name,
      wantedItemName(strings, item),
    ),
    final items => strings.wantedSearchAccepted(
      batch.instance.instance.name,
      items.length,
    ),
  };
  final answers = <(SearchBatch, Result<Command, ServiceFailure>?)>[];
  String line(SearchBatch batch, Result<Command, ServiceFailure>? result) {
    final name = batch.instance.instance.name;
    return switch (result) {
      null when batch.items.isEmpty => strings.wantedNothingToSearch(name),
      null => strings.releaseServiceChanged(name),
      Ok() => accepted(batch),
      Err(error: OutcomeUnknown()) => strings.wantedSearchUnknown(
        batch.items.length,
        name,
      ),
      Err(error: NotFound()) => strings.wantedSearchFailed(
        name,
        UiLocalizations.of(messenger.context).itemGone,
      ),
      Err(:final error) => strings.wantedSearchFailed(
        name,
        failureMessage(messenger.context, error),
      ),
    };
  }

  await runAction<void>(
    context,
    action: () async {
      for (final (batch, result) in sent) {
        answers.add((batch, await result));
      }
      // Any one not accepted makes the message stay until it is dismissed.
      return answers.every((answer) => answer.$2 is Ok)
          ? const Ok(null)
          : const Err(Conflict());
    },
    acceptedMessage: [for (final (batch, _) in sent) accepted(batch)]
        .join('\n'),
    describeFailure: (_) =>
        [for (final (batch, result) in answers) line(batch, result)].join('\n'),
    onRefresh: () {},
  );
  for (final (batch, result) in answers) {
    if (result case Err(error: OutcomeUnknown() || NotFound())) {
      onRefresh(batch.instance.instance.id);
    }
  }
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
