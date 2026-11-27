/// The primary destinations. What is offered of each follows the profile's
/// capabilities; not all of their content is built yet.
library;

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../features/activity/history/blocklist_screen.dart';
import '../../features/activity/history/history_tab.dart';
import '../../features/activity/queue/queue_tab.dart';
import '../../features/calendar/calendar_screen.dart';
import '../../features/home/home_overview.dart';
import '../../features/home/profile_switcher.dart';
import '../../features/home/refresh_home.dart';
import '../../features/home/unreachable_offer.dart';
import '../../features/library/library_controller.dart';
import '../../features/library/library_view_body.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/wanted/wanted_screen.dart';
import '../../src/l10n/generated/app_localizations.dart';
import '../navigation/destinations.dart';
import '../navigation/locations.dart';
import '../providers.dart';
import 'message_page.dart';

/// Home, which is the onboarding screen while the profile has no instance.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    final saved = ref.watch(profileInstancesProvider);
    return Scaffold(
      appBar: AppBar(
        title: switch (saved) {
          AsyncData(value: final active?) => ProfileSwitcher(
            active: active.profile,
          ),
          _ => Text(strings.navHome),
        },
        actions: [
          // Pulling down does this too, which a screen reader cannot.
          if (saved.value?.instances.isNotEmpty ?? false)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: strings.homeRefresh,
              onPressed: () => unawaited(refreshHome(ref)),
            ),
          ..._searchActions(context, ref),
        ],
      ),
      body: switch (saved) {
        AsyncData(value: final active?) when active.instances.isNotEmpty =>
          UnreachableOffer(child: HomeOverview(instances: active.instances)),
        AsyncData() => StateMessage(
          icon: Icons.dns_outlined,
          message: strings.noServicesYet,
          action: FilledButton(
            onPressed: () => context.push(addInstanceLocation),
            child: Text(strings.addService),
          ),
        ),
        AsyncError() => StateMessage(
          icon: Icons.error_outline,
          message: strings.loadFailed,
          announce: true,
        ),
        _ => const _Loading(),
      },
    );
  }
}

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    final tabs = Navigation.of(ref.watch(scopeProvider)).libraryTabs;
    final kinds = [
      for (final tab in tabs)
        switch (tab) {
          LibraryTab.movies => MediaKind.movie,
          LibraryTab.series => MediaKind.series,
          LibraryTab.music => MediaKind.artist,
          LibraryTab.books => MediaKind.author,
        },
    ];
    return _Tabbed(
      title: strings.navLibrary,
      actions: [
        if (kinds.isNotEmpty)
          // Pulling down does this too, which a screen reader cannot.
          Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: strings.libraryRefresh,
              onPressed: () {
                final kind = kinds[DefaultTabController.of(context).index];
                unawaited(ref.read(libraryProvider(kind).notifier).refresh());
              },
            ),
          ),
        ..._searchActions(context, ref),
      ],
      tabs: [
        for (final tab in tabs)
          switch (tab) {
            LibraryTab.movies => strings.tabMovies,
            LibraryTab.series => strings.tabSeries,
            LibraryTab.music => strings.tabMusic,
            LibraryTab.books => strings.tabBooks,
          },
      ],
      views: [for (final kind in kinds) LibraryViewBody(kind: kind)],
    );
  }
}

class DiscoverScreen extends ConsumerWidget {
  const DiscoverScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    final tabs = Navigation.of(ref.watch(scopeProvider)).discoverTabs;
    return _Tabbed(
      title: strings.navDiscover,
      actions: _searchActions(context, ref),
      tabs: [
        for (final tab in tabs)
          switch (tab) {
            DiscoverTab.browse => strings.tabBrowse,
            DiscoverTab.requests => strings.tabRequests,
            DiscoverTab.issues => strings.tabIssues,
          },
      ],
      views: [
        for (final tab in tabs)
          switch (tab) {
            DiscoverTab.browse => const _BrowseTab(),
            DiscoverTab.requests || DiscoverTab.issues => const _NotBuilt(),
          },
      ],
    );
  }
}

/// The request services to browse, whose screens are their modules'.
class _BrowseTab extends ConsumerWidget {
  const _BrowseTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(scopeProvider);
    return ListView(
      children: [
        if (scope != null)
          for (final (active, provider) in scope.providers(
            CapabilityKind.discovery,
          ))
            ListTile(
              title: Text(active.instance.name),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(provider.entryRoute().location),
            ),
      ],
    );
  }
}

