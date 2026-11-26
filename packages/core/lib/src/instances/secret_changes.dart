/// Changes to the database and the secret store that stand or fall together.
library;

import 'package:drift/drift.dart';

import '../secrets/secret_store.dart';
import '../storage/database.dart';

/// Logs a warning about [error], naming no secret.
typedef SecretWarning = void Function(String message, Object error);

/// Runs [change] in a transaction of [database]. If it fails, the secrets it
/// wrote or deleted are put back, as far as the store allows.
Future<T> changingSecrets<T>(
  AppDatabase database,
  SecretStore store,
  SecretWarning warn,
  Future<T> Function(SecretChanges secrets) change,
) async {
  final secrets = SecretChanges._(store, warn);
  try {
    return await database.transaction(() async {
      try {
        return await change(secrets);
      } catch (_) {
        // Before the transaction ends, so that no other change reads or
        // overwrites what is being put back.
        await secrets._undo();
        rethrow;
      }
    });
  } catch (_) {
    // For a failed commit; after the above there is nothing left to undo.
    await secrets._undo();
    try {
      await addPendingSecretDeletions(database, secrets._notErased);
    } catch (error) {
      // The failure of the change is what the caller must see.
      warn('A credential left behind could not be noted', error);
    }
    rethrow;
  }
}

/// Notes secure storage keys that are still to be erased (data-model.md
/// PendingSecretDeletion).
Future<void> addPendingSecretDeletions(
  AppDatabase database,
  Iterable<String> keys,
) async {
  for (final key in keys) {
    await database
        .into(database.pendingSecretDeletions)
        .insert(
          PendingSecretDeletionsCompanion.insert(secretKey: key),
          mode: InsertMode.insertOrIgnore,
        );
  }
}

/// The secret writes of one change, so that they can be taken back.
final class SecretChanges {
  SecretChanges._(this._secrets, this._warn);

  final SecretStore _secrets;
  final SecretWarning _warn;
  final _previous = <String, String?>{};

  /// Keys that [_undo] should have erased and could not.
  final _notErased = <String>[];

  /// Writes [value]. [previous] is what [key] holds now, null for nothing; if
  /// that is unknown, pass `restorable: false`.
  Future<void> write(
    String key,
    String value, {
    required String? previous,
    bool restorable = true,
  }) {
    // Before the write: a failed one may have removed the previous value.
    if (restorable) _previous.putIfAbsent(key, () => previous);
    return _secrets.write(key, value);
  }

  /// Deletes what [key] holds, which is [previous].
  Future<void> delete(String key, {required String previous}) {
    // Before the delete: a failed one may have removed the value all the same.
    _previous.putIfAbsent(key, () => previous);
    return _secrets.delete(key);
  }

  /// Puts back what was changed. Does so once: another call does nothing.
  Future<void> _undo() async {
    final changed = Map.of(_previous);
    _previous.clear();
    for (final MapEntry(:key, value: previous) in changed.entries) {
      try {
        if (previous == null) {
          await _secrets.delete(key);
        } else {
          await _secrets.write(key, previous);
        }
      } catch (error) {
        if (previous == null) _notErased.add(key);
        _warn('A credential could not be put back', error);
      }
    }
  }
}
