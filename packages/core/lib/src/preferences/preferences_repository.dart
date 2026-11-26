import 'package:drift/drift.dart';

import '../models/add_choices.dart';
import '../models/media_kind.dart';
import '../storage/database.dart';
import 'app_lock.dart';
import 'app_theme_mode.dart';
import 'library_layout.dart';
import 'library_view.dart';
import 'preferences.dart';
import 'preferences_json.dart';

/// Stores the user's preferences in the database.
///
/// The rows of a deleted profile or instance go with it. A view also names
/// instances inside its columns: those that are not in its profile are left out
/// when it is read.
class PreferencesRepository {
  /// Creates a [PreferencesRepository].
  PreferencesRepository(this._database);

  final AppDatabase _database;

  /// The app-wide preferences.
  Future<Preferences> read() async => _preferences(
    await _database.select(_database.appPreferences).getSingleOrNull(),
  );

  /// The app-wide preferences, now and after every change.
  Stream<Preferences> watch() => _database
      .select(_database.appPreferences)
      .watchSingleOrNull()
      .map(_preferences)
      .distinct();

  /// Makes [profileId], which must exist, the active profile.
  Future<void> setActiveProfile(String profileId) =>
      _write(AppPreferencesCompanion(activeProfileId: Value(profileId)));

  /// Sets [Preferences.themeMode].
  Future<void> setThemeMode(AppThemeMode mode) =>
      _write(AppPreferencesCompanion(themeMode: Value(mode.name)));

  /// Sets [Preferences.trueBlack].
  Future<void> setTrueBlack(bool value) =>
      _write(AppPreferencesCompanion(trueBlack: Value(value)));

  /// Sets [Preferences.dynamicColor].
  Future<void> setDynamicColor(bool value) =>
      _write(AppPreferencesCompanion(dynamicColor: Value(value)));

  /// Sets [Preferences.loadThirdPartyArtwork].
  Future<void> setLoadThirdPartyArtwork(bool value) =>
      _write(AppPreferencesCompanion(loadThirdPartyArtwork: Value(value)));

  /// Sets [Preferences.appLock]. The delay must not be negative.
  Future<void> setAppLock(AppLock lock) {
    RangeError.checkNotNegative(lock.delaySeconds, 'delaySeconds');
    return _write(
      AppPreferencesCompanion(
        appLockEnabled: Value(lock.enabled),
        appLockDelaySeconds: Value(lock.delaySeconds),
      ),
    );
  }

  /// How [library], named by the kind of its top-level items, was left in a
  /// profile; the default view if it never was saved.
  Future<LibraryView> view(String profileId, MediaKind library) async {
    final row =
        await (_database.select(_database.viewPreferences)..where(
              (row) =>
                  row.profileId.equals(profileId) &
                  row.library.equals(library.name),
            ))
            .getSingleOrNull();
    if (row == null) return const LibraryView();

    final instances = await (_database.select(
      _database.instances,
    )..where((instance) => instance.profileId.equals(profileId))).get();
    final ids = {for (final instance in instances) instance.id};
    return _view(row).mapInstances((id) => ids.contains(id) ? id : null);
  }

  /// Stores the view of [library] in a profile, which must exist.
  Future<void> saveView(
    String profileId,
    MediaKind library,
    LibraryView view,
  ) => _database
      .into(_database.viewPreferences)
      .insertOnConflictUpdate(_row(profileId, library.name, view));

  /// Removes a deleted instance from the stored views.
  Future<void> removeInstanceFromViews(String instanceId) =>
      _database.transaction(() async {
        final rows = await _database.select(_database.viewPreferences).get();
        for (final row in rows) {
          final view = _view(row);
          final without = view.mapInstances(
            (id) => id == instanceId ? null : id,
          );
          if (without == view) continue;
          await _database
              .update(_database.viewPreferences)
              .replace(_row(row.profileId, row.library, without));
        }
      });

  /// Gives a copied profile the views of the original. [instanceIds] maps each
  /// instance of the original to its copy.
  Future<void> copyViews({
    required String fromProfileId,
    required String toProfileId,
    required Map<String, String> instanceIds,
  }) => _database.transaction(() async {
    final rows = await (_database.select(
      _database.viewPreferences,
    )..where((row) => row.profileId.equals(fromProfileId))).get();
    for (final row in rows) {
      final copy = _view(row).mapInstances((id) => instanceIds[id]);
      await _database
          .into(_database.viewPreferences)
          .insertOnConflictUpdate(_row(toProfileId, row.library, copy));
    }
  });

  /// What was last chosen when adding to an instance, or null.
  Future<AddChoices?> lastAddChoices(String instanceId) async {
    final row = await (_database.select(
      _database.lastAddChoices,
    )..where((row) => row.instanceId.equals(instanceId))).getSingleOrNull();
    return row == null ? null : decodeAddChoices(row.choices);
  }

  /// Remembers what was chosen when adding to an instance, which must exist.
  Future<void> saveLastAddChoices(String instanceId, AddChoices choices) =>
      _database
          .into(_database.lastAddChoices)
          .insertOnConflictUpdate(
            LastAddChoicesCompanion.insert(
              instanceId: instanceId,
              choices: encodeAddChoices(choices),
            ),
          );

  /// Changes only the columns set in [values], in the one row.
  Future<void> _write(AppPreferencesCompanion values) => _database
      .into(_database.appPreferences)
      .insert(values, onConflict: DoUpdate((_) => values));

  Preferences _preferences(PreferencesRow? row) {
    if (row == null) return const Preferences();
    return Preferences(
      activeProfileId: row.activeProfileId,
      themeMode:
          AppThemeMode.values.asNameMap()[row.themeMode] ?? AppThemeMode.system,
      trueBlack: row.trueBlack,
      dynamicColor: row.dynamicColor,
      loadThirdPartyArtwork: row.loadThirdPartyArtwork,
      appLock: AppLock(
        enabled: row.appLockEnabled,
        delaySeconds: row.appLockDelaySeconds,
      ),
    );
  }

  LibraryView _view(ViewPreferenceRow row) => LibraryView(
    layout: LibraryLayout.values.asNameMap()[row.layout] ?? LibraryLayout.grid,
    sort: decodeSort(row.sort),
    filters: decodeFilters(row.filters),
    instanceScope: row.instanceScope,
  );

  // All columns are given, so that a null scope replaces a stored one.
  ViewPreferencesCompanion _row(
    String profileId,
    String library,
    LibraryView view,
  ) => ViewPreferencesCompanion(
    profileId: Value(profileId),
    library: Value(library),
    layout: Value(view.layout.name),
    sort: Value(encodeSort(view.sort)),
    filters: Value(encodeFilters(view.filters)),
    instanceScope: Value(view.instanceScope),
  );
}
