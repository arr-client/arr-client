import 'package:core/core.dart';

import 'add_draft.dart';

/// What is known about adding the title to one instance.
sealed class AddTarget {
  const AddTarget();
}

/// Asking the instance.
final class TargetLoading extends AddTarget {
  const TargetLoading({this.checking = false});

  /// Whether this is to see what became of an add that was sent.
  final bool checking;
}

/// The instance could not say what it has or what can be chosen.
final class TargetFailed extends AddTarget {
  const TargetFailed(this.failure, {this.after});

  final ServiceFailure failure;

  /// How the add before this went wrong, if one was sent.
  final ServiceFailure? after;
}

/// The instance has the title.
final class TargetHeld extends AddTarget {
  const TargetHeld(this.ref, {this.added = false, this.after});

  /// The item there.
  final ItemRef ref;

  /// Whether the server accepted it from this screen.
  final bool added;

  /// The failure after which it was found there.
  final ServiceFailure? after;
}

/// The title can be added.
final class TargetReady extends AddTarget {
  const TargetReady({
    required this.candidate,
    required this.options,
    required this.draft,
    this.problem,
  });

  /// What to hand to `add`.
  final AddCandidate candidate;
  final AddOptions options;
  final AddDraft draft;

  /// Why the last attempt did not add it.
  final ServiceFailure? problem;

  TargetReady withDraft(AddDraft draft) => TargetReady(
    candidate: candidate,
    options: options,
    draft: draft,
    problem: problem,
  );
}

/// What the add screen and its sheet show.
final class AddState {
  const AddState({this.selected, this.targets = const {}});

  /// The instance chosen in the sheet.
  final String? selected;

  /// By instance id, for those that have been asked.
  final Map<String, AddTarget> targets;

  AddState copyWith({String? selected, Map<String, AddTarget>? targets}) =>
      AddState(
        selected: selected ?? this.selected,
        targets: targets ?? this.targets,
      );
}
