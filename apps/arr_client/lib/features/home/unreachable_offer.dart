import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/providers.dart';
import '../../src/l10n/generated/app_localizations.dart';
import '../settings/profiles/switch_profile.dart';

/// [child], below an offer to switch profile while instances of the active one
/// cannot be reached and there is another to switch to (spec, edge cases). They
/// can also be checked again. The app never switches by itself.
class UnreachableOffer extends ConsumerStatefulWidget {
  const UnreachableOffer({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<UnreachableOffer> createState() => _UnreachableOfferState();
}

class _UnreachableOfferState extends ConsumerState<UnreachableOffer> {
  /// The ids of the instances last found unreachable, which stay so while they
  /// are checked again.
  var _unreachable = <String>{};

  @override
  Widget build(BuildContext context) {
    final scope = ref.watch(scopeProvider);
    final instances = scope?.instances ?? const <ActiveInstance>[];
    _unreachable = {
      for (final active in instances)
        if (switch (active.connection) {
          // Only failures that another address could mend.
          ConnectionOffline(:final failure) =>
            failure is Unreachable || failure is DnsFailure,
          ConnectionProbing() => _unreachable.contains(active.instance.id),
          ConnectionUnknown() || ConnectionOnline() => false,
        })
          active.instance.id,
    };
    final unreachable = [
      for (final active in instances)
        if (_unreachable.contains(active.instance.id)) active,
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
          Expanded(child: widget.child),
        ],
      ),
    );
  }
}

class _Offer extends ConsumerWidget {
  const _Offer({required this.unreachable, required this.others});

  final List<ActiveInstance> unreachable;
  final List<Profile> others;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    final checking = unreachable.any(
      (active) => active.connection is ConnectionProbing,
    );
    return MaterialBanner(
      leading: const Icon(Icons.cloud_off_outlined),
      forceActionsBelow: true,
      content: Semantics(
        liveRegion: true,
        child: Text(
          strings.profileUnreachable(
            unreachable.length,
            unreachable.first.instance.name,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: checking
              ? null
              : () {
                  final prober = ref.read(appServicesProvider).prober;
                  for (final active in unreachable) {
                    prober.probe(active.instance.id);
                  }
                },
          child: Text(checking ? strings.checkingAgain : strings.tryAgain),
        ),
        for (final profile in others)
          TextButton(
            onPressed: () => unawaited(switchProfile(context, ref, profile.id)),
            child: Text(strings.switchProfile(profile.name)),
          ),
      ],
    );
  }
}
