# Data Model

All server-derived ids are scoped by `instanceId`; the global key of an item is
`(instanceId, kind, remoteId)`.

## Persisted

### Profile
| Field | Type | Rules |
|---|---|---|
| id | UUID | generated, immutable |
| name | string | 1–40 chars, unique ignoring case |
| sortOrder | int | |

At least one profile always exists; the first is created on first launch, named "Default". Copying a
profile creates new ids for the profile and each instance and copies their records, credentials,
links (remapped to the copies), saved views and notification subscriptions; caches and markers are not
copied. Deleting an instance or profile also deletes its subscriptions, markers, caches and secrets.
A secret is erased only after the deletion of its records is saved; see PendingSecretDeletion.

### Instance
| Field | Type | Rules |
|---|---|---|
| id | UUID | generated, immutable |
| profileId | UUID | owning Profile |
| name | string | 1–40 chars, unique ignoring case within its profile |
| serviceType | string | id of a registered module (validated against the registry); immutable |
| url | URL | http or https, may include sub-path; no userinfo, query or fragment |
| authKind | enum | apiKey, userPassword, mediaServerAccount, none |
| authFailed | bool | set by any rejected token or login; blocks all automatic requests that authenticate (polling, probes, background) until the credentials are edited or the user retries; persisted, so background work honours it |
| certPin | sha256? | accepted self-signed leaf certificate; cleared when the url's scheme, host or port changes |
| customCa | PEM? | optional private CA for this instance; at most 64 KiB |
| enabled | bool | default true |
| sortOrder | int | |
| detectedVersion | string? | from last successful test |
| lastProbe | {product, version, capabilities, permissions}? | persisted at each successful probe; drives navigation when offline. Saving a changed url without a successful test keeps its capabilities until the next probe and clears detectedVersion |
| links | list<{type, instanceId}> | `subtitlesFor` only: Bazarr → Sonarr/Radarr in the same profile; at most one of each |
| createdAt, updatedAt | datetime | UTC |

### Credential (secure storage only, key `cred/<instanceId>`)
apiKey?, username?, password?, basicUser?, basicPassword?, customHeaders map (name: valid HTTP
token, not `Host` or `Content-Length`), sessionCookie?.

Rules: secrets are sent only to the instance's saved url, or the url being tested in its form, and
never to another host by redirect. Editing the url in the app keeps the secrets: saving or testing
the form is the user's decision to use them there. A session cookie is discarded when the url's
origin changes. For imports see contracts/backup-format.md. `customHeaders` and basic auth count as
secrets. A qBittorrent API key uses `Authorization`, so basicUser cannot be combined with it; for
password login on qBittorrent 5.2+ see spec Edge Cases.

### PendingSecretDeletion
secretKey: a secure storage key still to be erased, never a secret. Added in the same transaction that
deletes an instance's records (and for a secret that could not be taken back after a failed change),
removed once the secret is erased, and retried at each launch. A key that an instance has again is
removed from the list and its secret kept. Not exported.

### Preferences
activeProfileId, themeMode, trueBlack, dynamicColor, loadThirdPartyArtwork (default true), appLock {enabled,
delaySeconds}, view (per library)
{layout, sort, filters, instanceScope}, lastAddChoices per instance.
`view` is keyed by (profileId, library), where library is the kind of its top-level items (movie,
series, artist, author); profile copy copies it with instance ids remapped. Its parts:
- layout: grid (default) or list.
- sort: {field (default title), ascending}.
- filters: {text, states[], monitored?, qualityProfiles[], tags[]}; each quality profile or tag id is
  a pair (instanceId, optionId).
- instanceScope: instanceId?; absent means all instances.

A saved scope or server filter id that no longer resolves is dropped (scope falls back to all
instances). An instance resolves while it is in the view's profile; the quality profile and tag ids of
an instance whose options are not available, for example an unreachable one, are kept.
Credential and view data of deleted instances are removed with them.

### NotificationSubscription
instanceId, eventType (imported, downloadProblem, healthIssue, pendingRequest,
ownRequestUpdate), enabled (default false).

