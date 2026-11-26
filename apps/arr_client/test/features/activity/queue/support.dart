/// Services with a queue that the test answers for.
library;

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/fake_library.dart';
import '../../../app/support.dart';

/// A queue that answers what the test says and records what it was asked.
class FakeQueue implements QueueProvider {
  var items = <QueueItem>[];

  /// Fails every read while set.
  ServiceFailure? failure;

  /// Holds back every read while set.
  Completer<void>? readGate;

  /// Holds back every change while set.
  Completer<void>? writeGate;

  /// What every change answers.
  Result<void, ServiceFailure> answer = const Ok(null);

  /// How often the queue was read.
  var reads = 0;

  /// What was sent, in order.
  final writes = <String>[];

  @override
  ServiceResult<List<QueueItem>> queue() async {
    reads++;
    await readGate?.future;
    return switch (failure) {
      final failure? => Err(failure),
      null => Ok(List.of(items)),
    };
  }

  @override
  ServiceResult<void> remove(int queueId, RemoveOptions options) =>
      _write('remove $queueId ${_text(options)}');

  @override
  ServiceResult<void> removeMany(List<int> queueIds, RemoveOptions options) =>
      _write('removeMany $queueIds ${_text(options)}');

  @override
  ServiceResult<void> grabNow(int queueId) => _write('grab $queueId');

  ServiceResult<void> _write(String what) async {
    writes.add(what);
    await writeGate?.future;
    return answer;
  }

  static String _text(RemoveOptions options) =>
      'client=${options.removeFromClient} blocklist=${options.blocklist} '
      'search=${options.searchReplacement}';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A service with a queue for each of its instances.
class QueueModule extends FakeModule {
  /// With a [library], the service has one.
  QueueModule({FakeLibrary? library})
    : _library = library,
      super(
        'films',
        offers: {
          CapabilityKind.queue,
          CapabilityKind.history,
          if (library != null) CapabilityKind.library,
        },
      );

  final FakeLibrary? _library;

  /// By the instance's name.
  final queues = <String, FakeQueue>{};

  FakeQueue of(String name) => queues.putIfAbsent(name, FakeQueue.new);

  @override
  T? capability<T extends Capability>(InstanceContext context) {
    final Capability? found = switch (T) {
      const (QueueProvider) => of(context.instance.name),
      const (LibraryProvider) => _library,
      _ => null,
    };
    return found as T?;
  }
}

/// A download client that answers what the test says. It can only be read.
class FakeProgress implements DownloadProgressProvider {
  /// Set by the module once the instance is known.
  var instanceId = '';
  var torrents = <DownloadProgress>[];
  ServiceFailure? failure;
  Completer<void>? readGate;
  var reads = 0;

  @override
  ServiceResult<List<DownloadProgress>> progress() async {
    reads++;
    await readGate?.future;
    return switch (failure) {
      final failure? => Err(failure),
      null => Ok([
        for (final one in torrents)
          DownloadProgress(
            instanceId: instanceId,
            hash: one.hash,
            infohashV1: one.infohashV1,
            progress: one.progress,
            downSpeed: one.downSpeed,
            eta: one.eta,
            state: one.state,
          ),
      ]),
    };
  }
}

/// A download client for each of its instances.
class ProgressModule extends FakeModule {
  ProgressModule()
    : super('qBittorrent', offers: {CapabilityKind.downloadProgress});

  /// By the instance's name.
  final clients = <String, FakeProgress>{};

  FakeProgress of(String name) => clients.putIfAbsent(name, FakeProgress.new);

  @override
  T? capability<T extends Capability>(InstanceContext context) {
    final Capability? found = switch (T) {
      const (DownloadProgressProvider) => of(
        context.instance.name,
      )..instanceId = context.instance.id,
      _ => null,
    };
    return found as T?;
  }
}

DownloadProgress torrent(
  String hash, {
  String? infohashV1,
  double progress = 0.5,
  int speed = 0,
  Duration? eta,
  DownloadState state = DownloadState.downloading,
}) => DownloadProgress(
  instanceId: '',
  hash: hash,
  infohashV1: infohashV1,
  progress: progress,
  downSpeed: speed,
  eta: eta,
  state: state,
);

QueueItem entry(
  int id,
  String title, {
  QueueStatus status = QueueStatus.downloading,
  TrackedState trackedState = TrackedState.downloading,
  QueueSeverity severity = QueueSeverity.ok,
  List<String> messages = const [],
  String? downloadId = 'own',
  Duration? eta = const Duration(minutes: 5),
  bool needsManualImport = false,
  ItemRef? parent,
  ItemRef? itemRef,
}) {
  final delayed = status == QueueStatus.delayed;
  return QueueItem(
    id: id,
    title: title,
    status: status,
    trackedState: trackedState,
    severity: severity,
    messages: messages,
    progress: delayed ? 0 : 0.5,
    sizeLeft: delayed ? 0 : 1536 * 1024 * 1024,
    protocol: DownloadProtocol.torrent,
    downloadId: delayed
        ? null
        : downloadId == 'own'
        ? 'download-$id'
        : downloadId,
    eta: eta,
    quality: const Quality(id: 3, name: 'WEBDL-1080p'),
    downloadClient: delayed ? null : 'Torrents',
    needsManualImport: needsManualImport,
    parent: parent,
    itemRef: itemRef,
  );
}

void useScreen(WidgetTester tester, [Size size = const Size(400, 800)]) {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Lets transitions and answers finish, without reaching the next poll. Unlike
/// `pumpAndSettle` it ends while a progress bar keeps moving.
Future<void> step(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// Chooses a destination of the bottom bar.
Future<void> go(WidgetTester tester, String destination) async {
  await tester.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text(destination),
    ),
  );
  await step(tester);
}
