import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/navigation/locations.dart';
import '../../app/providers.dart';
import '../../src/l10n/generated/app_localizations.dart';
import '../settings/profiles/switch_profile.dart';

/// A profile to switch to, or none to manage them. A record, as a menu takes a
/// null value for a dismissal.
typedef _Choice = ({String? profileId});

/// The name of the active profile, which opens the choice of another.
class ProfileSwitcher extends ConsumerWidget {
  const ProfileSwitcher({required this.active, super.key});

  final Profile active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    final profiles = ref.watch(profilesProvider).value?.all ?? [active];
    return PopupMenuButton<_Choice>(
      tooltip: strings.chooseProfile,
      position: PopupMenuPosition.under,
      onSelected: (choice) {
        final id = choice.profileId;
        if (id == null) {
          unawaited(context.push(profilesLocation));
        } else if (id != active.id) {
          unawaited(switchProfile(context, ref, id));
        }
      },
      itemBuilder: (context) => [
        for (final profile in profiles)
          CheckedPopupMenuItem(
            value: (profileId: profile.id),
            checked: profile.id == active.id,
            child: Text(profile.name),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: (profileId: null),
          child: Text(strings.manageProfiles),
        ),
      ],
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: kMinInteractiveDimension,
          minHeight: kMinInteractiveDimension,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: Text(active.name, overflow: TextOverflow.ellipsis)),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }
}