### EventMarker
instanceId, eventType, lastSeenCursor (server history id, or server timestamp), openKeys (map of
condition key to severity; a key notifies when new or when severity rises, and is dropped when the
condition clears), requestSnapshot (map of request id to {status, availability}). Initialized from
the server's newest event, current conditions and current requests on subscribe, on import, on
re-enabling an instance and on activating its profile (at the first successful check if it is
unreachable), without notifying. Only instances of the active profile are checked.
- imported: history events after the cursor.
- downloadProblem: queue items whose severity is warning or error, plus history `failed` events
  after the cursor (condition key: instance + download id, so one failure notifies once).
- healthIssue: health entries (condition key: source + message).
- pendingRequest: ids new to the snapshot with status pending.
- ownRequestUpdate: own requests whose status becomes approved or declined, or whose availability
  becomes available or partial.

### CacheEntry
instanceId, kind, remoteId, parentRemoteId? (episodes, tracks, albums, books), sortTitle, state,
monitored, qualityProfileId, tagIds, addedAt, rawJson, fetchedAt. Keyed by (instanceId, kind,
remoteId). Deleted with its instance. The entries under a series, artist, album or author are also
removed when it is removed or a full fetch no longer has it.

### CacheFetches
instanceId, kind, parentRemoteId (-1 for a fetch of all entries of the kind), fetchedAt; keyed by the
first three. When a list was last fetched: it tells a list never fetched from one fetched and empty. A
fetch of all entries replaces the kind's earlier fetches by parent, and also records one for each
parent then cached or named by an entry. Removed with the instance, and with the parent.

## In memory

### LibraryItem (common)
ref, title, sortTitle, year?, overview?, images[], monitored, state, qualityProfileId?, tags[],
path?, sizeOnDisk, addedAt?, parent?, parentTitle?
- parent and parentTitle: an episode's series, an album's artist, a track's album, a book's author;
  absent for top-level items.
- state: downloaded, partial, missing, unreleased, downloading, unmonitored.
  Precedence: downloading > downloaded > partial > unmonitored > unreleased > missing.
- Movie: runtime, genres, certification, ratings, studio, dates, minimumAvailability, file?
- Series: seriesType, seasonFolder, network, status, runtime, genres, certification, ratings,
  seasons[]; Season: number, monitored, counts;
  Episode: season, number, title, airDateUtc?, monitored, hasFile, file?
- Artist: metadataProfileId, albums[]; Album: type, releaseDate?, monitored, tracks[];
  Track: number, discNumber, title, duration?, hasFile, file?
- Author: metadataProfileId, books[]; Book: seriesTitle?, editions[], monitored, files[];
  Edition: title, format?, isbn?, pageCount?, releaseDate?, monitored

### AddCandidate
externalIds, display fields (including parentTitle?: an album's artist or a book's author),
existingRefs[] (one per instance that already has it),
sourceByInstance {instanceId: rawJson}. Adding to a target instance whose lookup did not produce the
candidate first looks it up on that instance by external id; that rawJson is posted back.

### Release
guid, indexerId, indexer, title, protocol (torrent, usenet), size, ageHours, quality, languages[],
score, seeders?, leechers?, rejections[], rawJson. Grab sends back what the service requires.

### QueueItem
id, downloadId?, itemRef?, parent? (series, artist or author of itemRef), title, status, trackedState,
severity (ok, warning, error, unknown), messages[], progress 0–1, sizeLeft, eta?,
quality, downloadClient?, protocol, needsManualImport.

### HistoryEvent / HealthIssue / DiskSpace / Command
HistoryEvent: id, eventType (grabbed, imported, failed, renamed, deleted, other), date, itemRef?,
downloadId?, sourceTitle, details. details are the server's text values, without any that holds a URL
(also percent-encoded, or a magnet link) or looks like a secret, and without any under a key that
names a URL, GUID or secret: a grab records indexer addresses that carry the indexer's API key.
HealthIssue: source, level, message, helpUrl?. DiskSpace: path, free, total.
Command: id, name, status (queued, started, completed, failed, aborted, cancelled, orphaned,
unknown), result? (successful, unsuccessful, indeterminate, unknown), message?. `failed`,
`aborted`, `cancelled` and `orphaned` are terminal failures. `completed` is success only when
`result` is absent or `successful`; `unsuccessful` is a failure; `indeterminate` or `unknown` is shown
as an unknown outcome. An `unknown` status stops polling and is shown as an unknown outcome.

