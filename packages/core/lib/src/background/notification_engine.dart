import 'package:drift/drift.dart';

import '../logging/log_level.dart';
import '../logging/logger.dart';
import '../models/availability.dart';
import '../models/health_level.dart';
import '../models/history_event.dart';
import '../models/history_event_type.dart';
import '../models/media_request.dart';
import '../models/queue_item.dart';
import '../models/queue_severity.dart';
import '../models/request_status.dart';
import '../models/result_page.dart';
import '../module/capabilities/history_provider.dart';
import '../module/capability_kind.dart';
import '../module/result.dart';
import '../module/service_result.dart';
import '../preferences/preferences_repository.dart';
import '../registry/active_instance.dart';
import '../registry/profile_scope.dart';
import '../storage/database.dart';
import 'event_marker.dart';
import 'notice.dart';
import 'notification_event_type.dart';

/// Finds what to notify of, from capabilities only (data-model.md
/// NotificationSubscription and EventMarker).
///
/// It keeps nothing in memory between calls: the background isolate has its own
/// database connection and may be new at every check.
///
/// A marker says what has been seen of one event type of one instance. Without
/// one, the next successful read takes the current state as seen and notifies
/// nothing. A read that fails does not move it past what was missed.
class NotificationEngine {
  /// Creates a [NotificationEngine].
  NotificationEngine({required this._database, required this._log});

  final AppDatabase _database;
  final Logger _log;

  /// More events of one instance than this in one check become a summary.
  static const _mostNotices = 5;

  /// A server leaves out the whole second it is asked since, so this is taken
  /// off the date of the cursor, and what was seen already is told by its id.
  static const _sinceMargin = Duration(seconds: 1);

  /// The event types [instance] can notify of, by what it offers.
  Set<NotificationEventType> offered(ActiveInstance instance) {
    final kinds = instance.capabilities;
    final requests = kinds.contains(CapabilityKind.request);
    final history = kinds.contains(CapabilityKind.history);
    return {
      for (final type in NotificationEventType.values)
        if (switch (type) {
          NotificationEventType.imported => history,
          NotificationEventType.downloadProblem =>
            history || kinds.contains(CapabilityKind.queue),
          NotificationEventType.healthIssue => kinds.contains(
            CapabilityKind.health,
          ),
          NotificationEventType.pendingRequest ||
          NotificationEventType.ownRequestUpdate => requests,
        })
          type,
    };
  }

  /// The events the user has enabled for an instance.
  Future<Set<NotificationEventType>> subscribed(String instanceId) async {
    final rows =
        await (_database.select(_database.notificationSubscriptions)..where(
              (row) =>
                  row.instanceId.equals(instanceId) & row.enabled.equals(true),
            ))
            .get();
    final names = {for (final row in rows) row.eventType};
    return {
      for (final type in NotificationEventType.values)
        if (names.contains(type.name)) type,
    };
  }

  /// Enables [type] for [instance] and takes its baseline, without notifying.
  /// If the instance does not answer, the first successful check takes it.
  Future<void> subscribe(
    ActiveInstance instance,
    NotificationEventType type,
  ) async {
    await _setEnabled(instance.instance.id, type, enabled: true);
    await _baseline(instance, type, _Requests(this, instance));
  }

  /// Disables [type] for an instance.
  Future<void> unsubscribe(String instanceId, NotificationEventType type) =>
      _setEnabled(instanceId, type, enabled: false);

  /// Starts [instances] again from their current state, without notifying: call
  /// with a profile's instances when it is activated, and with an instance when
  /// it is re-enabled. One that does not answer starts at its first successful
  /// check.
  Future<void> initialise(Iterable<ActiveInstance> instances) async {
    final all = instances.toList();
    final ids = [for (final instance in all) instance.instance.id];
    // All before anything is read, so that no check meanwhile goes on from an
    // old marker.
    await (_database.delete(
      _database.eventMarkers,
    )..where((row) => row.instanceId.isIn(ids))).go();
    await Future.wait([for (final instance in all) _initialiseOne(instance)]);
  }

