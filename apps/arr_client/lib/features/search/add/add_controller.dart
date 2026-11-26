/// What the add screen and its sheet know about each instance the title could
/// be added to (spec story 3).
library;

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../add_request.dart';
import 'add_draft.dart';
import 'add_sends.dart';
import 'add_state.dart';

/// The instances of [scope] that add titles of [kind].
List<(ActiveInstance, LookupProvider)> addTargets(
  ProfileScope? scope,
  MediaKind kind,
) => [
  if (scope != null)
    for (final (active, lookup) in scope.providers(CapabilityKind.lookup))
      if (lookup.itemKinds.contains(kind)) (active, lookup),
];

/// The item of [candidate]'s search that [instanceId] has.
ItemRef? heldRef(AddCandidate candidate, String instanceId) => candidate
    .existingRefs
    .where((ref) => ref.instanceId == instanceId)
    .firstOrNull;

final addProvider = NotifierProvider.autoDispose
    .family<AddController, AddState, AddRequest>(AddController.new);

class AddController extends Notifier<AddState> {
  AddController(this.request);

  final AddRequest request;

  AddCandidate get _candidate => request.candidate;

  /// The latest read for each instance; what an older one answers is dropped.
  final _reads = <String, Object>{};

  /// The client each target was read with: an edited instance has another.
  final _clients = <String, Object>{};

  /// What the form of each instance last held. It outlasts a read that fails,
  /// so that asking again does not put back other choices.
  final _drafts = <String, AddDraft>{};

  /// The instances to which this controller is sending.
  final _sending = <String>{};

  @override
  AddState build() {
    ref.listen(scopeProvider, (_, scope) => _scopeChanged(scope));
    ref.listen(addSendsProvider, (before, now) {
      // An add that another visit of this screen sent has been answered.
      for (final key
          in before?.sending.difference(now.sending) ?? const <AddKey>{}) {
        final (id, _, _) = key;
        if (key == addKey(id, _candidate) &&
            !_sending.contains(id) &&
            state.targets.containsKey(id)) {
          _read(id);
        }
      }
    });
    // What may have changed since the search is asked at once.
    scheduleMicrotask(_confirm);
    return const AddState();
  }

  /// Asks the instances that the search showed as having the title, which may
  /// have been deleted since, and those the app has added to, which the search
  /// does not know about.
  void _confirm() {
    if (!ref.mounted) return;
    final sent = ref.read(addSendsProvider).sent;
    for (final (active, _) in addTargets(
      ref.read(scopeProvider),
      _candidate.kind,
    )) {
      final id = active.instance.id;
      if ((sent.contains(addKey(id, _candidate)) ||
              heldRef(_candidate, id) != null) &&
          !state.targets.containsKey(id)) {
        _read(id);
      }
    }
  }

  /// Chooses an instance, unless the chosen one can still take the title: the
  /// first that can.
  void open() {
    final targets = [
      for (final (active, _) in addTargets(
        ref.read(scopeProvider),
        _candidate.kind,
      ))
        active.instance.id,
    ];
    final selected = state.selected;
    if (selected != null && targets.contains(selected) && !_known(selected)) {
      select(selected);
      return;
    }
    // With none left to take it, the choice stays where it was.
    final first =
        targets.where((id) => !_known(id)).firstOrNull ??
        (targets.contains(selected) ? selected : targets.firstOrNull);
    if (first != null) select(first);
  }

  /// Chooses [instanceId] and asks it what is not yet known.
  void select(String instanceId) {
    state = state.copyWith(selected: instanceId);
    switch (state.targets[instanceId]) {
      case null:
        _read(instanceId);
      case TargetFailed(:final after):
        _read(instanceId, problem: after);
      case TargetLoading() || TargetHeld() || TargetReady():
        break;
    }
  }

  /// Asks [instanceId] again after it failed to answer.
  void retry(String instanceId) {
    final target = state.targets[instanceId];
    _read(instanceId, problem: target is TargetFailed ? target.after : null);
  }

  /// Keeps what the user chose.
  void change(String instanceId, AddDraft draft) {
    if (state.targets[instanceId] case final TargetReady ready) {
      _set(instanceId, ready.withDraft(draft));
    }
  }

  /// Sends the add to [instanceId], once. Null if nothing was sent. The result
  /// is given even if the screen has been left meanwhile.
  Future<Result<ItemRef, ServiceFailure>?> submit(String instanceId) async {
    final ready = state.targets[instanceId];
    final (active, lookup) = _target(instanceId);
    if (ready is! TargetReady || active == null || lookup == null) return null;
    final choices = ready.draft.choices;
    if (choices == null) return null;

    final sends = ref.read(addSendsProvider.notifier);
    _sending.add(instanceId);
    _set(
      instanceId,
      TargetReady(
        candidate: ready.candidate,
        options: ready.options,
        draft: ready.draft,
      ),
    );
    final result = await sends.send(active, lookup, ready.candidate, choices);
    if (!ref.mounted) return result;
    _sending.remove(instanceId);
    // Retired meanwhile: the scope's listener has dropped the target.
    if (result == null || !active.isCurrent) return result;

    switch (result) {
      case Ok(:final value):
        _reads.remove(instanceId);
        _set(instanceId, TargetHeld(value, added: true));
      // The server has it, or may have it: ask it, and send nothing.
      case Err(error: final error && (Conflict() || OutcomeUnknown())):
        await _read(instanceId, problem: error, checking: true);
      // A root folder, say, may be gone: read what can be chosen now.
      case Err(error: final error && Validation()):
        await _read(instanceId, problem: error);
      case Err(:final error):
        _set(
          instanceId,
          TargetReady(
            candidate: ready.candidate,
            options: ready.options,
            draft: ready.draft,
            problem: error,
          ),
        );
    }
    return result;
  }

