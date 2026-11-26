# Tasks: Modular companion app

**Input**: spec.md, plan.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: required for adapters (constitution V): write them first and see them fail. Every adapter
test also runs under the allow-list harness with its module's `test/allow_list.dart` (FR-019).

Format: `- [ ] ID [P] [Story] description`. [P] = may run alongside neighbouring [P] tasks: different
files and no dependency on an unfinished task in the same phase. Unmarked tasks run in order.

## Phase 1: Setup

- [ ] T001 Create pub workspace in `pubspec.yaml` (exact `environment.flutter` version, matching `.fvmrc`) with app and package skeletons per plan.md and `flutter_lints` as a root dev dependency (the existing root `analysis_options.yaml` includes it, so CI fails without it); extend `.gitignore`
- [ ] T002 Owner decision: confirm the immutable application id and developer verification registration (name is `arr-client`); record in `docs/decisions.md`
- [ ] T003 Create Android project in `apps/arr_client/android/` using the confirmed id, minSdk 26, compile/target 37, declaring `android.permission.INTERNET` in `src/main/AndroidManifest.xml` (the template adds it only to debug and profile builds)
- [ ] T004 [P] Check that every package is analyzed under the root `analysis_options.yaml` as `docs/standards/coding-standards.md` requires, with no package-level overrides
- [ ] T005 [P] Write `tool/check_dependencies.dart` enforcing plan.md allowed dependencies, with tests in `tool/test/`
- [ ] T006 [P] Write `tool/check_licenses.dart` rejecting GPL-incompatible and proprietary dependencies
- [ ] T007 Verify that the existing `.github/workflows/ci.yml`, once code exists, runs formatting, analysis, package tests, tool tests, the dependency and license checks, a debug APK build and emulator integration tests (`.github/scripts/codegen.sh` builds generated files, which are not committed); add a `pub` entry to `.github/dependabot.yml`
- [ ] T008 [P] Add build and run instructions to `README.md` and `CONTRIBUTING.md`
- [ ] T009 [P] Add `docs/verification-matrix.md` listing every service and minimum/best-effort row of spec Supported Services as unverified
- [ ] T010 [P] Create dev stack in `tool/devstack/compose.yaml` and `tool/devstack/keys.sh`, including a self-signed reverse proxy and an HTML login page proxy
- [ ] T011 [P] Write `tool/gen_large_library.dart` producing 10,000-movie and 1,000-series fixtures
- [ ] T012 [P] Write `tool/sanitize_fixture.dart` removing keys, hosts, paths and user data, with tests

## Phase 2: Foundational (blocks all stories)

