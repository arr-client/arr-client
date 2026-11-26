# Contract: Service Module

Normative shape in Dart-like pseudocode. Names may be refined in implementation; the rules may not.

```dart
abstract interface class ServiceModule {
  String get id;                       // stable, used in storage and exports
  ModuleDescriptor get descriptor;     // display name, icon, category, authKinds, default port,
                                       // minimum and tested versions, authNotes
  Future<ProbeResult> probe(InstanceContext ctx); // verifies type, returns name and version
  Set<Capability> capabilitiesFor(ProbeResult probe, SessionInfo? session);
  T? capability<T extends Capability>(InstanceContext ctx);
  List<ModuleRoute> routes();          // screens owned by the module
}
```

`authNotes` are localizable warnings the module attaches to an auth kind, optionally only when HTTP
basic authentication is filled in. The add and edit form shows them without checking a module id.

## Navigation intents (declared in core)

Modules never import the app. A module screen requests shared flows through `AppNavigator`, supplied
in `InstanceContext` and implemented by the app: `openReleases(target)`, `openEdit(ref)`,
`openDelete(ref)`, `openHistory(ref)`, `openAdd(candidate)`. Detail screens may
also declare named slots that the app fills from other capabilities: `subtitles` and
`downloadProgress`. Every movie, series, episode, album and book detail screen declares both where
they can apply.

App screens reach module-owned screens only through route operations on capabilities, never
through module ids or hard-coded route strings. Each returns a `ModuleRoute`:

| Operation | Opened from |
|---|---|
| `LibraryProvider.detailRoute(ref)` | library, search (including "already exists"), queue, history, calendar, wanted, Home, notifications |
| `DiscoveryProvider.entryRoute()`, `detailRoute(title)` | Discover tab, app-wide search |
| `RequestProvider.requestRoute(title, is4k)` | app-wide search and merged results |
| `RequestProvider.requestsRoute()`, `issuesRoute()` | Discover tabs, Home, notifications |
| `SubtitleProvider.entryRoute()` | More |
| `IndexerSearchProvider.entryRoute()` | More |

`routes()` registers these with the router; the operations say which route serves which purpose.

`SessionAuthenticator` (core) performs login through a module-supplied function, stores the session
in secure storage, re-authenticates once for reads when the module's `isSessionExpired(response)`
says so (401/403 for most), and asks the user when it cannot. A rejected login sets
`Instance.authFailed`; no further automatic login or authenticated request is made while it is set.

`capabilitiesFor` results are persisted (data-model Instance.lastProbe) so navigation and cached
screens work at an offline launch.

The background engine in core composes notifications only from capabilities
(`HistoryProvider.eventsSince`, `QueueProvider.queue`, `HealthProvider.health`,
`RequestProvider.list`), for the active profile only; modules have no separate notification code.
The registry builds capabilities only for enabled instances of the active profile.

`InstanceContext` supplies the instance record, an HTTP client already configured with its
address, authentication, certificate trust and redaction, an artwork loader built on it, the navigator, a
cache scope, and a logger. Modules never create
their own HTTP clients or read secure storage directly. Session-based services receive a
`SessionAuthenticator` hook for login and re-login.

## Capabilities (declared in core)

| Capability | Operations | Providers |
|---|---|---|
| LibraryProvider | list, get, children, files, options, credits, setMonitored, applyMonitorOption, edit, bulkEdit, delete, deleteFile | sonarr radarr lidarr readarr |
| LookupProvider | lookup, addOptions, add | sonarr radarr lidarr readarr |
| CommandProvider | search, refresh, rescan, commandStatus | sonarr radarr lidarr readarr |
| ReleaseProvider | releases(target), grab | sonarr radarr lidarr readarr |
| QueueProvider | queue, remove, removeMany, grabNow, importCandidates, importChoices, reprocess, import | sonarr radarr lidarr readarr |
| HistoryProvider | history(item?), markFailed, eventsSince, blocklist, unblock | sonarr radarr lidarr readarr |
| WantedProvider | missing, cutoffUnmet | sonarr radarr lidarr readarr |
| CalendarProvider | events(from, to), recentlyAdded, importedOn(day) | sonarr radarr lidarr readarr |
| HealthProvider | health, diskSpace (Prowlarr: health only) | sonarr radarr lidarr readarr prowlarr |
| IndexerSearchProvider | indexers, categories, search, grab | prowlarr |
| DownloadProgressProvider | progress (read only) | qbittorrent |
| DiscoveryProvider | discover, search, detail | seerr |
| RequestProvider | session, quota, request, list, approve, decline, retry, delete, issues, issueDetail, reportIssue, comment, setIssueStatus | seerr |
| SubtitleProvider | browse (series, movies, episodes), wanted, history, forMedia, autoSearch, manualSearch, download, delete, sync | bazarr |

## Rules

1. Cross-service screens use capabilities only; they never check a module id.
2. A capability absent or not permitted means the matching UI is not shown (FR-002).
3. Operations return `Result<T, ServiceFailure>`; no raw transport exceptions escape a module.
4. `ServiceFailure`: unreachable, dnsFailure, certificateUntrusted, certificateChanged,
   authFailed, forbidden, wrongService, proxyInterception, redirected, hostRejected,
   unsupportedVersion, writesRefused,
   permissionDenied, notFound, conflict, validation(messages), serverError, malformedResponse,
   outcomeUnknown.
5. Read operations may be retried once; write operations never.
6. Unknown enum values map to `other`/`unknown`; unknown fields are ignored but kept in raw JSON.
7. Each module ships its request allow-list with its tests; core holds only the checking logic.
8. A module registers by being added to `apps/arr_client/lib/app/modules.dart` and nowhere else.
