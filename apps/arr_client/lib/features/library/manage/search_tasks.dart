/// The automatic searches started for selected items, and how they go. Each
/// search is sent once; only its state is asked for again. They outlive the
/// screen that started them.
library;

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import 'manage_calls.dart';

/// How long between two reads of running commands (research R11).
const commandPollInterval = Duration(seconds: 2);

/// How many reads in a row may fail before a command is no longer followed.
const _readAttempts = 3;

/// The search for one item.
final class SearchPart {
  const SearchPart({
    required this.item,
    required this.title,
    this.command,
    this.failure,
    this.lost = false,
    this.notSent = false,
    this.failedReads = 0,
  });

  final ItemRef item;

  /// The item's name, as it was when the search was asked for.
  final String title;

  /// The command as the server last described it; null until it accepted one.
  final Command? command;

  /// Why it was not accepted, or why it could not be read.
  final ServiceFailure? failure;

  /// Whether an accepted command is no longer followed.
  final bool lost;

  /// Whether nothing was sent, as the instance had changed by then.
  final bool notSent;

  final int failedReads;

  /// What can be said about the search.
  CommandOutcome get outcome {
    if (lost) return CommandOutcome.unknown;
    if (notSent) return CommandOutcome.failed;
    return switch ((command, failure)) {
      (final command?, _) => command.outcome,
      (null, OutcomeUnknown()) => CommandOutcome.unknown,
      (null, _?) => CommandOutcome.failed,
      (null, null) => CommandOutcome.pending,
    };
  }

  SearchPart _with({
    Command? command,
    ServiceFailure? failure,
    bool lost = false,
    bool notSent = false,
    int failedReads = 0,
  }) => SearchPart(
    item: item,
    title: title,
    command: command ?? this.command,
    failure: failure,
    lost: lost,
    notSent: notSent,
    failedReads: failedReads,
  );
}

/// One request of the user to search for several items of one instance.
final class SearchTask {
  const SearchTask({
    required this.id,
    required this.instance,
    required this.kind,
    required this.parts,
  });

  final int id;
  final ActiveInstance instance;
  final MediaKind kind;
  final List<SearchPart> parts;

  int get finished =>
      parts.where((part) => part.outcome != CommandOutcome.pending).length;

  bool get isFinished => finished == parts.length;
}

final searchTasksProvider = NotifierProvider<SearchTasks, List<SearchTask>>(
  SearchTasks.new,
);

class SearchTasks extends Notifier<List<SearchTask>> {
  var _next = 0;
  var _watchers = 0;
  var _reading = false;
  Timer? _timer;

  @override
  List<SearchTask> build() {
    ref.onDispose(() => _timer?.cancel());
    return const [];
  }

  /// Says that a screen showing the searches is visible. Their state is read
  /// only until the returned function is called.
  void Function() watch() {
    _watchers++;
    _schedule();
    var released = false;
    return () {
      if (released) return;
      released = true;
      if (--_watchers == 0) {
        _timer?.cancel();
        _timer = null;
      }
    };
  }

  /// Searches for each of [items] on [instance], one command each, as not every
  /// service takes several items in one.
  Future<void> start(
    ActiveInstance instance,
    CommandProvider commands,
    List<({ItemRef item, String title})> items,
  ) async {
    if (items.isEmpty) return;
    final id = _next++;
    state = [
      ...state,
      SearchTask(
        id: id,
        instance: instance,
        kind: items.first.item.kind,
        parts: [
          for (final (:item, :title) in items)
            SearchPart(item: item, title: title),
        ],
      ),
    ];
    final services = ref.read(appServicesProvider);
    for (var i = 0; i < items.length; i++) {
      if (!instance.isCurrent) {
        _put(id, i, (part) => part._with(notSent: true));
        continue;
      }
      final result = await sendOnce(
        services,
        instance,
        () => commands.search([MediaTarget(items[i].item)]),
      );
      if (!ref.mounted) return;
      _put(
        id,
        i,
        (part) => switch (result) {
          Ok(:final value) => part._with(command: value),
          Err(:final error) => part._with(failure: error),
        },
      );
      _schedule();
    }
  }

  /// Forgets a task.
  void dismiss(int id) => state = [
    for (final task in state)
      if (task.id != id) task,
  ];

  void _put(int id, int index, SearchPart Function(SearchPart) change) {
    state = [
      for (final task in state)
        if (task.id == id)
          SearchTask(
            id: task.id,
            instance: task.instance,
            kind: task.kind,
            parts: [
              for (final (i, part) in task.parts.indexed)
                i == index ? change(part) : part,
            ],
          )
        else
          task,
    ];
  }

  static bool _isRunning(SearchPart part) =>
      part.command != null && part.outcome == CommandOutcome.pending;

  void _schedule() {
    if (_watchers == 0 || _reading || _timer != null) return;
    if (!state.any((task) => task.parts.any(_isRunning))) return;
    _timer = Timer(commandPollInterval, () {
      _timer = null;
      unawaited(_poll());
    });
  }

  Future<void> _poll() async {
    // Nothing is asked while the app is out of sight.
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      return _schedule();
    }
    _reading = true;
    try {
      final services = ref.read(appServicesProvider);
      for (final task in state) {
        for (final (i, part) in task.parts.indexed) {
          final command = part.command;
          if (command == null || !_isRunning(part)) continue;
          final commands = task.instance.capability(CapabilityKind.command);
          // An edited or removed instance is not asked.
          if (!task.instance.isCurrent || commands == null) {
            _put(task.id, i, (part) => part._with(lost: true));
            continue;
          }
          final result = await readOf(
            services,
            () => commands.commandStatus(command.id),
          );
          if (!ref.mounted) return;
          _put(
            task.id,
            i,
            (part) => switch (result) {
              Ok(:final value) => part._with(command: value),
              Err(:final error) => part._with(
                failure: error,
                lost:
                    error is NotFound || part.failedReads + 1 >= _readAttempts,
                failedReads: part.failedReads + 1,
              ),
            },
          );
        }
      }
    } finally {
      _reading = false;
    }
    if (ref.mounted) _schedule();
  }
}