  /// Checks the instances of [scope] and returns what is new since the last
  /// check, each event once. More than five events of one instance are one
  /// [SummaryNotice].
  ///
  /// Gives nothing if the profile of [scope] is no longer the active one when
  /// it is done, also where another isolate has switched.
  Future<List<Notice>> check(ProfileScope scope) async {
    final found = await Future.wait([
      for (final instance in scope.instances) _check(scope, instance),
    ]);
    if (!await _isActive(scope)) return const [];
    return [for (final notices in found) ...notices];
  }

  Future<void> _initialiseOne(ActiveInstance instance) async {
    try {
      final requests = _Requests(this, instance);
      for (final type in await subscribed(instance.instance.id)) {
        await _baseline(instance, type, requests);
      }
    } catch (error, stackTrace) {
      _report(error, stackTrace);
    }
  }

  Future<void> _baseline(
    ActiveInstance instance,
    NotificationEventType type,
    _Requests requests,
  ) async {
    try {
      // A check may have taken it meanwhile, and what is new since is its.
      if (await _marker(instance.instance.id, type) != null) return;
      final step = await _step(instance, type, null, requests);
      if (step != null) await _store(instance, type, null, step.marker);
    } catch (error, stackTrace) {
      _report(error, stackTrace);
    }
  }

  Future<List<Notice>> _check(
    ProfileScope scope,
    ActiveInstance instance,
  ) async {
    final id = instance.instance.id;
    final notices = <Notice>[];
    try {
      final requests = _Requests(this, instance);
      for (final type in await subscribed(id)) {
        // Each by itself: one that fails must not lose what the others found,
        // as their markers have moved.
        try {
          final marker = await _marker(id, type);
          final step = await _step(instance, type, marker, requests);
          if (step == null) continue;
          if (await _store(instance, type, marker, step.marker, scope: scope)) {
            notices.addAll(step.notices);
          }
        } catch (error, stackTrace) {
          _report(error, stackTrace);
        }
      }
    } catch (error, stackTrace) {
      _report(error, stackTrace);
    }
    return notices.length > _mostNotices
        ? [SummaryNotice(instanceId: id, count: notices.length)]
        : notices;
  }

  /// What reading [type] now finds against [marker], and the marker to store.
  /// Null if the instance does not offer it or could not be read.
  Future<_Step?> _step(
    ActiveInstance instance,
    NotificationEventType type,
    EventMarkerRow? marker,
    _Requests requests,
  ) => switch (type) {
    NotificationEventType.imported => _imported(instance, marker),
    NotificationEventType.downloadProblem => _downloads(instance, marker),
    NotificationEventType.healthIssue => _health(instance, marker),
    NotificationEventType.pendingRequest => _pending(
      instance,
      marker,
      requests,
    ),
    NotificationEventType.ownRequestUpdate => _own(instance, marker, requests),
  };

  Future<_Step?> _imported(
    ActiveInstance instance,
    EventMarkerRow? marker,
  ) async {
    final history = instance.capability(CapabilityKind.history);
    if (history == null) return null;
    final cursor = decodeCursor(marker?.lastSeenCursor);
    final events = await _events(history, marker, cursor);
    if (events == null) return null;
    return _Step(
      _newMarker(
        instance,
        NotificationEventType.imported,
        cursor: advanceCursor(cursor, events),
      ),
      [
        if (marker != null)
          for (final event in events)
            if (event.eventType == HistoryEventType.imported)
              ImportedNotice(instanceId: instance.instance.id, event: event),
      ],
    );
  }

