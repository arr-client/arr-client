# Contract: Upstream Interfaces Used

This file covers the services of feature 001. Each module keeps its own allow-list in
`packages/modules/<service>/test/allow_list.dart`, reviewed against the contract of the feature that
specifies it; a later service lists its requests in its own spec directory, not here.

This is the complete list of requests the app may make to a service. Every operation is marked
**R** (reads), **W** (changes server data) or **A** (authentication or session). The allow-list
test harness fails any request, of any class, that is not listed here. Anything not listed,
including every configuration write, is forbidden (FR-019). Exact parameters are fixed by
contract-test fixtures.

## Servarr family (header `X-Api-Key`)

Base: `/api/v3` Sonarr, Radarr; `/api/v1` Lidarr, Readarr, Prowlarr.

Common to Sonarr, Radarr, Lidarr, Readarr:

- **R** `GET system/status`, `health`, `diskspace`, `qualityprofile`, `rootfolder`, `tag`,
  `language`, `qualitydefinition`
- **R** `GET calendar`, `history`, `history/since`, `wanted/missing`, `wanted/cutoff`, `queue`,
  `queue/details`, `blocklist`, `release`, `command/{id}`, `manualimport`, `mediacover/...`
- **W** `DELETE queue/{id}`, `queue/bulk` (removeFromClient, blocklist, skipRedownload;
  `skipRedownload` only matters when `blocklist=true`)
- **W** `POST queue/grab/{id}`, `history/failed/{id}`, `release`. A grab sends `guid` and
  `indexerId`. For a release the server could not match (`downloadAllowed` is false) it also sends
  what was searched for, as the web UI does after a confirmation: `movieId` (Radarr), `episodeId`,
  or `seriesId` and `seasonNumber` (Sonarr), or `albumId` or `artistId` (Lidarr). No other field is
  sent.
- **W** `DELETE blocklist/{id}`, `blocklist/bulk`
- **W** `POST command` (search, refresh, rescan, manual import execution)
- **W** `POST manualimport` (reprocess a corrected candidate)

`GET queue` reads, including background checks, set the service's include-unknown flag to `true`
(`includeUnknownSeriesItems`, `includeUnknownMovieItems`, `includeUnknownArtistItems`,
`includeUnknownAuthorItems`); the default hides downloads the server cannot match. `GET queue/details`
has no such parameter: without an item filter it returns the whole queue, unmatched downloads included.

Cover artwork of a resource in the library: the `url` of its image is the web UI's path, under the
server's URL base, `/MediaCover/<id>/<file>`, or `/MediaCover/Albums/<id>/<file>` (Lidarr albums) and
`/MediaCover/Books/<id>/<file>` (Readarr books). It may carry a query, which differs by version:

- `?h=`: Radarr 6.4.0.10540 and later; Sonarr 5 (pre-release, seen in 5.0.0.3041).
- `?lastWrite=`: earlier Radarr, including the 5.6 minimum; Sonarr 4; Lidarr; Readarr.

That path is behind the web UI's authentication. The listed `mediacover/...` read, which takes the
API key, is `mediacover/<id>/<file>` on Sonarr and Radarr, `mediacover/artist/<id>/<file>` and
`mediacover/album/<id>/<file>` on Lidarr, and `mediacover/author/<id>/<file>` and
`mediacover/book/<id>/<file>` on Readarr.

A lookup result that is not in the library instead carries `/MediaCoverProxy/<hash>/<file>` in
`url`. No listed read serves that path, so its `remoteUrl` is used. Such a result has no `id`:
Radarr 7.0.3 and Sonarr 4.0.20 leave the field out rather than sending 0, and both mean the same.

Delete with an import exclusion: the query parameter is `addImportExclusion` on Radarr and
`addImportListExclusion` on Sonarr, Lidarr and Readarr.

Bookshelf reports `appName` `Readarr` in `system/status`, so the name does not tell the two apart.

Manual import language correction exists only for Sonarr and Radarr.

Tags are assigned from existing ones only; tags are never created.

