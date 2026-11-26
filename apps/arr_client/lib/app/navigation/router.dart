import 'package:core/core.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../features/activity/history/item_history.dart';
import '../../features/activity/queue/queue_details_screen.dart';
import '../../features/library/releases/releases_screen.dart';
import '../../features/onboarding/instance_form_screen.dart';
import '../../features/onboarding/service_picker_screen.dart';
import '../../features/search/add_request.dart';
import '../../features/search/search_screen.dart';
import '../../features/settings/instances/instances_screen.dart';
import '../../src/l10n/generated/app_localizations.dart';
import '../screens/destination_screens.dart';
import '../screens/message_page.dart';
import 'destinations.dart';
import 'instance_route.dart';
import 'locations.dart';
import 'shell.dart';

/// The routes of the app, with the screens of [modules].
GoRouter createRouter(ModuleRegistry modules) {
  StatefulShellBranch branch(
    AppDestination destination,
    Widget screen, {
    List<RouteBase> routes = const [],
  }) => StatefulShellBranch(
    routes: [
      GoRoute(
        path: destinationLocation(destination),
        builder: (context, state) => screen,
        routes: routes,
      ),
    ],
  );

  // Everything instance-scoped explains itself when its instance cannot be used.
  GoRoute scoped(
    String path,
    Widget Function(BuildContext, ActiveInstance, GoRouterState) builder, {
    String? serviceType,
  }) => GoRoute(
    path: '/instances/:instanceId$path',
    builder: (context, state) => InstanceRoute(
      instanceId: state.pathParameters['instanceId'] ?? '',
      serviceType: serviceType,
      builder: (context, active) => builder(context, active, state),
    ),
  );

  return GoRouter(
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        // In the order of [AppDestination], which the shell relies on.
        branches: [
          branch(AppDestination.home, const HomeScreen()),
          branch(AppDestination.library, const LibraryScreen()),
          branch(AppDestination.discover, const DiscoverScreen()),
          branch(AppDestination.activity, const ActivityScreen()),
          branch(
            AppDestination.more,
            const MoreScreen(),
            routes: [
              for (final entry in MoreEntry.values)
                GoRoute(
                  path: morePath(entry),
                  builder: (context, state) => entry == MoreEntry.services
                      ? const InstancesScreen()
                      : MorePage(entry: entry),
                ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: searchLocation,
        builder: (context, state) => const SearchScreen(),
      ),
      // A placeholder until the add flow is built, which works from the
      // `extra`.
      GoRoute(
        path: addLocation,
        builder: (context, state) {
          final strings = AppLocalizations.of(context);
          return switch (state.extra) {
            AddRequest(:final candidate) => MessagePage(
              title: strings.addItem,
              icon: Icons.construction_outlined,
              message: strings.addNotBuilt(candidate.title),
            ),
            _ => PlaceholderPage(title: strings.addItem),
          };
        },
      ),
      GoRoute(
        path: addInstanceLocation,
        builder: (context, state) => const ServicePickerScreen(),
        routes: [
          GoRoute(
            path: ':serviceType',
            builder: (context, state) => InstanceFormScreen.add(
              serviceType: state.pathParameters['serviceType'] ?? '',
            ),
          ),
        ],
      ),
      GoRoute(
        path: editInstancePath,
        builder: (context, state) => InstanceFormScreen.edit(
          instanceId: state.pathParameters['instanceId'] ?? '',
        ),
      ),
      for (final module in modules.modules)
        for (final screen in module.routes())
          scoped(
            '/${screen.path}',
            serviceType: module.id,
            (context, active, state) => screen.builder(
              context,
              active.context,
              {...state.pathParameters, ...state.uri.queryParameters},
            ),
          ),
      scoped(
        '/queue/:queueId',
        (context, active, state) => QueueDetailsScreen(
          instanceId: active.instance.id,
          queueId: int.tryParse(state.pathParameters['queueId'] ?? ''),
        ),
      ),
      for (final flow in InstanceFlow.values)
        scoped('/${flow.name}', (context, active, state) {
          final strings = AppLocalizations.of(context);
          return switch (flow) {
            InstanceFlow.releases => switch (releaseTarget(
              active.instance.id,
              state.uri.queryParameters,
            )) {
              final target? => ReleasesScreen(
                // Another target at the same path starts over.
                key: ValueKey(target),
                instance: active,
                target: target,
              ),
              null => MessagePage(
                title: strings.releases,
                message: strings.pageUnknown,
              ),
            },
            InstanceFlow.edit => PlaceholderPage(title: strings.editItem),
            InstanceFlow.delete => PlaceholderPage(title: strings.deleteItem),
            InstanceFlow.history => switch (itemQueryRef(
              active.instance.id,
              state.uri.queryParameters,
            )) {
              final item? => ItemHistoryScreen(
                // Another item at the same path starts over.
                key: ValueKey(item),
                instance: active,
                item: item,
              ),
              null => MessagePage(
                title: strings.itemHistory,
                message: strings.pageUnknown,
              ),
            },
          };
        }),
      scoped(
        '/$itemPlaceholderPath',
        (context, active, state) =>
            PlaceholderPage(title: state.uri.queryParameters['title'] ?? ''),
      ),
      // Any other path under an instance: the instance may be gone, or else
      // there is no such page.
      for (final path in ['', '/:rest(.*)'])
        scoped(
          path,
          (context, active, state) =>
              MessagePage(message: AppLocalizations.of(context).pageUnknown),
        ),
    ],
    errorBuilder: (context, state) =>
        MessagePage(message: AppLocalizations.of(context).pageUnknown),
  );
}
