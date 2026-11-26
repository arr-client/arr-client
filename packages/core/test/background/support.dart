/// A registry over a database in memory, with modules whose capabilities read a
/// server held in memory. Nothing is sent anywhere.
library;

import 'dart:async';

import 'package:core/core.dart';
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart' show IconData;
import 'package:flutter_test/flutter_test.dart';

import '../artwork/support.dart';
import '../network/support.dart';
import '../registry/support.dart' show MemorySecrets;

/// The names of the reads a [FakeServer] answers.
const eventsSinceRead = 'eventsSince';
const historyRead = 'history';
const queueRead = 'queue';
const healthRead = 'health';
const requestsRead = 'requests';
const sessionRead = 'session';

/// The signed-in user of a request service, and somebody else.
const me = ServiceUser(id: 7, name: 'me');
const other = ServiceUser(id: 8, name: 'other');

/// What one server holds, and how it answers.
///
/// Its clock starts in 2001 and moves only when told, so that a position taken
/// from the device's clock misses everything.
class FakeServer {
  FakeServer(this.name);

  final String name;

  Uri get url => Uri.parse('http://$name.test');

  final events = <HistoryEvent>[];
  final queue = <QueueItem>[];
  final issues = <HealthIssue>[];
  final requests = <int, MediaRequest>{};

  var now = DateTime.utc(2001);
  var _eventId = 0;

  /// How many requests a page of the list holds.
  var requestPageSize = 20;

  /// Reads that fail.
  final failing = <String>{};

  /// Reads that throw.
  final throwing = <String>{};

  /// Every read made.
  final reads = <String>[];

  final _held = <String, Completer<void>>{};
  final _arrived = <String, Completer<void>>{};

  void goDown() => failing.addAll(const [
    eventsSinceRead,
    historyRead,
    queueRead,
    healthRead,
    requestsRead,
    sessionRead,
  ]);

  void comeUp() => failing.clear();

  /// Holds back the answers to [read] until [release].
  void hold(String read) {
    _held[read] = Completer();
    _arrived[read] = Completer();
  }

  void release(String read) => _held.remove(read)!.complete();

  /// Completes when [read], which is held, has been asked for.
  Future<void> arrival(String read) => _arrived[read]!.future;

  /// Adds a history event. Without [sameSecond] it is a second after the last.
  HistoryEvent record(
    HistoryEventType type,
    String title, {
    String? downloadId,
    bool sameSecond = false,
  }) {
    if (!sameSecond) now = now.add(const Duration(seconds: 1));
    final event = HistoryEvent(
      id: ++_eventId,
      eventType: type,
      date: now,
      sourceTitle: title,
      downloadId: downloadId,
      itemRef: ItemRef(
        instanceId: name,
        kind: MediaKind.movie,
        remoteId: _eventId,
      ),
    );
    events.add(event);
    return event;
  }

  HistoryEvent imported(String title, {bool sameSecond = false}) =>
      record(HistoryEventType.imported, title, sameSecond: sameSecond);

  HistoryEvent failed(String title, {String? downloadId}) =>
      record(HistoryEventType.failed, title, downloadId: downloadId);

  /// Puts an entry in the queue, replacing the one of the same [id].
  void download(
    int id,
    String title,
    QueueSeverity severity, {
    String? downloadId,
  }) {
    queue.removeWhere((item) => item.id == id);
    queue.add(
      QueueItem(
        id: id,
        title: title,
        status: QueueStatus.downloading,
        trackedState: TrackedState.downloading,
        severity: severity,
        progress: 0.5,
        sizeLeft: 1,
        protocol: DownloadProtocol.torrent,
        downloadId: downloadId,
      ),
    );
  }

  /// Replaces the health problems with these.
  void health(List<(String, String, HealthLevel)> now) {
    issues
      ..clear()
      ..addAll([
        for (final (source, message, level) in now)
          HealthIssue(source: source, level: level, message: message),
      ]);
  }

