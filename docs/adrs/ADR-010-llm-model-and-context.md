# ADR-001: Stack Selection — Elixir/Ash 3.x/Phoenix/Spark

**Status:** Accepted  
**Date:** 2026-03  
**Deciders:** Platform team

---

## Context

Foundry needs to read, validate, and generate code for a specific technology stack.
The choice of target stack determines the entire automation surface.
A general-purpose approach (language-agnostic) would have near-zero automation leverage.

We evaluated three options:
1. Language-agnostic meta-platform (like Backstage)
2. Elixir/raw Ecto/Phoenix
3. Elixir/Ash 3.x/Phoenix/Spark DSL extensions

## Decision

**Elixir/Ash 3.x/Phoenix LiveView/Spark DSL extensions.**

This ADR covers two distinct stacks:

- **The Foundry meta-platform** — the Studio UI, copilot engine, Mix tasks, and CLI
- **Target platforms** — platforms built *using* Foundry (iGaming, fintech, healthcare, legal, etc.)

Both stacks share the same core. Where they differ, this ADR says so explicitly.

---

## Core Stack (both Foundry and all target platforms)

| Library | Version constraint | Role |
|---|---|---|
| Ash Framework | 3.x only (not 2.x — APIs are incompatible) | Domain resource layer |
| ash_postgres | current stable | Postgres data layer for all Ash resources |
| Spark DSL | bundled with Ash 3.x | DSL introspection foundation |
| Phoenix | 1.7.x+ | Web layer |
| Phoenix LiveView | 0.20.x+ | UI components |
| Ecto SQL | current stable | Database adapter (transitive via ash_postgres — see ADR-004) |
| Postgrex | current stable | Postgres driver (transitive via ash_postgres — see ADR-004) |
| Igniter | current stable | All code generation and AST manipulation |
| Jason | current stable | JSON serialisation — implicit in every Mix task output |
| Req | current stable | HTTP client (see ADR-004: no HTTPoison) |
| Finch | current stable | HTTP connection pool (transitive via Req) |
| Bandit | current stable | HTTP server adapter (replaces Cowboy) |
| Telemetry | current stable | Instrumentation events |
| telemetry_metrics | current stable | Metrics aggregation |
| telemetry_poller | current stable | VM and process metrics |

---

## Ash Ecosystem Extensions

### Always present in target platforms

| Library | Role | Classification notes |
|---|---|---|
| `ash_postgres` | Postgres data layer | Migration lifecycle — see below |
| `ash_state_machine` | Lifecycle-bearing resource states | Transitions are `:behavioral` class changes (ADR-005) |
| `ash_oban` | Background job integration | New workers are `:behavioral`; queue config is infrastructure (ADR-006) |
| `ash_double_entry` | Financial ledger resources | Resources are always `:sensitive` (ADR-005) |
| `ash_json_api` | JSON API routes | Route additions are `:behavioral`; auth-bearing routes may be `:sensitive` |
| `ash_paper_trail` | Change history / audit trail | Required on all `:sensitive` resources — see INV-011 |
| `ash_archival` | Soft delete | Required on all `:sensitive` resources — see INV-012 |
| `ash_authentication` | Authentication strategies | User credential resources are always `:sensitive` |
| `ash_authentication_phoenix` | Authentication LiveView routes/components | Generates routes outside `Op.AddLivePage` — see scaffold note below |

### Conditionally present (project declares in manifest)

| Library | Role |
|---|---|
| `ash_money` | Monetary Ash attribute type (`Ash.Type.Money`) |
| `AshStateMachine` | Already listed above — present when lifecycle resources exist |
| `AshPyro` | Back-office LiveView component library (DaisyUI/Tailwind-based) |
| `Beacon` | CMS integration — explicitly out of scope for Foundry v1 (see below) |
| `AshAI` | AI/vector integration on Ash resources — Foundry v1 does not introspect AshAI DSL declarations; see below |

---

## Money / Currency Stack

When a target platform handles monetary values, the following libraries form an
interdependent group and must all be present together:

```
ex_money          — currency types, arithmetic, CLDR data
ex_money_sql      — Postgres composite type (money_with_currency)
ash_money         — Ash.Type.Money attribute type
ash_double_entry  — ledger resource DSL
```

