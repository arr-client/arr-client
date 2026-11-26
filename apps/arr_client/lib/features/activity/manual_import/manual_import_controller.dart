/// What the manual import of one download reads and sends.
library;

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/widgets.dart'
    show AppLifecycleListener, AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../queue/queue_controller.dart';
import 'import_file.dart';

/// How long after an answer the import's command is asked for again
/// (research R11).
const importCommandPollInterval = Duration(seconds: 2);

/// One download of one instance. An edited instance has another client, so
/// that nothing read or chosen through the old one is sent through the new.
typedef ManualImportKey = ({String instanceId, Object client, QueueItem item});

/// The manual import of one download, while its screen is open.
final manualImportProvider = NotifierProvider.autoDispose
    .family<ManualImportController, ManualImportState, ManualImportKey>(
      ManualImportController.new,
    );

/// Whether the files of [instance] need episodes besides a series. Null if
/// this app cannot import for it.
bool? importNeedsEpisodes(ActiveInstance instance) =>
    switch (instance.capability(CapabilityKind.library)?.itemKind) {
      MediaKind.movie => false,
      MediaKind.series => true,
      _ => null,
    };

/// What is known of a download's files and of an import of them.
final class ManualImportState {
  const ManualImportState({
    this.needsEpisodes = false,
    this.files,
    this.fetchedAt,
    this.failure,
    this.loading = true,
    this.choices,
    this.choicesFailure,
    this.items,
    this.itemsFailure,
    this.episodes = const {},
    this.episodeFailures = const {},
    this.sending = false,
    this.outcomeUnknown = false,
    this.command,
    this.commandFailure,
  });

  /// Whether a file needs episodes besides its series.
  final bool needsEpisodes;

  /// The files as last read, with the user's corrections; null if no read has
  /// succeeded.
  final List<ImportFile>? files;

  /// When [files] was read.
  final DateTime? fetchedAt;

  /// Why reading the files last failed; null if it succeeded.
  final ServiceFailure? failure;

  /// Whether the files are being read.
  final bool loading;

  final ImportChoices? choices;
  final ServiceFailure? choicesFailure;

  /// The movies or series of the library; null until read.
  final List<LibraryItem>? items;
  final ServiceFailure? itemsFailure;

  /// The episodes of the series that were needed, by the series' id.
  final Map<int, List<Episode>> episodes;
  final Map<int, ServiceFailure> episodeFailures;

  /// Whether an import is being sent.
  final bool sending;

  /// Whether an import was sent of which it is not known whether the server
  /// received it.
  final bool outcomeUnknown;

  /// The command of the accepted import, as last read.
  final Command? command;

  /// Why [command] could not be read again.
  final ServiceFailure? commandFailure;

  /// Whether an accepted import has not finished, as far as is known.
  bool get commandRunning => !(command?.isFinished ?? true);

  /// Whether the files shown may no longer be what the server has.
  bool get isStale => failure != null;

  /// Whether a correction or an import may be made.
  bool get canChange => !loading && !isStale && !sending && !commandRunning;

  /// The item that [ref] names, if it was read.
  LibraryItem? item(ItemRef ref) =>
      items?.where((item) => item.ref == ref).firstOrNull;

  /// The episode [id] of [series], if it was read.
  Episode? episode(ItemRef series, int id) => episodes[series.remoteId]
      ?.where((episode) => episode.ref.remoteId == id)
      .firstOrNull;

  /// Whether [candidate] says enough to be imported, in words the user has
  /// seen: its movie, or its series and episodes.
  bool isReady(ManualImportCandidate candidate) {
    final match = candidate.matchedRef;
    if (match == null || item(match) == null) return false;
    return !needsEpisodes ||
        (candidate.episodeIds.isNotEmpty &&
            candidate.episodeIds.every((id) => episode(match, id) != null));
  }

  /// Whether [file] can be marked together with the others, without being
  /// looked at on its own.
  bool isReadyUnrejected(ImportFile file) =>
      !file.isRejected && isReady(file.candidate);

  /// The files marked for import, if every one of them can be imported now;
  /// otherwise none.
  List<ImportFile> get importable {
    final selected = [
      for (final file in files ?? const <ImportFile>[])
        if (file.selected) file,
    ];
    return canChange &&
            selected.every((f) => !f.checking && isReady(f.candidate))
        ? selected
        : const [];
  }
}

/// Reads the files of a download, has corrections evaluated and sends an
/// import. No write is ever sent a second time.
final class ManualImportController extends Notifier<ManualImportState> {
  ManualImportController(this.key);

  final ManualImportKey key;

