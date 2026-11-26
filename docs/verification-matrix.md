# Verification matrix

Which service versions have been checked. The rows come from Supported Services in the
[spec](../specs/001-arr-companion-app/spec.md), which holds the notes on each service.

A row counts as supported only once a passing fixture set or a recorded manual check exists for it
(constitution principle V, [constitution](../.specify/memory/constitution.md)). Until then it is
**unverified**, whether it is a minimum or best effort.

The dev stack (`tool/devstack/`) runs only current versions and cannot exercise download scenarios, so
a check against it does not cover an older version or anything that needs a download
([quickstart](../specs/001-arr-companion-app/quickstart.md), Limits of the dev stack).

| Service | Version | Level | Status | Evidence |
|---|---|---|---|---|
| Sonarr | 4.0 | Minimum | Unverified | None |
| Sonarr | 5 beta, through its v3-compatible interface | Best effort | Unverified | None |
| Radarr | 5.6 | Minimum | Unverified | None |
| Lidarr | 2.0 | Minimum | Unverified | None |
| Readarr | 0.4 | Minimum | Unverified | None |
| Bookshelf (API-compatible fork of Readarr) | Not specified | Best effort | Unverified | None |
| Prowlarr | 1.0 | Minimum | Unverified | None |
| Bazarr | 1.5 | Minimum | Unverified | None |
| Seerr | 3.0 | Minimum | Unverified | None |
| Overseerr | 1.34+ | Best effort | Unverified | None |
| Jellyseerr | 2.x | Best effort | Unverified | None |
| qBittorrent | 4.4 | Minimum | Unverified | None |

## Recording a result

Change a row's status only when you can name the evidence: the fixture set and the tests that pass
against it, or a manual check with its date, the exact service version and what was checked. Keep
keys, passwords, host names and personal data out of the record.
