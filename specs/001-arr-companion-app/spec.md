# Feature Specification: Modular companion app for self-hosted media services

**Feature Branch**: `001-arr-companion-app`

**Created**: 2026-11-26

**Status**: Draft

**Input**: User description: "A client for Sonarr/Radarr etc. Modular, so people who self-host
select the services they want to control. Full featured (search, see details of movies/series).
Not a configuration tool, a usage tool. Flutter, Android first. Open source and free."

Clarified with the owner on 2026-11-26: the first release covers the full *arr family (Sonarr,
Radarr, Lidarr, Readarr, Bazarr, Prowlarr) plus request apps; the license is GPL-3.0.

Further direction from the owner on 2026-11-26: HTTP and HTTPS are both supported; each service is
added with its address and token, tested, then used; the user can keep several profiles with
different addresses and switches between them by hand; the only download client is qBittorrent, and
only to show how far a download has really got. The project name is `arr-client`.

## Terms

- **Service**: a kind of server software the app supports.
- **Token**: whatever a service uses to authenticate: an API key, or a user name and password.
  Elsewhere "token or login" means this.
- **Profile**: a named set of service entries (for example "Home" and "Away"). Exactly one profile
  is active at a time. (Server-side "quality profiles" and "metadata profiles" are different things
  and are always named in full.)
- **Instance**: one service entry in one profile: one address and its token or login. A profile may
  hold several instances of the same service (for example HD and 4K movie servers).
- **Library services**: movies (Radarr), series (Sonarr), music (Lidarr), books (Readarr or an
  API-compatible successor).
- **Indexer search service**: Prowlarr. **Subtitle service**: Bazarr.
- **Request service**: Seerr, and best effort for its predecessors Overseerr and Jellyseerr.
- **Download client**: qBittorrent, read only, for real download progress.

## User Scenarios & Testing *(mandatory)*

Priorities: P1 stories form the first usable release; P2 and P3 complete the 1.0 release. All
stories below are in scope for 1.0.

### User Story 1 - Connect my services (Priority: P1)

A self-hoster installs the app, picks only the services they run, enters each one's address and
token, tests the connection, and lands in an app that shows only what those services offer. They
can keep more than one profile, with different addresses, and switch between them.

**Why this priority**: Nothing else works without a connection, and this is where modularity shows.

**Independent Test**: Add one movie server, confirm the test succeeds and only movie-related
areas appear; remove it and confirm they disappear.

**Acceptance Scenarios**:

1. **Given** a first launch, **When** the user chooses a service and enters an address (HTTP or
   HTTPS) and token or login, **Then** the app tests it, reports the server's name and version and
   saves it to the active profile. A first profile exists without the user having to create one.
   If the test fails (for example when preparing an "Away" profile at home), the user can still
   save, when adding or editing; the instance then shows its failure and is probed again later.
2. **Given** a wrong token, unreachable address, wrong service type, untrusted certificate or
   denied local network permission, **When** the user tests, **Then** the message says which of
   these happened and what to do next.
3. **Given** an HTTPS server with a self-signed certificate, **When** the user is shown its
   fingerprint and accepts it, **Then** that instance connects, and a later different certificate is
   refused until the user accepts it again. A user with a private certificate authority can instead
   import its certificate for that instance, so renewed certificates keep working.
4. **Given** one profile, **When** the user creates another (empty, or as a copy of an existing one
   including its tokens) and edits addresses in it, **Then** each profile keeps its own addresses.
5. **Given** several profiles, **When** the user switches from the home screen, **Then** all content,
   searches and actions use the newly active profile only. The app never switches profile by itself.
6. **Given** no download client is configured, **When** the user views the queue, **Then** progress
   comes from the library services and no download client placeholders appear.
7. **Given** an instance exists, **When** the user disables it, **Then** it contributes no content,
   notifications or network traffic until re-enabled, and its settings are kept.
8. **Given** a server newer than the tested versions, **Then** it connects with a visible notice.
9. **Given** a rejected token or login, **Then** the app stops trying that instance automatically,
   says so, and tries again only when the credentials are edited or the user asks it to.
10. **Given** a profile, **When** the user renames or deletes it, **Then** deletion needs confirmation
   naming it and removes its stored tokens and cached data; the last profile cannot be deleted.

---

### User Story 2 - Browse movies and series and see their details (Priority: P1)

