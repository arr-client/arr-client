import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';

import '../instances/credential.dart';
import '../instances/credential_json.dart';
import '../instances/instance.dart';
import '../instances/instance_rules.dart';
import '../instances/profile_repository.dart';
import '../instances/secret_changes.dart';
import '../logging/diagnostic_log.dart';
import '../logging/log_level.dart';
import '../models/media_kind.dart';
import '../module/module_descriptor.dart';
import '../module/result.dart';
import '../module/service_module.dart';
import '../preferences/preferences_json.dart';
import '../preferences/preferences_repository.dart';
import '../secrets/secret_store.dart';
import '../storage/database.dart';
import 'backup_content.dart';
import 'backup_crypto.dart' as crypto;
import 'backup_problem.dart';
import 'import_action.dart';
import 'import_plan.dart';
import 'import_preview.dart';
import 'imported_setting.dart';
import 'setup_file.dart';

const _format = 'arr-client-setup';
const _version = 1;
const _kdf = 'argon2id';
const _cipher = 'aes-256-gcm';
const _maximumFileBytes = 1024 * 1024;
const _minimumPassphraseLength = 10;

/// Exports and imports the app's setup (contracts/backup-format.md).
///
/// Neither the passphrase nor anything of a file is logged, and the credentials
/// that are read are registered with the [DiagnosticLog].
class SetupBackup {
  /// Creates a [SetupBackup]. [profiles] and [preferences] must use the same
  /// [database], and [profiles] the same [secrets], [log] and [modules]. [now]
  /// dates the exports and what is imported.
  SetupBackup({
    required this._database,
    required this._profiles,
    required this._preferences,
    required this._secrets,
    required this._log,
    required Iterable<ServiceModule> modules,
    this._now = DateTime.now,
  }) : _modules = {for (final module in modules) module.id: module.descriptor};

  final AppDatabase _database;
  final ProfileRepository _profiles;
  final PreferencesRepository _preferences;
  final SecretStore _secrets;
  final DiagnosticLog _log;
  final Map<String, ModuleDescriptor> _modules;
  final DateTime Function() _now;

  /// The setup as the bytes of a file. Without a [passphrase] it holds no
  /// credentials; with one it holds them and is encrypted. Throws what the
  /// secret store throws.
  ///
  /// Nothing is left out: it is refused as [BackupProblem.unreadableRecord] if
  /// something saved cannot be read, and the file is one that [read] accepts.
  Future<Result<Uint8List, BackupProblem>> export({String? passphrase}) async {
    if (passphrase != null &&
        passphrase.runes.length < _minimumPassphraseLength) {
      return const Err(BackupProblem.passphraseTooShort);
    }
    final withCredentials = passphrase != null;
    final String text;
    try {
      // One transaction, so that no change comes between the records and their
      // credentials.
      text = jsonEncode(
        await _database.transaction(() => _payload(withCredentials)),
      );
    } on _Unreadable {
      return const Err(BackupProblem.unreadableRecord);
    }
    final clear = utf8.encode(text);
    if (clear.length > _maximumFileBytes) {
      return const Err(BackupProblem.tooLarge);
    }
    // As an import will, so that a backup is not found to be useless only when
    // it is needed.
    final payload = jsonDecode(text) as Object?;
    if (_content(payload, withCredentials: withCredentials) == null) {
      return const Err(BackupProblem.invalidContent);
    }

    final Object? body;
    if (passphrase == null) {
      body = payload;
    } else {
      final salt = _random(crypto.saltLength);
      final nonce = _random(crypto.nonceLength);
      final sealed = await crypto.seal(
        clear,
        passphrase: passphrase,
        salt: salt,
        nonce: nonce,
      );
      body = {
        'kdf': {
          'name': _kdf,
          'salt': base64.encode(salt),
          'memoryKiB': crypto.exportMemoryKiB,
          'iterations': crypto.exportIterations,
          'parallelism': 1,
        },
        'cipher': _cipher,
        'nonce': base64.encode(nonce),
        'data': base64.encode(sealed),
      };
    }
    final file = utf8.encode(
      jsonEncode({
        'format': _format,
        'version': _version,
        'createdAt': _now().toUtc().toIso8601String(),
        'encrypted': withCredentials,
        'payload': body,
      }),
    );
    return file.length > _maximumFileBytes
        ? const Err(BackupProblem.tooLarge)
        : Ok(file);
  }