  /// Adds a request, or changes the one of the same [id].
  void request(
    int id, {
    ServiceUser by = other,
    RequestStatus status = RequestStatus.pending,
    Availability availability = Availability.unknown,
  }) => requests[id] = MediaRequest(
    id: id,
    titleRef: DiscoveryRef(mediaType: DiscoveryMediaType.movie, tmdbId: id),
    requestedBy: by,
    status: status,
    availability: availability,
    is4k: false,
  );

  ServiceResult<T> _answer<T>(String read, T Function() value) async {
    reads.add(read);
    final arrived = _arrived[read];
    if (arrived != null && !arrived.isCompleted) arrived.complete();
    await _held[read]?.future;
    if (throwing.contains(read)) throw StateError('broken');
    if (failing.contains(read)) return const Err(Unreachable());
    return Ok(value());
  }

  /// Newest first.
  List<HistoryEvent> get _newestFirst => events.reversed.toList();
}

class _History implements HistoryProvider {
  _History(this.server);

  final FakeServer server;

  @override
  ServiceResult<ResultPage<HistoryEvent>> history({
    MediaTarget? target,
    int page = 1,
  }) => server._answer(historyRead, () => _page(server._newestFirst, page, 20));

  /// As the real servers: asking since a reported time, which is in whole
  /// seconds, leaves out that whole second.
  @override
  ServiceResult<List<HistoryEvent>> eventsSince(DateTime since) {
    final second = since.millisecondsSinceEpoch ~/ 1000;
    return server._answer(
      eventsSinceRead,
      () => [
        for (final event in server._newestFirst)
          if (event.date.millisecondsSinceEpoch ~/ 1000 > second) event,
      ],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Queue implements QueueProvider {
  _Queue(this.server);

  final FakeServer server;

  @override
  ServiceResult<List<QueueItem>> queue() =>
      server._answer(queueRead, () => [...server.queue]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Health implements HealthProvider {
  _Health(this.server);

  final FakeServer server;

  @override
  ServiceResult<List<HealthIssue>> health() =>
      server._answer(healthRead, () => [...server.issues]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Requests implements RequestProvider {
  _Requests(this.server);

  final FakeServer server;

  @override
  ServiceResult<SessionUser> session() => server._answer(
    sessionRead,
    () => SessionUser(id: me.id, name: me.name, permissions: const {}),
  );

  /// Newest first.
  @override
  ServiceResult<ResultPage<MediaRequest>> list({int page = 1}) =>
      server._answer(requestsRead, () {
        final all = server.requests.values.toList()
          ..sort((a, b) => b.id.compareTo(a.id));
        return _page(all, page, server.requestPageSize);
      });

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ResultPage<T> _page<T>(List<T> all, int page, int size) => ResultPage(
  items: all.skip((page - 1) * size).take(size).toList(),
  page: page,
  hasMore: all.length > page * size,
);

const _arrKinds = <CapabilityKind>{
  CapabilityKind.history,
  CapabilityKind.queue,
  CapabilityKind.health,
};
const _requestKinds = <CapabilityKind>{CapabilityKind.request};

class _Module implements ServiceModule {
  _Module(this.id, this.kinds, this.servers);

  @override
  final String id;

  final Set<CapabilityKind> kinds;
  final Map<Uri, FakeServer> servers;

  @override
  ModuleDescriptor get descriptor => ModuleDescriptor(
    displayName: id,
    icon: const IconData(0),
    category: ModuleCategory.movies,
    authKinds: const [AuthKind.apiKey],
    apiKeyHeader: apiKeyHeader,
    defaultPort: 80,
    minimumVersion: '1',
    testedVersion: '1',
  );

  @override
  SessionHandler? get sessionHandler => null;

  @override
  Set<CapabilityKind> capabilitiesFor(
    ProbeResult probe,
    SessionInfo? session,
  ) => kinds;

  @override
  T? capability<T extends Capability>(InstanceContext context) {
    final server = servers[context.instance.url]!;
    final Capability? found = switch (T) {
      const (HistoryProvider) => _History(server),
      const (QueueProvider) => _Queue(server),
      const (HealthProvider) => _Health(server),
      const (RequestProvider) => _Requests(server),
      _ => null,
    };
    return found as T?;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Navigator implements AppNavigator {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The app's records, with the steps the app takes around the engine.
class World {
  World._();

  final servers = <Uri, FakeServer>{};
  final database = AppDatabase(NativeDatabase.memory());
  final log = DiagnosticLog();
  final secrets = MemorySecrets();
  final directory = temporaryDirectory();

  late final _modules = [
    _Module('arr', _arrKinds, servers),
    _Module('requests', _requestKinds, servers),
  ];
  late final preferences = PreferencesRepository(database);
  late final profiles = ProfileRepository(
    database: database,
    secrets: secrets,
    log: log,
    preferences: preferences,
    modules: _modules,
  );
  late final InstanceRegistry registry;

  /// The profile made at first launch.
  late final String home;

  static Future<World> start() async {
    final world = World._();
    addTearDown(world.database.close);
    await world.profiles.ensureDefaultProfile();
    world.home = (await world.profiles.profiles()).single.id;
    world.registry = InstanceRegistry(
      modules: ModuleRegistry(world._modules),
      profiles: world.profiles,
      preferences: world.preferences,
      cache: CacheRepository(world.database),
      artwork: cacheIn(world.directory),
      navigator: _Navigator(),
      log: world.log,
      localNetwork: FakePermission(),
    );
    addTearDown(world.registry.close);
    await world.registry.start();
    return world;
  }

  /// A new one each time, as the background isolate may be new at every check.
  NotificationEngine get engine =>
      NotificationEngine(database: database, log: log);

  Future<String> profile(String name) async => ((await profiles.createProfile(
    name,
  )) as Ok<Profile, RuleViolation>).value.id;

  InstanceDraft _draft(
    String name,
    String serviceType,
    Uri url, {
    bool enabled = true,
  }) => InstanceDraft(
    name: name,
    serviceType: serviceType,
    url: url,
    authKind: AuthKind.apiKey,
    enabled: enabled,
    probe: ProbeSnapshot(
      product: 'Fake',
      version: '1',
      capabilities: serviceType == 'arr' ? _arrKinds : _requestKinds,
    ),
  );

  /// Adds an instance of [server] and returns its id.
  Future<String> add(
    FakeServer server, {
    String serviceType = 'arr',
    String? profileId,
  }) async {
    servers[server.url] = server;
    final added = await profiles.addInstance(
      profileId ?? home,
      _draft(server.name, serviceType, server.url),
      credential: const Credential(apiKey: apiKey),
    );
    await registry.refresh();
    return (added as Ok<Instance, RuleViolation>).value.id;
  }

  ActiveInstance active(String id) => registry.scope!.instance(id)!;

  Future<void> subscribe(
    String id, [
    Iterable<NotificationEventType> types = NotificationEventType.values,
  ]) async {
    for (final type in types) {
      await engine.subscribe(active(id), type);
    }
  }

  Future<List<Notice>> check() => engine.check(registry.scope!);

  /// Switches profile and initialises its instances, as the app does.
  Future<void> activate(String profileId) async {
    await registry.switchTo(profileId);
    await engine.initialise(registry.scope!.instances);
  }

  /// Disables an instance, or enables it and initialises it, as the app does.
  Future<void> setEnabled(String id, bool enabled) async {
    final instance = (await profiles.instance(id))!;
    final result = await profiles.updateInstance(
      id,
      _draft(
        instance.name,
        instance.serviceType,
        instance.url,
        enabled: enabled,
      ),
    );
    expect(result, isA<Ok<Instance, RuleViolation>>());
    await registry.refresh();
    if (enabled) await engine.initialise([active(id)]);
  }
}

/// What a notice is about, in few words.
String describe(Notice notice) => switch (notice) {
  ImportedNotice(:final event) => 'imported ${event.sourceTitle}',
  DownloadProblemNotice(:final title) => 'problem $title',
  HealthNotice(:final issue) => 'health ${issue.message} ${issue.level.name}',
  PendingRequestNotice(:final request) => 'pending ${request.id}',
  OwnRequestNotice(:final request) =>
    'own ${request.id} ${request.status.name} ${request.availability.name}',
  SummaryNotice(:final count) => 'summary $count',
};

List<String> described(List<Notice> notices) => notices.map(describe).toList();