The user scrolls their movie and series libraries, filters and sorts them, and opens a title to see
artwork, overview, ratings, status, files, and for series every season and episode.

**Why this priority**: The most frequent use of any client.

**Independent Test**: With one movie and one series server, browse, filter, and open details.

**Acceptance Scenarios**:

1. **Given** a library of 2,000 movies, **When** the user opens it, **Then** a poster grid appears
   and scrolls smoothly, with each item's state (downloaded, missing, unreleased, unmonitored,
   downloading).
2. **Given** the library view, **When** the user filters by state, monitored flag, quality profile
   or tag, sorts, or types in the filter box, **Then** the list updates and the choice is remembered.
3. **Given** a movie, **When** opened, **Then** the user sees overview, year, runtime, genres,
   certification, ratings, studio, release dates, cast where the server provides it, quality
   profile, path, file details (quality, size, languages, codecs) and history.
4. **Given** a series, **When** opened, **Then** the user sees overview, year, status, network,
   runtime, genres, certification, ratings, series type, quality profile, path, size, tags,
   per-season progress, per-episode title, air date, state and file details, and history.
5. **Given** the server is unreachable but was loaded before, **When** the user opens the library,
   **Then** the last known data is shown, clearly marked with its age, and actions are disabled.
6. **Given** an item that was deleted on the server, **When** the user opens or acts on it, **Then**
   the app says it no longer exists and removes it from the list.
7. **Given** the same title in two instances, **Then** each entry shows its instance name.
8. **Given** cached data, **When** the user clears it in settings, **Then** it is removed and loaded
   again from the server next time.

---

### User Story 3 - Search for something and add it (Priority: P1)

The user searches by name, sees results with enough detail to pick the right one, and adds it to a
server with the options they want.

**Why this priority**: Adding new titles is the main reason to reach for a phone.

**Independent Test**: Search a title not in the library, add it, confirm it appears on the server.

**Acceptance Scenarios**:

1. **Given** movie and series servers, **When** the user searches once, **Then** results from both
   are shown grouped by type, each marked with the instances that already have it. A title held by
   one instance can still be added to another.

2. **Given** a result, **When** the user opens it, **Then** they see its details before adding.
3. **Given** a result not in the library, **When** adding, **Then** the user chooses instance,
   root folder, quality profile, monitoring option, tags, whether to search immediately, and the
   service-specific choices (series type and season folders for series; minimum availability for
   movies). Their last choices are preselected.
4. **Given** one search source fails, **When** others succeed, **Then** their results are shown with
   a visible notice about the failed one.
5. **Given** the item was added elsewhere meanwhile, **When** the user confirms, **Then** the app
   says it already exists and offers to open it.
6. **Given** a request service is also configured, **When** a title is found by both it and a movie
   or series server (matched by a shared TMDB or TVDB identifier), **Then** it appears once,
   offering "add" for permitted servers and "request" through the request service. Results without
   a shared identifier are shown separately.

---

### User Story 4 - Watch and fix downloads in progress (Priority: P1)

The user sees what is queued across library services, why something is stuck, and can act on it.

**Why this priority**: Stuck downloads are the commonest day-to-day problem.

**Independent Test**: With an active and a failed queue item, view them, remove one with a replacement search, and grab a delayed item at once.

**Acceptance Scenarios**:

1. **Given** active downloads, **When** the user opens Activity, **Then** items from all library
   instances appear with progress, time remaining, quality, client and state, refreshing while
   visible.
2. **Given** an item with warnings or errors, **When** opened, **Then** the server's reasons are
   shown in full.
3. **Given** a queue item, **When** the user removes it, **Then** they can choose to remove it from
   the download client and to block that release; when blocking, they can also choose whether the
   server searches for a replacement (its own settings may still prevent that). They must confirm.
   The same choices apply to several selected items, and a delayed item can be grabbed at once.
4. **Given** a completed download awaiting manual import, **When** the user opens it, **Then** they
   see candidate files with the server's matches and rejections, can correct the matched item,
   quality and language, and import the selected files.
5. **Given** history, **When** the user views it (overall or for one item), **Then** grabs, imports,
   failures, renames and deletions are listed newest first, and a grab can be marked as failed.
6. **Given** blocked releases, **When** the user opens the blocklist, **Then** they can see why each
   was blocked and remove one or several entries after confirmation.

---

### User Story 5 - Manage items and choose releases (Priority: P2)