  /// Queue entries and history failures, which share their keys so that one
  /// failure is notified once.
  Future<_Step?> _downloads(
    ActiveInstance instance,
    EventMarkerRow? marker,
  ) async {
    final queue = instance.capability(CapabilityKind.queue);
    final history = instance.capability(CapabilityKind.history);
    if (queue == null && history == null) return null;
    final cursor = decodeCursor(marker?.lastSeenCursor);

    // The queue first: a download that has left it by now has its failure in
    // the history, which is read after.
    final items = queue == null ? <QueueItem>[] : await _read(queue.queue);
    final events = history == null
        ? <HistoryEvent>[]
        : await _events(history, marker, cursor);
    final complete = items != null && events != null;
    // A baseline needs both; a check goes on with either.
    if (marker == null ? !complete : items == null && events == null) {
      return null;
    }

    final id = instance.instance.id;
    final found = <String, (ConditionSeverity, Notice)>{};
    for (final item in items ?? const <QueueItem>[]) {
      final severity = switch (item.severity) {
        QueueSeverity.warning => ConditionSeverity.warning,
        QueueSeverity.error => ConditionSeverity.error,
        QueueSeverity.ok || QueueSeverity.unknown => null,
      };
      if (severity == null) continue;
      final key = item.downloadId == null
          ? 'queue:${item.id}'
          : 'download:${item.downloadId}';
      if (!severity.risesFrom(found[key]?.$1)) continue;
      found[key] = (
        severity,
        DownloadProblemNotice(
          instanceId: id,
          title: item.title,
          itemRef: item.itemRef,
          downloadId: item.downloadId,
        ),
      );
    }
    // At a baseline the history only gives the cursor.
    if (marker != null) {
      for (final event in events ?? const <HistoryEvent>[]) {
        if (event.eventType != HistoryEventType.failed) continue;
        final key = event.downloadId == null
            ? 'event:${event.id}'
            : 'download:${event.downloadId}';
        found[key] = (
          ConditionSeverity.error,
          found[key]?.$2 ??
              DownloadProblemNotice(
                instanceId: id,
                title: event.sourceTitle,
                itemRef: event.itemRef,
                downloadId: event.downloadId,
              ),
        );
      }
    }

    final before = _openKeys(marker);
    return _Step(
      _newMarker(
        instance,
        NotificationEventType.downloadProblem,
        cursor: advanceCursor(cursor, events ?? const []),
        openKeys: {
          // A condition has cleared only if both reads say so. So a key from
          // the history alone is kept until the next check, where the queue
          // may still show it.
          if (!complete) ...before,
          for (final MapEntry(:key, :value) in found.entries) key: value.$1,
        },
      ),
      marker == null ? const [] : _risen(found, before),
    );
  }

  Future<_Step?> _health(
    ActiveInstance instance,
    EventMarkerRow? marker,
  ) async {
    final health = instance.capability(CapabilityKind.health);
    if (health == null) return null;
    final issues = await _read(health.health);
    if (issues == null) return null;

    final found = <String, (ConditionSeverity, Notice)>{};
    for (final issue in issues) {
      final severity = switch (issue.level) {
        HealthLevel.warning => ConditionSeverity.warning,
        HealthLevel.error => ConditionSeverity.error,
        HealthLevel.notice || HealthLevel.unknown => null,
      };
      if (severity == null) continue;
      // With its length, no source and message read as another pair.
      final key = '${issue.source.length}:${issue.source}${issue.message}';
      if (!severity.risesFrom(found[key]?.$1)) continue;
      found[key] = (
        severity,
        HealthNotice(instanceId: instance.instance.id, issue: issue),
      );
    }

    return _Step(
      _newMarker(
        instance,
        NotificationEventType.healthIssue,
        openKeys: {
          for (final MapEntry(:key, :value) in found.entries) key: value.$1,
        },
      ),
      marker == null ? const [] : _risen(found, _openKeys(marker)),
    );
  }

  Future<_Step?> _pending(
    ActiveInstance instance,
    EventMarkerRow? marker,
    _Requests requests,
  ) async {
    final list = await requests.list;
    if (list == null) return null;
    final before = _snapshot(marker);
    return _Step(
      _snapshotMarker(
        instance,
        NotificationEventType.pendingRequest,
        before,
        list,
      ),
      [
        if (marker != null)
          for (final request in list)
            if (request.status == RequestStatus.pending &&
                !before.containsKey(request.id))
              PendingRequestNotice(
                instanceId: instance.instance.id,
                request: request,
              ),
      ],
    );
  }