**Bootstrap requirement:** `ex_money_sql` requires the `money_with_currency` Postgres composite
type to exist before migrations run. This is a one-time setup step (`mix money.gen.migration`)
that must run before `mix ash.migrate` on a new database. The scaffold operations that create
monetary attributes (`Op.AddAttribute` with type `Ash.Type.Money`) must include this check.

**Type authority:** Use `Ash.Type.Money` (from `ash_money`) as the attribute type, not
`Money.t()` directly. The Foundry linter checks for this.

**CLDR backend:** The project must declare a `Cldr` backend module. The copilot reads its
configuration to know which currencies are valid when generating monetary constraints.

---

## Migration Lifecycle

`ash_postgres` introduces a two-command lifecycle that is part of every structural code change
involving resources or attributes:

```
mix ash.codegen <migration_name>   — generates migration from DSL diff
mix ash.migrate                    — applies migrations to the database
```

**This lifecycle is in scope for Foundry.** Scaffold operations that add resources or attributes
(`Op.AddResource`, `Op.AddAttribute`, `Op.AddRelationship`) must include a corresponding
migration proposal in their diff output. The review panel shows both the code change and
the generated migration side by side.

**Migration governance:** Schema mutations on `:sensitive` resources carry the same approval
class as code mutations on those resources. A migration that adds a column to `LedgerEntry`
is a `:sensitive` change requiring dual approval, not a `:structural` change. The change
classifier (ADR-005) must inspect migration files for which tables they touch.

**Pending migration detection:** `mix foundry.context` returns `pending_migrations: true/false`
for each resource, sourced from whether `mix ash.codegen --check` exits non-zero.

---

## Authentication Scaffold

`ash_authentication_phoenix` generates LiveView routes and components via its own Igniter
operations. These are outside the `Op.AddLivePage` catalogue operation's scope.

Foundry's stance:
- Authentication resource creation (User, Token resources) is handled via a dedicated
  `Op.AddAuthenticationResource` operation that wraps the `ash_authentication` Igniter generators.
- Auth strategy configuration (password, OAuth2, magic link) is a `:behavioral` change.
- Token resource and session resource are always classified as `:sensitive`.
- `ash_authentication_phoenix` route generation is called internally by `Op.AddAuthenticationResource`.

---

## Observability Stack

All platforms — Foundry itself and target platforms — must instrument with:

```
opentelemetry              — trace/span API
opentelemetry_exporter     — OTLP export to collector
telemetry                  — Elixir telemetry events (always present via Phoenix/Ash)
telemetry_metrics           — metric aggregations
telemetry_poller           — VM metrics
```

Foundry's copilot engine emits telemetry spans for each `Foundry.Operations.run/2` call,
each LLM API call, and each `mix foundry.context` invocation. These are the primary
diagnostic signals for the runbooks.

**Target platform requirement:** The `Op.AddTransfer` and `Op.AddObanJob` operations
automatically include telemetry span wrappers in generated code. This is not optional —
trace correlation across Reactors and Oban jobs is required for the audit chain in
regulated platforms.

The `mix foundry.context` schema includes `telemetry_prefix` for each module so the
Operations Board can correlate runbook events with live traces.

---

## Feature Flags

`fun_with_flags` (and optionally `fun_with_flags_ui`) provides feature flag infrastructure.

Foundry's governance stance on feature flags:
- A flag that gates a compliance control is a `:compliance` class change (ADR-005).
- A flag that gates a `:sensitive` operation is a `:sensitive` class change.
- Adding a new flag is `:behavioral` by default.
- The linter checks that flags on `:sensitive` operations are not removable without
  a corresponding ADR (INV-013).

`fun_with_flags_ui` is an admin dashboard. Its route must be behind authentication
(same requirement as `oban_web` and `phoenix_live_dashboard`).

---

## Rate Limiting

`hammer` (with `hammer_plug` for Plug integration) provides rate limiting.

Rate limit configuration on sensitive endpoints (withdrawal APIs, authentication endpoints,
bonus claim flows) is a `:behavioral` change. Removing or weakening a rate limit on a
compliance-relevant endpoint is a `:compliance` change.

The `mix foundry.context` schema surfaces `rate_limited: true/false` for resources that
declare `hammer_plug` middleware.

---

## Caching

`nebulex` is the caching library for both Foundry's internal caches and target platforms.

