import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../src/l10n/generated/app_localizations.dart';
import 'calendar_data.dart';
import 'calendar_tiles.dart';
import 'service_answer.dart';

/// The scrolling body of a view over one read: the choice of services, a notice
/// for each that failed, then the view's own rows. With nothing at all to show
/// yet it says that it is loading.
class CalendarPage<T> extends ConsumerWidget {
  const CalendarPage({
    required this.provider,
    required this.hidden,
    required this.onHiddenChanged,
    required this.builder,
    this.leading = const [],
    super.key,
  });

  final NotifierProvider<CalendarReadNotifier<T>, ServiceAnswers<T>?> provider;

  /// The instances the user has filtered out.
  final Set<String> hidden;
  final ValueChanged<Set<String>> onHiddenChanged;

  /// Rows above the data, shown whatever its state.
  final List<Widget> leading;

  /// The view's rows, from the answers of the services shown.
  final List<Widget> Function(CalendarContent<T> content) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    final answers = ref.watch(provider);
    final loading = Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: CircularProgressIndicator(
          semanticsLabel: UiLocalizations.of(context).loading,
        ),
      ),
    );
    final shown = <ServiceAnswer<T>>[
      for (final answer in answers ?? <ServiceAnswer<T>>[])
        if (!hidden.contains(answer.instanceId)) answer,
    ];
    final content = CalendarContent<T>(
      shown,
      several: (answers?.length ?? 0) > 1,
    );

    final rows = <Widget>[
      if (answers != null && answers.length > 1)
        _Filter(
          services: [
            for (final answer in answers) (answer.instanceId, answer.name),
          ],
          hidden: hidden,
          onChanged: onHiddenChanged,
        ),
      ...leading,
      if (answers == null)
        loading
      else if (answers.isEmpty)
        CalendarNote(strings.notOffered)
      else if (shown.isEmpty)
        CalendarNote(strings.calendarAllHidden)
      else ...[
        for (final answer in shown)
          if (answer.failure != null)
            ServiceNotice<T>(
              answer: answer,
              onRetry: () => unawaited(
                ref
                    .read(provider.notifier)
                    .reload(instanceId: answer.instanceId),
              ),
            ),
        // While some have yet to answer, what the others gave is shown.
        if (shown.every((answer) => answer.loading && answer.value == null))
          loading
        else ...[
          if (shown.any((answer) => answer.loading))
            LinearProgressIndicator(
              semanticsLabel: UiLocalizations.of(context).loading,
            ),
          // With nothing read, "nothing" would not be true.
          if (shown.any((answer) => answer.value != null)) ...builder(content),
        ],
      ],
    ];

    return RefreshIndicator(
      onRefresh: () => ref.read(provider.notifier).reload(),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          bottom: 16 + MediaQuery.paddingOf(context).bottom,
        ),
        itemCount: rows.length,
        itemBuilder: (context, index) => rows[index],
      ),
    );
  }
}

/// What the shown services have given.
final class CalendarContent<T> {
  const CalendarContent(this.answers, {required this.several});

  final ServiceAnswers<T> answers;

  /// Whether there is more than one service, so rows name theirs.
  final bool several;

  /// Whether a read is under way.
  bool get isReading => answers.any((answer) => answer.loading);

  /// Whether every service shown has given something and none failed since: only
  /// then does an empty day mean that there is nothing.
  bool get isComplete =>
      answers.every((answer) => answer.value != null && answer.failure == null);
}

/// One chip for each service.
class _Filter extends StatelessWidget {
  const _Filter({
    required this.services,
    required this.hidden,
    required this.onChanged,
  });

  /// Instance ids and names.
  final List<(String, String)> services;
  final Set<String> hidden;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(
      horizontal: screenMargin(MediaQuery.sizeOf(context).width),
      vertical: 4,
    ),
    child: Semantics(
      container: true,
      label: AppLocalizations.of(context).calendarFilter,
      explicitChildNodes: true,
      child: Wrap(
        spacing: 8,
        children: [
          for (final (id, name) in services)
            FilterChip(
              label: Text(name),
              selected: !hidden.contains(id),
              onSelected: (selected) => onChanged(
                selected ? ({...hidden}..remove(id)) : {...hidden, id},
              ),
            ),
        ],
      ),
    ),
  );
}
