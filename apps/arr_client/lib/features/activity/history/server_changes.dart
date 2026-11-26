/// The changes to histories and blocklists: marking a download as failed and
/// removing blocked releases. Each is sent once and never again.
library;

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';

/// What a change is about: a history event or a blocklist entry.
enum ChangeKind { markFailed, unblock }

/// An event or entry of the instance whose client [client] is.
typedef ChangeTarget = ({Object client, ChangeKind kind, int id});

/// Kept for as long as the app runs, so that leaving a screen and coming back
/// does not offer again what is still being sent.
final serverChangesProvider =
    NotifierProvider<ServerChanges, ServerChangesState>(ServerChanges.new);

/// What is being sent, and how much has been answered.
final class ServerChangesState {
  const ServerChangesState({this.sending = const {}, this.answered = const {}});

  /// Nothing may be sent for these again until the server has answered.
  final Set<ChangeTarget> sending;

  /// How many changes each client has had an answer to, whatever it was.
  /// Whoever shows what that instance has reads it again when this grows.
  final Map<Object, int> answered;

  bool isSending(ActiveInstance instance, ChangeKind kind, int id) =>
      sending.contains((client: instance.context.http, kind: kind, id: id));
}

final class ServerChanges extends Notifier<ServerChangesState> {
  @override
  ServerChangesState build() => const ServerChangesState();

  /// Marks the grab of [eventId] as failed. [affected] is every event known to
  /// be of the same download, [eventId] included.
  ServiceResult<void> markFailed(
    ActiveInstance instance,
    int eventId, {
    required Set<int> affected,
  }) => _send(
    instance,
    ChangeKind.markFailed,
    affected,
    (provider) => provider.markFailed(eventId),
  );

  /// Removes [entryIds] from the blocklist of [instance].
  ServiceResult<void> unblock(ActiveInstance instance, List<int> entryIds) =>
      _send(
        instance,
        ChangeKind.unblock,
        entryIds.toSet(),
        (provider) => provider.unblock(entryIds),
      );

  ServiceResult<void> _send(
    ActiveInstance instance,
    ChangeKind kind,
    Set<int> ids,
    ServiceResult<void> Function(HistoryProvider provider) send,
  ) async {
    final provider = instance.capability(CapabilityKind.history);
    // Nothing is sent for what has been edited, removed or switched away from.
    if (!instance.isCurrent || provider == null) {
      return const Err(Unreachable());
    }
    final log = ref.read(appServicesProvider).log;
    final client = instance.context.http;
    final targets = {
      for (final id in ids) (client: client, kind: kind, id: id),
    };
    state = ServerChangesState(
      sending: {...state.sending, ...targets},
      answered: state.answered,
    );
    try {
      return await send(provider);
    } catch (error) {
      // The type only: the text of an error may quote an address or a secret.
      log.log(LogLevel.error, 'A history change failed (${error.runtimeType})');
      return const Err(OutcomeUnknown());
    } finally {
      // At once, so that what is read again is under way before the targets
      // are offered again.
      state = ServerChangesState(
        sending: state.sending.difference(targets),
        answered: {
          ...state.answered,
          client: (state.answered[client] ?? 0) + 1,
        },
      );
    }
  }
}
