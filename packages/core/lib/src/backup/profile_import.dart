import 'import_action.dart';

/// What an import does with one profile.
final class ProfileImport {
  /// Creates a [ProfileImport].
  const ProfileImport({
    required this.id,
    required this.name,
    required this.nameInFile,
    required this.action,
  });

  /// The profile's id.
  final String id;

  /// The name it will be saved with, suffixed if that in the file is in use.
  final String name;

  /// The name the file gives it.
  final String nameInFile;

  /// Whether it is added or replaces one.
  final ImportAction action;
}
