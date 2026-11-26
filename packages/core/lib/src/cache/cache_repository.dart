import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../models/item_ref.dart';
import '../models/media_kind.dart';
import '../models/server_option.dart';
import '../models/server_option_kind.dart';
import '../storage/database.dart';
import 'cache_entry.dart';
import 'cache_scope.dart';
import 'cache_snapshot.dart';
import 'cached.dart';

/// The cached library data of all instances, kept in the database.
///
/// Entries are deleted with their instance. Those of a series, artist, album or
/// author also go when it does: when it is removed, or a full fetch no longer
/// has it.
final class CacheRepository {
  /// Creates a [CacheRepository]. [now] dates the full fetches.
  CacheRepository(this._database, {this._now = DateTime.now});

  final AppDatabase _database;
  final DateTime Function() _now;
  // Open for as long as the app runs, as the repository is.
  // ignore: close_sinks
  final _removals = StreamController<ItemRef>.broadcast();

  /// The items removed from any instance's cache, as [CacheScope.removals]
  /// announces them.
  Stream<ItemRef> get removals => _removals.stream;

  /// The cache of one instance. Entries are returned ordered by sort title.
  ///
  /// Writing an entry of another instance, kind or parent than asked for is an
  /// [ArgumentError], and nothing is stored.
  CacheScope scope(String instanceId) =>
      _InstanceCache(_database, _now, _removals, instanceId);

  /// Removes everything cached, for all instances.
  Future<void> clear() => _database.transaction(() async {
    await _database.delete(_database.cacheEntries).go();
    await _database.delete(_database.cacheFetches).go();
    await _database.delete(_database.cacheOptions).go();
  });
}

/// What an item of each kind is the parent of.
const _childKinds = {
  MediaKind.series: MediaKind.episode,
  MediaKind.artist: MediaKind.album,
  MediaKind.album: MediaKind.track,
  MediaKind.author: MediaKind.book,
};

/// How many ids go into one statement; SQLite limits its variables.
const _chunkSize = 500;

final class _InstanceCache implements CacheScope {
  _InstanceCache(this._database, this._now, this._removals, this._instanceId);

  final AppDatabase _database;
  final DateTime Function() _now;
  final StreamController<ItemRef> _removals;
  final String _instanceId;

  $CacheEntriesTable get _entries => _database.cacheEntries;
  $CacheFetchesTable get _fetches => _database.cacheFetches;

  @override
  Future<CacheSnapshot?> read(MediaKind kind, {int? parentRemoteId}) =>
      _database.transaction(() async {
        final fetchedAt = await _fetchedAt(kind, parentRemoteId);
        if (fetchedAt == null) return null;
        final query = _database.select(_entries)
          ..where((row) => _matches(row, kind, parentRemoteId))
          ..orderBy([
            (row) => OrderingTerm(expression: row.sortTitle),
            (row) => OrderingTerm(expression: row.remoteId),
          ]);
        final rows = await query.get();
        return CacheSnapshot(
          entries: rows.map(_entry).toList(),
          fetchedAt: fetchedAt,
        );
      });

  @override
  Future<CacheEntry?> entry(MediaKind kind, int remoteId) async {
    final query = _database.select(_entries)
      ..where(
        (row) => _matches(row, kind, null) & row.remoteId.equals(remoteId),
      );
    final row = await query.getSingleOrNull();
    return row == null ? null : _entry(row);
  }

  @override
  Future<void> replace(
    MediaKind kind,
    List<CacheEntry> entries, {
    int? parentRemoteId,
  }) async {
    for (final entry in entries) {
      _checkInstance(entry);
      if (entry.kind != kind) {
        throw ArgumentError.value(entry.kind, 'entries', 'not of kind $kind');
      }
      if (parentRemoteId != null && entry.parentRemoteId != parentRemoteId) {
        throw ArgumentError.value(
          entry.parentRemoteId,
          'entries',
          'not under parent $parentRemoteId',
        );
      }
    }
    final fetchedAt = _now().toUtc();
    await _database.transaction(() async {
      final kept = {for (final entry in entries) entry.remoteId};
      final cached = await _ids((row) => _matches(row, kind, parentRemoteId));
      await _remove(kind, cached.where((id) => !kept.contains(id)).toList());
      await _database.batch(
        (batch) => batch.insertAllOnConflictUpdate(
          _entries,
          entries.map(_row).toList(),
        ),
      );
      // A fetch of everything replaces the earlier fetches by parent.
      if (parentRemoteId == null) {
        await (_database.delete(_fetches)..where(
              (row) =>
                  row.instanceId.equals(_instanceId) &
                  row.kind.equalsValue(kind),
            ))
            .go();
      }
      final lists = {
        parentRemoteId ?? CacheFetches.noParent,
        if (parentRemoteId == null) ...await _knownParents(kind, entries),
      };
      await _database.batch(
        (batch) => batch.insertAllOnConflictUpdate(_fetches, [
          for (final parent in lists)
            CacheFetchesCompanion.insert(
              instanceId: _instanceId,
              kind: kind,
              parentRemoteId: parent,
              fetchedAt: fetchedAt,
            ),
        ]),
      );
    });
  }

  @override
  Future<void> put(CacheEntry entry) async {
    _checkInstance(entry);
    await _database.into(_entries).insertOnConflictUpdate(_row(entry));
  }

  @override
  Future<void> remove(MediaKind kind, int remoteId) async {
    await _database.transaction(() => _remove(kind, [remoteId]));
    _removals.add(
      ItemRef(instanceId: _instanceId, kind: kind, remoteId: remoteId),
    );
  }

  @override
  Stream<ItemRef> get removals =>
      _removals.stream.where((ref) => ref.instanceId == _instanceId);

