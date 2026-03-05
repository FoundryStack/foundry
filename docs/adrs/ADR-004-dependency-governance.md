# ADR-004: Dependency Governance — Category-Based Approval

**Status:** Accepted  
**Date:** 2026-03  
**Deciders:** Platform team

---

## Context

Agents can propose adding dependencies. An unconstrained approved-list approach requires
constant maintenance and becomes stale. We need a policy that scales without manual updates.

## Decision

**Category-based auto-approval with a precise forbidden list.**

```
:auto_approve (no ADR, no human approval needed):
  - :testing_tools       # stream_data, mox, bypass, ex_machina, faker
  - :dev_tools           # credo, dialyxir, sobelow, ex_doc

:require_adr (ADR explaining why, then routes to domain lead):
  - :http_clients        # adding a second HTTP client — use Req by default
  - :databases           # anything touching data storage layers
  - :auth                # authentication/authorization libraries
  - :payments            # payment provider SDKs
  - :feature_flags       # feature flag libraries (fun_with_flags is the standard — a second one requires ADR)
  - :caching             # caching libraries (nebulex is the standard — a second one requires ADR)
  - :email               # email delivery libraries (swoosh is the standard)
  - :clustering          # cluster topology libraries (libcluster is the standard)

:always_forbidden (compiler error, no override):
  - :httpoison           # use Req
  - {:ecto, direct: true}  # see clarification below — transitive via ash_postgres is permitted
  - {:oban, conflicts_with: :ash_oban}
  - any library not published to Hex (no git deps in production)
```

Anything not in any list above: classified as `:require_adr`.

## Clarification: `:ecto` Forbidden List Scope

The forbidden entry is `{:ecto, direct: true}` — meaning Ecto as a **direct application-level
dependency** is forbidden. The correct data layer is Ash, which uses `ash_postgres`, which
depends on `ecto_sql` and `postgrex` as transitive dependencies.

What is forbidden: adding `{:ecto, "~> 3.x"}` to your `mix.exs` directly and using
`Ecto.Repo` / `Ecto.Schema` directly in application code.

What is permitted: `ecto_sql` and `postgrex` appearing in your lockfile as transitive
dependencies of `ash_postgres`. An agent reading the lockfile must not flag these as violations.

The linter implements this distinction: it inspects `mix.exs` `deps` declarations, not the
lockfile. A direct `:ecto` declaration in `mix.exs` is a lint error; presence in the lockfile
is not.

## Clarification: `Req` and `Finch`

`Req` is the standard HTTP client. `Finch` is `Req`'s connection pool dependency — it
appears in the lockfile as a transitive dependency and is permitted.

Configuring `Finch` pool sizes directly (in `config/`) for performance tuning is permitted
as infrastructure configuration (ADR-006). Adding `finch` as a direct dependency is only
needed if you are bypassing `Req` and using `Finch`'s API directly — this requires an ADR
(`:http_clients` category).

Foundry's copilot engine uses `Req` for its LLM API calls (ADR-010). This uses the same
`Finch` instance as the application. If pool contention is observed, a dedicated `Finch`
pool for the copilot engine may be configured — this is an infrastructure concern (ADR-006),
not a dependency addition.

## Test Tool Specifications

The `:auto_approve` testing tools are used as follows in generated test modules (ADR-007):

| Library | Used for |
|---|---|
| `stream_data` | Property-based tests for Transfer rules and Blueprint boundaries |
| `mox` | Adapter contract test doubles |
| `bypass` | HTTP mock server for external adapter integration tests |
| `ex_machina` | Fixture factories in `<AppName>Test.Generators` module |
| `faker` | Realistic data in fixtures (names, emails, amounts) |

Generated test skeletons from `Op.AddTestModule` use these libraries by convention name.
The copilot reads the project's generator module to confirm what is available before referencing
a generator in a skeleton. It never references a generator that doesn't exist in the project.

## Consequences

- Agents may add testing and dev dependencies without ceremony
- Adding a payment SDK requires an ADR first — this is appropriate given the stakes
- The forbidden list stays small and precise; it's not a whitelist of allowed libraries
- The `:ecto` forbidden rule targets direct application usage, not transitive lockfile presence
- `Req` / `Finch` pool configuration is infrastructure, not a dependency addition