  /// Checks and, if encrypted, decrypts a file. Changes nothing.
  Future<Result<SetupFile, BackupProblem>> read(
    List<int> bytes, {
    String? passphrase,
  }) async {
    const notASetupFile = Err<SetupFile, BackupProblem>(
      BackupProblem.notASetupFile,
    );
    if (bytes.length > _maximumFileBytes) {
      return const Err(BackupProblem.tooLarge);
    }
    final json = _json(bytes);
    if (json is! Map<String, Object?> || json['format'] != _format) {
      return notASetupFile;
    }
    final version = json['version'];
    if (version is! int || version < _version) return notASetupFile;
    if (version > _version) return const Err(BackupProblem.newerVersion);
    final createdAt = readBackupDate(json['createdAt']);
    final encrypted = json['encrypted'];
    var payload = json['payload'];
    if (createdAt == null ||
        encrypted is! bool ||
        payload is! Map<String, Object?>) {
      return notASetupFile;
    }

    if (encrypted) {
      switch (await _decrypt(payload, passphrase)) {
        case Ok(:final value):
          payload = _json(value);
        case Err(:final error):
          return Err(error);
      }
    }
    final content = _content(payload, withCredentials: encrypted);
    return content == null
        ? const Err(BackupProblem.invalidContent)
        : Ok(_SetupFile(createdAt, encrypted, content));
  }

  /// What importing [file] into what is saved now would do. Changes nothing.
  /// Throws what the secret store throws: a rule of manual entry can depend on
  /// a stored credential.
  Future<Result<ImportPreview, BackupProblem>> preview(SetupFile file) {
    final content = switch (file) {
      _SetupFile(:final content) => content,
      _ => throw ArgumentError.value(file, 'file', 'was not read by this'),
    };
    return _database.transaction(() async {
      switch (await _plan(content)) {
        case Err(:final error):
          return Err(error);
        case Ok(value: final plan):
          // Planning the secrets finds the broken rules, and writes nothing.
          return await _planSecrets(plan) == null
              ? const Err(BackupProblem.invalidContent)
              : Ok(plan);
      }
    });
  }

  /// Imports what the user confirmed in [preview]. All of it or, if refused or
  /// if the secret store throws, nothing.
  Future<Result<void, BackupProblem>> apply(ImportPreview preview) {
    if (preview is! ImportPlan) {
      throw ArgumentError.value(preview, 'preview', 'was not made by this');
    }
    const outdated = Err<void, BackupProblem>(BackupProblem.outdatedPreview);
    return changingSecrets(_database, _secrets, _warn, (secrets) async {
      final ImportPlan now;
      switch (await _plan(preview.content)) {
        case Ok(:final value):
          now = value;
        case Err():
          return outdated;
      }
      if (!preview.matches(now)) return outdated;
      final changes = await _planSecrets(now);
      if (changes == null) return outdated;

      // The records first: a failure there leaves the secrets untouched.
      await _writeProfiles(now);
      await _writeInstances(now, changes);
      await _writePreferences(now);
      for (final change in changes.values) {
        final previous = change.previous;
        switch (change.next) {
          case final next? when next != previous:
            await secrets.write(change.key, next, previous: previous);
          case null when previous != null:
            await secrets.delete(change.key, previous: previous);
          default:
        }
      }
      return const Ok(null);
    });
  }

  // Export.

