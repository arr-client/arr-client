/// The sheet that adds a title to one instance.
library;

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../../app/providers.dart';
import '../../../src/l10n/generated/app_localizations.dart';
import '../add_request.dart';
import 'add_controller.dart';
import 'add_form.dart';
import 'add_sends.dart';
import 'add_state.dart';
import 'open_item.dart';

/// Opens the add sheet of [request].
Future<void> showAddSheet(BuildContext context, AddRequest request) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => AddSheet(request: request),
    );

class AddSheet extends ConsumerStatefulWidget {
  const AddSheet({required this.request, super.key});

  final AddRequest request;

  @override
  ConsumerState<AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends ConsumerState<AddSheet> {
  @override
  void initState() {
    super.initState();
    // A provider is not changed while the tree is being built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(addProvider(widget.request).notifier).open();
    });
  }

  /// Sends the add, and says how it went: in the sheet while it is open, and
  /// else in a message.
  Future<void> _submit(String instanceId, String name) async {
    final strings = AppLocalizations.of(context);
    // Taken before the wait, after which the sheet may be gone.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final route = ModalRoute.of(context);

    final result = await ref
        .read(addProvider(widget.request).notifier)
        .submit(instanceId);
    if (result == null || !messenger.mounted) return;
    final open = mounted && (route?.isCurrent ?? false);
    switch (result) {
      case Ok():
        if (open) navigator.pop();
        messenger.showSnackBar(SnackBar(content: Text(strings.addAdded(name))));
      case Err(:final error):
        if (open) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              strings.addFailedOn(
                name,
                failureMessage(messenger.context, error),
              ),
            ),
            persist: true,
            showCloseIcon: true,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final candidate = widget.request.candidate;
    final provider = addProvider(widget.request);
    final state = ref.watch(provider);
    final targets = addTargets(ref.watch(scopeProvider), candidate.kind);
    final selected = targets
        .where((target) => target.$1.instance.id == state.selected)
        .firstOrNull
        ?.$1;
    final id = selected?.instance.id;
    final name = selected?.instance.name ?? '';
    final target = id == null ? null : state.targets[id];
    final sending =
        id != null &&
        ref.watch(
          addSendsProvider.select(
            (sends) => sends.sending.contains(addKey(id, candidate)),
          ),
        );

    final body = switch (target) {
      _ when targets.isEmpty => Text(strings.addNoService),
      null => const _Waiting(),
      TargetLoading(:final checking) => _Waiting(
        message: checking ? strings.addChecking(name) : null,
      ),
      TargetFailed(:final failure, :final after) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (after != null) ...[
            _Problem(failureMessage(context, after)),
            const SizedBox(height: 8),
          ],
          _Problem(
            failure is NotFound
                ? strings.addNotFound(name)
                : failureMessage(context, failure),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => ref.read(provider.notifier).retry(id!),
            child: Text(UiLocalizations.of(context).retry),
          ),
        ],
      ),
      TargetHeld(ref: final item, :final added, :final after) => _Held(
        message: added
            ? strings.addAdded(name)
            : switch (after) {
                // It may be there because of this add or someone else's.
                OutcomeUnknown() => strings.addThereNow(name, candidate.title),
                _ => strings.addAlreadyHas(name, candidate.title),
              },
        name: name,
        location: itemLocation(selected, item, candidate.title),
      ),
      TargetReady(:final options, :final draft, :final problem) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (problem != null) ...[
            _Problem(switch (problem) {
              NotFound() => strings.addNotFound(name),
              OutcomeUnknown() =>
                '${failureMessage(context, problem)}\n'
                    '${strings.addNotListedYet(name)}',
              _ => failureMessage(context, problem),
            }),
            const SizedBox(height: 16),
          ],
          if (draft.choices == null) ...[
            _Problem(strings.addNothingToChoose(name)),
            const SizedBox(height: 8),
          ],
          AddForm(
            options: options,
            draft: draft,
            enabled: !sending,
            onChanged: (draft) =>
                ref.read(provider.notifier).change(id!, draft),
          ),
        ],
      ),
    };

    final ready = target is TargetReady ? target : null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      strings.addSheetTitle(candidate.title),
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (targets.isNotEmpty) ...[
                    AddChoice<String>(
                      label: strings.addTarget,
                      value: id,
                      items: {
                        for (final (active, _) in targets)
                          active.instance.id: switch (state.targets[active
                              .instance
                              .id]) {
                            TargetHeld() => strings.addServiceHasIt(
                              active.instance.name,
                            ),
                            null
                                when heldRef(candidate, active.instance.id) !=
                                    null =>
                              strings.addServiceHasIt(active.instance.name),
                            _ => active.instance.name,
                          },
                      },
                      // The sheet stays with what it is sending.
                      onChanged: sending
                          ? null
                          : ref.read(provider.notifier).select,
                    ),
                    const SizedBox(height: 16),
                  ],
                  body,
                ],
              ),
            ),
          ),
          if (ready != null && id != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (sending) ...[
                    const LinearProgressIndicator(),
                    const SizedBox(height: 8),
                  ],
                  Semantics(
                    liveRegion: sending,
                    child: FilledButton(
                      onPressed: sending || ready.draft.choices == null
                          ? null
                          : () => unawaited(_submit(id, name)),
                      child: Text(
                        sending
                            ? strings.addAdding(name)
                            : strings.addToService(name),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Column(
      children: [
        CircularProgressIndicator(
          semanticsLabel: UiLocalizations.of(context).loading,
        ),
        if (message case final message?) ...[
          const SizedBox(height: 16),
          Semantics(
            liveRegion: true,
            child: Text(message, textAlign: TextAlign.center),
          ),
        ],
      ],
    ),
  );
}

/// What went wrong, marked by an icon as well as colour and announced.
class _Problem extends StatelessWidget {
  const _Problem(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
      const SizedBox(width: 8),
      Expanded(child: Semantics(liveRegion: true, child: Text(message))),
    ],
  );
}

/// The chosen instance has the title: offers to open it.
class _Held extends StatelessWidget {
  const _Held({
    required this.message,
    required this.name,
    required this.location,
  });

  final String message;
  final String name;
  final String? location;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Semantics(liveRegion: true, child: Text(message)),
      if (location case final location?) ...[
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () {
            final router = GoRouter.of(context);
            Navigator.pop(context);
            unawaited(router.push<void>(location));
          },
          child: Text(AppLocalizations.of(context).addOpenIn(name)),
        ),
      ],
    ],
  );
}
