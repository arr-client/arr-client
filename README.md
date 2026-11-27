# arr-client

A free, open-source mobile client for the *arr apps you host yourself. Android first, built with
Flutter, GPL-3.0.

> **Status: early development.** There is no usable app yet and nothing to install. The spec is
> written and the project skeleton builds, but the app only shows an empty screen. This is a good
> time to join.

arr-client is for **using** your services, not configuring them. Add each service with its address
and token, test it, and go.

## Planned for 1.0

| Area | Services |
|---|---|
| Libraries | Sonarr, Radarr, Lidarr, Readarr (and Bookshelf) |
| Requests | Seerr (Overseerr and Jellyseerr best effort) |
| Search and subtitles | Prowlarr, Bazarr |
| Real download progress (read only) | qBittorrent |

Browse and search, add titles, handle the queue, pick releases, calendar, notifications without
any third-party server, and switchable profiles. HTTP and HTTPS both work; an address typed without
either is taken as HTTPS.

No analytics, no ads, no project-run servers.

## Build from source

With the [development environment](CONTRIBUTING.md#development-environment) set up:

```sh
flutter pub get
cd apps/arr_client
flutter build apk --debug    # build/app/outputs/flutter-apk/app-debug.apk
flutter run                  # with an Android device or emulator connected
```

Release builds are unsigned for now. See [Build, run and check](CONTRIBUTING.md#build-run-and-check)
for the checks, release builds and setting up an emulator.

## Documents

- [Specification](specs/001-arr-companion-app/spec.md): what it does
- [Plan](specs/001-arr-companion-app/plan.md): how it is built
- [Tasks](specs/001-arr-companion-app/tasks.md): the work, in order
- [Constitution](.specify/memory/constitution.md): rules every change follows
- [Wiki](https://github.com/arr-client/arr-client/wiki): guides

## Get involved

Each service is its own module, so you can add or improve one without learning the others. Start
with [CONTRIBUTING.md](CONTRIBUTING.md). Questions and ideas go in
[Discussions](https://github.com/arr-client/arr-client/discussions).

## Disclaimer

arr-client is an independent community project. It is not affiliated with or endorsed by Sonarr,
Radarr, Lidarr, Readarr, Prowlarr, Bazarr, Seerr or qBittorrent.

## License

[GPL-3.0](LICENSE). The Spec Kit templates, scripts and `speckit-*` skills in `.specify/` and `.claude/` are from
[GitHub Spec Kit](https://github.com/github/spec-kit), under its [MIT license](.specify/LICENSE). The Flutter and Dart skills are from
[flutter/skills](https://github.com/flutter/skills), under its
[BSD-3-Clause license](.claude/skills/LICENSE-flutter-skills).