  Future<Map<String, Object?>> _payload(bool withCredentials) async {
    final profiles = await _profiles.profiles();
    final instances = <Instance>[];
    for (final profile in profiles) {
      // Not `ProfileRepository.instances`, which leaves out what it cannot read.
      final table = _database.instances;
      final query = _database.selectOnly(table)
        ..addColumns([table.id])
        ..where(table.profileId.equals(profile.id))
        ..orderBy([
          OrderingTerm(expression: table.sortOrder),
          OrderingTerm(expression: table.id),
        ]);
      for (final row in await query.get()) {
        instances.add(
          await _readable(() async {
            return (await _profiles.instance(row.read(table.id)!))!;
          }),
        );
      }
    }

    final credentials = <String, Map<String, Object?>>{};
    if (withCredentials) {
      for (final instance in instances) {
        final text = await _secrets.read(_key(instance.id));
        if (text == null) continue;
        final stored = decodeCredential(text);
        if (stored == null) throw const _Unreadable();
        _log.addCredential(stored);
        // The session stays on the device.
        final entered = jsonDecode(
          encodeCredential(withSession(stored, null)),
        ) as Map<String, Object?>;
        if (entered.isNotEmpty) credentials[instance.id] = entered;
      }
    }

    final ids = {for (final instance in instances) instance.id};
    final subscriptions = await _database
        .select(_database.notificationSubscriptions)
        .get();
    return {
      'profiles': [
        for (final profile in profiles)
          {
            'id': profile.id,
            'name': profile.name,
            'sortOrder': profile.sortOrder,
          },
      ],
      'instances': [
        for (final instance in instances)
          {
            'id': instance.id,
            'profileId': instance.profileId,
            'name': instance.name,
            'serviceType': instance.serviceType,
            'url': instance.url.toString(),
            'authKind': instance.authKind.name,
            'certPin': ?instance.certPin,
            'customCa': ?instance.customCa,
            'enabled': instance.enabled,
            'sortOrder': instance.sortOrder,
            'links': [
              for (final link in instance.links)
                {'type': link.type.name, 'instanceId': link.instanceId},
            ],
            'createdAt': instance.createdAt.toUtc().toIso8601String(),
            'updatedAt': instance.updatedAt.toUtc().toIso8601String(),
            'credential': ?credentials[instance.id],
          },
      ],
      'preferences': await _exportedPreferences(ids),
      'subscriptions': [
        for (final row in subscriptions)
          // Of a type this version does not know, nothing can be said.
          if (ids.contains(row.instanceId) &&
              subscriptionEventTypes.contains(row.eventType))
            {
              'instanceId': row.instanceId,
              'eventType': row.eventType,
              'enabled': row.enabled,
            },
      ],
    };
  }

  /// Without the active profile and app lock, which belong to the device.
  Future<Map<String, Object?>> _exportedPreferences(
    Set<String> instanceIds,
  ) async {
    final preferences = await _preferences.read();
    final views = <String, Map<String, Object?>>{};
    final table = _database.viewPreferences;
    final query = _database.selectOnly(table)
      ..addColumns([table.profileId, table.library]);
    for (final row in await query.get()) {
      final profileId = row.read(table.profileId)!;
      final library = MediaKind.values.asNameMap()[row.read(table.library)];
      if (library == null || !viewLibraries.contains(library)) continue;
      final view = await _readable(() => _preferences.view(profileId, library));
      (views[profileId] ??= {})[library.name] = {
        'layout': view.layout.name,
        'sort': sortToJson(view.sort),
        'filters': filtersToJson(view.filters),
        'instanceScope': ?view.instanceScope,
      };
    }
    final choices = <String, Object?>{};
    for (final id in instanceIds) {
      final last = await _readable(() => _preferences.lastAddChoices(id));
      if (last != null) choices[id] = addChoicesToJson(last);
    }
    return {
      'themeMode': preferences.themeMode.name,
      'trueBlack': preferences.trueBlack,
      'dynamicColor': preferences.dynamicColor,
      'loadThirdPartyArtwork': preferences.loadThirdPartyArtwork,
      if (views.isNotEmpty) 'view': views,
      if (choices.isNotEmpty) 'lastAddChoices': choices,
    };
  }

  /// [read], with what a damaged value throws turned into [_Unreadable].
  Future<T> _readable<T>(Future<T> Function() read) async {
    try {
      return await read();
    } on FormatException {
      throw const _Unreadable();
    } on ArgumentError {
      // An unknown name of an enum.
      throw const _Unreadable();
    }
  }

  // Reading.

  /// The JSON of UTF-8 [bytes], or null. The error of a failure is dropped, as
  /// it quotes the input.
  static Object? _json(List<int> bytes) {
    try {
      return jsonDecode(utf8.decode(bytes)) as Object?;
    } on FormatException {
      return null;
    }
  }

  BackupContent? _content(Object? payload, {required bool withCredentials}) {
    final content = readBackupContent(
      payload,
      withCredentials: withCredentials,
      modules: _modules,
    );
    for (final instance in content?.instances ?? const <BackupInstance>[]) {
      if (instance.credential case final credential?) {
        _log.addCredential(credential);
      }
    }
    return content;
  }

