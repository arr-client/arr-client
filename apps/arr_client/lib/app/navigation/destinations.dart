/// What the app shows for what the active profile offers
/// (contracts/navigation.md). Only capabilities decide, never a service type.
library;

import 'package:core/core.dart';

/// The primary destinations, in their order.
enum AppDestination { home, library, discover, activity, more }

/// The tabs of the library.
enum LibraryTab { movies, series, music, books }

/// The tabs of Discover.
enum DiscoverTab { browse, requests, issues }

/// The tabs of Activity.
enum ActivityTab { queue, history }

/// The entries of More, in their order.
enum MoreEntry {
  calendar,
  wanted,
  blocklist,
  subtitles,
  indexerSearch,
  services,
  settings,
}

const _aboutRequests = {
  ServicePermission.requestMovies,
  ServicePermission.requestSeries,
  ServicePermission.request4kMovies,
  ServicePermission.request4kSeries,
  ServicePermission.manageRequests,
};

const _aboutIssues = {
  ServicePermission.reportIssues,
  ServicePermission.viewIssues,
  ServicePermission.manageIssues,
};

/// What of the navigation applies to one [ProfileScope].
final class Navigation {
  /// Without a [scope], only what is always there.
  factory Navigation.of(ProfileScope? scope) {
    final offered = scope?.capabilities ?? const <CapabilityKind>{};
    final kinds = <MediaKind>{
      if (scope != null)
        for (final (_, library) in scope.providers(CapabilityKind.library))
          library.itemKind,
    };
    // What the identities of the request services may do.
    final permissions = <ServicePermission>{
      if (scope != null)
        for (final (active, _) in scope.providers(CapabilityKind.request))
          ...active.permissions,
    };
    return Navigation._(
      libraryTabs: [
        if (kinds.contains(MediaKind.movie)) LibraryTab.movies,
        if (kinds.contains(MediaKind.series)) LibraryTab.series,
        if (kinds.contains(MediaKind.artist)) LibraryTab.music,
        if (kinds.contains(MediaKind.author)) LibraryTab.books,
      ],
      discoverTabs: [
        if (offered.contains(CapabilityKind.discovery)) ...[
          DiscoverTab.browse,
          if (permissions.any(_aboutRequests.contains)) DiscoverTab.requests,
          if (permissions.any(_aboutIssues.contains)) DiscoverTab.issues,
        ],
      ],
      activityTabs: [
        if (offered.contains(CapabilityKind.queue)) ...[
          ActivityTab.queue,
          if (offered.contains(CapabilityKind.history)) ActivityTab.history,
        ],
      ],
      moreEntries: [
        if (offered.contains(CapabilityKind.calendar)) MoreEntry.calendar,
        if (offered.contains(CapabilityKind.wanted)) MoreEntry.wanted,
        // The blocklist belongs to the history capability.
        if (offered.contains(CapabilityKind.history)) MoreEntry.blocklist,
        if (offered.contains(CapabilityKind.subtitle)) MoreEntry.subtitles,
        if (offered.contains(CapabilityKind.indexerSearch))
          MoreEntry.indexerSearch,
        MoreEntry.services,
        MoreEntry.settings,
      ],
      canSearch:
          offered.contains(CapabilityKind.lookup) ||
          offered.contains(CapabilityKind.discovery),
    );
  }

  const Navigation._({
    required this.libraryTabs,
    required this.discoverTabs,
    required this.activityTabs,
    required this.moreEntries,
    required this.canSearch,
  });

  final List<LibraryTab> libraryTabs;
  final List<DiscoverTab> discoverTabs;
  final List<ActivityTab> activityTabs;
  final List<MoreEntry> moreEntries;

  /// Whether the app-wide search has anything to query.
  final bool canSearch;

  /// The destinations to show.
  List<AppDestination> get destinations => [
    AppDestination.home,
    if (libraryTabs.isNotEmpty) AppDestination.library,
    if (discoverTabs.isNotEmpty) AppDestination.discover,
    if (activityTabs.isNotEmpty) AppDestination.activity,
    AppDestination.more,
  ];
}