  @override
  Future<Cached<List<ServerOption>>?> readOptions() async {
    final query = _database.select(_database.cacheOptions)
      ..where((row) => row.instanceId.equals(_instanceId));
    final row = await query.getSingleOrNull();
    if (row == null) return null;
    final options = _decodeOptions(row.options);
    return options == null ? null : Cached(options, fetchedAt: row.fetchedAt);
  }

  @override
  Future<void> replaceOptions(List<ServerOption> options) => _database
      .into(_database.cacheOptions)
      .insertOnConflictUpdate(
        CacheOptionsCompanion.insert(
          instanceId: _instanceId,
          options: jsonEncode([
            for (final option in options)
              {
                'kind': option.kind.name,
                'id': option.id,
                'label': option.label,
                'freeSpace': option.freeSpace,
              },
          ]),
          fetchedAt: _now().toUtc(),
        ),
      );

  /// Null for what cannot be read, which is as good as never stored. A kind
  /// this version does not know is left out.
  static List<ServerOption>? _decodeOptions(String json) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      return null;
    }
    if (decoded is! List<Object?>) return null;
    final kinds = ServerOptionKind.values.asNameMap();
    return [
      for (final entry in decoded)
        if (entry case {
          'kind': final String name,
          'id': final int id,
          'label': final String label,
        })
          if (kinds[name] case final kind?)
            ServerOption(
              kind: kind,
              id: id,
              label: label,
              freeSpace: switch (entry['freeSpace']) {
                final int bytes => bytes,
                _ => null,
              },
            ),
    ];
  }

  /// The parents whose lists a fetch of everything of [kind] answers for: those
  /// cached and those of [entries]. A parent that appears later was not asked
  /// about. Empty if the kind has no parent.
  Future<Set<int>> _knownParents(
    MediaKind kind,
    List<CacheEntry> entries,
  ) async {
    for (final MapEntry(key: parentKind, value: childKind)
        in _childKinds.entries) {
      if (childKind != kind) continue;
      return {
        ...await _ids((row) => _matches(row, parentKind, null)),
        for (final entry in entries) ?entry.parentRemoteId,
      };
    }
    return const {};
  }

  Future<DateTime?> _fetchedAt(MediaKind kind, int? parentRemoteId) async {
    final query = _database.select(_fetches)
      ..where(
        (row) =>
            row.instanceId.equals(_instanceId) &
            row.kind.equalsValue(kind) &
            row.parentRemoteId.equals(parentRemoteId ?? CacheFetches.noParent),
      );
    return (await query.getSingleOrNull())?.fetchedAt;
  }

  Expression<bool> _matches(
    $CacheEntriesTable row,
    MediaKind kind,
    int? parentRemoteId,
  ) {
    final ofKind =
        row.instanceId.equals(_instanceId) & row.kind.equalsValue(kind);
    return parentRemoteId == null
        ? ofKind
        : ofKind & row.parentRemoteId.equals(parentRemoteId);
  }

  Future<List<int>> _ids(
    Expression<bool> Function($CacheEntriesTable row) filter,
  ) {
    final query = _database.selectOnly(_entries)
      ..addColumns([_entries.remoteId])
      ..where(filter(_entries));
    return query.map((row) => row.read(_entries.remoteId)!).get();
  }

  /// Removes entries and everything under them. Call inside a transaction.
  Future<void> _remove(MediaKind kind, List<int> remoteIds) async {
    final childKind = _childKinds[kind];
    for (var start = 0; start < remoteIds.length; start += _chunkSize) {
      final chunk = remoteIds.skip(start).take(_chunkSize).toList();
      await (_database.delete(_entries)..where(
            (row) => _matches(row, kind, null) & row.remoteId.isIn(chunk),
          ))
          .go();
      if (childKind == null) continue;
      await (_database.delete(_fetches)..where(
            (row) =>
                row.instanceId.equals(_instanceId) &
                row.kind.equalsValue(childKind) &
                row.parentRemoteId.isIn(chunk),
          ))
          .go();
      final children = await _ids(
        (row) =>
            _matches(row, childKind, null) & row.parentRemoteId.isIn(chunk),
      );
      await _remove(childKind, children);
    }
  }

  void _checkInstance(CacheEntry entry) {
    if (entry.instanceId != _instanceId) {
      throw ArgumentError.value(
        entry.instanceId,
        'instanceId',
        'not the instance of this cache',
      );
    }
  }

  static CacheEntry _entry(CacheEntryRow row) => CacheEntry(
    instanceId: row.instanceId,
    kind: row.kind,
    remoteId: row.remoteId,
    parentRemoteId: row.parentRemoteId,
    sortTitle: row.sortTitle,
    state: row.state,
    monitored: row.monitored,
    qualityProfileId: row.qualityProfileId,
    tagIds: row.tagIds,
    addedAt: row.addedAt,
    rawJson: row.rawJson,
    fetchedAt: row.fetchedAt,
  );

  // With its nulls present, so that they overwrite the old values; an upsert
  // leaves out those of a plain row.
  static CacheEntriesCompanion _row(CacheEntry entry) => CacheEntryRow(
    instanceId: entry.instanceId,
    kind: entry.kind,
    remoteId: entry.remoteId,
    parentRemoteId: entry.parentRemoteId,
    sortTitle: entry.sortTitle,
    state: entry.state,
    monitored: entry.monitored,
    qualityProfileId: entry.qualityProfileId,
    tagIds: entry.tagIds,
    addedAt: entry.addedAt?.toUtc(),
    rawJson: entry.rawJson,
    fetchedAt: entry.fetchedAt.toUtc(),
  ).toCompanion(false);
}
