/// The grabs sent while the app runs. A grab downloads something, so one is
/// never sent twice by itself, also when its screen is left and opened again.
library;

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui/ui.dart';

import '../../../app/providers.dart';

/// A release as a server knows it.
typedef GrabKey = ({String instanceId, int indexerId, String guid});

/// The key of [release] on the instance [instanceId].
GrabKey grabKey(String instanceId, Release release) =>
    (instanceId: instanceId, indexerId: release.indexerId, guid: release.guid);

/// The marks of the releases that have one. It outlives the screens.
final releaseGrabsProvider =
    NotifierProvider<ReleaseGrabsController, Map<GrabKey, GrabMark>>(
      ReleaseGrabsController.new,
    );

/// Sends grabs, each once.
final class ReleaseGrabsController extends Notifier<Map<GrabKey, GrabMark>> {
  @override
  Map<GrabKey, GrabMark> build() => const {};

  /// Has [instance] download [release]. Null, with nothing sent, while a grab
  /// of it is under way or after one was accepted; found before anything is
  /// awaited, so that a second call cannot overtake the first.
  Future<Result<void, ServiceFailure>>? grab(
    ActiveInstance instance,
    Release release,
  ) {
    final key = grabKey(instance.instance.id, release);
    final before = state[key];
    if (before == GrabMark.sending || before == GrabMark.accepted) return null;
    final provider = instance.capability(CapabilityKind.release);
    // Nothing is sent for what has been edited, removed or switched away from.
    if (!instance.isCurrent || provider == null) {
      return Future.value(const Err(Unreachable()));
    }
    if (instance.instance.authFailed) {
      return Future.value(const Err(AuthFailed()));
    }
    _mark(key, GrabMark.sending);
    return _send(provider, release, key, before);
  }

  Future<Result<void, ServiceFailure>> _send(
    ReleaseProvider provider,
    Release release,
    GrabKey key,
    GrabMark? before,
  ) async {
    final log = ref.read(appServicesProvider).log;
    Result<void, ServiceFailure> result;
    try {
      result = await provider.grab(release);
    } catch (error) {
      // The type only: the text of an error may quote an address or a secret.
      log.log(LogLevel.error, 'A grab failed (${error.runtimeType})');
      result = const Err(OutcomeUnknown());
    }
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

  /// Lets the accepted releases of [instanceId] be grabbed again, for a new
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
