# Implementation Plan: Modular companion app for self-hosted media services

**Branch**: `001-arr-companion-app` | **Date**: 2026-11-26 | **Spec**: [spec.md](spec.md)

## Summary

A Flutter app, released for Android, made of a thin shell, a core that defines the module contract
and owns connections, and one package per service. Modules declare capabilities; cross-service
screens (search, activity, calendar, home, notifications) are composed from those capabilities.
Decisions and their reasons are in [research.md](research.md).

## Technical Context

**Language/Version**: Dart 3.14 / Flutter 3.50 stable (pin exact version in `.fvmrc` and CI)

**Primary Dependencies**: flutter_riverpod, go_router, dio, freezed + json_serializable, drift,
flutter_secure_storage, workmanager, flutter_local_notifications, flutter_cache_manager (with our
own file service, research R10), local_auth, cryptography. SQLite is built from source (research
R17). Versions are resolved when added; each is license-checked.

**Storage**: drift (SQLite) for instances and cache; secure storage for credentials

**Testing**: flutter_test, mocktail, recorded-fixture contract tests, integration_test on emulator

**Target Platform**: Android 8.0 (API 26) and later; compile and target API 37

**Project Type**: mobile app, multi-package Dart pub workspace

**Performance Goals**: SC-003, SC-004, SC-005

**Constraints**: no proprietary SDKs; no project backend; offline read of cached data

**Scale/Scope**: 8 service modules, about 45 screens, libraries up to 10,000 movies / 100,000
episodes

## Constitution Check

| Principle | How the plan meets it | Result |
|---|---|---|
| I Usage only | Contracts list the only server writes allowed; `config` endpoints are never written | Pass |
| II Modular | One package per module; dependency rule enforced by a CI check | Pass |
| III Private/secure | Single network layer in core; secure storage; pinning; redaction | Pass |
| IV Android first | Platform services behind core interfaces, implemented in the app | Pass |
| V Real contracts | Fixtures per service version, tests before adapters | Pass |
| VI Resilient UI | Shared state scaffold and confirm dialog in `ui` | Pass |
| VII FOSS | CI license check; no Google Play services or ML Kit | Pass |

Re-checked after design: pass, no deviations.

## Project Structure

### Documentation

```text
specs/001-arr-companion-app/
├── spec.md  plan.md  research.md  data-model.md  quickstart.md  tasks.md
├── contracts/  (module-contract.md, upstream-apis.md, backup-format.md, navigation.md)
└── checklists/requirements.md
```

### Source Code

```text
pubspec.yaml                  # workspace root
apps/arr_client/              # shell: composition root, routing, Android code, platform adapters
  lib/{main.dart, app/, features/{onboarding,home,library,search,activity,calendar,wanted,settings}/}
  android/  test/  integration_test/
packages/core/                # module contract, capabilities, profiles, instances, network, secrets,
                              # cache, errors, logging, background engine, navigation intents
                              # (Flutter package with no platform-specific code)
packages/ui/                  # theme, shared widgets, state scaffolds, localization helpers
packages/platform_local_network/ # local Flutter plugin: permission state, usable in background
packages/servarr/             # shared client and models for Sonarr/Radarr/Lidarr/Readarr/Prowlarr
packages/modules/<service>/   # sonarr radarr lidarr readarr prowlarr bazarr seerr qbittorrent
  lib/<service>_module.dart   # only public entry point
  lib/src/{api,models,adapters,screens,l10n}/
  test/{fixtures/<version>/,contract/,widget/}
tool/                         # check_dependencies.dart, check_licenses.dart, sanitize_fixture.dart
.github/                      # workflows (ci, release, labels, triage, stale, wiki), issue forms,
                              # labels, CODEOWNERS, release notes config
docs/                         # user and decision docs; docs/wiki/ is published to the wiki
```

**Structure Decision**: Separate packages make principle II enforceable by the build and CI rather
than by convention.

