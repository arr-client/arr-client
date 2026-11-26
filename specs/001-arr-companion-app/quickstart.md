# Quickstart: Validating the App

## Prerequisites
Flutter (version in `.fvmrc`), Android SDK with API 37, JDK 17+, Docker, an emulator or device.

## Setup
```sh
docker compose -f tool/devstack/compose.yaml up -d
flutter pub get
bash .github/scripts/codegen.sh
dart run tool/check_dependencies.dart
dart run tool/check_licenses.dart
flutter analyze
(for p in apps/arr_client packages/core packages/ui packages/servarr packages/modules/*; do
  (cd "$p" && flutter test) || exit 1; done)
cd apps/arr_client && flutter run
```
From an emulator the host machine is `10.0.2.2`; keys are printed by `tool/devstack/keys.sh`.

## Scenarios

| # | Story | Do | Expect |
|---|---|---|---|
| 1 | US1 | Add Radarr only over HTTP; test; copy the profile, change the address, switch | Name and version shown; only movie areas; each profile uses its own address |
| 2 | US1 | Wrong key; stopped container; self-signed proxy; HTML login page | A distinct message each |
| 3 | US2 | Open Movies, filter Missing, open one; stop Radarr; reopen | Details; then cached data with age, actions disabled |
| 4 | US3 | Search a title with Radarr and Sonarr, add it | Appears in the web UI with chosen options |
| 5 | US4 | Grab, watch queue, remove with blocklist; manual import a stuck item; view history, mark a grab failed; unblock | Web UI agrees at each step |
| 6 | US5 | Unmonitor a season; interactive search; edit profile | Web UI matches; other fields unchanged |
| 7 | US6 | Import something; open Calendar, "Downloaded today", Wanted and Home with one server stopped | The import is listed under today; others still load |
| 8 | US7 | Queue a torrent from Radarr; add qBittorrent; compare percentages; stop qBittorrent | Client's figure shown, then a notice and the arr figure; nothing in qBittorrent changed |
| 9 | US8 | Add artist and author | Appear with profiles chosen |
| 10 | US9 | Request as limited user; approve as admin | Status changes; limited user has no approve action |
| 11 | US10 | Manual subtitle search and download | File listed on the title |
| 12 | US11 | Indexer search and grab | Appears in qBittorrent's own web UI |
| 13 | US12 | Subscribe; complete an import; force the background task | One notification; tap opens item |
| 14 | US13 | Export with passphrase; clear data; import | Connects without retyping |

Release checks: SC-003/004 with the generated 10,000-movie fixture in profile mode; SC-006/007 by
running scenarios through an intercepting proxy;
SC-001 and SC-002 by timing three first-time users or runs; SC-010 on a physical device under the
stated conditions; SC-011 with TalkBack at 200% text; permission
behaviour on Android 17 and on Android 16.