  Future<_Step?> _own(
    ActiveInstance instance,
    EventMarkerRow? marker,
    _Requests requests,
  ) async {
    final provider = instance.capability(CapabilityKind.request);
    if (provider == null) return null;
    final list = await requests.list;
    if (list == null) return null;
    final before = _snapshot(marker);
    // The snapshot holds everyone's requests, so that signing in as another
    // user does not make that user's old ones news.
    final changed = [
      if (marker != null)
        for (final request in list)
          if (_isNews(before[request.id], request)) request,
    ];
    var own = const <MediaRequest>[];
    if (changed.isNotEmpty) {
      final user = await _read(provider.session);
      // The marker stays, so that they are told apart later.
      if (user == null) return null;
      own = [
        for (final request in changed)
          if (request.requestedBy.id == user.id) request,
      ];
    }
    return _Step(
      _snapshotMarker(
        instance,
        NotificationEventType.ownRequestUpdate,
        before,
        list,
      ),
      [
        for (final request in own)
          OwnRequestNotice(instanceId: instance.instance.id, request: request),
      ],
    );
  }

  /// Whether a request has become approved or declined, or what it asked for
  /// available or partly so.
  static bool _isNews(RequestState? before, MediaRequest now) {
    final decided =
        now.status != before?.status &&
        (now.status == RequestStatus.approved ||
            now.status == RequestStatus.declined);
    final arrived =
        now.availability != before?.availability &&
        (now.availability == Availability.available ||
            now.availability == Availability.partial &&
                before?.availability != Availability.available);
    return decided || arrived;
  }

  /// The notices of the conditions that are new or worse than [before].
  static List<Notice> _risen(
    Map<String, (ConditionSeverity, Notice)> found,
    Map<String, ConditionSeverity> before,
  ) => [
    for (final MapEntry(:key, value: (severity, notice)) in found.entries)
      if (severity.risesFrom(before[key])) notice,
  ];

  static Map<String, ConditionSeverity> _openKeys(EventMarkerRow? marker) =>
      marker == null ? const {} : decodeOpenKeys(marker.openKeys);

  static Map<int, RequestState> _snapshot(EventMarkerRow? marker) =>
      marker == null ? const {} : decodeSnapshot(marker.requestSnapshot);

  /// The events after [cursor], oldest first; without a [marker], only the
  /// newest, for the cursor to start from. Null if they could not be read.
  Future<List<HistoryEvent>?> _events(
    HistoryProvider history,
    EventMarkerRow? marker,
    HistoryCursor? cursor,
  ) async {
    final List<HistoryEvent>? events;
    if (cursor != null) {
      final since = await _read(
        () => history.eventsSince(cursor.date.subtract(_sinceMargin)),
      );
      events = since?.where((event) => event.id > cursor.id).toList();
    } else if (marker == null) {
      events = (await _read(history.history))?.items.toList();
    } else {
      // There was no history at the baseline: all there is now is new. One
      // added while the pages are read moves another onto the next page.
      final all = await _allPages((page) => history.history(page: page));
      events = all == null
          ? null
          : {for (final event in all) event.id: event}.values.toList();
    }
    return events?..sort((a, b) => a.id.compareTo(b.id));
  }

  /// The items of every page, or null if one could not be read.
  Future<List<T>?> _allPages<T>(
    ServiceResult<ResultPage<T>> Function(int page) read,
  ) async {
    final all = <T>[];
    for (var page = 1; ; page++) {
      final answer = await _read(() => read(page));
      if (answer == null) return null;
      all.addAll(answer.items);
      if (!answer.hasMore || answer.items.isEmpty) return all;
    }
  }

  /// What [read] gives, or null if it fails or throws.
  Future<T?> _read<T>(ServiceResult<T> Function() read) async {
    try {
      return switch (await read()) {
        Ok(:final value) => value,
        Err() => null,
      };
    } catch (error, stackTrace) {
      _report(error, stackTrace);
      return null;
    }
  }

