# Agent skills

Optional helpers for contributors who use an AI coding agent. You never need them.

| Skills | Source | License |
|---|---|---|
| `speckit-*` | [GitHub Spec Kit](https://github.com/github/spec-kit) | [MIT](../../.specify/LICENSE) |
| `flutter-*`, `dart-*` | [flutter/skills](https://github.com/flutter/skills) at commit `ff6d472ee66dbed566c4500edee460c94fde0a02`, unmodified | [BSD-3-Clause](LICENSE-flutter-skills) |

**Where a skill disagrees with this project, the project wins**: the constitution,
[coding standards](../../docs/standards/coding-standards.md) and
[patterns](../../docs/standards/patterns.md). For example, we prefer hand-written fakes to mocking
libraries.

## Adding or updating a skill

Skills are instructions that run inside other people's agents, so they are reviewed like code. Read
every file, pin the source commit, include its license and send it as its own pull request.
