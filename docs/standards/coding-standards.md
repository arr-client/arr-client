# Coding standards

These apply to every pull request. "CI" marks what is checked automatically; the rest is checked in
review. To change a standard, open a pull request that edits this file.

## Language and style

- Follow [Effective Dart](https://dart.dev/effective-dart).
- `dart format` with default settings (CI).
- `flutter analyze` is clean, with the rules in `analysis_options.yaml` (CI). An `// ignore:` needs a
  comment saying why.
- No `dynamic` outside JSON decoding. No `!` where a null check or pattern match will do.
- Sound null safety; prefer `final`; models are immutable.

## Naming and layout

- Files `snake_case.dart`, one main public type per file.
- Packages expose one entry point; everything else is under `lib/src/`, except test support that
  `core` offers to modules under `lib/testing/`.
- Each package's `l10n.yaml` sets `output-dir: lib/src/l10n/generated`, which is not committed.
- Name by role: `RadarrApi`, `MovieDto`, `RadarrLibraryAdapter`, `MovieDetailController`,
  `MovieDetailScreen`.
- Tests end in `_test.dart` and are grouped as the plan shows: `test/contract/` and `test/widget/`
  in modules, otherwise by source area.

## Errors and async

- Operations that cross a module boundary return `Result<T, ServiceFailure>`; they do not throw.
- Never catch and discard. Map to a failure or let it surface.
- Cancel work when its screen or profile goes away. Never retry a write.

## Security

- Never log, print or put in an exception message: tokens, passwords, headers, cookies, full URLs
  with queries.
- Only the core network layer creates HTTP clients.
- Fixtures are sanitized before commit.

## User interface

See also the [UI standard](ui.md).

- All visible text is localized; no string literals in widgets.
- Every screen handles loading, empty, error and stale states.
- Semantics labels on icon-only controls; touch targets at least 48 dp; test at 200% text.
- Colours and spacing come from the theme.

## Tests

- Adapters are test-first against recorded responses.
- Prefer hand-written fakes to mocks.
- A bug fix comes with a test that failed before it.
- Tests do not touch the network or real servers.

## Dependencies

- A new dependency states why it is needed, and is GPL-3.0 compatible with no proprietary SDKs (CI
  once `tool/check_licenses.dart` exists).

## Documentation and commits

- Public APIs of `core`, `ui` and `servarr` have doc comments.
- Pull request titles follow [Conventional Commits](https://www.conventionalcommits.org/).
- A decision that is costly to reverse is recorded in `docs/decisions.md`.
