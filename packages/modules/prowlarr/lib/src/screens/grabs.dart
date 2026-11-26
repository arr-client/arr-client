/// The grabs sent while the app runs. A grab downloads something, so one is
/// never sent twice by itself, also when its screen is left and opened again.
library;

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui/ui.dart';

import 'prowlarr_source.dart';

/// A result as a server knows it. The guid can hold a key: it stays in memory
/// and is never shown or logged.
typedef GrabKey = ({String instanceId, int indexerId, String guid});

/// The key of [release] on the instance [instanceId].
GrabKey grabKey(String instanceId, Release release) =>
    (instanceId: instanceId, indexerId: release.indexerId, guid: release.guid);

/// The marks of the results that have one. It outlives the screens.
final grabsProvider = NotifierProvider<GrabsController, Map<GrabKey, GrabMark>>(
  GrabsController.new,
);

/// Sends grabs, each once.
final class GrabsController extends Notifier<Map<GrabKey, GrabMark>> {
  @override
  Map<GrabKey, GrabMark> build() => const {};

  /// Has the server download [release]. Null, with nothing sent, while a grab
  /// of it is under way or after one was accepted; found before anything is
  /// awaited, so that a second call cannot overtake the first.
  Future<Result<void, ServiceFailure>>? grab(
    ProwlarrSource source,
    Release release,
  ) {
    final key = grabKey(source.instanceId, release);
    final before = state[key];
    if (before == GrabMark.sending || before == GrabMark.accepted) return null;
    _mark(key, GrabMark.sending);
    return _send(source, release, key, before);
  }

  Future<Result<void, ServiceFailure>> _send(
    ProwlarrSource source,
    Release release,
    GrabKey key,
    GrabMark? before,
  ) async {
    final result = await source.guard(
      () => source.provider.grab(release),
      otherwise: const OutcomeUnknown(),
    );
    if (ref.mounted) {
      _mark(key, switch (result) {
        Ok() => GrabMark.accepted,
        Err(error: OutcomeUnknown()) => GrabMark.unknown,
        // A failure says nothing about an earlier grab.
        Err() => before,
      });
    }
    return result;
  }

  /// Lets the accepted results of [instanceId] be grabbed again, for a new
  /// search. Unknown outcomes stay known, and are confirmed before a grab.
  void forgetAccepted(String instanceId) {
    bool forgotten(GrabKey key, GrabMark mark) =>
        key.instanceId == instanceId && mark == GrabMark.accepted;
    if (state.entries.any((entry) => forgotten(entry.key, entry.value))) {
      state = {...state}..removeWhere(forgotten);
    }
  }

  void _mark(GrabKey key, GrabMark? mark) {
    final marks = {...state};
    if (mark == null) {
      marks.remove(key);
    } else {
      marks[key] = mark;
    }
    state = marks;
  }
}
