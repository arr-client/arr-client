import 'package:drift/drift.dart';

import '../logging/diagnostic_log.dart';
import '../logging/log_level.dart';
import '../module/module_category.dart';
import '../module/module_descriptor.dart';
import '../module/result.dart';
import '../module/service_module.dart';
import '../preferences/preferences_repository.dart';
import '../secrets/secret_store.dart';
import '../storage/database.dart';
import 'credential.dart';
import 'credential_json.dart';
import 'instance.dart';
import 'instance_draft.dart';
import 'instance_link.dart';
import 'instance_rules.dart';
import 'probe_snapshot_json.dart';
import 'profile.dart';
import 'rule_violation.dart';
import 'uuid.dart';

/// Stores profiles, their instances and the instances' credentials.
///
/// Records are kept in the database and credentials in the [SecretStore]. Every
/// change runs in one database transaction, secret writes included, so changes
/// do not interleave. A refused change returns [Err] and changes nothing.
/// Naming a profile or instance to change that does not exist is an
/// [ArgumentError]; deleting or latching one that is gone does nothing.
///
/// Credentials are registered with the [DiagnosticLog] as soon as they are
/// given or read.
///
/// The secret store may fail:
///
/// - A failed read or write throws what the store threw, and the change is not
///   made. Saving new credentials works even if the old ones cannot be read.
/// - A failed delete does not keep an instance or profile from being deleted.
///   It is logged, and the secret, which nothing reads any more, stays in the
///   store.
class ProfileRepository {
  /// Creates a [ProfileRepository]. [preferences] must use the same [database].
  /// [modules] are the registered ones. [now] dates the instances.
  ProfileRepository({
    required this._database,
    required this._secrets,
    required this._log,
    required this._preferences,
    required Iterable<ServiceModule> modules,
    this._now = DateTime.now,
  }) : _modules = {for (final module in modules) module.id: module.descriptor};

  static const _defaultName = 'Default';

  final AppDatabase _database;
  final SecretStore _secrets;
  final DiagnosticLog _log;
  final PreferencesRepository _preferences;
  final Map<String, ModuleDescriptor> _modules;
  final DateTime Function() _now;

  /// Creates the first profile if there is none, and makes a profile active if
  /// none is. Call at every launch.
  Future<void> ensureDefaultProfile() => _database.transaction(() async {
    final existing = await profiles();
    final first = existing.isEmpty
        ? await _insertProfile(_defaultName, existing)
        : existing.first;
    if ((await _preferences.read()).activeProfileId == null) {
      await _preferences.setActiveProfile(first.id);
    }
  });

  /// All profiles, in their order.
  Future<List<Profile>> profiles() async {
    final query = _database.select(_database.profiles)
      ..orderBy([
        (row) => OrderingTerm(expression: row.sortOrder),
        (row) => OrderingTerm(expression: row.id),
      ]);
    return [
      for (final row in await query.get())
        Profile(id: row.id, name: row.name, sortOrder: row.sortOrder),
    ];
  }

  /// Adds an empty profile after the others. It does not become active.
  Future<Result<Profile, RuleViolation>> createProfile(String name) =>
      _database.transaction(() async {
        final existing = await profiles();
        final violation = _checkProfileName(name, existing);
        if (violation != null) return Err(violation);
        return Ok(await _insertProfile(name, existing));
      });

  /// Renames a profile.
  Future<Result<void, RuleViolation>> renameProfile(String id, String name) =>
      _database.transaction(() async {
        final existing = await profiles();
        _require(existing.any((profile) => profile.id == id), id);
        final violation = _checkProfileName(name, existing, except: id);
        if (violation != null) return Err(violation);
        await (_database.update(_database.profiles)
              ..where((row) => row.id.equals(id)))
            .write(ProfilesCompanion(name: Value(name)));
        return const Ok(null);
      });