class ActivityScreen extends ConsumerWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    final tabs = Navigation.of(ref.watch(scopeProvider)).activityTabs;
    return _Tabbed(
      title: strings.navActivity,
      tabs: [
        for (final tab in tabs)
          switch (tab) {
            ActivityTab.queue => strings.tabQueue,
            ActivityTab.history => strings.tabHistory,
          },
      ],
      views: [
        for (final tab in tabs)
          switch (tab) {
            ActivityTab.queue => const QueueTab(),
            ActivityTab.history => const HistoryTab(),
          },
      ],
    );
  }
}

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(strings.navMore)),
      body: ListView(
        children: [
          for (final entry in Navigation.of(
            ref.watch(scopeProvider),
          ).moreEntries)
            ListTile(
              leading: Icon(_moreIcon(entry)),
              title: Text(_moreTitle(strings, entry)),
              onTap: () => context.go(moreLocation(entry)),
            ),
        ],
      ),
    );
  }
}

/// A page of More. Subtitles and indexer search are screens of a module, which
/// are reached through the capability's route.
class MorePage extends ConsumerWidget {
  const MorePage({
    required this.entry,
    this.calendarTab = CalendarTab.agenda,
    super.key,
  });

  final MoreEntry entry;

  /// The view a calendar opens on.
  final CalendarTab calendarTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    final scope = ref.watch(scopeProvider);
    final title = _moreTitle(strings, entry);
    // The page can stay open while the profile changes under it.
    if (scope != null && !Navigation.of(scope).moreEntries.contains(entry)) {
      return MessagePage(title: title, message: strings.notOffered);
    }
    if (entry == MoreEntry.calendar) {
      return CalendarScreen(initialTab: calendarTab);
    }
    if (entry == MoreEntry.wanted) return const WantedScreen();
    if (entry == MoreEntry.blocklist) return const BlocklistScreen();
    if (entry == MoreEntry.settings) return const SettingsScreen();
    final owned = switch (entry) {
      MoreEntry.subtitles => [
        if (scope != null)
          for (final (active, provider) in scope.providers(
            CapabilityKind.subtitle,
          ))
            (active.instance.name, provider.entryRoute()),
      ],
      MoreEntry.indexerSearch => [
        if (scope != null)
          for (final (active, provider) in scope.providers(
            CapabilityKind.indexerSearch,
          ))
            (active.instance.name, provider.entryRoute()),
      ],
      _ => null,
    };
    if (owned == null) return PlaceholderPage(title: title);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        children: [
          for (final (name, route) in owned)
            ListTile(
              title: Text(name),
              onTap: () => context.push(route.location),
            ),
        ],
      ),
    );
  }
}

IconData _moreIcon(MoreEntry entry) => switch (entry) {
  MoreEntry.calendar => Icons.calendar_month_outlined,
  MoreEntry.wanted => Icons.bookmark_border_outlined,
  MoreEntry.blocklist => Icons.block_outlined,
  MoreEntry.subtitles => Icons.subtitles_outlined,
  MoreEntry.indexerSearch => Icons.manage_search_outlined,
  MoreEntry.services => Icons.dns_outlined,
  MoreEntry.settings => Icons.settings_outlined,
};

String _moreTitle(AppLocalizations strings, MoreEntry entry) => switch (entry) {
  MoreEntry.calendar => strings.moreCalendar,
  MoreEntry.wanted => strings.moreWanted,
  MoreEntry.blocklist => strings.moreBlocklist,
  MoreEntry.subtitles => strings.moreSubtitles,
  MoreEntry.indexerSearch => strings.moreIndexerSearch,
  MoreEntry.services => strings.moreServices,
  MoreEntry.settings => strings.moreSettings,
};

/// The search button of Home, Library and Discover, while anything can be
/// searched.
List<Widget> _searchActions(BuildContext context, WidgetRef ref) => [
  if (Navigation.of(ref.watch(scopeProvider)).canSearch)
    IconButton(
      icon: const Icon(Icons.search),
      tooltip: AppLocalizations.of(context).search,
      onPressed: () => context.push(searchLocation),
    ),
];

class _Tabbed extends StatelessWidget {
  const _Tabbed({
    required this.title,
    required this.tabs,
    this.actions = const [],
    this.views,
  });

  final String title;
  final List<String> tabs;

  /// One for each of [tabs]; without them each says it is not built.
  final List<Widget>? views;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    // While switching profile there is nothing to choose between.
    if (tabs.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: const _Loading(),
      );
    }
    return DefaultTabController(
      // Starts over when the profile offers other tabs.
      key: ValueKey(tabs.join('\n')),
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          actions: actions,
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [for (final tab in tabs) Tab(text: tab)],
          ),
        ),
        body: TabBarView(
          children: views ?? [for (final _ in tabs) const _NotBuilt()],
        ),
      ),
    );
  }
}

class _NotBuilt extends StatelessWidget {
  const _NotBuilt();

  @override
  Widget build(BuildContext context) => StateMessage(
    icon: Icons.construction_outlined,
    message: AppLocalizations.of(context).notBuilt,
  );
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => Center(
    child: CircularProgressIndicator(
      semanticsLabel: UiLocalizations.of(context).loading,
    ),
  );
}
