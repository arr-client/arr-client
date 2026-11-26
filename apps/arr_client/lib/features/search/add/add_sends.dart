/// The adds that have been sent. They outlive the screens that started them, so
/// that leaving one and coming back cannot send the same add twice.
library;

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';

/// One title on one instance.
typedef AddKey = (String instanceId, MediaKind kind, String title);

/// The key of adding [candidate] to [instanceId], by the identifier its kind of
/// server knows it by, as two searches may know different further ones.
AddKey addKey(String instanceId, AddCandidate candidate) {
  final ids = candidate.externalIds;
  final Object? id = switch (candidate.kind) {
    MediaKind.movie => ids.tmdbId,
    MediaKind.series => ids.tvdbId,
    _ => ids.musicBrainzId ?? ids.foreignId,
  };
  return (instanceId, candidate.kind, '${id ?? candidate.title}');
}

final class AddSendsState {
  const AddSendsState({this.sending = const {}, this.sent = const {}});

  /// Sent and not yet answered.
  final Set<AddKey> sending;

  /// Ever sent by this run of the app, whatever the answer: what a search said
  /// about them before may no longer hold.
  final Set<AddKey> sent;
}

final addSendsProvider = NotifierProvider<AddSends, AddSendsState>(
  AddSends.new,
);

class AddSends extends Notifier<AddSendsState> {
  @override
  AddSendsState build() => const AddSendsState();

  /// Adds [candidate] with [lookup] of [instance], once, and remembers the
  /// choices if the server accepts. Null, without sending anything, while the
  /// same title is already being added there.
  Future<Result<ItemRef, ServiceFailure>?> send(
    ActiveInstance instance,
    LookupProvider lookup,
    AddCandidate candidate,
    AddChoices choices,
  ) async {
    final id = instance.instance.id;
    final key = addKey(id, candidate);
    if (state.sending.contains(key) || !instance.isCurrent) return null;
    state = AddSendsState(
      sending: {...state.sending, key},
      sent: {...state.sent, key},
    );
    final services = ref.read(appServicesProvider);
    Result<ItemRef, ServiceFailure> result;
    try {
      result = await lookup.add(candidate, choices);
    } catch (error, stackTrace) {
      // Whether anything was sent is not known. The type only: the text of an
      // error may quote an address or a secret.
      services.log.log(
        LogLevel.error,
        'Adding failed (${error.runtimeType})',
        stackTrace: stackTrace,
      );
      result = const Err(OutcomeUnknown());
    }
    if (result is Ok) {
      try {
        await services.preferences.saveLastAddChoices(id, choices);
      } catch (error) {
        // The instance may have been removed meanwhile.
        services.log.log(
          LogLevel.warning,
          'The add choices could not be saved (${error.runtimeType})',
        );
      }
    }
    state = AddSendsState(
      sending: state.sending.difference({key}),
      sent: state.sent,
    );
    return result;
  }
}
