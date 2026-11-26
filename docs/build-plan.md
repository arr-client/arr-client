# Build plan

How [tasks.md](../specs/001-arr-companion-app/tasks.md) is split between build agents. **One task per
builder, one pull request per task** (except the chained tasks below, which share one). Up to five builders run at once, each in its own git worktree.
QA agents are not counted in the five.

## Loop for every pull request

1. The build agent branches from the latest `origin/main`, does its task and opens a pull request. In a
   chain (below), the last builder opens it.
2. A **new** QA agent reviews that exact commit. It changes nothing.
3. Findings go back to the same build agent (in a chain, the one whose task the finding concerns). After the fix, another **new** QA agent reviews.
4. Squash merge when the latest commit has passed QA **and** CI.
5. A rebase that needed conflict resolution counts as a new commit and is reviewed again.
6. If QA comes back two or three times with different complaints about the same code, that part may
   be rewritten instead of patched again. The same build agent or a new one may do the rewrite, and a
   new QA agent reviews it like any other change.

Build agents do not edit `tasks.md`; completed tasks are ticked in separate pull requests, so
parallel branches do not collide.

## Task order

A task starts when everything it needs has merged. A builder may start earlier on top of an unmerged
branch, and then rebases onto `main` before opening its pull request.

Some tasks form a chain that shares one branch and one pull request, because failing tests cannot
merge on their own: a test-writing task, then the task or tasks that make those tests pass, each by
its own builder in turn.

| Task | Needs |
|---|---|
| T001, T003, T004 workspace and Android project | done, merged together |
| T005 dependency checker | T001 |
| T006 license checker | T001 |
| T007 CI verification | T005, T006 |
| T008 build instructions | T003 |
| T009 verification matrix | nothing |
| T010 dev stack | nothing |
| T011 large library generator | T001 |
| T012 fixture sanitizer | T001 |
| T013 module contract | T001 |
| T014 database | T013 |
| T015 secret store | T013 |
| T016 cache repository | T014, T029 |
| T017 preference storage | T014 |
| T018 then T019 instances and profiles | T014, T015, T016, T017 |
| T020 backup exclusion | T014, T015 |
| T021 redacting log | T013 |
| T022, then T023, then T024: network tests, client, pinning and custom CA (one chain) | T019, T021 |
| T025 connectivity | T013 |
| T026 local network plugin | T013 |
| T027 cleartext and deep link config | T003 |
| T028 session authenticator | T024 |
| T029 shared records | T013 |
| T030 registry and profile switching | T019, T028, T031 |
| T031 artwork loader | T024 |
| T032 allow-list harness | T013 |
| T033 theme and localization | T001 |
| T034 shared widgets | T013, T033 |
| T035 app shell and navigation | T025, T026, T028, T030, T034 |
| T036, then T037: shared Servarr client (one chain) | T024, T029, T032 |

T013 also declares the types the module contract refers to but later tasks implement: every record
used in a capability signature, as plain types (T029 adds their behaviour and tests),
`InstanceContext`, the instance and credential records and auth kinds as plain types (T019 adds
validation and persistence), and the abstract interfaces for the logger, secret store, cache scope,
artwork loader, connectivity and local network permission.

Tasks for the user stories (T038 onwards) are added here when the foundation is in place.

T002 is the owner's and is recorded in [decisions.md](decisions.md).
