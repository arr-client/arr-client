import 'import_action.dart';

/// What an import does with one instance. Holds no secrets.
final class InstanceImport {
  /// Creates an [InstanceImport].
  const InstanceImport({
    required this.id,
    required this.profileId,
    required this.name,
    required this.nameInFile,
    required this.action,
    required this.url,
    this.previousUrl,
    this.certPin,
    this.customCa,
  });

  /// The instance's id.
  final String id;

  /// The profile it will be in.
  final String profileId;

  /// The name it will be saved with, suffixed if that in the file is in use.
  final String name;

  /// The name the file gives it.
  final String nameInFile;

  /// Whether it is added or replaces one.
  final ImportAction action;

  /// The address it will have.
  final Uri url;

  /// The address it has now, if the import changes it; otherwise null.
  final Uri? previousUrl;

  /// The certificate fingerprint the file would make the app trust.
  final String? certPin;

  /// The certificate authority the file would make the app trust, PEM.
  final String? customCa;
}
