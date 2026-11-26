# Architecture and patterns

Use these patterns so that any module looks familiar. The normative contract is
[module-contract.md](../../specs/001-arr-companion-app/contracts/module-contract.md).

## Layers inside a module

```text
screens  →  controllers  →  capabilities (interfaces in core)
                                 ↑ implemented by
                              adapters  →  api  →  InstanceContext HTTP client
```

| Layer | Directory | Does | Must not |
|---|---|---|---|
| API | `src/api/` | One method per upstream request; returns DTOs | Hold state or know about widgets |
| Models | `src/models/` | DTOs matching the wire format | Be shown to the UI |
| Adapters | `src/adapters/` | Implement a capability; map DTOs to core records and errors to `ServiceFailure` | Contain widgets |
| Controllers | `src/screens/` | Riverpod notifiers holding screen state | Call the API directly |
| Screens | `src/screens/` | Render state, forward intent | Contain business rules |

## Patterns we use

| Pattern | Where |
|---|---|
| **Plugin module** behind `ServiceModule` | One package per service, registered in one place |
| **Adapter** | Upstream API to capability interface |
| **Capability interfaces** | Cross-service features; never test a module id |
| **Repository** | Profiles, instances, cache and preferences in core |
| **Result type** | Expected failures; exceptions are for programming errors |
| **Sealed states** and exhaustive `switch` | Screen and connection states |
| **Dependency injection** by Riverpod providers and `InstanceContext` | No global singletons or service locators |
| **Fetch, merge, put** | Edits that must keep unknown server fields |
| **Tolerant reader** | Ignore unknown fields; map unknown enum values to `unknown` |

## Dependency rule

`app → modules, core, ui, platform plugins`; `module → core, ui, servarr (family only)`;
`servarr → core`; `ui → core`. A module never imports another module. CI enforces this once
`tool/check_dependencies.dart` exists.

## Anti-patterns

- A screen that checks `serviceType == 'radarr'` in the app.
- Business logic in `build()`.
- A shared "utils" package that everything depends on.
- Copying server configuration screens into the app.
