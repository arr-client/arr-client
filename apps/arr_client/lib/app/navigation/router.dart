import 'package:core/core.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../features/activity/queue/queue_details_screen.dart';
import '../../features/onboarding/instance_form_screen.dart';
import '../../features/onboarding/service_picker_screen.dart';
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

  GoRoute page(String path, String Function(AppLocalizations) title) => GoRoute(
    path: path,
    builder: (context, state) =>
        PlaceholderPage(title: title(AppLocalizations.of(context))),
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
                  builder: (context, state) => MorePage(entry: entry),
                ),
            ],
          ),
        ],
      ),
      page(searchLocation, (strings) => strings.search),
      page(addLocation, (strings) => strings.addItem),
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
          return PlaceholderPage(
            title: switch (flow) {
              InstanceFlow.releases => strings.releases,
              InstanceFlow.edit => strings.editItem,
              InstanceFlow.delete => strings.deleteItem,
              InstanceFlow.history => strings.itemHistory,
            },
          );
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