  /// Copies a profile with its instances, their credentials, links and
  /// notification subscriptions, and its saved views. The copies have new ids.
  /// Caches, event markers and last add choices are not copied.
  Future<Result<Profile, RuleViolation>> copyProfile(
    String id, {
    required String name,
  }) => _changing((secrets) async {
    final existing = await profiles();
    _require(existing.any((profile) => profile.id == id), id);
    final violation = _checkProfileName(name, existing);
    if (violation != null) return Err(violation);

    final copy = await _insertProfile(name, existing);
    final originals = await _instanceRows(id);
    final ids = {for (final row in originals) row.id: newUuid()};
    final now = _now().toUtc();

    for (final row in originals) {
      await _database
          .into(_database.instances)
          .insert(
            row.copyWith(
              id: ids[row.id],
              profileId: copy.id,
              createdAt: now,
              updatedAt: now,
            ),
          );
    }
    // After all instances, which the links refer to.
    for (final MapEntry(key: from, value: to) in ids.entries) {
      for (final link in await _linkRows([from])) {
        await _database
            .into(_database.instanceLinks)
            .insert(
              link.copyWith(
                instanceId: to,
                targetInstanceId: ids[link.targetInstanceId],
              ),
            );
      }
      final subscriptions = await (_database.select(
        _database.notificationSubscriptions,
      )..where((row) => row.instanceId.equals(from))).get();
      for (final subscription in subscriptions) {
        await _database
            .into(_database.notificationSubscriptions)
            .insert(subscription.copyWith(instanceId: to));
      }
    }
    await _preferences.copyViews(
      fromProfileId: id,
      toProfileId: copy.id,
      instanceIds: ids,
    );
    for (final MapEntry(key: from, value: to) in ids.entries) {
      final stored = await credential(from);
      if (stored != null) {
        await secrets.write(_key(to), encodeCredential(stored), previous: null);
      }
    }
    return Ok(copy);
  });

  /// Deletes a profile with its instances and everything of theirs. If it was
  /// active, the first remaining one becomes active.
  Future<Result<void, RuleViolation>> deleteProfile(String id) =>
      _database.transaction(() async {
        final existing = await profiles();
        if (!existing.any((profile) => profile.id == id)) return const Ok(null);
        if (existing.length == 1) return const Err(RuleViolation.lastProfile);

        final active = (await _preferences.read()).activeProfileId;
        for (final row in await _instanceRows(id)) {
          await _deleteSecret(row.id);
        }
        // The database cascades to the instances and everything of theirs.
        await (_database.delete(
          _database.profiles,
        )..where((row) => row.id.equals(id))).go();
        if (active == id || active == null) {
          await _preferences.setActiveProfile(
            existing.firstWhere((profile) => profile.id != id).id,
          );
        }
        return const Ok(null);
      });

  /// The instances of a profile, in their order.
  Future<List<Instance>> instances(String profileId) =>
      _database.transaction(() async {
        final rows = await _instanceRows(profileId);
        final links = await _linkRows([for (final row in rows) row.id]);
        return [for (final row in rows) _instance(row, links)];
      });

  /// One instance, or null.
  Future<Instance?> instance(String id) => _database.transaction(() async {
    final row = await _instanceRow(id);
    return row == null ? null : _instance(row, await _linkRows([id]));
  });

