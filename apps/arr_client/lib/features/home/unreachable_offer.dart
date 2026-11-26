import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/providers.dart';
import '../../src/l10n/generated/app_localizations.dart';
import '../settings/profiles/switch_profile.dart';

/// [child], below an offer to switch profile while instances of the active one
/// cannot be reached and there is another to switch to (spec, edge cases). The
/// app never switches by itself.
class UnreachableOffer extends ConsumerWidget {
  const UnreachableOffer({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(scopeProvider);
    // Only failures that another address could mend.
    final unreachable = [
      for (final active in scope?.instances ?? const <ActiveInstance>[])
        if (active.connection case ConnectionOffline(
          failure: Unreachable() || DnsFailure(),
        ))
          active.instance.name,
    ];
    final others = [
      for (final profile
          in ref.watch(profilesProvider).value?.all ?? const <Profile>[])
        if (profile.id != scope?.profileId) profile,
    ];
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        children: [
          if (unreachable.isNotEmpty && others.isNotEmpty)
            // Leaves room for the content however many profiles there are.
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: constraints.maxHeight / 2),
              child: SingleChildScrollView(
                child: _Offer(unreachable: unreachable, others: others),
              ),
            )
          else
            const SizedBox.shrink(),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _Offer extends ConsumerWidget {
  const _Offer({required this.unreachable, required this.others});

  final List<String> unreachable;
  final List<Profile> others;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    return MaterialBanner(
      leading: const Icon(Icons.cloud_off_outlined),
      forceActionsBelow: true,
      content: Semantics(
        liveRegion: true,
        child: Text(
          strings.profileUnreachable(unreachable.length, unreachable.first),
        ),
      ),
      actions: [
        for (final profile in others)
          TextButton(
            onPressed: () => unawaited(switchProfile(context, ref, profile.id)),
            child: Text(strings.switchProfile(profile.name)),
          ),
      ],
    );
  }
}
