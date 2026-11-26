# Build plan

How [tasks.md](../specs/001-arr-companion-app/tasks.md) is split between build agents. Up to five
run at once, each in its own git worktree, each producing one pull request.

## Loop for every pull request

1. The build agent branches from the latest `origin/main`, does its tasks and opens a pull request.
2. A **new** QA agent reviews that exact commit. It changes nothing.
3. Findings go back to the same build agent. After the fix, another **new** QA agent reviews.
4. Squash merge when the latest commit has passed QA **and** CI.
5. A rebase that needed conflict resolution counts as a new commit and is reviewed again.
6. If QA comes back two or three times with different complaints about the same code, that part may
   be rewritten instead of patched again. The same build agent or a new one may do the rewrite, and a
   new QA agent reviews it like any other change.

Build agents do not edit `tasks.md`; completed tasks are ticked in separate pull requests, so
parallel branches do not collide.

## Work packages

A package starts when everything it needs has merged.

| Package | Tasks | Needs |
|---|---|---|
| P1 workspace and Android project | T001, T003, T004 | nothing |
| P2 module contract, shared records, redacting log | T013, T021, T029 | P1 |
| P3 storage, secrets, cache, preferences, backup exclusion | T014–T017, T020 | P2 |
| P4 theme and localization | T033 | P1 |
| P5 repository tooling | T005, T006, T011, T012 | P1 |
| P6 CI check, docs, dev stack | T007–T010 | P5 |
| P7 profiles and instances | T018, T019 | P3 |
| P8 network client, pinning, cleartext config | T022–T024, T027 | P7 |
| P9 connectivity and local network permission | T025, T026 | P2 |
| P10 shared widgets | T034 | P2, P4 |
| P11 allow-list harness | T032 | P2 |
| P12 session authenticator | T028 | P8 |
| P13 registry and profile switching | T030 | P12, P14 |
| P14 artwork loader | T031 | P8 |
| P15 shared Servarr client | T036, T037 | P8, P11 |
| P16 app shell and navigation | T035 | P9, P10, P13 |

P2 also declares the types the module contract refers to but later packages implement:
`InstanceContext`, the instance and credential records and auth kinds as plain types (P7 adds
validation and persistence), and the abstract interfaces for the logger, secret store, cache scope,
artwork loader, connectivity and local network permission.

The foundation is mostly a chain, so fewer than five agents run during parts of it. The user
stories after it are where five can run steadily.

Packages for the user stories (T038 onwards) are added here when the foundation is in place.

T002 is the owner's and is recorded in [decisions.md](decisions.md).
