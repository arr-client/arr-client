import 'instance_import.dart';
import 'preference_change.dart';
import 'profile_import.dart';

/// What confirming an import would do. Nothing has been changed.
abstract interface class ImportPreview {
  /// The file's profiles.
  List<ProfileImport> get profiles;

  /// The file's instances.
  List<InstanceImport> get instances;

  /// The settings whose values would change.
  List<PreferenceChange> get preferenceChanges;

  /// The empty profile of a fresh install that will be removed, or null.
  String? get removedProfileId;
}