From a title the user changes what is monitored, triggers searches, picks a specific release by
hand, edits per-item options, and deletes items or files.

**Why this priority**: Completes control of existing libraries.

**Independent Test**: Toggle monitoring on a season, run an interactive search and grab a result.

**Acceptance Scenarios**:

1. **Given** a series, season, episode or movie, **When** the user toggles monitoring, **Then** the
   server reflects it; if the server rejects it, the toggle returns and the reason is shown.
2. **Given** a movie, series, season or episode (or artist, album, author or book), **When** the
   user starts an automatic search, or a metadata refresh or disk rescan where the server offers it
   at that level, **Then** the app shows it was accepted and shows its progress or outcome.
3. **Given** a movie, season or episode, **When** the user runs an interactive search, **Then**
   releases are listed with title, indexer, size, age, quality, languages, seeders/leechers where
   relevant, score and rejection reasons, and can be sorted and filtered.
4. **Given** a rejected release, **When** the user chooses to grab it anyway, **Then** the reasons
   are repeated and a confirmation is required.
5. **Given** an item, **When** the user edits quality profile, tags, series type or minimum
   availability, or (for series, artists and authors) applies a monitoring option, **Then** the
   change is saved without altering other server fields.
6. **Given** an item, **When** the user deletes it, **Then** they choose whether to delete files and
   whether to exclude it from re-adding by import lists, and confirm in a dialog that names the item
   (no typing required).
7. **Given** several selected items, **When** the user changes monitoring, quality profile or tags,
   **Then** all are updated and any failures are listed.
8. **Given** an item changed elsewhere since it was displayed, **When** the user saves an edit,
   **Then** only the fields the user changed are applied on top of the current server state, and
   the screen refreshes.

---

### User Story 6 - See what is coming and what needs attention (Priority: P2)

A home screen and calendar show upcoming releases, recently added items, missing and below-cutoff
items, server health warnings and free disk space.

**Why this priority**: Gives an at-a-glance reason to open the app. The owner names the calendar,
seeing what is coming up and what was downloaded today, as an important part of the app.

**Independent Test**: With seeded upcoming and missing items, confirm they appear and link through.

**Acceptance Scenarios**:

1. **Given** library services, **When** the user opens the calendar, **Then** a merged agenda and
   month view shows dated releases, filterable by service, in the device's time zone.
2. **Given** missing or below-cutoff items, **When** the user opens Wanted, **Then** they can browse
   them and search one, several, or all (with confirmation showing the count).
3. **Given** a server reporting health problems or low space, **When** the home screen loads,
   **Then** these are shown read-only with the server's message and help link.
4. **Given** several instances, **When** one is unreachable, **Then** its section shows an error and
   a retry, and the rest of the home screen works.
5. **Given** imports today, **When** the user opens the calendar or home screen, **Then** "Downloaded
   today" lists what every library instance imported since local midnight, newest first, with time and
   quality, each opening its item; the user can step back to earlier days.

---

### User Story 7 - See how far a download has really got (Priority: P2)

The library services report download progress that can lag or be coarse. With qBittorrent added,
the user sees the client's own figure next to each queued item.

**Why this priority**: Answers "is it actually moving?" without leaving the app.

**Independent Test**: With an active torrent queued by a movie server, add qBittorrent and compare
the percentage shown with the one in qBittorrent.

**Acceptance Scenarios**:

1. **Given** qBittorrent is added and a queue item matches one of its torrents, **When** the user
   views the queue or the item's details, **Then** the client's percentage, speed, time remaining and
   state are shown, labelled as from qBittorrent, beside the library service's own progress, and
   refresh while visible.
2. **Given** several queue items from one torrent (for example a season pack), **Then** each shows
   the whole torrent's figures and says they are for the whole download.
3. **Given** a queue item with no matching torrent (for example a Usenet download), **Then** only the
   library service's progress is shown.
4. **Given** qBittorrent is unreachable, **Then** the queue still works with the library service's
   progress and a notice that live progress is unavailable.
5. **Given** qBittorrent, **Then** the app offers no way to add, pause, delete or otherwise change
   anything in it.

---

### User Story 8 - Music and books (Priority: P2)

The user browses, searches, adds and manages artists/albums/tracks and authors/books the same way
they do movies and series.

**Why this priority**: Required for the full family, used by fewer people than movies and series.

**Independent Test**: With a music server, add an artist, monitor one album, grab a release.

**Acceptance Scenarios**:

