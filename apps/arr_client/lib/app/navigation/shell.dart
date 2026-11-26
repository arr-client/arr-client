import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../src/l10n/generated/app_localizations.dart';
import '../providers.dart';
import 'destinations.dart';

/// From this width on, a navigation rail replaces the bottom bar.
const railBreakpoint = 600.0;

/// The frame around the primary destinations: a bottom bar or a rail with those
/// the active profile offers.
class AppShell extends ConsumerWidget {
  const AppShell({required this.shell, super.key});

  /// Has one branch for each [AppDestination], in their order.
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(scopeProvider);
    final offered = Navigation.of(scope).destinations;
    final current = AppDestination.values[shell.currentIndex];
    // While switching profile it is not yet known what stays.
    final shown = [
      for (final destination in AppDestination.values)
        if (offered.contains(destination) ||
            scope == null && destination == current)
          destination,
    ];

    // The current destination has gone: leave it for Home, but not from under
    // a page that is open above. Asking for the route rebuilds this when that
    // page is closed.
    final onTop = ModalRoute.isCurrentOf(context) ?? true;
    if (onTop && !shown.contains(current)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) shell.goBranch(AppDestination.home.index);
      });
    }
    final selected = shown.contains(current) ? shown.indexOf(current) : 0;

    void select(int index) {
      final branch = shown[index].index;
      // Choosing the current one again goes back to its first page.
      shell.goBranch(branch, initialLocation: branch == shell.currentIndex);
    }

    final strings = AppLocalizations.of(context);
    String label(AppDestination destination) => switch (destination) {
      AppDestination.home => strings.navHome,
      AppDestination.library => strings.navLibrary,
      AppDestination.discover => strings.navDiscover,
      AppDestination.activity => strings.navActivity,
      AppDestination.more => strings.navMore,
    };

    final wide = MediaQuery.sizeOf(context).width >= railBreakpoint;
    // The same tree for both, so that turning the device keeps the state of the
    // screens.
    return Scaffold(
      body: Row(
        children: [
          if (wide)
            SafeArea(
              right: false,
              child: NavigationRail(
                scrollable: true,
                labelType: NavigationRailLabelType.all,
                selectedIndex: selected,
                onDestinationSelected: select,
                destinations: [
                  for (final destination in shown)
                    NavigationRailDestination(
                      icon: Icon(_icon(destination)),
                      selectedIcon: Icon(_selectedIcon(destination)),
                      label: Text(label(destination)),
                    ),
                ],
              ),
            )
          else
            const SizedBox.shrink(),
          // The rail keeps clear of the left inset, so the screens beside it
          // must not again. Wrapped in both layouts, to keep their state.
          Expanded(
            // The context below the Scaffold: its MediaQuery already lacks the
            // bottom padding and keyboard that the Scaffold has dealt with.
            child: Builder(
              builder: (context) => MediaQuery.removePadding(
                context: context,
                removeLeft: wide,
                child: shell,
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: selected,
              onDestinationSelected: select,
              destinations: [
                for (final destination in shown)
                  NavigationDestination(
                    icon: Icon(_icon(destination)),
                    selectedIcon: Icon(_selectedIcon(destination)),
                    label: label(destination),
                  ),
              ],
            ),
    );
  }

  static IconData _icon(AppDestination destination) => switch (destination) {
    AppDestination.home => Icons.home_outlined,
    AppDestination.library => Icons.video_library_outlined,
    AppDestination.discover => Icons.explore_outlined,
    AppDestination.activity => Icons.downloading_outlined,
    AppDestination.more => Icons.menu_outlined,
  };

  static IconData _selectedIcon(AppDestination destination) =>
      switch (destination) {
        AppDestination.home => Icons.home,
        AppDestination.library => Icons.video_library,
        AppDestination.discover => Icons.explore,
        AppDestination.activity => Icons.downloading,
        AppDestination.more => Icons.menu,
      };
}
