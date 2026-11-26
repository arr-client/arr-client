import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../../src/l10n/generated/app_localizations.dart';
import 'search_tasks.dart';

/// How the searches started in the library of [kind] are going, for the
/// instances it shows. Their state is read while this is visible.
class SearchProgress extends ConsumerStatefulWidget {
  const SearchProgress({
    required this.kind,
    required this.instanceIds,
    super.key,
  });

  final MediaKind kind;
  final Set<String> instanceIds;

  @override
  ConsumerState<SearchProgress> createState() => _SearchProgressState();
}

class _SearchProgressState extends ConsumerState<SearchProgress> {
  void Function()? _release;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Tickers are off behind another destination or page.
    if (TickerMode.valuesOf(context).enabled) {
      _release ??= ref.read(searchTasksProvider.notifier).watch();
    } else {
      _release?.call();
      _release = null;
    }
  }

  @override
  void dispose() {
    _release?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The newest first, so that what was just asked for is in sight.
    final tasks = [
      for (final task in ref.watch(searchTasksProvider).reversed)
        if (task.kind == widget.kind &&
            widget.instanceIds.contains(task.instance.instance.id))
          task,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final task in tasks)
          _Task(
            key: ValueKey(task.id),
            task: task,
            onDismiss: () =>
                ref.read(searchTasksProvider.notifier).dismiss(task.id),
          ),
      ],
    );
  }
}

class _Task extends StatelessWidget {
  const _Task({required this.task, required this.onDismiss, super.key});

  final SearchTask task;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final count = task.parts.length;
    final succeeded = task.parts
        .where((part) => part.outcome == CommandOutcome.succeeded)
        .length;
    // Whether every search has been answered.
    final sent = task.parts.every(
      (part) => part.command != null || part.failure != null || part.notSent,
    );
    final status = task.isFinished
        ? strings.bulkSearchDone(succeeded, count)
        : sent
        ? strings.bulkSearchRunning(task.finished, count)
        : strings.bulkSearchStarting(task.finished, count);
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      child: LayoutBuilder(
        builder: (context, constraints) => Padding(
          padding: EdgeInsets.symmetric(
            horizontal: screenMargin(constraints.maxWidth),
            vertical: 8,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                strings.bulkSearchTaskTitle(count, task.instance.instance.name),
                style: theme.textTheme.titleSmall,
              ),
              Semantics(liveRegion: true, child: Text(status)),
              for (final part in task.parts)
                if (_problem(context, part) case final problem?)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(strings.titleProblem(part.title, problem)),
                  ),
              if (!task.isFinished) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  semanticsLabel: UiLocalizations.of(context).loading,
                ),
              ] else
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton(
                    onPressed: onDismiss,
                    child: Text(strings.bulkSearchDismiss),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// What went wrong with one search, or null if nothing has.
  static String? _problem(BuildContext context, SearchPart part) {
    final strings = AppLocalizations.of(context);
    final command = part.command;
    final failure = part.failure;
    if (part.notSent) return strings.bulkNotSent;
    return switch (part.outcome) {
      CommandOutcome.pending || CommandOutcome.succeeded => null,
      // Accepted, and the server says it did not do it.
      CommandOutcome.failed when command != null => switch (command.message) {
        final message? when message.isNotEmpty => message,
        _ => strings.bulkSearchFailed,
      },
      // Not accepted, or sent without an answer.
      _ when command == null && failure != null => failureMessage(
        context,
        failure,
      ),
      _ => strings.bulkSearchUnknown,
    };
  }
}