1. **Given** a music server, **When** browsing, **Then** artists, their albums by type, and tracks
   with file state are shown with details and artwork.
2. **Given** a book server, **When** browsing, **Then** authors, books, series membership and
   edition/file state are shown.
3. **Given** either, **When** the user searches and adds, **Then** the options include quality and
   metadata profile, root folder and monitoring choice.
4. **Given** either, **Then** queue, history, wanted, calendar, interactive search, edit and delete
   behave as in stories 4 to 6, except that manual import has no language correction for music and
   books.

---

### User Story 9 - Request media (Priority: P2)

A household member without direct access to library services discovers titles and requests them;
an administrator reviews requests.

**Why this priority**: Lets non-administrators use the app safely.

**Independent Test**: Sign in as a limited user, request a movie; approve it as an administrator.

**Acceptance Scenarios**:

1. **Given** a request service, **When** the user signs in with a service account or an
   administrator key, **Then** the app offers only what that identity is permitted to do.
2. **Given** discovery, **When** the user browses trending, popular and upcoming or searches (from
   Discover or the app-wide search), **Then** each title shows availability and request status.
3. **Given** a title unavailable in the wanted variant (standard or 4K, tracked separately), **When** the user requests it (choosing seasons for series, and
   a 4K variant where permitted), **Then** the request appears with its status.
4. **Given** pending requests, **When** a permitted user approves, declines, retries or deletes
   one, **Then** its status updates.
5. **Given** a title with a known problem, **When** the user reports an issue, **Then** it is filed
   and its comments can be read and added; a permitted user can resolve or reopen it.

---

### User Story 10 - Subtitles (Priority: P3)

The user sees which movies and episodes lack wanted subtitles and fetches them.

**Why this priority**: Valuable to some, not core.

**Independent Test**: Pick a wanted item, search providers manually, download one.

**Acceptance Scenarios**:

1. **Given** a subtitle service, **When** opened, **Then** wanted movie and episode subtitles are
   listed, with history.
2. **Given** a wanted item, **When** the user runs an automatic or manual search, **Then** manual
   results show provider, language, score and match details and can be downloaded.
3. **Given** the same title also in a configured movie or series instance that the user has linked
   to the subtitle service, **When** viewing that title, **Then** its subtitle state and actions
   appear there too.
4. **Given** existing subtitles, **When** the user deletes one or asks to synchronize it, **Then**
   the service performs it after confirmation. These are reachable by browsing titles inside the
   subtitle area, with or without linking.

---

### User Story 11 - Search indexers directly (Priority: P3)

The user runs a free-text search across indexers, and sends a result to a download client through
the indexer service.

**Why this priority**: For things outside the libraries.

**Independent Test**: Search a term, filter by category, grab one result.

**Acceptance Scenarios**:

1. **Given** an indexer service, **When** the user searches with optional category and indexer
   filters, **Then** results show title, indexer, size, age and peers, sortable.
2. **Given** a result, **When** the user grabs it, **Then** the server's acceptance or refusal is
   shown.
3. **Given** indexers, **When** viewed, **Then** their status and recent failures are shown
   read-only.

---

### User Story 12 - Be told when something happens (Priority: P3)

The user opts into notifications generated on the device, with no third-party push service.

**Why this priority**: Convenient, but limited by how often a phone may check in the background.

**Independent Test**: Enable "import completed", finish a download, receive one notification.

**Acceptance Scenarios**:

1. **Given** notifications are off by default, **When** the user enables them per instance and event
   type, **Then** the app explains that delivery is periodic and may be delayed.
2. **Given** enabled events (item imported, download failed or needing attention, new or worsened
   (warning to error) health problem, new pending request, own request
   approved/declined/available), **When** the app next checks, **Then** each event notifies once and
   tapping it opens the related screen.
3. **Given** the instance is unreachable during a check, **Then** no notification is raised for that
   and missed events are reported at the next successful check; more than 5 events for one instance
   in one check become a single summary.
4. **Given** the notification permission is denied or revoked, **Then** settings say so and offer to
   open system settings.
5. **Given** several profiles, **Then** only the active profile is checked. After switching, the
   newly active profile starts from its current state, so events from while it was inactive are not
   notified.

---

### User Story 13 - Keep my setup (Priority: P3)

The user exports their app setup and restores it on another device, and can lock the app.

**Why this priority**: Saves re-entering many addresses and keys.

