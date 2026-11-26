/// What an import of a file would do to what is saved now.
library;

import 'dart:convert';

import '../instances/profile.dart';
import '../preferences/preferences.dart';
import '../storage/database.dart';
import 'backup_content.dart';
import 'backup_names.dart';
import 'import_action.dart';
import 'import_preview.dart';
import 'imported_setting.dart';
import 'instance_import.dart';
import 'preference_change.dart';
import 'profile_import.dart';

/// Where an instance is and what it is called, which is read even of one whose
/// other values cannot be.
typedef LocalName = ({String id, String profileId, String name});

/// An [ImportPreview] with what it was made from.
final class ImportPlan implements ImportPreview {
  ImportPlan._({
    required this.content,
    required this.profiles,
    required this.instances,
    required this.preferenceChanges,
    required this.removedProfileId,
    required this.replaced,
    required this._localState,
  });

  /// Plans the import of [content]. [localProfiles] and [localNames] are what
  /// is saved, and [replaced] the rows of the instances that the file names,
  /// by id.
  ///
  /// Null if the file would move an instance to another profile or change its
  /// service, which the app never does.
  static ImportPlan? of(
    BackupContent content, {
    required List<Profile> localProfiles,
    required List<LocalName> localNames,
    required Map<String, InstanceRow> replaced,
    required Preferences preferences,
  }) {
    for (final instance in content.instances) {
      final row = replaced[instance.id];
      if (row != null &&
          (row.profileId != instance.profileId ||
              row.serviceType != instance.serviceType)) {
        return null;
      }
    }

    final fileProfiles = {for (final profile in content.profiles) profile.id};
    final fileInstances = {for (final one in content.instances) one.id};
    final current = {for (final profile in localProfiles) profile.id: profile};
    // The empty profile of a fresh install makes way for the file's.
    final removed =
        localProfiles.length == 1 &&
            localNames.isEmpty &&
            content.profiles.isNotEmpty &&
            !fileProfiles.contains(localProfiles.single.id)
        ? localProfiles.single.id
        : null;

    final profileNames = uniqueNames(
      [
        for (final profile in content.profiles)
          (name: profile.name, current: current[profile.id]?.name),
      ],
      [
        for (final profile in localProfiles)
          if (profile.id != removed && !fileProfiles.contains(profile.id))
            profile.name,
      ],
    );
    final profiles = [
      for (final (index, profile) in content.profiles.indexed)
        ProfileImport(
          id: profile.id,
          name: profileNames[index],
          nameInFile: profile.name,
          action: current.containsKey(profile.id)
              ? ImportAction.replace
              : ImportAction.add,
        ),
    ];

    // Instance names are unique within a profile.
    final kept = <String, List<String>>{};
    final localName = <String, String>{};
    for (final local in localNames) {
      if (fileInstances.contains(local.id)) {
        localName[local.id] = local.name;
      } else {
        (kept[local.profileId] ??= []).add(local.name);
      }
    }
    final byProfile = <String, List<BackupInstance>>{};
    for (final instance in content.instances) {
      (byProfile[instance.profileId] ??= []).add(instance);
    }
    final instanceNames = <String, String>{};
    for (final MapEntry(key: profileId, value: group) in byProfile.entries) {
      final names = uniqueNames([
        for (final instance in group)
          (name: instance.name, current: localName[instance.id]),
      ], kept[profileId] ?? const []);
      for (final (index, instance) in group.indexed) {
        instanceNames[instance.id] = names[index];
      }
    }

    final instances = <InstanceImport>[];
    for (final instance in content.instances) {
      final row = replaced[instance.id];
      instances.add(
        InstanceImport(
          id: instance.id,
          profileId: instance.profileId,
          name: instanceNames[instance.id]!,
          nameInFile: instance.name,
          action: row == null ? ImportAction.add : ImportAction.replace,
          url: instance.url,
          previousUrl: row == null || row.url == instance.url.toString()
              ? null
              : Uri.parse(row.url),
          certPin: instance.certPin,
          customCa: instance.customCa,
        ),
      );
    }

    final changes = <PreferenceChange>[];
    void compare(ImportedSetting setting, Object from, Object? to) {
      if (to != null && to != from) {
        changes.add(PreferenceChange(setting: setting, from: from, to: to));
      }
    }

    final file = content.preferences;
    compare(ImportedSetting.themeMode, preferences.themeMode, file.themeMode);
    compare(ImportedSetting.trueBlack, preferences.trueBlack, file.trueBlack);
    compare(
      ImportedSetting.dynamicColor,
      preferences.dynamicColor,
      file.dynamicColor,
    );
    compare(
      ImportedSetting.loadThirdPartyArtwork,
      preferences.loadThirdPartyArtwork,
      file.loadThirdPartyArtwork,
    );

    return ImportPlan._(
      content: content,
      profiles: List.unmodifiable(profiles),
      instances: List.unmodifiable(instances),
      preferenceChanges: List.unmodifiable(changes),
      removedProfileId: removed,
      replaced: replaced,
      // Of what is saved, all that the preview or the user's decision rests on.
      localState: jsonEncode([
        removed,
        for (final profile in profiles)
          [profile.id, profile.name, current[profile.id]?.name],
        for (final instance in instances)
          [
            instance.id,
            instance.name,
            if (replaced[instance.id] case final row?) ...[
              row.name,
              row.url,
              row.authKind.name,
              row.certPin,
              row.customCa,
              row.updatedAt.toIso8601String(),
            ],
          ],
        for (final change in changes) [change.setting.name, '${change.from}'],
      ]),
    );
  }

  /// The file.
  final BackupContent content;

  /// The rows the file replaces, as read for this plan, by instance id.
  final Map<String, InstanceRow> replaced;

  final String _localState;

  @override
  final List<ProfileImport> profiles;

  @override
  final List<InstanceImport> instances;

  @override
  final List<PreferenceChange> preferenceChanges;

  @override
  final String? removedProfileId;

  /// Whether [other], made from the same file, would do the same.
  bool matches(ImportPlan other) => other._localState == _localState;
}