Allowed dependencies: `app → modules, core, ui, platform_local_network`; `module → core, ui, servarr (family only)`;
`servarr → core`; `ui → core`; `core → (none of ours)`.

## Community and Repository

Public repository `arr-client/arr-client`. Contributions follow `CONTRIBUTING.md`: new features and
services arrive as a spec pull request (their own `specs/NNN-name/`) before code. Labels, triage,
release notes and the wiki are kept as files in the repository.

## Standards

Coding standards, patterns and the UI standard are in `docs/standards/`; lint rules in the root
`analysis_options.yaml`.

## Delivery Order

1. Setup and foundation.
2. P1: stories 1–4 (first public pre-release).
3. P2: stories 5–9 (story 7 adds qBittorrent download progress).
4. P3: stories 10–13.
5. Polish, accessibility, performance, security review, 1.0.

## Risks

| Risk | Mitigation |
|---|---|
| Upstream API drift (Sonarr v5, Seerr, qBittorrent) | Version detection, tolerant parsing, fixtures per version |
| Readarr is dead and forks may diverge | Claim only Readarr 0.4 and Bookshelf; module is optional |
| Android 17 local network permission | Handled in foundation, tested on API 37 and older |
| Background work killed by vendors | Notifications documented as best effort |
| Developer verification friction | Owner decides before first release |
| Large scope for a new project | Priority order gives a usable release after story 4 |

## Complexity Tracking

The number of packages is a direct consequence of principle II.

| Deviation | Why | Follow-up |
|---|---|---|
| Principle V: parts of the shared Servarr client's reads and activity (T036, T037, T069) are tested against values written by hand from the API resource classes and source of Radarr 7.0.3.10918 and Sonarr 4.0.20.3014, not against recordings. They are: queue statuses `unknown`, `failed`, `downloadClientUnavailable` and `fallback`; tracked states `importing`, `imported`, `failedPending`, `failed` and `ignored`; severity `error`; usenet queue items other than a delayed release; health level `notice`; command statuses other than `queued`, `started` and `completed`, and results other than `successful` and `unknown`; folder import history events; manual import candidates without a quality, without languages or without rejections, a rejection of type `temporary`, and a reprocessing answer without a match or without rejections; blocklist entries without a quality, a reason or an item; and the failures of the activity writes other than a removal or grab of an entry that is gone, marking an event that is gone, and a grab the server could not download | The recording runs on throwaway servers (qBittorrent with a web seed, pushed releases, imports by hand) did not produce them | None planned; record them if a server that has them becomes available |
| Principle V: parts of the overview tests (T096) use values written by hand: import events at other times, for other items, of one second, without an item or a quality, and of other types; the instants of local midnights in zones with and without daylight saving; calendar records without a date and dates around a window's ends; wanted pages after the first; several disks and a full one. The free and total bytes of the recorded disk are made up | A recording run on throwaway servers cannot place imports at chosen times or produce these states, and the recorded bytes were those of the recording machine | They stay listed here |
| Principle V: parts of the Radarr overview tests (T097) use values written by hand: release dates at month and year starts, on clock-change days, unreadable or absent; queued, unreleased and unmonitored movies; imports at local midnights and without a movie; wanted pages after the first. The free and total bytes of the recorded disks are made up | A recording run on throwaway servers cannot place imports at chosen times or produce these states, and the recorded bytes were those of the recording machine | They stay listed here |
| Principle V: parts of the Sonarr overview tests (T098) alter the recordings by hand: series and episode titles; episode numbers, air times and file and monitored flags; records without a series, title, time or another field; import events at other times, for other episodes and a long season pack; queue entries for the overview's episodes; longer and empty wanted lists; and failed answers. The free and total bytes of the recorded disks are made up | A recording run on throwaway servers cannot place episodes and imports at chosen times or produce these states, and the recorded bytes were those of the recording machine | They stay listed here |