**Independent Test**: Export with credentials, reinstall, import, connect without retyping.

**Acceptance Scenarios**:

1. **Given** configured instances, **When** the user exports, **Then** they choose whether to include
   credentials; including them requires a passphrase and the file is encrypted.
2. **Given** an export file, **When** imported, **Then** the user previews what will be added or
   replaced, including profiles, any address changes, imported certificate trust and changed settings, before
   anything changes. App lock is not carried between devices.
   A name that collides with another profile, or another instance in the same profile, is given a
   numbered suffix shown in the preview.
3. **Given** app lock is on, **When** the app is reopened after the chosen delay, **Then** device
   authentication is required and content is hidden from the recent-apps preview. Notification
   taps also wait behind the lock.
4. **Given** settings, **When** the user picks light, dark, true-black or system theme or dynamic
   colour, **Then** the app changes immediately; layouts adapt to phones and tablets.
5. **Given** a problem to report, **When** the user opens the diagnostic log, **Then** they can read
   it, with secrets removed, and share it only by their own action.

### Edge Cases

- A server runs behind a reverse proxy under a sub-path, needs basic authentication or extra
  headers, or the proxy answers with a login web page instead of data (report as such).
- A server redirects to a different host: credentials are not forwarded; the user is told.
- A server rejects the host name used to reach it: reported with guidance on the server's allowed
  host names.