- [ ] T013 Define module contract, capabilities, `ServiceFailure`, `AppNavigator`, capability route operations, detail slots and `SessionAuthenticator` interface in `packages/core/lib/src/module/` per contracts/module-contract.md
- [ ] T014 Configure SQLite source build (research R17) and implement drift database in `packages/core/lib/src/storage/database.dart` with migration test and a CI check that no prebuilt binary is downloaded
- [ ] T015 Define `SecretStore` in `packages/core/lib/src/secrets/` and implement it in `apps/arr_client/lib/app/platform/secret_store.dart`
- [ ] T016 Implement cache repository with fetch age in `packages/core/lib/src/cache/` for data-model.md CacheEntry.instanceId, CacheEntry.kind, CacheEntry.remoteId, CacheEntry.parentRemoteId, CacheEntry.sortTitle, CacheEntry.state, CacheEntry.monitored, CacheEntry.qualityProfileId, CacheEntry.tagIds, CacheEntry.addedAt, CacheEntry.rawJson, CacheEntry.fetchedAt
- [ ] T017 Implement preference storage in `packages/core/lib/src/preferences/` for data-model.md Preferences.activeProfileId, Preferences.themeMode, Preferences.trueBlack, Preferences.dynamicColor, Preferences.loadThirdPartyArtwork, Preferences.appLock, Preferences.view, Preferences.lastAddChoices
- [ ] T018 Write profile and instance validation and credential-rule tests in `packages/core/test/instance_test.dart` for data-model.md Profile.id, Profile.name, Instance.id, Instance.profileId, Instance.name, Instance.serviceType, Instance.url, Instance.certPin, Instance.customCa, Credential.customHeaders, including HTTP accepted, profile copy (including views) and delete, the authFailed latch and the last-profile rule
- [ ] T019 Implement models, validators and the profile repository in `packages/core/lib/src/instances/` for data-model.md Profile.id, Profile.name, Profile.sortOrder, Instance.id, Instance.profileId, Instance.name, Instance.serviceType, Instance.url, Instance.authKind, Instance.authFailed, Instance.certPin, Instance.customCa, Instance.enabled, Instance.sortOrder, Instance.detectedVersion, Instance.lastProbe, Instance.links, Instance.createdAt, Instance.updatedAt, Credential.apiKey, Credential.username, Credential.password, Credential.basicUser, Credential.basicPassword, Credential.customHeaders, Credential.sessionCookie
- [ ] T020 Exclude secrets and database from backup and device transfer in `apps/arr_client/android/app/src/main/res/xml/` and manifest
- [ ] T021 Implement redacting diagnostic log in `packages/core/lib/src/logging/` with tests that seeded secrets never appear
- [ ] T022 Write network tests in `packages/core/test/network/`: no bytes before pin match, custom CA, cross-origin redirect, plain HTTP, no write retry, redaction, every `ServiceFailure` classification
- [ ] T023 Implement per-instance HTTP client with auth, custom headers, redirect policy and failure mapping in `packages/core/lib/src/network/client.dart`
- [ ] T024 Implement leaf pinning and per-instance custom CA per research R4 in `packages/core/lib/src/network/trust.dart`
- [ ] T025 Implement connectivity and transport-type adapter in `apps/arr_client/lib/app/platform/connectivity.dart`
- [ ] T026 Create local plugin `packages/platform_local_network/` (registered, so usable from background isolates) and implement the research R6 flow in `apps/arr_client/lib/app/platform/local_network.dart`, with address classification tests in `apps/arr_client/test/platform/`
- [ ] T027 Add cleartext network security config in `apps/arr_client/android/app/src/main/res/xml/network_security_config.xml` and set `flutter_deeplinking_enabled=false` in the manifest
- [ ] T028 Implement `SessionAuthenticator` with secure session storage re-login and the data-model.md Instance.authFailed latch (including from the background isolate) in `packages/core/lib/src/session/` with tests
- [ ] T029 Implement shared records in `packages/core/lib/src/models/` for data-model.md LibraryItem.state (with precedence), Release.protocol, QueueItem.progress, HistoryEvent.eventType, Command.status, Command.result, DownloadProgress.progress, DownloadProgress.state, ServerOption.kind, DiscoveryTitle.availability, DiscoveryTitle.availability4k, Request.status, SubtitleFile.mediaType
- [ ] T030 Implement module registry, active-profile scoping and profile switching (research R5), persisted probe capabilities (data-model.md Instance.lastProbe) and aggregation with per-instance failure isolation in `packages/core/lib/src/registry/`
- [ ] T031 Implement artwork loader per research R10 (custom FileService on the instance client, credential-free remote client) in `packages/core/lib/src/artwork/`, with redirect, pin and no-credential tests
- [ ] T032 Write the allow-list test harness in `packages/core/lib/testing/allow_list.dart`: it holds only checking logic and fails any request not in the list each module supplies from `test/allow_list.dart` (contracts/upstream-apis.md)
- [ ] T033 [P] Implement theme (light, dark, black, dynamic) and localization setup (generated into `lib/src/l10n/generated`) in `packages/ui/lib/src/theme/` and `packages/ui/lib/src/l10n/`
- [ ] T034 Implement shared loading/empty/error/stale scaffold, confirm dialog, item-gone and action-outcome handling in `packages/ui/lib/src/widgets/`
- [ ] T035 Implement composition root, module list, `AppNavigator` and capability-driven navigation per contracts/navigation.md in `apps/arr_client/lib/app/`
- [ ] T036 Write shared Servarr tests (paging, status, options, unmatched queue items, queue read, history read, command status and result including completed-but-unsuccessful, aborted and orphaned, health) in `packages/servarr/test/contract/`
- [ ] T037 Implement shared Servarr client and those reads in `packages/servarr/lib/src/`