### ManualImportCandidate
path, size, downloadId?, matchedRef?, episodeIds[]/albumId/trackIds[]/bookId as the service needs,
quality, languages[], rejections[], selected, rawJson. Correction choices come from the server's
quality definitions and languages.

### DownloadProgress (from qBittorrent, not persisted)
instanceId, hash, infohashV1?, progress 0–1, downSpeed, eta?, state (queued, downloading, paused,
stalled, checking, processing, seeding, completed, error, unknown).
Matching: a QueueItem matches when its `downloadId` equals `hash` or `infohashV1`, ignoring case,
across all qBittorrent instances of the active profile (first match by instance order). Items
sharing a downloadId share one DownloadProgress.

### Other records
ServerOption {kind: qualityProfile|metadataProfile|rootFolder|tag, id, label, freeSpace?};
CalendarEvent {itemRef, title, date, dateKind, state};
ImportedItem {itemRef?, title, importedAt, quality} (history import events from local midnight of the
day to the next, grouped by item); Credit {person, role, character?, image?};
MediaFile {id, path, size, quality, languages[], video?, audio?}; BlocklistEntry {id, itemRef?,
sourceTitle, date, quality, reason};
Indexer {id, name, protocol, enabled, failureUntil?, lastFailure?}; IndexerCategory {id, name};
MediaImage {type, instancePath? (relative to the instance's url, possibly with a query),
remoteUrl? (loaded without credentials)}, the element of `images[]`.

### Request service
SessionUser {id, name, permissions, quota}; DiscoveryTitle {tmdbId, tvdbId?, year?, mediaId? (the
server's own media record id, `mediaInfo.id`, present only for
titles it already knows; issues are filed against it, so issue reporting is offered only when
present), mediaType, title, poster? (a MediaImage; the module turns the server's relative poster
path into it, research R10),
availability and availability4k (each: unknown, pending, processing, partial, available, blocklisted, deleted)};
the request action is decided per variant;
the wire value is an integer decoded per product, for both variants: 1–5 are unknown, pending,
processing, partial, available everywhere; Seerr and Jellyseerr use 6 = blocklisted and 7 = deleted
(7 absent in early Jellyseerr 2.x); Overseerr 1.35 uses 6 = deleted and has no blocklisted state;
Overseerr 1.34 stops at 5;
blocklisted offers no request action;
DiscoveryTitle also carries requestStatus? and requestStatus4k?. Request {id, title ref, requestedBy, status (pending, approved, declined, failed, completed),
availability, seasons[], is4k}; Issue {id, type, status, mediaRef, tmdbId, title, createdBy, createdAt, comments[]}.

### Subtitles
SubtitleWant {kind, seriesId?, episodeId?, radarrId?, title, missing[{language, forced, hi}]};
SubtitleCandidate {provider, language, forced, hi, score, matches[], dontMatches[], originalFormat,
token}; SubtitleFile {mediaType, mediaId, seriesId?, path, language, forced, hi};
SubtitleHistoryEvent {whenText (server-supplied relative and server-local text, shown as is; keep
the server's newest-first order), mediaRef, title, language, provider?, action, score?};
SubtitleTitle {kind, seriesId?, radarrId?, title, year?, missingCount, missing[{language, forced,
hi}] (movies and episodes), files[]}.

### SetupExport
See [contracts/backup-format.md](contracts/backup-format.md).

## Transitions
- Instance connection: unknown → probing → online | offline(failureClass); a network change or a
  profile switch returns it to unknown.
- Action: idle → submitting → accepted | rejected(reason) | outcomeUnknown → refreshed.
- Command: queued → started → completed | failed | aborted | cancelled | orphaned; outcome per the
  Command rules above.