- qBittorrent behind a proxy that wants basic authentication: with a qBittorrent API key this
  cannot be combined (both use the same header). With a user name and password, version 5.2 and
  later also reads that header as its own login, so it works only if the proxy removes the header
  before forwarding, or both user name and password are identical. The form says so, and a rejected
  attempt is not retried automatically (repeated failures can ban the proxy's address).
- The user is away from home with the home profile active: instances show as unreachable and offer
  to switch profile.
- The network changes in the middle of an action: the app does not silently resend an action that
  changes data; it reports an unknown outcome and refreshes to show the real state.
- Server version is older than supported (blocked with explanation) or newer than tested (allowed
  with a notice).
- A response contains unknown values or lacks optional fields: the screen still renders.
- An item is deleted on the server while open in the app (story 2 scenario 6).
- Very large libraries (10,000+ movies, 100,000+ episodes) and very large queues.
- Several instances of one service, including identical titles in each.
- A notification or link refers to an instance in an inactive profile: the app offers to switch.
- Two phones or the web UI change the same item concurrently (story 5 scenario 8).
- Server and device clocks or time zones differ: dates are shown from server timestamps converted
  to device time, and notification positions come from server data, never the device clock. The
  subtitle service supplies no machine-readable history time, so its text is shown as given.
- The device is offline entirely.
- The operating system kills background work or revokes a permission: background checks are
  rescheduled at next launch and the missing permission is shown in settings.

## Requirements *(mandatory)*

### Functional Requirements

**Connections and modularity**

- **FR-001**: Users MUST be able to add, test, edit, rename, reorder, disable and remove any number
  of instances of any supported service within a profile.
- **FR-002**: The app MUST show navigation, screens, search sources, dashboard content, background
  checks and notifications only for enabled instances of the active profile and only for
  capabilities they support.
- **FR-003**: Each instance MUST take one HTTP or HTTPS address (sub-path allowed) and the token or
  login its service uses, with optional HTTP basic authentication and custom headers (limits for
  qBittorrent are in Edge Cases). HTTP MUST work without warnings or extra steps.
- **FR-004**: Users MUST be able to create, copy, rename, delete and switch between profiles. The app
  MUST NOT switch profile or address by itself, and MUST show which profile is active.
- **FR-005**: The app MUST support per-instance acceptance of a self-signed certificate by
  fingerprint (refusing a changed one until accepted) or import of a private certificate authority.
- **FR-006**: The app MUST request the operating system's local network permission only when an
  instance needs it, explain why, and report clearly when it is denied.
- **FR-007**: A connection test MUST verify the service type and version and classify failures:
  unreachable, name not resolved, certificate, authentication, wrong service, proxy page,
  redirect, rejected host name, unsupported version, permission.
- **FR-008**: The supported services and minimum versions MUST be published in the documentation and
  matched by the app's behaviour (see Supported Services).

**Library**

- **FR-010**: Users MUST be able to browse each library as grid or list, filter, sort and
  text-filter it, and choose which instance or all instances of a type to view.
- **FR-011**: Detail screens MUST show the information listed in stories 2 and 8, omitting rather
  than inventing missing values.
- **FR-012**: Users MUST be able to search for new items across all enabled library instances at
  once, with in-library items marked. A request service is also a search source.
- **FR-013**: Users MUST be able to add items choosing every option listed in stories 3 and 8, from
  values the server provides.
- **FR-014**: Users MUST be able to toggle monitoring at every level the service supports.
- **FR-015**: Users MUST be able to trigger automatic search, refresh and disk rescan, and see the
  outcome.
- **FR-016**: Users MUST be able to run interactive release searches and grab results, with a
  confirmation for rejected releases.
- **FR-017**: Users MUST be able to edit per-item options, apply monitoring, quality profile and tag
  changes to several selected items, and delete items or individual files with confirmation.
- **FR-018**: Edits MUST preserve server fields the app does not display.
- **FR-019**: Users MUST NOT be able to create or edit any server configuration listed in
  constitution principle I.

**Activity**

- **FR-020**: The app MUST show a combined queue with warnings and errors, and support removal with
  the choices in story 4, force grab of delayed items, and bulk removal.
- **FR-021**: The app MUST support manual import for items awaiting it.
- **FR-025**: The app MUST show the blocklist and allow removing entries.
- **FR-022**: The app MUST show history overall and per item, and allow marking a grab as failed.
- **FR-023**: The app MUST show wanted (missing and cutoff unmet) lists with search actions.
- **FR-024**: The app MUST show a combined calendar and a home screen with upcoming, recently added,
  active downloads, health and disk space. "Recently added" means the latest import history events,
  grouped by item.
- **FR-026**: The app MUST show what was downloaded (imported) today and on a chosen earlier day, by
  the device's local day.

**Download progress**

- **FR-030**: With qBittorrent configured, the app MUST show its progress, speed, time remaining and
  state for queue items that match its torrents, as in story 7.
- **FR-031**: The app MUST NOT change anything in a download client.

**Requests**

- **FR-040**: The app MUST support sign-in to the request service with a local account, a media
  server account, or an administrator key, and honour the signed-in identity's permissions.
- **FR-041**: The app MUST support discovery, search, request, request management, quota display and
  issue reporting and resolution as in story 9.

**Subtitles and indexers**

- **FR-050**: The app MUST support wanted lists, history, automatic and manual subtitle search,
  download, delete and synchronize.
- **FR-051**: Users MUST be able to link a subtitle instance to the movie and series instances it
  serves; the app MUST NOT guess the link.
- **FR-052**: The app MUST support indexer search with filters, grabbing, and read-only indexer
  status.

**Notifications, data and settings**

- **FR-060**: Notifications MUST be opt-in per instance and event type, cover the active profile, generated on the device,
  without any third-party or project server.
- **FR-061**: The app MUST cache previously viewed library data for offline viewing, mark its age,
  and let the user clear it.
- **FR-062**: Users MUST be able to export and import their setup as in story 13.
- **FR-063**: Users MUST be able to enable app lock.
- **FR-064**: The app MUST offer light, dark, true-black and system themes, optional dynamic colour,
  phone and tablet layouts, and localizable text (English at 1.0).
- **FR-065**: The app MUST offer a user-viewable diagnostic log with credentials, headers and
  query secrets removed, shared only when the user chooses.

**Safety and behaviour**

- **FR-070**: Credentials MUST be stored in secure device storage, never logged, never included in
  device cloud backups, and sent only to the address saved for (or being tested for) their instance,
  never to another host through a redirect.
- **FR-071**: The app MUST NOT contain analytics, advertising or third-party tracking.
- **FR-072**: Destructive actions MUST require confirmation naming the target and consequence.
- **FR-073**: Actions that change data MUST NOT be queued while offline or automatically retried
  after they may have reached the server.
- **FR-074**: A failing or slow instance MUST NOT block other instances' content.
- **FR-075**: All screens MUST be usable with a screen reader, 200% text scale, and touch targets of
  at least 48 dp.

### Supported Services

Minimums are project choices and targets. A row counts as supported only once fixtures or a
recorded manual check exist for it (constitution V); until then the documentation marks it
"unverified".

| Service | Minimum | Notes (as of 2026-11-26) |
|---|---|---|
| Sonarr | 4.0 | v5 is in beta; supported through its v3-compatible interface, best effort |
| Radarr | 5.6 | 5.6 is the first version with the wanted lists |
| Lidarr | 2.0 | |
| Readarr | 0.4 | Upstream retired and archived in 2025; Bookshelf, an API-compatible fork, best effort. Other successors are not claimed |
| Prowlarr | 1.0 | |
| Bazarr | 1.5 | |
| Seerr | 3.0 | Overseerr (archived) 1.34+ and Jellyseerr 2.x best effort |
| qBittorrent | 4.4 | Read only. API key from 5.2, otherwise user name and password |

### Out of Scope for 1.0

- Any server configuration (constitution principle I).
- Managing downloads in a download client (add, pause, delete, limits, browsing its list), and
  opening magnet, torrent or NZB files.
- SABnzbd, NZBGet, Transmission and Deluge. Usenet downloads show the library service's progress.
- Automatic switching between addresses or profiles.
- Playing, streaming or downloading media to the phone.
- Media server apps (Jellyfin, Plex, Emby), statistics apps, and other services not listed.
- iOS, desktop and web releases.
- Push notifications through any server; home screen widgets; TV, watch and car interfaces.
- Single sign-on flows that require a browser-based login in front of a service (custom headers
  and basic authentication are supported). Plex account sign-in for request services.
- Client certificates (mutual TLS) and outbound HTTP proxies.
- Sync of app settings between devices.

### Key Entities

- **Profile**: name and order; one is active.
- **Instance**: profile, name, service type, address, authentication kind, certificate trust,
  enabled state, order, detected version, links to other instances.
- **Credential**: secret material belonging to one instance, held separately in secure storage.
- **Library item**: movie, series/season/episode, artist/album/track, author/book; identity scoped
  to its instance, with monitoring, state, artwork, files and options.
- **Server option**: quality profile, metadata profile, root folder, tag (read-only).
- **Release**: a candidate from an indexer, with quality, size, score and rejections.
- **Queue item / History event / Health issue / Disk space**: activity reported by a server.
- **Download progress**: what the download client reports for one torrent.
- **Discovery title / Request / Issue**: request service records.
- **Subtitle want / candidate**.
- **Notification subscription** and **seen-event marker**.
- **Setup export**: a portable, optionally encrypted description of profiles, instances and preferences.

## Success Criteria *(mandatory)*

Timings assume a mid-range phone, a server on the local network, and a healthy server.

- **SC-001**: A new user who knows their address and key connects the first service in under 2
  minutes.
- **SC-002**: A user can find a new title and add it in under 30 seconds using no more than 5 taps
  after typing, when keeping default options.
- **SC-003**: A previously viewed library of 2,000 items is visible within 2 seconds of opening the
  app, and scrolls without noticeable stutter (at least 95% of frames on time).
- **SC-004**: A library of 10,000 movies or 1,000 series loads and remains usable without the app
  crashing or freezing for more than 1 second.
- **SC-005**: With one of several instances unreachable, the others show content within 3 seconds.
- **SC-006**: No credential appears in logs, unencrypted exports or traffic to any host other than
  its instance, as verified by automated tests and a pre-release review.
- **SC-007**: The app makes zero network connections to hosts other than configured instances and
  artwork hosts those services point to or are documented to use (the latter can be switched off).
- **SC-008**: Every connection failure class in FR-007 yields its own message.
- **SC-009**: Adding a new service module requires no change to core or to other modules, apart from
  registering it in the app.
- **SC-010**: With notifications enabled, battery use unrestricted for the app, the screen having
  been on within the last hour and the server reachable, events are delivered within 30 minutes.
- **SC-011**: All primary flows pass an accessibility check with a screen reader and 200% text.

## Assumptions

- Users already run the services and can obtain their keys or passwords.
- Remote access (VPN, reverse proxy, port forwarding) is the user's responsibility.
- Notifications are best effort: the operating system controls background timing.
- Artwork may be served by the instance or by public metadata hosts that the instance names. A
  request service without image caching gives only relative paths; the app then loads them from
  image.tmdb.org without credentials, and a setting turns this off (placeholders are shown).
- Minimum Android version is 8.0.
- Distribution is through GitHub releases first, then F-Droid. Google Play is optional. Android's
  developer verification requirement, being rolled out from 2026, can add friction to installing
  apps outside a store; the owner registers the app before the first release.
- The project name is `arr-client`, hosted at `github.com/arr-client/arr-client`. The application
  identifier is `io.github.arrclient.app`; it cannot change after publication.