  Future<void> _setEnabled(
    String instanceId,
    NotificationEventType type, {
    required bool enabled,
  }) => _database.transaction(() async {
    await _database
        .into(_database.notificationSubscriptions)
        .insertOnConflictUpdate(
          NotificationSubscriptionsCompanion.insert(
            instanceId: instanceId,
            eventType: type.name,
            enabled: Value(enabled),
          ),
        );
    // A marker of before says nothing about what has been seen since.
    await (_database.delete(_database.eventMarkers)..where(
          (row) =>
              row.instanceId.equals(instanceId) &
              row.eventType.equals(type.name),
        ))
        .go();
  });

  Future<EventMarkerRow?> _marker(
    String instanceId,
    NotificationEventType type,
  ) =>
      (_database.select(_database.eventMarkers)..where(
            (row) =>
                row.instanceId.equals(instanceId) &
                row.eventType.equals(type.name),
          ))
          .getSingleOrNull();

  /// Stores [next] if what was read still applies, and says whether it did.
  ///
  /// The subscription must still be enabled, which it is not once the instance
  /// is deleted, and the marker still [expected], so that of two reads at the
  /// same time only one notifies. In a check of [scope], the instance must also
  /// still be in use in the active profile; what another isolate has changed is
  /// seen only in the database.
  Future<bool> _store(
    ActiveInstance instance,
    NotificationEventType type,
    EventMarkerRow? expected,
    EventMarkerRow next, {
    ProfileScope? scope,
  }) => _database.transaction(() async {
    final id = instance.instance.id;
    if (!(await subscribed(id)).contains(type)) return false;
    if (scope != null) {
      if (!instance.isCurrent || !await _isActive(scope)) return false;
      final saved = await (_database.select(
        _database.instances,
      )..where((row) => row.id.equals(id))).getSingle();
      if (!saved.enabled) return false;
    }
    if (await _marker(id, type) != expected) return false;
    await _database.into(_database.eventMarkers).insertOnConflictUpdate(next);
    return true;
  });

  Future<bool> _isActive(ProfileScope scope) async {
    final preferences = await PreferencesRepository(_database).read();
    return scope.isCurrent && preferences.activeProfileId == scope.profileId;
  }

  static EventMarkerRow _newMarker(
    ActiveInstance instance,
    NotificationEventType type, {
    HistoryCursor? cursor,
    Map<String, ConditionSeverity> openKeys = const {},
    Map<int, RequestState> snapshot = const {},
  }) => EventMarkerRow(
    instanceId: instance.instance.id,
    eventType: type.name,
    lastSeenCursor: encodeCursor(cursor),
    openKeys: encodeOpenKeys(openKeys),
    requestSnapshot: encodeSnapshot(snapshot),
  );

  /// Requests no longer listed are kept: a paged read can miss one when the
  /// list changes under it, and it would be new again at the next check.
  static EventMarkerRow _snapshotMarker(
    ActiveInstance instance,
    NotificationEventType type,
    Map<int, RequestState> before,
    List<MediaRequest> list,
  ) => _newMarker(
    instance,
    type,
    snapshot: {
      ...before,
      for (final request in list) request.id: requestState(request),
    },
  );

  // The type only: the text of an error may quote an address or a secret.
  void _report(Object error, StackTrace stackTrace) => _log.log(
    LogLevel.error,
    'A background check failed (${error.runtimeType})',
    stackTrace: stackTrace,
  );
}

/// The marker to store after a read, and what the read found.
final class _Step {
  _Step(this.marker, this.notices);

  final EventMarkerRow marker;
  final List<Notice> notices;
}

/// The whole request list of one instance, read once however many event types
/// need it.
final class _Requests {
  _Requests(this._engine, this._instance);

  final NotificationEngine _engine;
  final ActiveInstance _instance;

  /// Each request once, or null if the instance does not offer them or a page
  /// could not be read.
  late final Future<List<MediaRequest>?> list = _read();

  Future<List<MediaRequest>?> _read() async {
    final provider = _instance.capability(CapabilityKind.request);
    if (provider == null) return null;
    final all = await _engine._allPages((page) => provider.list(page: page));
    if (all == null) return null;
    return {for (final request in all) request.id: request}.values.toList();
  }
}