| | Sonarr | Radarr | Lidarr | Readarr |
|---|---|---|---|---|
| **R** Library | `series`, `series/{id}`, `episode`, `episodefile` | `movie`, `movie/{id}`, `moviefile`, `credit` | `artist`, `artist/{id}`, `album`, `album/{id}`, `track`, `trackfile`, `metadataprofile` | `author`, `author/{id}`, `book`, `book/{id}`, `edition`, `bookfile`, `metadataprofile` |
| **R** Lookup | `series/lookup` | `movie/lookup` | `artist/lookup`, `album/lookup` | `author/lookup`, `book/lookup`, `search` |
| **R** Item history | `history/series` | `history/movie` | `history/artist` | `history/author` |
| **W** Add | `POST series` | `POST movie` | `POST artist`, `POST album` | `POST author`, `POST book` |
| **W** Edit, delete | `PUT/DELETE series/{id}`, `series/editor` | `PUT/DELETE movie/{id}`, `movie/editor` | `PUT/DELETE artist/{id}`, `artist/editor`, `PUT/DELETE album/{id}` | `PUT/DELETE author/{id}`, `author/editor`, `PUT/DELETE book/{id}`, `book/editor` |
| **W** Monitor | `PUT episode/monitor` (seasons via `series/{id}`) | via `movie/{id}` | `PUT album/monitor` | `PUT book/monitor` |
| **W** Monitoring option | `POST seasonpass` | none (toggle only) | `POST albumstudio` | `POST bookshelf` |
| **W** File delete | `DELETE episodefile/{id}` | `DELETE moviefile/{id}` | `DELETE trackfile/{id}` | `DELETE bookfile/{id}` |

## Prowlarr (`/api/v1`)

- **R** `GET system/status`, `health`, `indexer`, `indexer/categories`, `indexerstatus`, `search`
- **W** `POST search` (grab)

## Bazarr (`/api`, header `X-API-KEY`)

- **R** `GET system/status`, `series` (paged with `start`, `length`), `movies` (paged),
  `episodes` (requires `seriesid[]` or `episodeid[]`), `episodes/wanted`, `movies/wanted` (paged),
  `episodes/history`, `movies/history`, `providers/episodes`, `providers/movies`
- **W** `PATCH episodes/subtitles`, `movies/subtitles` (automatic search for a language)
- **W** `POST providers/episodes`, `providers/movies` (download the chosen candidate, including its
  `original_format`)
- **W** `DELETE episodes/subtitles`, `movies/subtitles`
- **W** `PATCH subtitles` with action `sync` only

## Seerr (`/api/v1`)

Auth is `X-Api-Key` or a session cookie. With server CSRF protection on, writes need the token
handling in research R18. Posters: research R10.

Query values, `search?query=` in particular, are percent-encoded per RFC 3986 with the query string
built by hand: spaces as `%20` (never `+`) and every reserved character escaped, including
`!'()*`, which `Uri.encodeComponent` does not all escape. Seerr rejects them with 400.

- **R** `GET /imageproxy/...` (outside `/api/v1`; paths per research R10)
- **A** `POST auth/local`, `auth/jellyfin`, `auth/logout`
- **R** `GET auth/me`, `status`, `settings/public`, `search`, `discover/trending`,
  `discover/movies`, `discover/tv`, `discover/movies/upcoming`, `discover/tv/upcoming`,
  `movie/{id}`, `tv/{id}`, `tv/{id}/season/{n}`, `user/{id}/quota`, `request`, `request/count`,
  `issue`, `issue/{id}`
- **W** `POST request`, `DELETE request/{id}`, `POST request/{id}/{approve|decline}`,
  `POST request/{id}/retry`, `POST issue`, `POST issue/{id}/comment`,
  `POST issue/{id}/{open|resolved}`

Sign-in bodies, sent without any other field, answered with the session cookie `connect.sid`:

| Sign-in | Body | Rejected |
|---|---|---|
| `POST auth/local` | `{"email", "password"}` | 403 `{"message":"Access denied."}` |
| `POST auth/jellyfin` (Jellyfin and Emby; not on Overseerr) | `{"username", "password"}` | 401 `{"message":"INVALID_CREDENTIALS"}`; 403 `Access denied.` for a user who may not be created |