  /// The decrypted bytes of the encrypted [payload].
  static Future<Result<Uint8List, BackupProblem>> _decrypt(
    Map<String, Object?> payload,
    String? passphrase,
  ) async {
    const unsupported = Err<Uint8List, BackupProblem>(
      BackupProblem.unsupportedEncryption,
    );
    const damaged = Err<Uint8List, BackupProblem>(
      BackupProblem.wrongPassphraseOrDamaged,
    );
    final kdf = payload['kdf'];
    if (kdf is! Map<String, Object?> ||
        kdf['name'] != _kdf ||
        payload['cipher'] != _cipher) {
      return unsupported;
    }
    final memory = kdf['memoryKiB'];
    final iterations = kdf['iterations'];
    final salt = _base64(kdf['salt']);
    final nonce = _base64(payload['nonce']);
    // Checked before anything is derived with them.
    if (memory is! int ||
        memory < crypto.minimumMemoryKiB ||
        memory > crypto.maximumMemoryKiB ||
        iterations is! int ||
        iterations < 1 ||
        iterations > crypto.maximumIterations ||
        kdf['parallelism'] != 1 ||
        salt?.length != crypto.saltLength ||
        nonce?.length != crypto.nonceLength) {
      return unsupported;
    }
    if (passphrase == null) {
      return const Err(BackupProblem.passphraseRequired);
    }
    final data = _base64(payload['data']);
    if (data == null) return damaged;
    final clear = await crypto.open(
      data,
      passphrase: passphrase,
      salt: salt!,
      nonce: nonce!,
      memoryKiB: memory,
      iterations: iterations,
    );
    return clear == null ? damaged : Ok(clear);
  }

  static Uint8List? _base64(Object? value) {
    if (value is! String) return null;
    try {
      return base64.decode(value);
    } on FormatException {
      return null;
    }
  }

  // Import.

  Future<Result<ImportPlan, BackupProblem>> _plan(BackupContent content) async {
    final table = _database.instances;
    // These columns alone, as one bad value fails a whole read of rows.
    final query = _database.selectOnly(table)
      ..addColumns([table.id, table.profileId, table.name]);
    final names = [
      for (final row in await query.get())
        (
          id: row.read(table.id)!,
          profileId: row.read(table.profileId)!,
          name: row.read(table.name)!,
        ),
    ];
    final local = {for (final one in names) one.id};

    final replaced = <String, InstanceRow>{};
    try {
      for (final instance in content.instances) {
        if (!local.contains(instance.id)) continue;
        final row = await (_database.select(
          table,
        )..where((row) => row.id.equals(instance.id))).getSingle();
        // What is compared with the file must be readable.
        Uri.parse(row.url);
        replaced[row.id] = row;
      }
    } on FormatException {
      return const Err(BackupProblem.unreadableRecord);
    } on ArgumentError {
      return const Err(BackupProblem.unreadableRecord);
    }

    final plan = ImportPlan.of(
      content,
      localProfiles: await _profiles.profiles(),
      localNames: names,
      replaced: replaced,
      preferences: await _preferences.read(),
    );
    return plan == null ? const Err(BackupProblem.invalidContent) : Ok(plan);
  }

