/// Which episodes the events of a series' history are about.
library;

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import 'item_history_controller.dart';

/// The episodes of the series whose history is open, by their keys. Empty for
/// any other item, and until they are known.
final historyEpisodesProvider = NotifierProvider.autoDispose
    .family<HistoryEpisodes, Map<ItemRef, Episode>, ItemHistoryKey>(
      HistoryEpisodes.new,
    );

/// Takes the episodes as last saved, and asks for them again each time the
/// history is read from the start. A read that fails leaves what is had: the
/// history is shown without the codes it cannot tell.
final class HistoryEpisodes extends Notifier<Map<ItemRef, Episode>> {
  HistoryEpisodes(this.key);

  final ItemHistoryKey key;

  /// Counts the reads from the server, so that an older answer is dropped.
  var _generation = 0;

  /// Whether the server has answered, which saved episodes must not replace.
  var _answered = false;

  @override
  Map<ItemRef, Episode> build() {
    _answered = false;
    if (key.item.kind != MediaKind.series) return const {};
    ref.listen(
      itemHistoryProvider(key).select((history) => history.fetchedAt),
      (_, fetchedAt) {
        if (fetchedAt != null) unawaited(_read());
      },
      fireImmediately: true,
    );
    unawaited(_readSaved());
    return const {};
  }

  Future<void> _readSaved() async {
    final saved = await _ask(
      (library) async => switch (await library.cachedChildren(key.item)) {
        Ok(:final value) => value?.value,
        Err() => null,
      },
    );
    if (saved != null && !_answered) state = _byRef(saved);
  }

  Future<void> _read() async {
    final generation = ++_generation;
    final read = await _ask(
      (library) async => switch (await library.children(key.item)) {
        Ok(:final value) => value,
        Err() => null,
      },
    );
    if (read == null || generation != _generation) return;
    _answered = true;
    state = _byRef(read);
  }

  /// What [read] gives of the instance's library, or null if there is no
  /// answer to use.
  Future<List<LibraryItem>?> _ask(
    Future<List<LibraryItem>?> Function(LibraryProvider library) read,
  ) async {
    // Not at once: there is no state to change until [build] returns.
    await null;
    if (!ref.mounted) return null;
    final services = ref.read(appServicesProvider);
    final log = services.log;
    final active = services.registry.scope?.instance(key.item.instanceId);
    if (active == null ||
        !identical(active.context.http, key.client) ||
        active.instance.authFailed) {
      return null;
    }
    try {
      final library = active.capability(CapabilityKind.library);
      if (library == null) return null;
      final items = await read(library);
      return ref.mounted && active.isCurrent ? items : null;
    } catch (error) {
      // The type only: the text of an error may quote an address or a secret.
      log.log(LogLevel.error, 'An episode read failed (${error.runtimeType})');
      return null;
    }
  }

  static Map<ItemRef, Episode> _byRef(List<LibraryItem> items) => {
    for (final item in items)
      if (item is Episode) item.ref: item,
  };
}