  var _needsEpisodes = false;
  List<ImportFile>? _files;
  DateTime? _fetchedAt;
  ServiceFailure? _failure;
  var _loading = true;
  ImportChoices? _choices;
  ServiceFailure? _choicesFailure;
  List<LibraryItem>? _items;
  ServiceFailure? _itemsFailure;
  final _episodes = <int, List<Episode>>{};
  final _episodeFailures = <int, ServiceFailure>{};
  final _readingEpisodes = <int>{};
  var _sending = false;
  var _outcomeUnknown = false;
  Command? _command;
  ServiceFailure? _commandFailure;
  Timer? _timer;
  var _foreground = true;
  var _readingCommand = false;

  /// Counts the reads of the files, so that what belongs to an older one is
  /// dropped.
  var _generation = 0;

  /// Counts the times the episodes were forgotten, so that a read begun before
  /// is dropped.
  var _episodeEpoch = 0;

  @override
  ManualImportState build() {
    final lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        _foreground =
            state == AppLifecycleState.resumed ||
            state == AppLifecycleState.inactive;
        if (!_foreground) {
          _timer?.cancel();
        } else if (_commandFailure == null) {
          unawaited(_follow());
        }
      },
    );
    ref.onDispose(() {
      _timer?.cancel();
      lifecycle.dispose();
    });
    final active = _active();
    _needsEpisodes = active != null && (importNeedsEpisodes(active) ?? false);
    // Not at once: there is no state to change until this returns.
    scheduleMicrotask(() {
      if (ref.mounted) unawaited(reload());
    });
    return ManualImportState(needsEpisodes: _needsEpisodes);
  }

  /// Reads the files, and whatever else is still missing, from the server.
  /// Corrections and the selection are those of what was read before, and go
  /// with it.
  Future<void> reload() async {
    if (!ref.mounted) return;
    final generation = ++_generation;
    _loading = true;
    _episodeFailures.clear();
    _publish();
    unawaited(_readChoices());
    unawaited(_readItems());
    final result = await _read(
      CapabilityKind.queue,
      (queue) => queue.importCandidates(key.item),
    );
    if (result == null || generation != _generation) return;
    _loading = false;
    switch (result) {
      case Ok(:final value):
        // An import or the server may have changed them.
        _episodes.clear();
        _episodeFailures.clear();
        _readingEpisodes.clear();
        _episodeEpoch++;
        _files = [for (final candidate in value) ImportFile(candidate)];
        _fetchedAt = DateTime.now();
        _failure = null;
      case Err(:final error):
        _failure = error;
    }
    _publish();
    _readEpisodes();
  }

  /// Reads again at the user's request what could not be read. After a
  /// rejected sign-in this also has the instance try again.
  Future<void> retry() async {
    final services = ref.read(appServicesProvider);
    try {
      final active = _active();
      if (active != null &&
          (active.instance.authFailed || _failure is AuthFailed)) {
        await services.profiles.retryAuth(key.instanceId);
        await services.registry.refresh();
      }
    } catch (error) {
      services.log.log(
        LogLevel.warning,
        'A sign-in could not be retried (${error.runtimeType})',
      );
    }
    if (!ref.mounted) return;
    if (_failure != null || _files == null) return reload();
    // The files and their corrections stay.
    _episodeFailures.clear();
    _publish();
    unawaited(_readChoices());
    unawaited(_readItems());
    _readEpisodes();
  }

  /// Marks the file at [path] for import, or not.
  void select(String path, bool selected) => _change(
    path,
    (file) => file.withSelected(selected && state.isReady(file.candidate)),
  );

  /// Marks every file that can be imported and that the server did not reject,
  /// or none.
  void selectAll(bool selected) {
    _files = [
      for (final file in _files ?? const <ImportFile>[])
        file.withSelected(selected && state.isReadyUnrejected(file)),
    ];
    _publish();
  }

  /// Applies a correction and, once the file has all the server needs, has the
  /// server evaluate it. If it cannot, the correction stays.
  Future<void> correct(
    String path, {
    ItemRef? matchedRef,
    List<int>? episodeIds,
    Quality? quality,
    List<Language>? languages,
  }) async {
    final before = _files?.where((file) => file.path == path).firstOrNull;
    if (before == null || before.checking || !state.canChange) return;
    final candidate = correctedCandidate(
      before.candidate,
      matchedRef: matchedRef,
      episodeIds: episodeIds,
      quality: quality,
      languages: languages,
    );
    // The server fails on a file without its movie, series or episodes.
    final complete =
        candidate.matchedRef != null &&
        (!_needsEpisodes || candidate.episodeIds.isNotEmpty);
    final generation = _generation;
    // Kept until the server says otherwise.
    final earlier = before.candidate.rejections.isNotEmpty
        ? before.candidate.rejections
        : before.earlierRejections;
    // A file that lost its episodes cannot stay selected.
    _change(
      path,
      (file) => ImportFile(
        candidate,
        // Its episodes may still be on the way.
        selected:
            file.selected &&
            (!_needsEpisodes || candidate.episodeIds.isNotEmpty),
        checking: complete,
        unchecked: true,
        earlierRejections: earlier,
      ),
    );
    _readEpisodes();
    if (!complete) return;

    final result = await _send(
      (queue) => queue.reprocess([candidate]),
      'A manual import could not be checked',
    );
    if (!ref.mounted || generation != _generation) return;
    final answer = switch (result) {
      Ok(:final value) => value.where((c) => c.path == path).firstOrNull,
      Err() => null,
    };
    _change(path, (file) {
      if (answer == null) {
        return ImportFile(
          candidate,
          selected: file.selected,
          unchecked: true,
          earlierRejections: earlier,
          checkFailure: switch (result) {
            Err(:final error) => error,
            Ok() => const MalformedResponse(),
          },
        );
      }
      final dropped = _needsEpisodes && answer.episodeIds.isEmpty;
      return ImportFile(
        answer,
        selected: file.selected && answer.matchedRef != null && !dropped,
        episodesDropped: dropped,
      );
    });
    _readEpisodes();
  }

  /// Sends the import of [candidates], once.
  ServiceResult<Command> importFiles(
    List<ManualImportCandidate> candidates,
  ) async {
    if (!state.canChange) return const Err(Unreachable());
    final queue = ref.read(queueProvider.notifier);
    _sending = true;
    _outcomeUnknown = false;
    _command = null;
    _commandFailure = null;
    _publish();
    final result = await _send(
      (provider) => provider.importFiles(candidates),
      'A manual import failed',
    );
    // The queue may be gone with the profile, and then reads nothing.
    unawaited(queue.refresh(key.instanceId));
    if (!ref.mounted) return result;
    _sending = false;
    switch (result) {
      case Ok(:final value):
        _command = value;
        // So that the same files are not sent again by mistake.
        _files = [
          for (final file in _files ?? const <ImportFile>[])
            file.withSelected(false),
        ];
      case Err(error: OutcomeUnknown()):
        _outcomeUnknown = true;
      case Err():
        break;
    }
    _publish();
    if (result case Ok(:final value)) {
      if (value.isFinished) {
        unawaited(reload());
      } else {
        _schedule();
      }
    }
    return result;
  }

  /// Reads the command again at the user's request, after that failed.
  Future<void> checkCommand() {
    _commandFailure = null;
    _publish();
    return _follow();
  }

  void _schedule() {
    _timer?.cancel();
    if (_foreground) {
      _timer = Timer(importCommandPollInterval, () => unawaited(_follow()));
    }
  }

  Future<void> _follow() async {
    _timer?.cancel();
    final command = _command;
    if (command == null || command.isFinished || _readingCommand) return;
    // Without a way to follow it, how it ends is not known.
    if (_active()?.capability(CapabilityKind.command) == null) {
      _command = _lost(command);
      _publish();
      return;
    }
    _readingCommand = true;
    final result = await _read(
      CapabilityKind.command,
      (commands) => commands.commandStatus(command.id),
    );
    _readingCommand = false;
    if (result == null || !identical(command, _command)) return;
    switch (result) {
      case Ok(:final value):
        _command = value;
        _commandFailure = null;
      // The server forgets finished commands.
      case Err(error: NotFound()):
        _command = _lost(command);
      case Err(:final error):
        _commandFailure = error;
    }
    _publish();
    if (_command?.isFinished ?? false) {
      unawaited(ref.read(queueProvider.notifier).refresh(key.instanceId));
      await reload();
    } else if (_commandFailure == null) {
      _schedule();
    }
  }

  static Command _lost(Command command) => Command(
    id: command.id,
    name: command.name,
    status: CommandStatus.unknown,
  );

  /// Choices read before stay where reading them again fails.
  Future<void> _readChoices() async {
    _choicesFailure = null;
    final result = await _read(
      CapabilityKind.queue,
      (queue) => queue.importChoices(),
    );
    if (result == null) return;
    switch (result) {
      case Ok(:final value):
        _choices = value;
        _choicesFailure = null;
      case Err(:final error):
        _choicesFailure = error;
    }
    _publish();
  }

  Future<void> _readItems() async {
    _itemsFailure = null;
    final result = await _read(
      CapabilityKind.library,
      (library) => library.list(),
    );
    if (result == null) return;
    switch (result) {
      case Ok(:final value):
        _items = [...value]
          ..sort(
            (a, b) =>
                a.sortTitle.toLowerCase().compareTo(b.sortTitle.toLowerCase()),
          );
        _itemsFailure = null;
      case Err(:final error):
        _itemsFailure = error;
    }
    _publish();
  }

  /// Reads the episodes of the series the files are matched to, where they are
  /// not yet known.
  void _readEpisodes() {
    if (!_needsEpisodes) return;
    for (final file in _files ?? const <ImportFile>[]) {
      final series = file.candidate.matchedRef;
      if (series == null) continue;
      final id = series.remoteId;
      if (_episodes.containsKey(id) ||
          _episodeFailures.containsKey(id) ||
          !_readingEpisodes.add(id)) {
        continue;
      }
      unawaited(_readEpisodesOf(series));
    }
  }

  Future<void> _readEpisodesOf(ItemRef series) async {
    final epoch = _episodeEpoch;
    final result = await _read(
      CapabilityKind.library,
      (library) => library.children(series),
    );
    if (epoch != _episodeEpoch) return;
    _readingEpisodes.remove(series.remoteId);
    if (result == null) return;
    switch (result) {
      case Ok(:final value):
        _episodes[series.remoteId] = value.whereType<Episode>().toList()
          ..sort((a, b) {
            final bySeason = a.seasonNumber.compareTo(b.seasonNumber);
            return bySeason != 0
                ? bySeason
                : a.episodeNumber.compareTo(b.episodeNumber);
          });
      case Err(:final error):
        _episodeFailures[series.remoteId] = error;
    }
    _publish();
  }

  /// The instance, while it is still the one this was made for.
  ActiveInstance? _active() {
    final active = ref
        .read(appServicesProvider)
        .registry
        .scope
        ?.instance(key.instanceId);
    return active != null && identical(active.context.http, key.client)
        ? active
        : null;
  }

  /// One read, or null if there is no answer to show.
  Future<Result<T, ServiceFailure>?> _read<C extends Capability, T>(
    CapabilityKind<C> kind,
    ServiceResult<T> Function(C provider) read,
  ) async {
    if (!ref.mounted) return null;
    final active = _active();
    final provider = active?.capability(kind);
    if (active == null || provider == null) return null;
    final log = ref.read(appServicesProvider).log;
    Result<T, ServiceFailure> result;
    if (active.instance.authFailed) {
      result = Err<T, ServiceFailure>(const AuthFailed());
    } else {
      try {
        result = await read(provider);
      } catch (error) {
        // The type only: the text of an error may quote an address or a secret.
        log.log(LogLevel.error, 'An import read failed (${error.runtimeType})');
        result = Err<T, ServiceFailure>(const MalformedResponse());
      }
    }
    return ref.mounted && _active() != null ? result : null;
  }

  /// One write, sent once.
  ServiceResult<T> _send<T>(
    ServiceResult<T> Function(QueueProvider queue) send,
    String failed,
  ) async {
    final active = _active();
    final provider = active?.capability(CapabilityKind.queue);
    // Nothing is sent for what has been edited, removed or switched away from.
    if (active == null || !active.isCurrent || provider == null) {
      return Err<T, ServiceFailure>(const Unreachable());
    }
    final log = ref.read(appServicesProvider).log;
    try {
      return await send(provider);
    } catch (error) {
      log.log(LogLevel.error, '$failed (${error.runtimeType})');
      return Err<T, ServiceFailure>(const OutcomeUnknown());
    }
  }

  void _change(String path, ImportFile Function(ImportFile file) change) {
    _files = [
      for (final file in _files ?? const <ImportFile>[])
        file.path == path ? change(file) : file,
    ];
    _publish();
  }

  void _publish() {
    if (!ref.mounted) return;
    final files = _files;
    state = ManualImportState(
      needsEpisodes: _needsEpisodes,
      files: files == null ? null : List.unmodifiable(files),
      fetchedAt: _fetchedAt,
      failure: _failure,
      loading: _loading,
      choices: _choices,
      choicesFailure: _choicesFailure,
      items: _items,
      itemsFailure: _itemsFailure,
      episodes: {..._episodes},
      episodeFailures: {..._episodeFailures},
      sending: _sending,
      outcomeUnknown: _outcomeUnknown,
      command: _command,
      commandFailure: _commandFailure,
    );
  }
}
