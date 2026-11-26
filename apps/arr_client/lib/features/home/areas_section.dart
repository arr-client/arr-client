import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/navigation/destinations.dart';
import '../../app/navigation/locations.dart';
import '../../app/navigation/shell.dart';
import '../../app/providers.dart';
import '../../src/l10n/generated/app_localizations.dart';
import 'home_section.dart';

/// Links to the primary destinations that the active profile's services
/// provide; nothing while there is none, as with only a subtitle service.
class AreasSection extends ConsumerWidget {
  const AreasSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    final areas = [
      for (final destination in Navigation.of(
        ref.watch(scopeProvider),
      ).destinations)
        // Home is here, and More is there whatever is configured.
        if (destination != AppDestination.home &&
            destination != AppDestination.more)
          destination,
    ];
    if (areas.isEmpty) return const SliverToBoxAdapter();
    return HomeSection(
      title: strings.homeAreas,
      children: [
        for (final area in areas)
          ListTile(
            leading: Icon(destinationIcon(area)),
            title: Text(destinationLabel(strings, area)),
            onTap: () => context.go(destinationLocation(area)),
          ),
      ],
    );
  }
}