  /// What the import does to the secret of each instance whose secret it has
  /// to look at, by instance id. Reads, and writes nothing. Null if a rule of
  /// manual entry would be broken.
  Future<Map<String, _SecretChange>?> _planSecrets(ImportPlan plan) async {
    final changes = <String, _SecretChange>{};
    for (final instance in plan.content.instances) {
      final key = _key(instance.id);
      final given = instance.credential;
      final row = plan.replaced[instance.id];
      if (row == null) {
        // One left behind by a deleted instance with this id must not be sent
        // to the address of the file.
        changes[instance.id] = (
          key: key,
          previous: await _secrets.read(key),
          next: given == null ? null : encodeCredential(given),
          edited: false,
        );
        continue;
      }

      final newOrigin = isOtherOrigin(Uri.parse(row.url), instance.url);
      final newAuthKind = row.authKind != instance.authKind;
      if (given == null && !newOrigin && !newAuthKind) continue;

      final previous = await _secrets.read(key);
      final stored = previous == null ? null : decodeCredential(previous);
      if (stored != null) _log.addCredential(stored);

      String? next = previous;
      var edited = false;
      if (given != null) {
        // As the edit form saves one: the whole credential, and the session
        // only if nothing it belongs to changes.
        edited = _entered(given) != _entered(stored ?? const Credential());
        final keepsSession = !newOrigin && !newAuthKind && !edited;
        next = encodeCredential(
          withSession(given, keepsSession ? stored?.sessionCookie : null),
        );
      } else if (newOrigin) {
        // The user did not type this address.
        next = null;
      } else if (stored != null) {
        final module = _modules[instance.serviceType]!;
        if (excludesBasicAuth(module, instance.authKind) &&
            hasBasicAuth(stored)) {
          return null;
        }
        if (stored.sessionCookie != null) {
          next = encodeCredential(withSession(stored, null));
        }
      }
      changes[instance.id] = (
        key: key,
        previous: previous,
        next: next,
        edited: edited,
      );
    }
    return changes;
  }

  Future<void> _writeProfiles(ImportPlan plan) async {
    final existing = await _profiles.profiles();
    var position = _after([
      for (final profile in existing)
        if (profile.id != plan.removedProfileId) profile.sortOrder,
    ]);
    final added = <int>[];
    for (final (index, profile) in plan.profiles.indexed) {
      if (profile.action == ImportAction.add) {
        added.add(index);
        continue;
      }
      await (_database.update(_database.profiles)
            ..where((row) => row.id.equals(profile.id)))
          .write(ProfilesCompanion(name: Value(profile.name)));
    }
    _sortByPosition(added, (index) => plan.content.profiles[index].sortOrder);
    for (final index in added) {
      await _database
          .into(_database.profiles)
          .insert(
            ProfilesCompanion.insert(
              id: plan.profiles[index].id,
              name: plan.profiles[index].name,
              sortOrder: Value(position++),
            ),
          );
    }
    if (plan.removedProfileId case final removed?) {
      await _preferences.setActiveProfile(plan.profiles[added.first].id);
      await (_database.delete(
        _database.profiles,
      )..where((row) => row.id.equals(removed))).go();
    }
  }

  Future<void> _writeInstances(
    ImportPlan plan,
    Map<String, _SecretChange> secrets,
  ) async {
    final now = _now().toUtc();
    final content = plan.content;
    final names = {for (final one in plan.instances) one.id: one.name};
    final table = _database.instances;

    final positions = <String, int>{};
    for (final profileId in {
      for (final one in content.instances) one.profileId,
    }) {
      final query = _database.selectOnly(table)
        ..addColumns([table.sortOrder])
        ..where(table.profileId.equals(profileId));
      positions[profileId] = _after([
        for (final row in await query.get()) row.read(table.sortOrder)!,
      ]);
    }
    final order = [for (var i = 0; i < content.instances.length; i++) i];
    _sortByPosition(order, (index) => content.instances[index].sortOrder);

    for (final index in order) {
      final instance = content.instances[index];
      final url = instance.url.toString();
      final row = plan.replaced[instance.id];
      if (row == null) {
        final position = positions[instance.profileId]!;
        positions[instance.profileId] = position + 1;
        await _database
            .into(table)
            .insert(
              InstancesCompanion.insert(
                id: instance.id,
                profileId: instance.profileId,
                name: names[instance.id]!,
                serviceType: instance.serviceType,
                url: url,
                authKind: instance.authKind,
                certPin: Value(instance.certPin),
                customCa: Value(instance.customCa),
                enabled: Value(instance.enabled),
                sortOrder: Value(position),
                createdAt: instance.createdAt,
                updatedAt: now,
              ),
            );
        continue;
      }

      final newOrigin = isOtherOrigin(Uri.parse(row.url), instance.url);
      final newUrl = url != row.url;
      // Later than before even if the clock is not, as sessions are rebuilt
      // and probes repeated by it.
      final updatedAt = now.isAfter(row.updatedAt)
          ? now
          : row.updatedAt.toUtc().add(const Duration(milliseconds: 1));
      await (_database.update(
        table,
      )..where((other) => other.id.equals(instance.id))).write(
        InstancesCompanion(
          name: Value(names[instance.id]!),
          url: Value(url),
          authKind: Value(instance.authKind),
          authFailed: secrets[instance.id]?.edited ?? false
              ? const Value(false)
              : const Value.absent(),
          // A file without one does not take a stored one away, unless the
          // address it was accepted for goes.
          certPin: instance.certPin != null || newOrigin
              ? Value(instance.certPin)
              : const Value.absent(),
          customCa: Value(instance.customCa),
          enabled: Value(instance.enabled),
          detectedVersion: newUrl ? const Value(null) : const Value.absent(),
          unsupportedVersion: newUrl ? const Value(null) : const Value.absent(),
          createdAt: Value(instance.createdAt),
          updatedAt: Value(updatedAt),
        ),
      );
    }

    // After all instances, which the links refer to.
    for (final instance in content.instances) {
      await (_database.delete(
        _database.instanceLinks,
      )..where((link) => link.instanceId.equals(instance.id))).go();
      for (final link in instance.links) {
        await _database
            .into(_database.instanceLinks)
            .insert(
              InstanceLinksCompanion.insert(
                instanceId: instance.id,
                type: link.type,
                targetInstanceId: link.instanceId,
              ),
            );
      }
      // Without a marker, a baseline is taken before anything notifies.
      await (_database.delete(
        _database.eventMarkers,
      )..where((row) => row.instanceId.equals(instance.id))).go();
      await (_database.delete(
        _database.notificationSubscriptions,
      )..where((row) => row.instanceId.equals(instance.id))).go();
    }
    for (final subscription in content.subscriptions) {
      await _database
          .into(_database.notificationSubscriptions)
          .insert(
            NotificationSubscriptionsCompanion.insert(
              instanceId: subscription.instanceId,
              eventType: subscription.eventType,
              enabled: Value(subscription.enabled),
            ),
          );
    }
  }

