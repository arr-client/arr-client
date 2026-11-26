import 'dart:typed_data';

import '../instances/profile_repository.dart';
import '../logging/diagnostic_log.dart';
import '../module/result.dart';
import '../module/service_module.dart';
import '../preferences/preferences_repository.dart';
import '../secrets/secret_store.dart';
import '../storage/database.dart';
import 'backup_problem.dart';
import 'import_preview.dart';
import 'setup_file.dart';

/// Exports and imports the app's setup (contracts/backup-format.md).
class SetupBackup {
  /// Creates a [SetupBackup]. [profiles] and [preferences] must use the same
  /// [database], and [profiles] the same [secrets], [log] and [modules]. [now]
  /// dates the exports and what is imported.
  // T153 may change the parameters; the tests build this in one place.
  SetupBackup({
    required AppDatabase database,
    required ProfileRepository profiles,
    required PreferencesRepository preferences,
    required SecretStore secrets,
    required DiagnosticLog log,
    required Iterable<ServiceModule> modules,
    DateTime Function() now = DateTime.now,
  });

  /// The setup as the bytes of a file. Without a [passphrase] it holds no
  /// credentials; with one it holds them and is encrypted. Throws what the
  /// secret store throws.
  Future<Result<Uint8List, BackupProblem>> export({String? passphrase}) =>
      throw UnimplementedError('T153');

  /// Checks and, if encrypted, decrypts a file. Changes nothing.
  Future<Result<SetupFile, BackupProblem>> read(
    List<int> bytes, {
    String? passphrase,
  }) => throw UnimplementedError('T153');

  /// What importing [file] into what is saved now would do. Changes nothing.
  Future<Result<ImportPreview, BackupProblem>> preview(SetupFile file) =>
      throw UnimplementedError('T153');

  /// Imports what the user confirmed in [preview]. All of it or, if refused or
  /// if the secret store throws, nothing.
  Future<Result<void, BackupProblem>> apply(ImportPreview preview) =>
      throw UnimplementedError('T153');
}