  /// Whether [instanceId] is known to have the title.
  bool _known(String instanceId) => switch (state.targets[instanceId]) {
    TargetHeld() => true,
    TargetReady() => false,
    _ => heldRef(_candidate, instanceId) != null,
  };

  /// Finds out whether [instanceId] has the title and, if not, what can be
  /// chosen there. [problem] is what went wrong with an add before this.
  Future<void> _read(
    String instanceId, {
    ServiceFailure? problem,
    bool checking = false,
  }) async {
    final (active, lookup) = _target(instanceId);
    if (active == null || lookup == null) return;
    final read = _reads[instanceId] = Object();
    _clients[instanceId] = active.context.http;
    bool stale() =>
        !ref.mounted ||
        !identical(_reads[instanceId], read) ||
        !active.isCurrent;
    void fail(ServiceFailure failure) =>
        _set(instanceId, TargetFailed(failure, after: problem));

    // After a send, what the search said may no longer hold.
    final sent = ref
        .read(addSendsProvider)
        .sent
        .contains(addKey(instanceId, _candidate));
    final searched = heldRef(_candidate, instanceId) != null;
    _set(instanceId, TargetLoading(checking: checking));

    try {
      var candidate = _candidate;
      // A target whose search did not give the title looks it up itself. So
      // does one that may have gained or lost it since.
      if (sent ||
          searched ||
          !candidate.sourceByInstance.containsKey(instanceId)) {
        final found = await lookup.find(candidate);
        if (stale()) return;
        switch (found) {
          case Err(:final error):
            fail(error);
            return;
          case Ok(:final value):
            if (heldRef(value, instanceId) case final held?) {
              _set(instanceId, TargetHeld(held, after: problem));
              return;
            }
            candidate = value;
        }
      }

      final answer = await lookup.addOptions(candidate.kind);
      if (stale()) return;
      switch (answer) {
        case Err(:final error):
          fail(error);
        case Ok(value: final options):
          final remembered = await _remembered(instanceId);
          if (stale()) return;
          _set(
            instanceId,
            TargetReady(
              candidate: candidate,
              options: options,
              draft:
                  _drafts[instanceId]?.fitting(options) ??
                  AddDraft.from(candidate.kind, options, remembered),
              problem: problem,
            ),
          );
      }
    } catch (error, stackTrace) {
      // The type only: the text of an error may quote an address or a secret.
      if (stale()) return;
      ref
          .read(appServicesProvider)
          .log
          .log(
            LogLevel.error,
            'A module failed to read (${error.runtimeType})',
            stackTrace: stackTrace,
          );
      fail(const MalformedResponse());
    }
  }

  Future<AddChoices?> _remembered(String instanceId) async {
    final services = ref.read(appServicesProvider);
    try {
      return await services.preferences.lastAddChoices(instanceId);
    } catch (error) {
      services.log.log(
        LogLevel.warning,
        'The add choices could not be read (${error.runtimeType})',
      );
      return null;
    }
  }

  (ActiveInstance?, LookupProvider?) _target(String instanceId) {
    for (final (active, lookup) in addTargets(
      ref.read(scopeProvider),
      _candidate.kind,
    )) {
      if (active.instance.id == instanceId) return (active, lookup);
    }
    return (null, null);
  }

  void _set(String instanceId, AddTarget target) {
    if (target is TargetReady) _drafts[instanceId] = target.draft;
    state = state.copyWith(targets: {...state.targets, instanceId: target});
  }

  void _scopeChanged(ProfileScope? scope) {
    final gone = {
      for (final MapEntry(key: id, value: client) in _clients.entries)
        if (!identical(scope?.instance(id)?.context.http, client)) id,
    };
    for (final id in gone) {
      _clients.remove(id);
      _reads.remove(id);
      _sending.remove(id);
    }
    if (gone.isNotEmpty) {
      state = state.copyWith(
        targets: {
          for (final MapEntry(key: id, value: target) in state.targets.entries)
            if (!gone.contains(id)) id: target,
        },
      );
    }
    scheduleMicrotask(_confirm);
    // The instance that was chosen is asked again, or another is chosen.
    final selected = state.selected;
    if (scope != null &&
        selected != null &&
        !state.targets.containsKey(selected)) {
      open();
    }
  }
}
