# Build plan

How [tasks.md](../specs/001-arr-companion-app/tasks.md) is split between build agents. Up to five
run at once, each in its own git worktree, each producing one pull request.

## Loop for every pull request

1. The build agent branches from the latest `origin/main`, does its tasks and opens a pull request.
2. A **new** QA agent reviews that exact commit. It changes nothing.
3. Findings go back to the same build agent. After the fix, another **new** QA agent reviews.
4. Squash merge when the latest commit has passed QA **and** CI.
5. A rebase that needed conflict resolution counts as a new commit and is reviewed again.

Build agents do not edit `tasks.md`; completed tasks are ticked in separate pull requests, so
parallel branches do not collide.

## Work packages

A package starts when everything it needs has merged.

| Package | Tasks | Needs |
|---|---|---|
| P1 workspace and Android project | T001, T003, T004 | nothing |
| P2 module contract and shared records | T013, T029 | P1 |
| P3 storage, secrets, cache, preferences, backup exclusion | T014–T017, T020 | P1 |
| P4 theme and localization | T033 | P1 |
| P5 repository tooling | T005, T006, T011, T012 | P1 |
| P6 CI check, docs, dev stack, redacting log | T007–T010, T021 | P1 |
| P7 profiles and instances | T018, T019 | P2, P3 |
| P8 network client, pinning, cleartext config | T022–T024, T027 | P2, P6 |
| P9 connectivity and local network permission | T025, T026 | P2 |
| P10 shared widgets | T034 | P2, P4 |
| P11 allow-list harness | T032 | P2 |
| P12 session authenticator | T028 | P7, P8 |
| P13 registry and profile switching | T030 | P7 |
| P14 artwork loader | T031 | P8 |
| P15 shared Servarr client | T036, T037 | P8, P11 |
| P16 app shell and navigation | T035 | P10, P13 |

Packages for the user stories (T038 onwards) are added here when the foundation is in place.

T002 is the owner's and is recorded in [decisions.md](decisions.md).
