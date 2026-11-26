# Research and Decisions

Facts about upstream projects were checked against their GitHub repositories on 2026-11-26.

## R1 Upstream state
- Sonarr: latest stable 4.0.20; 5.0 pre-releases exist and contain both v3 and v5 APIs.
- Radarr 7.0 stable; API v3. Lidarr 3.1 stable; API v1. Prowlarr 3.x; API v1.
- Readarr: repository archived 2025-06-27. `pennydreadful/bookshelf` is a fork with the v1 API.
- Bazarr 1.x; API under `/api`, header `X-API-KEY`.
- Seerr 3.5 (merger of Overseerr and Jellyseerr; Overseerr archived 2026-02); API `/api/v1`.
- qBittorrent 5.3.1. WebAPI API keys (`Authorization: Bearer`) exist from 5.2.0, which also changed
  the login responses (contracts/upstream-apis.md).

## R2 State and navigation
**Decision**: Riverpod and go_router. **Why**: per-instance provider families, testable without
widgets. **Alternatives**: Bloc (more ceremony), Provider (weak scoping).

## R3 Module mechanism
**Decision**: compile all modules in; activate by configured instance. **Why**: Flutter cannot
safely load code at runtime and stores forbid it. **Alternative**: build flavours per module set
(multiplies releases for no user benefit).

## R4 HTTP, certificates and redirects
**Decision**: one `dio` client per instance built by core. For instances with an accepted certificate, the adapter uses
`HttpClient.connectionFactory` to open a `SecureSocket`, compares the SHA-256 of the peer's leaf
certificate with the pin, and returns the socket only on a match, so no request bytes or
credentials are sent first. Pinning replaces chain validation for that instance only. Automatic
redirects are disabled; same-origin redirects are followed by our code, others are errors.
**Why**: `badCertificateCallback` alone may report an issuer rather than the leaf and is not called
for valid chains.
**Private CAs**: Dart loads only the Android system root store, not user-installed CAs. An instance
may therefore carry an imported CA certificate (PEM), added to that instance's `SecurityContext`.
Outbound HTTP proxies and client certificates (mTLS) are not in 1.0.

## R5 Profiles and probing
**Decision**: one address per instance; alternative addresses are separate profiles that the user
switches by hand. **Why**: the owner's direction; predictable, and the app never decides where to
send a token. **Alternative**: automatic local/remote selection (rejected).

Switching profile cancels in-flight reads, rebuilds the per-instance providers for the new profile
and marks connections unknown. A write already sent is not cancelled or repeated; its outcome is
reported if known. A write the user has issued counts as under way even while it waits for a
sign-in, so it is still sent after it, though never to an address or kind of authentication saved
meanwhile.

Probes also run without a user-initiated test: after import, on re-enable, after an address or
credential change, on profile activation and on first contact in each app launch, updating
`lastProbe` (version notice, block, permissions). Until an instance has been probed it appears in
the instance list as "not yet checked", with a retry, and contributes no tabs.

## R6 Android local network permission
**Decision**: target API 37 and declare `INTERNET` (in the main manifest, so release builds have it)
and `ACCESS_LOCAL_NETWORK`. On API 37+, resolve the host name
and request the permission when the connection goes over Wi-Fi or Ethernet and any address is local
by Android's definition (private, link-local, carrier-grade NAT 100.64.0.0/10, multicast, directly
connected IPv6) or the name ends in `.local`. A denial looks like a timeout, so on any timeout check
the permission state before classifying the failure or falling back. Background checks never
prompt. Flutter provides no support (flutter/flutter#184859 was closed with documentation only), so
a registered plugin (our own local plugin, or a maintained one such as permission_handler) is
required, so that the permission state can also be read from the background isolate; a channel
registered only in `MainActivity` is not enough. **Source**: developer.android.com local
network permission and local network definition pages.

## R7 Cleartext traffic
**Decision**: permit cleartext in the network security configuration. HTTP is a supported choice,
addresses are unknown at build time, and the app shows no warnings about it.

## R8 Credentials
**Decision**: flutter_secure_storage (Android Keystore backed), keyed by instance id; Android
auto-backup excludes secrets and database. **Alternative**: encrypted database column (key
management would still need the Keystore).

## R9 Cache and large libraries
**Decision**: drift tables holding indexed summary columns plus the raw JSON; parse large responses
in a background isolate; refresh by full fetch with diff (the *arr library endpoints are not
paged). Lists are built lazily.

## R10 Artwork
**Decision**: instance artwork is fetched through the instance's core HTTP client (pinning, headers,
no cross-origin redirects) by a custom `FileService` for flutter_cache_manager.
Its default service must not be used: it follows redirects and would forward `X-Api-Key` and custom
headers. Remote artwork uses a separate client with no credentials or custom headers. Request
service posters use the instance's image proxy when its image cache is enabled: Seerr and later
Jellyseerr use `/imageproxy/tmdb/<path>`; Overseerr and early Jellyseerr use `/imageproxy/<path>`
(chosen by product and version, with fixtures for both). Otherwise image.tmdb.org is used unless
the user turned that off. Disk cache with a
size limit, keyed by instance.

## R11 Live updates
**Decision**: poll while a screen is visible (queue and download progress every 3–5 s, command status 2 s).
**Alternative**: SignalR (family-specific, needs reconnect handling); revisit after 1.0.

## R12 Notifications
**Decision**: workmanager periodic task, minimum 15 minutes, network required; per-subscription
markers prevent duplicates; local notifications only. No foreground service.

## R13 Editing without data loss
**Decision**: before PUT, GET the full resource, change only the edited fields in the raw JSON, and
send it back. Bulk changes use the services' editor endpoints.

## R14 Export encryption
**Decision**: Argon2id key derivation and AES-256-GCM via the `cryptography` package. See
[contracts/backup-format.md](contracts/backup-format.md).

## R15 Testing against services
**Decision**: a `docker compose` stack in `tool/devstack/` for manual verification and fixture
capture; fixtures pass through `tool/sanitize_fixture.dart` before commit.
**Limits**: the stack cannot exercise download scenarios and runs only current versions
(quickstart.md, Limits of the dev stack).

## R16 Items to confirm during implementation
These are not settled by this research and each has a task:
- Seerr media-server sign-in request bodies and permission bit values.

Settled since: qBittorrent login responses by version and API key use (5.2+), checked against its
source (4.4.0 to 5.3.1) and a 5.3.1 server; see contracts/upstream-apis.md.

## R17 SQLite from source
**Decision**: configure the `sqlite3` package build hook to compile a vendored SQLite
(`hooks.user_defines.sqlite3.source: source`) instead of downloading prebuilt binaries, for
F-Droid. The exact configuration key is verified when the dependency is added.

## R18 Seerr CSRF protection
When the server enables CSRF protection, every non-GET request needs the `_csrf` cookie and the
`X-XSRF-TOKEN` header taken from the `XSRF-TOKEN` cookie, including with an API key. The server
marks the cookies `Secure` but does not test the transport; the app handles `Set-Cookie` itself and
returns them to the same configured origin over HTTP as well, since HTTP is a supported choice.
Verify against a real server over both. `writesRefused` covers a server that still rejects writes.

## R19 Intents and deep links
**Decision**: set `flutter_deeplinking_enabled` to false (it is on by default). The app declares no
URL or file intent filters; the only external entry points are the launcher and its own notification
taps, which pass app lock first.
