# Contributing

Everyone taking part follows the [Code of Conduct](CODE_OF_CONDUCT.md). Thank you for helping. Code, testing against your own servers, documentation, translations and bug
reports are all useful.

## Ground rules

Read the [constitution](.specify/memory/constitution.md). The two that decide most questions:

- **Usage, not configuration.** Features that edit server configuration are not accepted.
- **Modules stay independent.** A service module never imports another module, and the core never
  imports a module.

Code follows the [coding standards](docs/standards/coding-standards.md) and
[patterns](docs/standards/patterns.md), and UI changes the [UI standard](docs/standards/ui.md).

## Development environment

With [Nix](https://nixos.org), `shell.nix` provides the pinned Flutter, JDK, Android SDK and tools.
It needs you to accept the Android SDK licences listed in that file, so read it first:

```sh
NIXPKGS_ACCEPT_ANDROID_SDK_LICENSE=1 nix-shell   # accepts the licences
```

With direnv, `direnv allow` does the same through `.envrc`. Add `--arg withEmulator true` for an
emulator.

Without Nix, install Flutter 3.50.1, JDK 17 and the Android SDK.

## Optional tools

None of these is required.

- [Agent skills](.claude/skills/README.md) for Spec Kit, Flutter and Dart are in the repository.
- Dart's MCP server (`dart mcp-server`, part of the Dart SDK) lets an agent analyze and test the
  project.
- [deslop](https://github.com/agent-sh/deslop) checks a change for stale docs, broken paths,
  duplicated code and leaked secrets. Install it yourself if you want it; it can send flagged lines
  to a language model, so read its documentation first.

## How work flows

This project is spec-driven, using [GitHub Spec Kit](https://github.com/github/spec-kit).

| Change | What to do |
|---|---|
| Bug fix, docs, translation | Open an issue, then a pull request |
| Task already in `tasks.md` | Say so on its issue (or open one), then a pull request |
| New feature or new service | Open an issue first. Once a maintainer accepts it, send the spec as its own pull request (`specify` → `clarify` → `plan` → `tasks` → `analyze`), then implement |

Spec Kit commands are included for Claude Code (`/speckit-specify` and friends). You do not need
an AI tool: the templates in `.specify/templates/` can be filled in by hand.

Each new feature gets its own `specs/NNN-short-name/` directory.

Spec Kit remembers the current feature in an uncommitted file. To work on tasks of the **existing**
feature from a fresh clone, point it there:

```sh
export SPECIFY_FEATURE_DIRECTORY=specs/001-arr-companion-app
```

Before specifying a **new** feature, `unset SPECIFY_FEATURE_DIRECTORY`; otherwise
`/speckit-specify` would overwrite the existing spec.

## Pull requests

- Branch from `main`; keep one topic per pull request.
- Title in [Conventional Commits](https://www.conventionalcommits.org/) style, for example
  `feat(radarr): add interactive search`.
- Add or update tests. Service adapters are test-first, using recorded responses.
- The title's `feat`, `fix` or `docs` prefix also labels the pull request for the release notes.
- Generated Dart files are not committed.
- CI must pass.

## Adding a service

Follow the [module contract](specs/001-arr-companion-app/contracts/module-contract.md). A module
lives in `packages/modules/<service>/` and is registered in one place in the app. It should need no
change to core or to other modules. Also:

1. List every request it makes in your spec's contract and in
   `packages/modules/<service>/test/allow_list.dart`; tests fail on anything else.
2. Add a `service: <name>` label to `.github/labels.json` and a path rule to `.github/labeler.yml`.
3. Add the service to the Service dropdown in `.github/ISSUE_TEMPLATE/bug.yml` and `feature.yml`,
   and to the table in `.github/workflows/issue-triage.yml`.

## Test data and secrets

Never commit API keys, passwords, host names or personal library data. Recorded responses must be
sanitized first. If you paste logs into an issue, check them for keys.

## Releases

Maintainers set `version: X.Y.Z+N` in `apps/arr_client/pubspec.yaml` (N always higher than the last
release), merge, then push tag `vX.Y.Z`. The release workflow refuses a mismatch. A pre-release uses
`version: X.Y.Z-beta.1+N` with tag `vX.Y.Z-beta.1`; the `-` is what marks the GitHub release as a
pre-release.

## License

Contributions are accepted under GPL-3.0, the project's license.
