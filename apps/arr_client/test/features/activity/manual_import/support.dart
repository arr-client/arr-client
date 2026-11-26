/// Services whose manual import the test answers for.
library;

import 'dart:async';

import 'package:core/core.dart';

import '../../../app/fake_library.dart';
import '../../../app/support.dart';
import '../queue/support.dart';

/// A queue with files to import, which records what is corrected and sent.
class FakeImportQueue extends FakeQueue {
  var files = <ManualImportCandidate>[];

  /// Fails reading the files while set.
  ServiceFailure? filesFailure;

  var choices = const ImportChoices(
    qualities: [
      Quality(id: 3, name: 'WEBDL-1080p'),
      Quality(id: 7, name: 'Bluray-1080p'),
    ],
    languages: [
      Language(id: 1, name: 'English'),
      Language(id: 4, name: 'German'),
    ],
  );

  /// Each candidate the server was asked to evaluate.
  final reprocessed = <ManualImportCandidate>[];

  /// What the server makes of a candidate; as sent unless set.
  ManualImportCandidate Function(ManualImportCandidate sent)? evaluate;

  ServiceFailure? reprocessFailure;

  /// Each import sent.
  final imports = <List<ManualImportCandidate>>[];

  /// Why an import fails.
  ServiceFailure? importFailure;

  /// Holds back every import while set.
  Completer<void>? importGate;

  var fileReads = 0;

  @override
  ServiceResult<List<ManualImportCandidate>> importCandidates(
    QueueItem item,
  ) async {
    fileReads++;
    return switch (filesFailure) {
      final failure? => Err(failure),
      null => Ok(List.of(files)),
    };
  }

  @override
  ServiceResult<ImportChoices> importChoices() async => Ok(choices);

  @override
  ServiceResult<List<ManualImportCandidate>> reprocess(
    List<ManualImportCandidate> candidates,
  ) async {
    reprocessed.addAll(candidates);
    return switch (reprocessFailure) {
      final failure? => Err(failure),
      null => Ok([for (final sent in candidates) evaluate?.call(sent) ?? sent]),
    };
  }

  @override
  ServiceResult<Command> importFiles(
    List<ManualImportCandidate> candidates,
  ) async {
    imports.add(candidates);
    await importGate?.future;
    return switch (importFailure) {
      final failure? => Err(failure),
      null => const Ok(
        Command(id: 9, name: 'ManualImport', status: CommandStatus.queued),
      ),
    };
  }
}

/// Answers for the command of an import.
class FakeCommands implements CommandProvider {
  var status = CommandStatus.completed;
  String? message;
  ServiceFailure? failure;
  var reads = 0;

  @override
  ServiceResult<Command> commandStatus(int commandId) async {
    reads++;
    return switch (failure) {
      final failure? => Err(failure),
      null => Ok(
        Command(
          id: commandId,
          name: 'ManualImport',
          status: status,
          message: message,
        ),
      ),
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A library with the episodes of its series.
class FakeEpisodes extends FakeLibrary {
  FakeEpisodes({super.itemKind, super.items});

  /// By the series' id.
  final episodes = <int, List<LibraryItem>>{};

  @override
  ServiceResult<List<LibraryItem>> children(ItemRef parent) async =>
      Ok(episodes[parent.remoteId] ?? const []);
}

/// A service with a queue, a library and commands, for one instance.
class ImportModule extends FakeModule {
  ImportModule({this.kind = MediaKind.movie})
    : super(
        'media',
        offers: {
          CapabilityKind.queue,
          CapabilityKind.library,
          CapabilityKind.command,
        },
      );

  final MediaKind kind;
  final queue = FakeImportQueue();
  final commands = FakeCommands();
  late final films = FakeEpisodes(itemKind: kind);
  String? instanceId;

  ItemRef ref(int id, [MediaKind? of]) =>
      ItemRef(instanceId: instanceId!, kind: of ?? kind, remoteId: id);

  @override
  T? capability<T extends Capability>(InstanceContext context) {
    final Capability? found = switch (T) {
      const (QueueProvider) => queue,
      const (LibraryProvider) => films,
      const (CommandProvider) => commands,
      _ => null,
    };
    return found as T?;
  }
}

Movie movie(ItemRef ref, String title, {int? year = 2020}) => Movie(
  ref: ref,
  title: title,
  sortTitle: title,
  year: year,
  monitored: true,
  state: ItemState.missing,
);

Series show(ItemRef ref, String title) => Series(
  ref: ref,
  title: title,
  sortTitle: title,
  monitored: true,
  state: ItemState.missing,
);

Episode episode(ItemRef ref, int season, int number, String title) => Episode(
  ref: ref,
  title: title,
  sortTitle: title,
  seasonNumber: season,
  episodeNumber: number,
  hasFile: false,
  monitored: true,
  state: ItemState.missing,
);

ManualImportCandidate candidate(
  String name, {
  ItemRef? match,
  List<int> episodeIds = const [],
  List<String> rejections = const [],
}) => ManualImportCandidate(
  path: '/downloads/pack/$name',
  size: 1536 * 1024 * 1024,
  rawJson: const {},
  downloadId: 'download-1',
  matchedRef: match,
  episodeIds: episodeIds,
  quality: const Quality(id: 3, name: 'WEBDL-1080p'),
  languages: const [Language(id: 1, name: 'English')],
  rejections: rejections,
);