Foundry internal usage:
- `Foundry.Context.DocCache` — spec-kit document cache, keyed by `{file_path, mtime}` (ADR-003)
- `Foundry.Context.DocCache` — ExDoc API cache, keyed by `{library_name, version}` (ADR-003)
- Both caches use a simple L1 (in-process ETS via Nebulex) configuration

Target platform usage: project-level concern, not governed by Foundry directly.

---

## Email / Notifications

`swoosh` is the email delivery library. It backs the notification channels declared in
INV-010 (`channel: :email`).

Foundry's `Foundry.Notifications.Dispatcher` uses `swoosh` for email delivery and a
configurable Slack webhook adapter for Slack channels. The manifest declaration
(`channel: :slack` / `channel: :email`) routes to the appropriate dispatcher.

---

## Clustering (Cloud Mode)

In cloud mode, Foundry runs as a multi-node Phoenix cluster. `libcluster` manages node
discovery and mesh formation. The topology strategy is declared in `config/foundry.exs`
and is infrastructure configuration (governed by ADR-006).

WebSocket connections for the Studio UI use Phoenix PubSub for cross-node message delivery.
Mix task subprocesses are always run on the node that received the request — there is no
distributed Mix task execution.

---

## Admin UI Libraries

The following admin UI libraries expose sensitive internal state and must be secured:

| Library | What it exposes | Security requirement |
|---|---|---|
| `oban_web` | Job queue contents, worker state, failure reasons | Must be behind `ash_authentication` session check |
| `phoenix_live_dashboard` | VM metrics, ETS tables, process list | Must be behind `ash_authentication` session check, restricted to admin role |
| `fun_with_flags_ui` | Feature flag state and overrides | Must be behind `ash_authentication` session check, restricted to admin role |

Changes to the routes or access policies for these dashboards are `:behavioral` changes.
Removing authentication from any of these routes is a `:sensitive` change.

---

## Foundry Studio UI Asset Pipeline

The Studio UI (`mix foundry.studio`) uses:

```
tailwind      — CSS framework (via mix task, no Node dependency required)
esbuild       — JavaScript bundling (via mix task)
heroicons     — Icon set (included via the Phoenix component library)
```

When `AshPyro` is used in target platform back-office UIs:
- `AshPyro` builds on DaisyUI which builds on Tailwind — the same `tailwind` mix task
  compilation pipeline applies.
- `AshPyro`-generated components satisfy the `data-*` attribute convention in ADR-007
  because `AshPyro` generates standard LiveView components with data attributes.
  The linter verifies this at compile time.

---

## Out of Scope for Foundry v1

The following are explicitly excluded. Exclusion is a decision, not an oversight.

| Library / Feature | Reason for exclusion |
|---|---|
| `Beacon` CMS | Requires a separate content management governance model; deferred to v2 |
| `AshAI` DSL introspection | AshAI DSL is not yet stable enough to freeze in `mix foundry.context` schema; Foundry v1 will not fail on `AshAI` declarations — it will ignore them and warn |
| Ash 2.x projects | APIs differ significantly; mixing 2.x and 3.x patterns is a lint error |
| Raw Ecto resources | No Spark introspection surface; these get no automation value |
| Non-Elixir target stacks | Automation leverage requires Spark DSL |

---

## Consequences

- Every agent prompt includes the full version manifest from `mix foundry.versions.check` (INV-006 / ADR-010)
- `ash_postgres` migration lifecycle is in scope for all scaffold operations that add resources or attributes
- Monetary attributes use `Ash.Type.Money` exclusively; the linter rejects raw `Money.t()` declarations
- Authentication resources are always `:sensitive`; `ash_authentication_phoenix` scaffold is via `Op.AddAuthenticationResource`
- `ash_paper_trail` and `ash_archival` are required on `:sensitive` resources (INV-011, INV-012)
- The forbidden dependency list in ADR-004 applies to direct application dependencies; `ecto_sql` and `postgrex` as transitive dependencies of `ash_postgres` are permitted
- Admin dashboards (`oban_web`, `phoenix_live_dashboard`, `fun_with_flags_ui`) require authentication — the linter checks route configuration

## What This Is Not

This ADR does not constrain what language the Studio UI itself is built in.
It constrains the **target stack** that Foundry reads, validates, and generates.
The Studio backend is also Elixir/Phoenix (same stack), but that is a consequence, not the decision.