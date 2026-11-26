/// Why a setup could not be exported or imported.
///
/// None carries any of the file's content or the passphrase.
enum BackupProblem {
  /// An export with credentials needs a passphrase of 10 characters or more.
  passphraseTooShort,

  /// The file is over 1 MiB, or the export would be.
  tooLarge,

  /// Not UTF-8 JSON of a setup export.
  notASetupFile,

  /// Written by a newer version of the format.
  newerVersion,

  /// Key derivation or cipher settings the app does not accept.
  unsupportedEncryption,

  /// The file is encrypted and no passphrase was given.
  passphraseRequired,

  /// The passphrase is wrong or the file was changed; which cannot be told.
  wrongPassphraseOrDamaged,

  /// A record breaks the schema or a rule of manual entry.
  invalidContent,

  /// What is saved changed after the preview, which no longer holds.
  outdatedPreview,
}
