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
- **W** `POST queue/grab/{id}`, `history/failed/{id}`, `release`
- **W** `DELETE blocklist/{id}`, `blocklist/bulk`
- **W** `POST command` (search, refresh, rescan, manual import execution)
- **W** `POST manualimport` (reprocess a corrected candidate)

Queue reads, including background checks, set the service's include-unknown flag to `true`
(`includeUnknownSeriesItems`, `includeUnknownMovieItems`, `includeUnknownArtistItems`,
`includeUnknownAuthorItems`); the default hides downloads the server cannot match.

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

## qBittorrent (`/api/v2`, read only)

Either an API key (`Authorization: Bearer`, 5.2+; the `auth/` endpoints are not used with it) or a
user name and password login. Send neither `Origin` nor `Referer`: qBittorrent accepts requests
without them, and with them a proxy that rewrites `Host` causes a 401. From 5.2, an
`Authorization: Basic` header is validated as qBittorrent's own credentials before dispatch and
failures count toward an address ban: with basic auth configured, a 401 is reported with this
possible cause and never retried automatically.

- **A** `POST auth/login`, `auth/logout`
- **R** `app/version`, `app/webapiVersion`, `torrents/info`

There are no **W** operations. Fields used: `hash`, `infohash_v1`, `progress`, `dlspeed`, `eta`,
`state`. Matching is by hash on the device (data-model DownloadProgress).

## Host name rejection

qBittorrent (host header validation, including a port mismatch) can refuse a correct credential with
a bare 401. Name this as a possible cause of any qBittorrent 401; classify `hostRejected` only where
it can be told apart (4.x password login, where a bad password is a 200 "Fails."). Where the response identifies this, map
it to `hostRejected`.
