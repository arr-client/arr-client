/// The tables for what data-model.md persists, except credentials, which are
/// only in secure storage.
///
/// To change the schema, raise [AppDatabase.schemaVersion], add the upgrade
/// step with a test, and export the new schema from `packages/core`:
///
///     dart run drift_dev schema dump lib/src/storage/database.dart drift_schemas/
library;

import 'dart:convert';

import 'package:drift/drift.dart';

import '../instances/auth_kind.dart';
import '../instances/instance_link_type.dart';
import '../models/item_state.dart';
import '../models/media_kind.dart';

part 'database.g.dart';

/// Stores a list of ids as a JSON array, which SQL can search with `json_each`.
class IdListConverter extends TypeConverter<List<int>, String> {
  /// Creates an [IdListConverter].
  const IdListConverter();

  @override
  List<int> fromSql(String fromDb) =>
      (jsonDecode(fromDb) as List<Object?>).cast<int>().toList();

  @override
  String toSql(List<int> value) => jsonEncode(value);
}

/// data-model.md Profile.
@DataClassName('ProfileRow')
class Profiles extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// data-model.md Instance, without its links.
@DataClassName('InstanceRow')
@TableIndex(name: 'instances_profile', columns: {#profileId})
class Instances extends Table {
  TextColumn get id => text()();
  TextColumn get profileId =>
      text().references(Profiles, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text()();
  TextColumn get serviceType => text()();
  TextColumn get url => text()();
  TextColumn get authKind => textEnum<AuthKind>()();
  BoolColumn get authFailed => boolean().withDefault(const Constant(false))();
  TextColumn get certPin => text().nullable()();
  TextColumn get customCa => text().nullable()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  TextColumn get detectedVersion => text().nullable()();

  /// A JSON object: product, version, capabilities and permissions.
  TextColumn get lastProbe => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// data-model.md Instance.links.
@DataClassName('InstanceLinkRow')
@TableIndex(name: 'instance_links_target', columns: {#targetInstanceId})
class InstanceLinks extends Table {
  @ReferenceName('links')
  TextColumn get instanceId =>
      text().references(Instances, #id, onDelete: KeyAction.cascade)();
  TextColumn get type => textEnum<InstanceLinkType>()();
  @ReferenceName('linkedFrom')
  TextColumn get targetInstanceId =>
      text().references(Instances, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column<Object>> get primaryKey => {instanceId, type, targetInstanceId};
}

/// The app-wide part of data-model.md Preferences, in at most one row, whose id
/// is 0.
@DataClassName('PreferencesRow')
class AppPreferences extends Table {
  IntColumn get id => integer().withDefault(const Constant(0))();
  TextColumn get activeProfileId => text().nullable().references(
    Profiles,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get themeMode => text().withDefault(const Constant('system'))();
  BoolColumn get trueBlack => boolean().withDefault(const Constant(false))();
  BoolColumn get dynamicColor => boolean().withDefault(const Constant(true))();
  BoolColumn get loadThirdPartyArtwork =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get appLockEnabled =>
      boolean().withDefault(const Constant(false))();
  IntColumn get appLockDelaySeconds =>
      integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  // An integer primary key of a rowid table is numbered by SQLite, which would
  // ignore the default.
  @override
  bool get withoutRowId => true;

  @override
  List<String> get customConstraints => ['CHECK (id = 0)'];
}

/// data-model.md Preferences.view, one row per profile and library.
@DataClassName('ViewPreferenceRow')
class ViewPreferences extends Table {
  TextColumn get profileId =>
      text().references(Profiles, #id, onDelete: KeyAction.cascade)();
  TextColumn get library => text()();
  TextColumn get layout => text()();
  TextColumn get sort => text()();

  /// JSON.
  TextColumn get filters => text()();

  /// The one instance shown, or null for all. Not a foreign key: a scope that
  /// no longer resolves is dropped when read.
  TextColumn get instanceScope => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {profileId, library};
}

/// data-model.md Preferences.lastAddChoices.
@DataClassName('LastAddChoicesRow')
class LastAddChoices extends Table {
  TextColumn get instanceId =>
      text().references(Instances, #id, onDelete: KeyAction.cascade)();

  /// A JSON object.
  TextColumn get choices => text()();

  @override
  Set<Column<Object>> get primaryKey => {instanceId};
}

/// data-model.md NotificationSubscription.
@DataClassName('NotificationSubscriptionRow')
class NotificationSubscriptions extends Table {
  TextColumn get instanceId =>
      text().references(Instances, #id, onDelete: KeyAction.cascade)();
  TextColumn get eventType => text()();
  BoolColumn get enabled => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {instanceId, eventType};
}

/// data-model.md EventMarker.
@DataClassName('EventMarkerRow')
class EventMarkers extends Table {
  TextColumn get instanceId =>
      text().references(Instances, #id, onDelete: KeyAction.cascade)();
  TextColumn get eventType => text()();
  TextColumn get lastSeenCursor => text().nullable()();

  /// A JSON object: condition key to severity.
  TextColumn get openKeys => text().withDefault(const Constant('{}'))();

  /// A JSON object: request id to status and availability.
  TextColumn get requestSnapshot => text().withDefault(const Constant('{}'))();

  @override
  Set<Column<Object>> get primaryKey => {instanceId, eventType};
}

/// data-model.md CacheEntry.
@DataClassName('CacheEntryRow')
@TableIndex(
  name: 'cache_entries_parent',
  columns: {#instanceId, #kind, #parentRemoteId},
)
@TableIndex(
  name: 'cache_entries_title',
  columns: {#instanceId, #kind, #sortTitle},
)
class CacheEntries extends Table {
  TextColumn get instanceId =>
      text().references(Instances, #id, onDelete: KeyAction.cascade)();
  TextColumn get kind => textEnum<MediaKind>()();
  IntColumn get remoteId => integer()();
  IntColumn get parentRemoteId => integer().nullable()();
  TextColumn get sortTitle => text()();
  TextColumn get state => textEnum<ItemState>()();
  BoolColumn get monitored => boolean()();
  IntColumn get qualityProfileId => integer().nullable()();
  TextColumn get tagIds => text().map(const IdListConverter())();
  DateTimeColumn get addedAt => dateTime().nullable()();
  TextColumn get rawJson => text()();
  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {instanceId, kind, remoteId};
}

/// When a whole list was last fetched. It tells a list never fetched from one
/// fetched and empty.
@DataClassName('CacheFetchRow')
class CacheFetches extends Table {
  /// The [parentRemoteId] of a fetch of all entries of a kind. A null would not
  /// do: SQLite treats nulls in a primary key as distinct.
  static const noParent = -1;

  TextColumn get instanceId =>
      text().references(Instances, #id, onDelete: KeyAction.cascade)();
  TextColumn get kind => textEnum<MediaKind>()();
  IntColumn get parentRemoteId => integer()();
  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {instanceId, kind, parentRemoteId};
}

/// The app's database, for the repositories in core.
///
/// Times are stored as ISO 8601 text; write them in UTC. Deleting a profile or
/// an instance deletes the rows that belong to it.
@DriftDatabase(
  tables: [
    Profiles,
    Instances,
    InstanceLinks,
    AppPreferences,
    ViewPreferences,
    LastAddChoices,
    NotificationSubscriptions,
    EventMarkers,
    CacheEntries,
    CacheFetches,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// The app chooses where the database lives.
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (details) async {
      // Off by default in SQLite, and the cascades depend on it.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
