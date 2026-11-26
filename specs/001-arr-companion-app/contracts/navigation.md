# Contract: Navigation and External Entry Points

## Primary destinations (shown only when an enabled instance of the active profile provides them)

| Destination | Shown when |
|---|---|
| Home | always |
| Library (Movies, Series, Music, Books tabs) | a LibraryProvider of that kind |
| Discover (Browse, Requests, Issues tabs) | a DiscoveryProvider; Requests and Issues filtered by permission |
| Activity (Queue, History tabs) | a QueueProvider |
| More (Calendar, Wanted, Blocklist, Subtitles, Indexer search, Services, Settings) | always; entries filtered by capability |

A search action is available from Home, Library and Discover; it queries every LookupProvider and
DiscoveryProvider. With no instances, Home is the onboarding
screen. The active profile's name is shown on Home with a
switcher; profiles are managed under Services. Home shows, for whatever is configured: upcoming, downloaded today, recently added, active
downloads, health and disk space (each per instance, as capabilities allow) and
recent own requests (pending ones for a request approver), so it is never blank when an instance
exists. It also always lists each instance's status, which is the whole of Home when nothing else
applies (for example only a subtitle service). Phones use a bottom bar; widths ≥ 600 dp use a navigation rail with list/detail panes.

## Routes
`/instances/:instanceId/...` for everything instance-scoped, so notifications and restores can
deep link. A route to a removed or disabled instance shows an explanation, not an error screen; a route to an
instance in an inactive profile offers to switch to that profile.

## External entry points
- Notification taps → instance-scoped routes.
- Flutter's built-in deep linking is disabled; the app declares no URL or file intent filters.
- With app lock on, every entry point authenticates first and then continues to the target.
- No exported component performs an action without user confirmation.