  Future<void> _writePreferences(ImportPlan plan) async {
    for (final change in plan.preferenceChanges) {
      final to = change.to;
      await switch (change.setting) {
        ImportedSetting.themeMode => _preferences.setThemeMode(
          plan.content.preferences.themeMode!,
        ),
        ImportedSetting.trueBlack => _preferences.setTrueBlack(to as bool),
        ImportedSetting.dynamicColor => _preferences.setDynamicColor(
          to as bool,
        ),
        ImportedSetting.loadThirdPartyArtwork =>
          _preferences.setLoadThirdPartyArtwork(to as bool),
      };
    }
    for (final MapEntry(key: (profileId, library), value: view)
        in plan.content.views.entries) {
      await _preferences.saveView(profileId, library, view);
    }
    for (final MapEntry(key: instanceId, value: choices)
        in plan.content.addChoices.entries) {
      await _preferences.saveLastAddChoices(instanceId, choices);
    }
  }

  /// Puts [indices] in the order of their [position]s, equal ones as they were.
  static void _sortByPosition(
    List<int> indices,
    int Function(int index) position,
  ) => indices.sort((a, b) {
    final order = position(a).compareTo(position(b));
    return order != 0 ? order : a.compareTo(b);
  });

  static int _after(List<int> positions) =>
      positions.fold(0, (next, position) => max(next, position + 1));

  /// What the user entered of [credential], to compare.
  static String _entered(Credential credential) =>
      encodeCredential(withSession(credential, null));

  static Uint8List _random(int length) {
    final random = Random.secure();
    return Uint8List.fromList([
      for (var i = 0; i < length; i++) random.nextInt(256),
    ]);
  }

  // The type only: what a store puts in its errors is not known.
  void _warn(String message, Object error) =>
      _log.log(LogLevel.warning, '$message (${error.runtimeType})');

  static String _key(String instanceId) => 'cred/$instanceId';
}

/// What an import does to one secret: [next] replaces [previous], and null is
/// nothing. [edited] says that what the user enters differs.
typedef _SecretChange = ({
  String key,
  String? previous,
  String? next,
  bool edited,
});

final class _SetupFile implements SetupFile {
  _SetupFile(this.createdAt, this.includesCredentials, this.content);

  @override
  final DateTime createdAt;

  @override
  final bool includesCredentials;

  final BackupContent content;
}

/// Something saved cannot be read.
final class _Unreadable implements Exception {
  const _Unreadable();
}
