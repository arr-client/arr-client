/// The profiles (spec story 1): create, copy, rename, delete and switch.
library;

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../../app/providers.dart';
import '../../../src/l10n/generated/app_localizations.dart';
import 'profile_dialog.dart';
import 'switch_profile.dart';

/// Lists the profiles and marks the active one.
class ProfilesScreen extends ConsumerWidget {
  const ProfilesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    final saved = ref.watch(profilesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(strings.profilesTitle)),
      floatingActionButton: switch (saved) {
        AsyncData(:final value) => FloatingActionButton.extended(
          // The shell keeps other pages alive, whose buttons would share a tag.
          heroTag: null,
          onPressed: () => unawaited(_create(context, ref, value.all)),
          icon: const Icon(Icons.add),
          label: Text(strings.newProfile),
        ),
        _ => null,
      },
      body: switch (saved) {
        AsyncData(:final value) => ListView(
          // So that the last row can be scrolled above the button.
          padding: const EdgeInsets.only(bottom: 88),
          children: [
            for (final profile in value.all)
              _ProfileTile(
                key: ValueKey(profile.id),
                profile: profile,
                profiles: value,
              ),
          ],
        ),
        AsyncError() => StateMessage(
          icon: Icons.error_outline,
          message: strings.loadFailed,
          announce: true,
        ),
        _ => Center(
          child: CircularProgressIndicator(
            semanticsLabel: UiLocalizations.of(context).loading,
          ),
        ),
      },
    );
  }
}

/// Asks for a new profile, empty or a copy of one of [profiles]. Neither makes
/// the new profile active.
Future<void> _create(
  BuildContext context,
  WidgetRef ref,
  List<Profile> profiles, {
  Profile? copyOf,
}) {
  final strings = AppLocalizations.of(context);
  final services = ref.read(appServicesProvider);
  return showProfileDialog(
    context,
    title: copyOf == null ? strings.newProfile : strings.copyProfileTitle,
    confirmLabel: copyOf == null ? strings.createProfile : strings.copyProfile,
    log: services.log,
    sources: profiles,
    copyOf: copyOf?.id,
    save: (name, source) => source == null
        ? services.profiles.createProfile(name)
        : services.profiles.copyProfile(source, name: name),
  );
}

enum _Action { use, rename, copy, delete }

class _ProfileTile extends ConsumerWidget {
  const _ProfileTile({
    required this.profile,
    required this.profiles,
    super.key,
  });

  final Profile profile;
  final Profiles profiles;

  bool get _isActive => profile.id == profiles.activeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    return ListTile(
      // The subtitle says it too, so that it is not shape alone.
      leading: Icon(
        _isActive ? Icons.radio_button_checked : Icons.radio_button_unchecked,
      ),
      title: Text(profile.name),
      subtitle: _isActive ? Text(strings.activeProfile) : null,
      selected: _isActive,
      onTap: _isActive
          ? null
          : () => unawaited(switchProfile(context, ref, profile.id)),
      trailing: PopupMenuButton<_Action>(
        tooltip: strings.profileOptions(profile.name),
        onSelected: (action) => _act(context, ref, action),
        itemBuilder: (context) => [
          if (!_isActive)
            PopupMenuItem(value: _Action.use, child: Text(strings.profileUse)),
          PopupMenuItem(
            value: _Action.rename,
            child: Text(strings.profileRename),
          ),
          PopupMenuItem(value: _Action.copy, child: Text(strings.profileCopy)),
          // The last profile stays.
          if (profiles.all.length > 1)
            PopupMenuItem(
              value: _Action.delete,
              child: Text(strings.profileDelete),
            ),
        ],
      ),
    );
  }

  void _act(BuildContext context, WidgetRef ref, _Action action) {
    switch (action) {
      case _Action.use:
        unawaited(switchProfile(context, ref, profile.id));
      case _Action.rename:
        unawaited(_rename(context, ref));
      case _Action.copy:
        unawaited(_create(context, ref, profiles.all, copyOf: profile));
      case _Action.delete:
        unawaited(_delete(context, ref));
    }
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    final services = ref.read(appServicesProvider);
    return showProfileDialog(
      context,
      title: strings.renameProfileTitle,
      confirmLabel: strings.save,
      log: services.log,
      name: profile.name,
      save: (name, _) => services.profiles.renameProfile(profile.id, name),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final strings = AppLocalizations.of(context);
    final services = ref.read(appServicesProvider);
    // Taken now: the tile is gone once the profile is.
    final messenger = ScaffoldMessenger.of(context);
    // The repository makes the first remaining profile active.
    final next = _isActive
        ? profiles.all.where((other) => other.id != profile.id).firstOrNull
        : null;
    final confirmed = await showConfirmDialog(
      context,
      title: strings.deleteProfileTitle,
      target: profile.name,
      consequence: [
        strings.deleteProfileConsequence,
        if (next != null) strings.deleteActiveProfileConsequence(next.name),
      ].join('\n\n'),
      confirmLabel: strings.deleteProfile,
    );
    if (!confirmed) return;
    String? problem;
    try {
      // Erases the secrets and the cache. The instance registry follows what is
      // saved.
      final result = await services.profiles.deleteProfile(profile.id);
      if (result is Err) problem = strings.lastProfile;
    } catch (error) {
      // The type only: the text of an error may quote an address or a secret.
      services.log.log(
        LogLevel.warning,
        'A profile could not be deleted (${error.runtimeType})',
      );
      problem = strings.changeFailed;
    }
    if (problem != null && messenger.mounted) {
      messenger.showSnackBar(SnackBar(content: Text(problem)));
    }
  }
}