## Phase 3: US1 Connect my services (P1)

- [ ] T038 [P] [US1] Create each module's `test/allow_list.dart` from contracts/upstream-apis.md for Radarr and Sonarr in `packages/modules/radarr/test/` and `packages/modules/sonarr/test/`; later modules add theirs with their first contract tests
- [ ] T039 [P] [US1] Write probe contract tests (success, wrong service, auth, proxy page, host rejected, old and newer-than-tested version) in `packages/modules/radarr/test/contract/`
- [ ] T040 [P] [US1] Write the same probe contract tests in `packages/modules/sonarr/test/contract/`
- [ ] T041 [US1] Implement Radarr descriptor and probe in `packages/modules/radarr/lib/radarr_module.dart`
- [ ] T042 [US1] Implement Sonarr descriptor and probe in `packages/modules/sonarr/lib/sonarr_module.dart`
- [ ] T043 [US1] Implement instance list with add, edit, rename, reorder, disable, remove (purging secrets and cache) in `apps/arr_client/lib/features/settings/instances/`
- [ ] T044 [US1] Implement profile create, copy, rename, delete and the Home profile switcher, with the switch-profile offer for unreachable instances, in `apps/arr_client/lib/features/settings/profiles/` and `apps/arr_client/lib/features/home/`
- [ ] T045 [US1] Implement auth-kind-driven add/test form (one HTTP or HTTPS address, API key or account sign-in, optional basic auth and custom headers, the module's `authNotes`, save anyway after a failed test) in `apps/arr_client/lib/features/onboarding/`
- [ ] T046 [US1] Implement fingerprint review, changed-certificate and CA import screens in `apps/arr_client/lib/features/onboarding/certificate/`
- [ ] T047 [US1] Show version notice, authentication-failed retry, not-yet-checked and connection state in `apps/arr_client/lib/features/settings/instances/status.dart`
- [ ] T048 [US1] Implement automatic probing per research R5 (import, re-enable, change, profile activation, first contact per launch) with tests in `packages/core/lib/src/registry/`
- [ ] T049 [US1] Implement the initial Home screen listing instance status and links to configured areas in `apps/arr_client/lib/features/home/`
- [ ] T050 [US1] Add US1 integration tests, including a distinct message per FR-007 class, HTTP and HTTPS, profile copy, switch and delete, and module visibility, in `apps/arr_client/integration_test/connect_test.dart`

## Phase 4: US2 Browse movies and series (P1)

- [ ] T051 [P] [US2] Write library, options, credits, item history and queue-state contract tests in `packages/modules/radarr/test/contract/`
- [ ] T052 [P] [US2] Write library, options, episode, item history and queue-state contract tests in `packages/modules/sonarr/test/contract/`
- [ ] T053 [US2] Implement Radarr LibraryProvider reads, item history and queue binding in `packages/modules/radarr/lib/src/adapters/library.dart`
- [ ] T054 [US2] Implement Sonarr LibraryProvider reads, item history and queue binding in `packages/modules/sonarr/lib/src/adapters/library.dart`
- [ ] T055 [US2] Implement poster grid/list with state badges, instance labels, filters, sort and saved view per profile (data-model.md Preferences.view) in `apps/arr_client/lib/features/library/`
- [ ] T056 [US2] Implement movie detail screen with `subtitles` and `downloadProgress` slots and `detailRoute` in `packages/modules/radarr/lib/src/screens/movie_detail.dart`
- [ ] T057 [US2] Implement series, season and episode screens with `subtitles` and `downloadProgress` slots and `detailRoute` in `packages/modules/sonarr/lib/src/screens/`
- [ ] T058 [US2] Implement item history view in `apps/arr_client/lib/features/activity/history/item_history.dart`
- [ ] T059 [US2] Wire cached offline reading, age banner, disabled actions and deleted-item handling in `packages/ui/lib/src/widgets/` and `packages/core/lib/src/cache/`
- [ ] T060 [US2] Implement the cache-clear action in `apps/arr_client/lib/features/settings/storage/`
- [ ] T061 [US2] Add US2 integration tests (including offline cold start, profile switch with saved filters and cache clear) and large-library performance tests in `apps/arr_client/integration_test/browse_test.dart`

## Phase 5: US3 Search and add (P1)

- [ ] T062 [P] [US3] Write lookup and add contract tests in `packages/modules/radarr/test/contract/`
- [ ] T063 [P] [US3] Write lookup and add contract tests in `packages/modules/sonarr/test/contract/`
- [ ] T064 [US3] Implement Radarr LookupProvider in `packages/modules/radarr/lib/src/adapters/lookup.dart`
- [ ] T065 [US3] Implement Sonarr LookupProvider in `packages/modules/sonarr/lib/src/adapters/lookup.dart`
- [ ] T066 [US3] Implement aggregated search over every search provider, grouping, identifier-based merging, per-instance in-library marks and partial failure in `apps/arr_client/lib/features/search/`
- [ ] T067 [US3] Implement pre-add detail and add sheet (per-target lookup, remembered choices, already exists) in `apps/arr_client/lib/features/search/add/`
- [ ] T068 [US3] Add US3 integration test in `apps/arr_client/integration_test/search_add_test.dart`

## Phase 6: US4 Activity and first pre-release (P1)

- [ ] T069 [P] [US4] Write queue actions, history, events-since, mark-failed, blocklist and manual import tests in `packages/servarr/test/contract/`
- [ ] T070 [P] [US4] Write activity and import mapping contract tests in `packages/modules/radarr/test/contract/`
- [ ] T071 [P] [US4] Write activity and import mapping contract tests in `packages/modules/sonarr/test/contract/`
- [ ] T072 [US4] Implement shared QueueProvider actions, HistoryProvider (including eventsSince), blocklist and import choices/reprocess in `packages/servarr/lib/src/activity/`
- [ ] T073 [US4] Bind activity and import mapping in `packages/modules/radarr/lib/src/adapters/activity.dart`
- [ ] T074 [US4] Bind activity and import mapping in `packages/modules/sonarr/lib/src/adapters/activity.dart`
- [ ] T075 [US4] Implement combined queue with visible-only polling, details, remove options, bulk remove and grab now in `apps/arr_client/lib/features/activity/queue/`
- [ ] T076 [US4] Implement manual import screen with item, quality and language correction in `apps/arr_client/lib/features/activity/manual_import/`
- [ ] T077 [US4] Implement history, mark-failed and blocklist screens in `apps/arr_client/lib/features/activity/history/`
- [ ] T078 [US4] Add US4 integration test in `apps/arr_client/integration_test/activity_test.dart`
- [ ] T079 [US4] Implement minimal settings (theme, diagnostic log view/share, licenses) in `apps/arr_client/lib/features/settings/`
- [ ] T080 [US4] Implement the third-party artwork toggle in `apps/arr_client/lib/features/settings/`
- [ ] T081 [US4] Pre-release gate: a connection check on the release-built APK, secret and traffic audit (SC-006, SC-007) and a TalkBack/200% text pass over US1–US4; record in `docs/release-checks.md`
- [ ] T082 [US4] Record Radarr and Sonarr results in `docs/verification-matrix.md`
- [ ] T083 [US4] Owner, only after the pre-release gate passes: create the Android signing key and the `release` environment secrets, wire `key.properties` into the Gradle build, set `version: 0.1.0-beta.1+1` in `apps/arr_client/pubspec.yaml` and tag `v0.1.0-beta.1`, the first pre-release, through `.github/workflows/release.yml`

## Phase 7: US5 Manage and choose releases (P2)

- [ ] T084 [US5] After the first pre-release: add the `improve-codebase-architecture` and `codebase-design` skills from https://github.com/mattpocock/skills (MIT; `skills/engineering/`) to `.claude/skills/`, reviewed, pinned to a commit and with the license, plus `GLOSSARY.md` and `docs/adr/` (moving `docs/decisions.md` there and updating references)
- [ ] T085 [P] [US5] Write release, command, edit-preservation and bulk-edit tests in `packages/servarr/test/contract/`
- [ ] T086 [P] [US5] Write release, command, monitor, edit and delete contract tests in `packages/modules/radarr/test/contract/`
- [ ] T087 [P] [US5] Write release, command, season/episode monitor, seasonpass, edit and delete contract tests in `packages/modules/sonarr/test/contract/`
- [ ] T088 [US5] Implement ReleaseProvider, command triggers and fetch-merge-put per research R13 in `packages/servarr/lib/src/manage/`
- [ ] T089 [US5] Bind releases, commands, monitor, edit, bulk edit, delete and file delete in `packages/modules/radarr/lib/src/adapters/manage.dart`
- [ ] T090 [US5] Bind the same plus season/episode monitoring and monitoring option in `packages/modules/sonarr/lib/src/adapters/manage.dart`
- [ ] T091 [US5] Implement interactive search with sort, filter and rejected-grab confirmation in `apps/arr_client/lib/features/library/releases/`
- [ ] T092 [US5] Implement edit sheet, multi-select actions, delete dialog and command progress in `apps/arr_client/lib/features/library/manage/`
- [ ] T093 [US5] Add monitor toggles (revert on rejection), automatic search, refresh, rescan, interactive-search entry, edit and delete-item entry points (`openEdit`, `openDelete`) and file delete with confirmation to movie screens in `packages/modules/radarr/lib/src/screens/`
- [ ] T094 [US5] Add the same, including edit and delete-item entry points, at series, season and episode level in `packages/modules/sonarr/lib/src/screens/`
- [ ] T095 [US5] Add US5 integration test in `apps/arr_client/integration_test/manage_test.dart`

## Phase 8: US6 Home, calendar, wanted (P2)

- [ ] T096 [P] [US6] Write calendar, wanted, recently added, imported-on-day (local midnight boundaries), health and disk tests in `packages/servarr/test/contract/`
- [ ] T097 [P] [US6] Write overview binding contract tests in `packages/modules/radarr/test/contract/`
- [ ] T098 [P] [US6] Write overview binding contract tests in `packages/modules/sonarr/test/contract/`
- [ ] T099 [US6] Implement CalendarProvider (including recently added and imported-on-day from import history), WantedProvider and HealthProvider in `packages/servarr/lib/src/overview/`
- [ ] T100 [US6] Bind overview providers in `packages/modules/radarr/lib/src/adapters/overview.dart`
- [ ] T101 [US6] Bind overview providers in `packages/modules/sonarr/lib/src/adapters/overview.dart`
- [ ] T102 [US6] Extend Home with independent per-instance upcoming, downloaded today, recently added, active downloads (library queue), health and disk sections in `apps/arr_client/lib/features/home/`
- [ ] T103 [US6] Implement agenda and month calendar with filters, device time zone and the downloaded-today view with earlier days in `apps/arr_client/lib/features/calendar/`
- [ ] T104 [US6] Implement wanted lists with single, selected and all search in `apps/arr_client/lib/features/wanted/`
- [ ] T105 [US6] Add US6 integration test, asserting every Home section and including one unreachable instance, in `apps/arr_client/integration_test/overview_test.dart`

## Phase 9: US7 Real download progress (P2)

- [ ] T106 [P] [US7] Write qBittorrent probe (success, wrong service, auth, version, host rejected) and read-only contract tests (API key and password login, no Origin or Referer sent, rejected login latches with no retry, 401 causes, hash and infohash_v1, states, basic auth collision) in `packages/modules/qbittorrent/test/contract/`
- [ ] T107 [P] [US7] Write matching tests (case, v1 hash, season pack, no match, several clients) for data-model.md DownloadProgress.progress and DownloadProgress.state in `packages/core/test/progress/`
- [ ] T108 [US7] Implement qBittorrent probe, authentication, `authNotes` for the basic-auth cases in spec Edge Cases, and DownloadProgressProvider in `packages/modules/qbittorrent/lib/`
- [ ] T109 [US7] Implement progress matching in `packages/core/lib/src/progress/`
- [ ] T110 [US7] Show client progress, speed, time remaining, state, whole-download note and unavailable notice in `apps/arr_client/lib/features/activity/queue/`
- [ ] T111 [US7] Fill the `downloadProgress` detail slot from matched progress in `apps/arr_client/lib/app/slots/`
- [ ] T112 [US7] Add US7 integration test, including that no write request is made, in `apps/arr_client/integration_test/progress_test.dart`
- [ ] T113 [US7] Record qBittorrent in `docs/verification-matrix.md`

## Phase 10: US8 Music and books (P2)

- [ ] T114 [P] [US8] Write Lidarr probe (success, wrong service, auth, version) and contract tests for every Servarr capability, including events-since, blocklist and apply-monitoring-option, in `packages/modules/lidarr/test/contract/`
- [ ] T115 [P] [US8] Write Readarr/Bookshelf probe (success, wrong service, auth, version) and contract tests for every Servarr capability, including events-since, blocklist and apply-monitoring-option, in `packages/modules/readarr/test/contract/`
- [ ] T116 [US8] Implement Lidarr probe, library and lookup/add with metadata profile in `packages/modules/lidarr/lib/`
- [ ] T117 [US8] Implement Lidarr activity, manual import, blocklist, releases, commands, manage, calendar, wanted and health in `packages/modules/lidarr/lib/src/adapters/`
- [ ] T118 [US8] Implement Lidarr `detailRoute` and detail screens (with the `downloadProgress` slot) with monitor toggles, search, refresh, rescan, interactive-search, edit and delete-item entry points and file delete in `packages/modules/lidarr/lib/src/screens/`
- [ ] T119 [US8] Implement Readarr/Bookshelf probe, library and lookup/add with metadata profile in `packages/modules/readarr/lib/`
- [ ] T120 [US8] Implement Readarr/Bookshelf activity, manual import, blocklist, releases, commands, manage, calendar, wanted and health in `packages/modules/readarr/lib/src/adapters/`
- [ ] T121 [US8] Implement Readarr/Bookshelf `detailRoute` and detail screens (with the `downloadProgress` slot) with monitor toggles, search, refresh, rescan, interactive-search, edit and delete-item entry points and file delete in `packages/modules/readarr/lib/src/screens/`
- [ ] T122 [US8] Add Music and Books tabs, search groups and add options in `apps/arr_client/lib/features/library/` and `apps/arr_client/lib/features/search/`
- [ ] T123 [US8] Extend manual import with artist/album/track and author/book pickers in `apps/arr_client/lib/features/activity/manual_import/`
- [ ] T124 [US8] Add US8 integration test in `apps/arr_client/integration_test/music_books_test.dart`
- [ ] T125 [US8] Record Lidarr, Readarr and Bookshelf in `docs/verification-matrix.md`

## Phase 11: US9 Requests (P2)

- [ ] T126 [US9] Confirm sign-in bodies and permission bits (research R16) and write Seerr probe and contract tests, including separate 4K status, issue filing by `mediaInfo.id` (data-model.md DiscoveryTitle.mediaId), per-product status numbers (Overseerr deleted title stays requestable), raw search URI encoding, CSRF over HTTP and HTTPS (R18), settings and both poster proxy forms, in `packages/modules/seerr/test/contract/`
- [ ] T127 [US9] Implement Seerr probe, API key and account sessions and CSRF handling in `packages/modules/seerr/lib/src/api/`
- [ ] T128 [US9] Implement DiscoveryProvider (as a search source) and RequestProvider with permissions, quota, issues and status changes in `packages/modules/seerr/lib/src/adapters/`
- [ ] T129 [US9] Implement discover, title, request and quota screens with their route operations in `packages/modules/seerr/lib/src/screens/` and the Discover destination in `apps/arr_client/lib/app/`
- [ ] T130 [US9] Implement request management and issue report/comment/resolve screens with `requestsRoute` and `issuesRoute` in `packages/modules/seerr/lib/src/screens/manage/`
- [ ] T131 [US9] Show request status per variant and the request action in app-wide search, including merged results, through `detailRoute`/`requestRoute` in `apps/arr_client/lib/features/search/`
- [ ] T132 [US9] Add recent and pending request sections to Home in `apps/arr_client/lib/features/home/`
- [ ] T133 [US9] Add US9 integration test for limited and admin identities, merged search results (story 3 scenario 6) and a request started from search, in `apps/arr_client/integration_test/requests_test.dart`
- [ ] T134 [US9] Record Seerr, Overseerr and Jellyseerr in `docs/verification-matrix.md`

## Phase 12: US10 Subtitles (P3)

- [ ] T135 [P] [US10] Write Bazarr probe (success, wrong service, auth, version) and contract tests (browse, wanted, history, search, download, delete, sync) in `packages/modules/bazarr/test/contract/`
- [ ] T136 [US10] Implement Bazarr probe and SubtitleProvider in `packages/modules/bazarr/lib/`
- [ ] T137 [US10] Implement wanted, history, title browse, search, delete and sync screens with `entryRoute` (data-model.md SubtitleFile.mediaType) with confirmations in `packages/modules/bazarr/lib/src/screens/`
- [ ] T138 [US10] Implement explicit instance linking (data-model.md Instance.links) in `apps/arr_client/lib/features/settings/instances/links.dart`
- [ ] T139 [US10] Fill the `subtitles` detail slot from SubtitleProvider in `apps/arr_client/lib/app/slots/`
- [ ] T140 [US10] Add US10 integration test in `apps/arr_client/integration_test/subtitles_test.dart`
- [ ] T141 [US10] Record Bazarr in `docs/verification-matrix.md`

## Phase 13: US11 Indexer search (P3)

- [ ] T142 [P] [US11] Write Prowlarr probe (success, wrong service, auth, version) and contract tests (system status, indexer status, health, categories, search, grab) in `packages/modules/prowlarr/test/contract/`
- [ ] T143 [US11] Implement Prowlarr probe, IndexerSearchProvider and HealthProvider in `packages/modules/prowlarr/lib/`
- [ ] T144 [US11] Implement search, grab and read-only indexer status screens with `entryRoute` in `packages/modules/prowlarr/lib/src/screens/`
- [ ] T145 [US11] Add US11 integration test in `apps/arr_client/integration_test/indexers_test.dart`
- [ ] T146 [US11] Record Prowlarr in `docs/verification-matrix.md`

## Phase 14: US12 Notifications (P3)

- [ ] T147 [P] [US12] Write engine tests against fake capabilities in `packages/core/test/background/`: imported, queue and history-failed dedupe, health severity and clearing, request snapshot diffs, baselines on subscribe/import/re-enable, more-than-5 summary, active profile only and silent re-initialisation on profile activation, subscriptions copied with a profile and deleted with their instance
- [ ] T148 [US12] Implement engine and subscriptions composed from capabilities in `packages/core/lib/src/background/` for data-model.md NotificationSubscription.instanceId, NotificationSubscription.eventType, NotificationSubscription.enabled, EventMarker.instanceId, EventMarker.eventType, EventMarker.lastSeenCursor, EventMarker.openKeys, EventMarker.requestSnapshot
- [ ] T149 [US12] Implement scheduler (active profile only, rescheduled at launch, permission state readable in background), channels, notification permission and deep links in `apps/arr_client/lib/app/background/`
- [ ] T150 [US12] Implement subscription settings with delivery explanation and permission state in `apps/arr_client/lib/features/settings/notifications/`
- [ ] T151 [US12] Add US12 integration test, including a background-engine permission check, in `apps/arr_client/integration_test/notifications_test.dart`

## Phase 15: US13 Export, import, lock (P3)

- [ ] T152 [P] [US13] Write export tests (no secrets in plain export, limits, tamper, profiles, authFailed never imported and cleared by replaced credentials, origin change purge with and without credentials, post-import probe, payload schema, name collision, fresh-install profile handling (restored Default keeps its name), suffixed names within 40 characters, marker baseline, app lock and active profile never imported, preference changes listed in preview) in `packages/core/test/backup/`
- [ ] T153 [US13] Implement contracts/backup-format.md in `packages/core/lib/src/backup/`
- [ ] T154 [US13] Implement export, import preview and file picking in `apps/arr_client/lib/features/settings/backup/`
- [ ] T155 [US13] Implement app lock gating every entry point and recent-apps hiding in `apps/arr_client/lib/app/lock/`
- [ ] T156 [US13] Add US13 integration test, including a notification tap while locked and for an inactive profile, in `apps/arr_client/integration_test/backup_lock_test.dart`

## Phase 16: Polish and release

- [ ] T157 Complete settings: true-black and dynamic colour, and about in `apps/arr_client/lib/features/settings/`
- [ ] T158 Implement tablet rail and list/detail layouts in `packages/ui/lib/src/layout/`
- [ ] T159 Accessibility pass with semantics tests and TalkBack at 200% text (SC-011) in `apps/arr_client/test/a11y/`
- [ ] T160 Run SC-001 to SC-005 timing and performance checks and fix findings; record in `docs/release-checks.md`
- [ ] T161 Run SC-006/SC-007 traffic and secret audit and a security review; record in `docs/release-checks.md`
- [ ] T162 Verify SC-008 messages and SC-010 delivery on a physical device; record in `docs/release-checks.md`
- [ ] T163 Test module isolation (SC-009) with a sample module in `apps/arr_client/test/modularity_test.dart`
- [ ] T164 Write user docs for connections, reverse proxies, certificates, notifications and supported versions in `docs/` and `README.md`
- [ ] T165 Add F-Droid metadata in `fastlane/metadata/android/`
- [ ] T166 Update the user guides in `docs/wiki/`
- [ ] T167 Execute every quickstart.md scenario and finalize `docs/verification-matrix.md`

## Dependencies

- Phase 1 → Phase 2 → US1 → everything else.
- US2 needs US1. US3 needs US2. US4 needs US2 (item matching, history view). US5 needs US2.
- US6 needs US4 (active downloads, import history) and US5 (search commands).
- US7 needs US4 (the queue). US9 and US11 need US1; US9 also needs US3 (app-wide search).
- US8 needs US2–US6.
- US10 needs US2 (detail slot).
- US12 needs US4, US6, US8, US9 and US11 (event sources).
- US13 needs US1, US10 (links) and US12 (subscriptions, markers); its lock test needs US12 (notification taps).
- Phase 16 comes last.

## Parallel examples

- Within a story the Radarr and Sonarr contract-test tasks can be written together.
- In US7 the contract tests and the matching tests are parallel.
- After US3, stories US9 and US11 can proceed while US4–US6 continue.

## Implementation strategy

US1 plus US2 is the internal MVP. The first public pre-release is US1–US4. Each later story ships
as its own increment, validated with its quickstart.md scenario. 1.0 contains all stories.