`hostname`, `port` and `serverType` belong to first-time setup; a configured server refuses
`hostname`. The user object a sign-in returns is partial: identity and permissions come from
`auth/me`.

A missing session or permission, an expired session and a wrong API key all get 403
`{"status":403,"error":"You do not have permission to access this endpoint"}`; a request with neither
cookie nor key gets 401. Other 403s carry `message` (quota, 4K or blocklist refusal, CSRF). Deleting a
request or changing an issue's status without the right to is a **401** with a `message`, which must
not count as a rejected credential. With an API key, `auth/me`, which needs no permission, tells a
rejected key from a refusal: the core reads it after a 401 or the 403 above.

Permission bits (the same in all three): 2 admin (implies every other), 16 manage requests, 32
request, 1024 request 4K, 2048 4K movies, 4096 4K series, 262144 request movies, 524288 request
series, 1048576 manage issues, 2097152 view issues, 4194304 create issues. 4K is also gated by
`movie4kEnabled` and `series4kEnabled` of `settings/public`, as in the web interface.

`POST request` takes `mediaType` (`movie`, `tv`), `mediaId` (the **TMDB** id), `is4k` and, for series,
`seasons`. `POST issue` takes `issueType` (1 video, 2 audio, 3 subtitles, 4 other), `message` and
`mediaId` (**`mediaInfo.id`**). Request status: 1 pending, 2 approved, 3 declined, 4 failed,
5 completed (not in Overseerr 1.34 or early Jellyseerr). The product follows from the major version of
`status`: 1 Overseerr, 2 Jellyseerr, 3 and later Seerr. Image proxy: `imageproxy/tmdb/...` on Seerr
and Jellyseerr 2.6.0 and later, which is also where status 7 (deleted) appears.

A development build reports `develop-<commit>`. It is accepted with the newer-than-tested notice, as
Overseerr where `settings/public` has no `mediaServerType` and else as Seerr; having no version
number, it counts as newer than every release.

## qBittorrent (`/api/v2`, read only)

Either an API key (`Authorization: Bearer`, 5.2+; the `auth/` endpoints are not used with it) or a
user name and password login. Send neither `Origin` nor `Referer`: qBittorrent accepts requests
without them, and with them a proxy that rewrites `Host` causes a 401. From 5.2, an
`Authorization: Basic` header is validated as qBittorrent's own credentials before dispatch and
failures count toward an address ban: with basic auth configured, a 401 is reported with this
possible cause and never retried automatically.

- **A** `POST auth/login`, `auth/logout`
- **R** `app/version`, `app/webapiVersion`, `torrents/info`

Login responses differ by version:

| `POST auth/login` | 4.4 to 5.1 | 5.2 and later |
|---|---|---|
| Accepted | 200, body `Ok.` | 204, empty body |
| Wrong user name or password | 200, body `Fails.` | 401 |
| Address banned | 403 | 403 |
| Session cookie (default name) | `SID` | `QBT_SID_<qBittorrent's own port>` |

A 401 or 403 at login is `authFailed`, so that it is not tried again: a ban is not retried at the
rate of polling. A read with a session qBittorrent does not know gets 403 on every version, which is
what signs in again; a 401 does not.

API keys exist from 5.2.0. The user creates one in qBittorrent's web UI; it is `qbt_` followed by 28
characters. (The web UI uses `POST app/rotateAPIKey`, which replaces any existing key; the app never
calls it.) A wrong or replaced key gets 403, not 401.

There are no **W** operations. Fields used: `hash`, `infohash_v1`, `progress`, `dlspeed`, `eta`,
`state`. Matching is by hash on the device (data-model DownloadProgress).

## Host name rejection

qBittorrent (host header validation, including a port mismatch) can refuse a correct credential with
a bare 401: body `Unauthorized` on every version, which is also how 5.2 and later answer a wrong
password. The response does not identify the cause, and at login the version is not yet known (and a
proxy's basic authentication answers 401 too), so it is not mapped to `hostRejected`. Report any
qBittorrent 401 as `authFailed` and name the host name as a possible cause.
