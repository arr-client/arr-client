/// The primary destinations. What is offered of each follows the profile's
/// capabilities; the content is not built yet.
library;

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../features/activity/queue/queue_tab.dart';
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
    final profile = ref.watch(activeProfileProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(switch (profile) {
          AsyncData(value: final active?) => active.profile.name,
          _ => strings.navHome,
        }),
        actions: _searchActions(context, ref),
      ),
      body: switch (profile) {
        AsyncData(value: final active?) when active.hasInstances =>
          const _NotBuilt(),
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
    return _Tabbed(
      title: strings.navLibrary,
      actions: _searchActions(context, ref),
      tabs: [
        for (final tab in Navigation.of(ref.watch(scopeProvider)).libraryTabs)
          switch (tab) {
            LibraryTab.movies => strings.tabMovies,
            LibraryTab.series => strings.tabSeries,
            LibraryTab.music => strings.tabMusic,
            LibraryTab.books => strings.tabBooks,
          },
      ],
    );
  }
}

class DiscoverScreen extends ConsumerWidget {
  const DiscoverScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    return _Tabbed(
      title: strings.navDiscover,
      actions: _searchActions(context, ref),
      tabs: [
        for (final tab in Navigation.of(ref.watch(scopeProvider)).discoverTabs)
          switch (tab) {
            DiscoverTab.browse => strings.tabBrowse,
            DiscoverTab.requests => strings.tabRequests,
            DiscoverTab.issues => strings.tabIssues,
          },
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
            ActivityTab.history => const _NotBuilt(),
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
  const MorePage({required this.entry, super.key});

  final MoreEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    final scope = ref.watch(scopeProvider);
    final title = _moreTitle(strings, entry);
    // The page can stay open while the profile changes under it.
    if (scope != null && !Navigation.of(scope).moreEntries.contains(entry)) {
      return MessagePage(title: title, message: strings.notOffered);
    }
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