  /// Adds an instance after the others of a profile.
  Future<Result<Instance, RuleViolation>> addInstance(
    String profileId,
    InstanceDraft draft, {
    Credential credential = const Credential(),
  }) {
    _log.addCredential(credential);
    return _changing((secrets) async {
      _require(
        (await profiles()).any((profile) => profile.id == profileId),
        profileId,
      );
      final siblings = await _instanceRows(profileId);
      final violation =
          _checkDraft(draft, siblings) ?? _checkCredential(draft, credential);
      if (violation != null) return Err(violation);

      final id = newUuid();
      final now = _now().toUtc();
      final probe = draft.probe;
      await _database
          .into(_database.instances)
          .insert(
            InstancesCompanion.insert(
              id: id,
              profileId: profileId,
              name: draft.name,
              serviceType: draft.serviceType,
              url: draft.url.toString(),
              authKind: draft.authKind,
              certPin: Value(draft.acceptedCertPin),
              customCa: Value(draft.customCa),
              enabled: Value(draft.enabled),
              sortOrder: Value(_after([for (final s in siblings) s.sortOrder])),
              detectedVersion: Value(probe?.version),
              lastProbe: Value(
                probe == null ? null : encodeProbeSnapshot(probe),
              ),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await _insertLinks(id, draft.links);
      final encoded = encodeCredential(credential);
      if (encoded != encodeCredential(const Credential())) {
        await secrets.write(_key(id), encoded, previous: null);
      }
      return Ok((await instance(id))!);
    });
  }

  /// Saves the edit form of an instance. A null [credential] keeps the stored
  /// one; otherwise it replaces it as a whole.
  ///
  /// When the scheme, host or port changes, the session cookie is dropped.
  Future<Result<Instance, RuleViolation>> updateInstance(
    String id,
    InstanceDraft draft, {
    Credential? credential,
  }) {
    if (credential != null) _log.addCredential(credential);
    return _changing((secrets) async {
      final row = await _instanceRow(id);
      if (row == null) throw ArgumentError.value(id, 'id', 'does not exist');
      if (draft.serviceType != row.serviceType) {
        return const Err(RuleViolation.serviceTypeChanged);
      }
      final violation = _checkDraft(
        draft,
        await _instanceRows(row.profileId),
        id: id,
      );
      if (violation != null) return Err(violation);

      final newOrigin = isOtherOrigin(Uri.parse(row.url), draft.url);
      final newUrl = draft.url.toString() != row.url;
      var credentialEdited = false;
      if (credential == null) {
        final refused = await _keepCredential(row, draft, newOrigin, secrets);
        if (refused != null) return Err(refused);
      } else {
        switch (await _replaceCredential(
          id,
          draft,
          credential,
          newOrigin,
          secrets,
        )) {
          case Ok(:final value):
            credentialEdited = value;
          case Err(:final error):
            return Err(error);
        }
      }

      final probe = draft.probe;
      await (_database.update(
        _database.instances,
      )..where((other) => other.id.equals(id))).write(
        InstancesCompanion(
          name: Value(draft.name),
          url: Value(draft.url.toString()),
          authKind: Value(draft.authKind),
          authFailed: credentialEdited
              ? const Value(false)
              : const Value.absent(),
          certPin: draft.acceptedCertPin != null || newOrigin
              ? Value(draft.acceptedCertPin)
              : const Value.absent(),
          customCa: Value(draft.customCa),
          enabled: Value(draft.enabled),
          detectedVersion: probe != null || newUrl
              ? Value(probe?.version)
              : const Value.absent(),
          lastProbe: probe != null
              ? Value(encodeProbeSnapshot(probe))
              : const Value.absent(),
          updatedAt: Value(_now().toUtc()),
        ),
      );
      await (_database.delete(
        _database.instanceLinks,
      )..where((link) => link.instanceId.equals(id))).go();
      await _insertLinks(id, draft.links);
      return Ok((await instance(id))!);
    });
  }

  /// Deletes an instance with its credential, subscriptions, markers, cache and
  /// the saved choices and views that name it.
  Future<void> deleteInstance(String id) => _database.transaction(() async {
    if (await _instanceRow(id) == null) return;
    await _deleteSecret(id);
    await _preferences.removeInstanceFromViews(id);
    // The database cascades to the other rows of the instance.
    await (_database.delete(
      _database.instances,
    )..where((row) => row.id.equals(id))).go();
  });

  /// The credential of an instance, or null if none is stored. Throws what the
  /// secret store throws.
  Future<Credential?> credential(String instanceId) async {
    final text = await _secrets.read(_key(instanceId));
    if (text == null) return null;
    final credential = decodeCredential(text);
    if (credential != null) _log.addCredential(credential);
    return credential;
  }

  /// Records that the instance rejected its credentials. Until the user edits
  /// them or retries, nothing may authenticate with them automatically.
  Future<void> markAuthFailed(String instanceId) =>
      _setAuthFailed(instanceId, true);

  /// Clears [markAuthFailed] because the user asked to try again.
  Future<void> retryAuth(String instanceId) =>
      _setAuthFailed(instanceId, false);

  Future<void> _setAuthFailed(String id, bool failed) async {
    await (_database.update(_database.instances)
          ..where((row) => row.id.equals(id)))
        .write(InstancesCompanion(authFailed: Value(failed)));
  }

  /// For an edit that keeps the stored credential. It is read only if the edit
  /// can break a rule or must drop the session, so that other edits work even
  /// if the store does not.
  Future<RuleViolation?> _keepCredential(
    InstanceRow row,
    InstanceDraft draft,
    bool newOrigin,
    _SecretChanges secrets,
  ) async {
    // The stored one was checked against the stored authKind.
    final module = _modules[draft.serviceType]!;
    final newlyExclusive =
        excludesBasicAuth(module, draft.authKind) &&
        !excludesBasicAuth(module, row.authKind);
    if (!newOrigin && !newlyExclusive) return null;

    final stored = await credential(row.id);
    if (stored == null) return null;
    final violation = _checkCredential(draft, stored);
    if (violation != null) return violation;
    if (newOrigin && stored.sessionCookie != null) {
      await secrets.write(
        _key(row.id),
        encodeCredential(_withoutSession(stored)),
        previous: encodeCredential(stored),
      );
    }
    return null;
  }

  /// Stores [given] for an instance. The value is whether it differs from the
  /// stored credential in what the user enters.
  Future<Result<bool, RuleViolation>> _replaceCredential(
    String id,
    InstanceDraft draft,
    Credential given,
    bool newOrigin,
    _SecretChanges secrets,
  ) async {
    // The user must be able to replace a credential that cannot be read. It
    // then counts as none.
    Credential? stored;
    var unreadable = false;
    try {
      stored = await credential(id);
    } catch (error) {
      unreadable = true;
      _warn('A stored credential could not be read', error);
    }
    // A cookie that may be the stored one does not follow to a new origin.
    final next =
        newOrigin &&
            (unreadable || given.sessionCookie == stored?.sessionCookie)
        ? _withoutSession(given)
        : given;
    final violation = _checkCredential(draft, next);
    if (violation != null) return Err(violation);

    final before = stored ?? const Credential();
    final encoded = encodeCredential(next);
    if (unreadable || encoded != encodeCredential(before)) {
      await secrets.write(
        _key(id),
        encoded,
        previous: stored == null ? null : encodeCredential(stored),
        restorable: !unreadable,
      );
    }
    return Ok(
      encodeCredential(_withoutSession(next)) !=
          encodeCredential(_withoutSession(before)),
    );
  }

  /// Runs [change] in a transaction. If it fails, the secrets it wrote are put
  /// back, as far as the store allows.
  Future<T> _changing<T>(
    Future<T> Function(_SecretChanges secrets) change,
  ) async {
    final secrets = _SecretChanges(_secrets, _warn);
    try {
      return await _database.transaction(() => change(secrets));
    } catch (_) {
      await secrets.undo();
      rethrow;
    }
  }

  Future<void> _deleteSecret(String instanceId) async {
    try {
      await _secrets.delete(_key(instanceId));
    } catch (error) {
      _warn('A deleted credential could not be erased', error);
    }
  }

  // Only the type: what a store puts in its errors is not known, and the
  // credential may never have been registered.
  void _warn(String message, Object error) =>
      _log.log(LogLevel.warning, '$message (${error.runtimeType})');

  Future<Profile> _insertProfile(String name, List<Profile> existing) async {
    final profile = Profile(
      id: newUuid(),
      name: name,
      sortOrder: _after([for (final other in existing) other.sortOrder]),
    );
    await _database
        .into(_database.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: profile.id,
            name: name,
            sortOrder: Value(profile.sortOrder),
          ),
        );
    return profile;
  }

  RuleViolation? _checkProfileName(
    String name,
    List<Profile> existing, {
    String? except,
  }) {
    if (!hasValidNameLength(name)) return RuleViolation.nameLength;
    final taken = existing.any(
      (profile) => profile.id != except && isSameName(profile.name, name),
    );
    return taken ? RuleViolation.nameTaken : null;
  }

  /// The rules for a draft saved as the instance [id], or as a new one, among
  /// the instances [siblings] of its profile.
  RuleViolation? _checkDraft(
    InstanceDraft draft,
    List<InstanceRow> siblings, {
    String? id,
  }) {
    final module = _modules[draft.serviceType];
    if (module == null) return RuleViolation.unknownServiceType;
    if (!hasValidNameLength(draft.name)) return RuleViolation.nameLength;
    if (siblings.any((s) => s.id != id && isSameName(s.name, draft.name))) {
      return RuleViolation.nameTaken;
    }
    if (!isValidInstanceUrl(draft.url)) return RuleViolation.url;
    final customCa = draft.customCa;
    if (customCa != null && !fitsCustomCa(customCa)) {
      return RuleViolation.customCaTooLarge;
    }

    if (draft.links.isEmpty) return null;
    if (module.category != ModuleCategory.subtitles) return RuleViolation.link;
    final linked = <ModuleCategory>{};
    for (final link in draft.links) {
      final target = siblings.where((s) => s.id == link.instanceId).firstOrNull;
      final category = _modules[target?.serviceType]?.category;
      // At most one of each category.
      if (category == null ||
          !isSubtitleTarget(category) ||
          !linked.add(category)) {
        return RuleViolation.link;
      }
    }
    return null;
  }

  RuleViolation? _checkCredential(InstanceDraft draft, Credential credential) {
    if (!credential.customHeaders.keys.every(isValidHeaderName)) {
      return RuleViolation.headerName;
    }
    final module = _modules[draft.serviceType]!;
    return excludesBasicAuth(module, draft.authKind) && hasBasicAuth(credential)
        ? RuleViolation.basicAuthWithApiKey
        : null;
  }

  Future<void> _insertLinks(String instanceId, List<InstanceLink> links) async {
    for (final link in links) {
      await _database
          .into(_database.instanceLinks)
          .insert(
            InstanceLinksCompanion.insert(
              instanceId: instanceId,
              type: link.type,
              targetInstanceId: link.instanceId,
            ),
          );
    }
  }

  Future<InstanceRow?> _instanceRow(String id) => (_database.select(
    _database.instances,
  )..where((row) => row.id.equals(id))).getSingleOrNull();

  Future<List<InstanceRow>> _instanceRows(String profileId) =>
      (_database.select(_database.instances)
            ..where((row) => row.profileId.equals(profileId))
            ..orderBy([
              (row) => OrderingTerm(expression: row.sortOrder),
              (row) => OrderingTerm(expression: row.id),
            ]))
          .get();

  Future<List<InstanceLinkRow>> _linkRows(List<String> instanceIds) =>
      (_database.select(_database.instanceLinks)
            ..where((link) => link.instanceId.isIn(instanceIds))
            ..orderBy([
              (link) => OrderingTerm(expression: link.targetInstanceId),
            ]))
          .get();

  Instance _instance(InstanceRow row, List<InstanceLinkRow> links) {
    final lastProbe = row.lastProbe;
    return Instance(
      id: row.id,
      profileId: row.profileId,
      name: row.name,
      serviceType: row.serviceType,
      url: Uri.parse(row.url),
      authKind: row.authKind,
      authFailed: row.authFailed,
      certPin: row.certPin,
      customCa: row.customCa,
      enabled: row.enabled,
      sortOrder: row.sortOrder,
      detectedVersion: row.detectedVersion,
      lastProbe: lastProbe == null ? null : decodeProbeSnapshot(lastProbe),
      links: [
        for (final link in links)
          if (link.instanceId == row.id)
            InstanceLink(type: link.type, instanceId: link.targetInstanceId),
      ],
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  static String _key(String instanceId) => 'cred/$instanceId';

  static Credential _withoutSession(Credential credential) => Credential(
    apiKey: credential.apiKey,
    username: credential.username,
    password: credential.password,
    basicUser: credential.basicUser,
    basicPassword: credential.basicPassword,
    customHeaders: credential.customHeaders,
  );

  static int _after(List<int> sortOrders) =>
      sortOrders.fold(0, (next, order) => order >= next ? order + 1 : next);

  static void _require(bool exists, String id) {
    if (!exists) throw ArgumentError.value(id, 'id', 'does not exist');
  }
}

/// The secret writes of one change, so that they can be taken back.
final class _SecretChanges {
  _SecretChanges(this._secrets, this._warn);

  final SecretStore _secrets;
  final void Function(String message, Object error) _warn;
  final _previous = <String, String?>{};

  /// Writes [value]. [previous] is what [key] holds now, null for nothing; if
  /// that is unknown, pass `restorable: false`.
  Future<void> write(
    String key,
    String value, {
    required String? previous,
    bool restorable = true,
  }) {
    // Before the write: a failed one may have removed the previous value.
    if (restorable) _previous[key] = previous;
    return _secrets.write(key, value);
  }

  Future<void> undo() async {
    for (final MapEntry(:key, value: previous) in _previous.entries) {
      try {
        if (previous == null) {
          await _secrets.delete(key);
        } else {
          await _secrets.write(key, previous);
        }
      } catch (error) {
        _warn('A credential could not be put back', error);
      }
    }
  }
}
