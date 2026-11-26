# arr-client Constitution

`arr-client` is a free, open-source mobile client for people who
self-host media automation services.

## Core Principles

### I. Usage, Not Configuration
The app MUST let people *use* their services: browse, search, add, monitor, grab, handle the
download queue, request, and resolve day-to-day problems. It MUST NOT create or edit service
configuration: indexers, download client definitions, notification connections,
quality/metadata/delay/release profiles, custom formats, root folders, naming, import lists, system
settings, updates or backups. Choosing among options that already exist on the server (for example
which quality profile an item uses) is usage. The app is not a download client: it only reads
download progress from one, and downloads are managed through the library services. A feature that
is not clearly on the usage side of this line is out of scope.

**Rationale**: Web UIs already configure well; a bounded scope keeps the app maintainable.

### II. Modular by Service
Each supported service MUST be a self-contained module behind one published module contract.
The core MUST NOT import a module, and a module MUST NOT import another module. Cross-service
features MUST be built on capabilities declared in the core. Shared code for a service family lives
in a shared library that modules depend on. A user who has not added a service MUST see no screens,
tabs, notifications or background traffic for it.

**Rationale**: People run different stacks, and contributors must be able to add a service without
understanding the others.

### III. Private and Secure by Default
The app MUST talk only to the addresses the user configures, plus artwork hosts that those services
point to or are documented to use; requests to artwork hosts MUST carry no credentials. It MUST NOT
include analytics, advertising, crash reporting to third parties, or any project-operated backend.
Credentials MUST be stored in hardware-backed or OS-provided secure storage, MUST NOT appear in
logs, error reports or unencrypted exports, and MUST be sent only to the address the user saved or
is testing for that service, never forwarded to another host by a redirect. HTTP and HTTPS
addresses are both supported; the choice is the user's, and the app MUST NOT block or nag about
either. For HTTPS, certificate validation MUST NOT be disabled globally; trusting a self-signed
certificate or a private certificate authority is a per-service user decision.

**Rationale**: These credentials control a person's home server.

### IV. Android First, Portable Core
Android is the only release target for the first version. Platform-specific code MUST be isolated
behind interfaces in the app shell, so core and service modules stay free of Android dependencies.

### V. Verified Against Real Contracts
Every service adapter MUST have contract tests built from responses of a real, named service
version, with secrets and personal data removed. Adapter tests are written before the adapter.
Support for a service version MUST NOT be claimed without a passing fixture set or a recorded
manual verification.

**Rationale**: Upstream APIs differ between versions and are often documented incompletely.

### VI. Honest, Resilient, Accessible UI
Every screen MUST have loading, empty, error and stale-data states. One unreachable service MUST
NOT block others. A destructive action MUST require confirmation that names what will be deleted.
The app MUST NOT report success until the server has accepted the action. The UI MUST work with a
screen reader and with 200% text scaling, and all user-visible text MUST be localizable.

### VII. Free and Open Source
The project is licensed GPL-3.0. All runtime dependencies MUST be GPL-3.0-compatible free
software. Proprietary SDKs (including Google Play services and Firebase) MUST NOT be required, so
the app stays eligible for F-Droid.

## Technology Constraints

- Flutter and Dart, as chosen by the project owner.
- A feature that needs a server component run by the project is not permitted.

## Development Workflow

- Work follows spec-kit: spec, plan, tasks, then implementation. A new feature or service is
  proposed in an issue and specified in its own pull request before code. Fixes and documentation
  need no spec.
- Contributors do not need any particular editor or AI tool.
- Code follows `docs/standards/coding-standards.md` and `docs/standards/patterns.md`, and UI work follows
  `docs/standards/ui.md`.
- Every change passes static analysis, formatting and tests in CI before merge.
- Each user story is delivered as an independently testable increment.

## Governance

This constitution overrides other project documents. Amendments are made by pull request that
states the reason and updates affected specs. Versioning is semantic: MAJOR for removing or
redefining a principle, MINOR for adding one or materially expanding guidance, PATCH for
clarifications. Plans and reviews MUST check compliance; deviations are recorded in the plan's
Complexity Tracking table.

**Version**: 1.0.0 | **Ratified**: 2026-11-26 | **Last Amended**: 2026-11-26
