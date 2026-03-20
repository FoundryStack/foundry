# ADR-020: Project Context Unification, File System Access Model, and Umbrella Support

**Status:** Accepted
**Date:** 2026-03
**Deciders:** Platform team
**Supersedes:** `mix foundry.project.snapshot` as defined in `docs/mix_task_summary_schemas.md` (schema replaced; see §Migration)
**Tags:** context, filesystem, umbrella, studio, security, system-map

---

## Context

Three separate design gaps surfaced during Studio prototype review:

1. `mix foundry.diagram.generate` and `mix foundry.context <Module>` produce data that
   the studio always consumes together. Keeping them as two subprocess calls with two
   cache entries adds latency and complexity with no benefit at current scale.

2. `mix foundry.project.snapshot` conflates a name that implies a point-in-time freeze
   with content that is specifically about *current health* — lint state, open proposals,
   compliance gaps, pending migrations. The name leaks an implementation detail
   (assembled at a moment in time) into the public interface.

3. The studio needs to serve source file content to the UI on demand (for the diff viewer,
   module inspector, and spec-kit overlay). No validated read boundary existed. Additionally,
   no model existed for umbrella projects or related multi-project workspaces.

---

## Decision

### 1. Unified project context command

Replace the two-command pattern (`mix foundry.diagram.generate` + per-module `mix foundry.context`)
with a single command:

```
mix foundry.project.context
```

This command performs one pass over all compiled modules and returns both the node corpus
and the full edge list in a single JSON response. It supersedes `mix foundry.diagram.generate`
for studio use. Per-module `mix foundry.context <Module>` is retained for copilot shell
access and CI introspection — it is not removed.

**Cache strategy:** Single entry keyed on `{project_root, max_mtime_across_all_source_files}`.
Invalidated when any `lib/` or `test/` file changes. In umbrella projects, mtime scan
covers all `apps/*/lib/` trees.

**Token budget:** `mix foundry.project.context` output is not included in the LLM context
directly. It is the data source for the studio UI. The LLM context (Tier 1 + Tier 2) continues
to use the spec-kit index and `mix foundry.project.status` respectively — see §2.

### 2. Rename snapshot → status

Replace `mix foundry.project.snapshot` with:

```
mix foundry.project.status
```

The output is a `ProjectStatus` struct. "Status" correctly names what the data describes:
the current condition of the project at this moment. The word "snapshot" is retired.

`mix foundry.project.status` remains the Tier 2 session context source for
`Foundry.Copilot.ContextBuilder`. Token bound and cache TTL are unchanged (≤ 400 tokens,
60-second TTL). The schema is expanded — see `docs/mix_task_summary_schemas.md`.

### 3. File system access via `Foundry.FileSystem`

All file reads from the studio UI and the copilot shell go through a single validated
module: `Foundry.FileSystem`. Direct `File.read!/1` calls from channels or controllers
are forbidden.

```elixir
Foundry.FileSystem.read(project_root :: String.t(), relative_path :: String.t())
:: {:ok, String.t()} | {:error, :outside_boundary} | {:error, :not_found}
```

**Permitted read roots per project context:**

| Root | Purpose |
|---|---|
| `lib/` | Elixir source — modules, DSL, resources |
| `test/` | Test files |
| `config/` | Runtime and compile config |
| `priv/repo/migrations/` | Migration files |
| `docs/adrs/` | ADR spec-kit documents |
| `docs/runbooks/` | Runbook spec-kit documents |
| `docs/regulations/` | Regulation spec-kit documents |
| `AGENTS.md` | Primary context document |
| `mix.exs` | Dependency manifest |
| `.foundry/manifest.exs` | Project manifest |
| `.foundry/usage_rules/` | Library usage rules |

Everything outside these roots is rejected with `{:error, :outside_boundary}`.
Specifically: `.env`, `_build/`, `deps/`, `.git/`, `*.secret.*` — never readable.

**`project_root` is always resolved server-side.** The channel resolves the root from
the authenticated session context (which project the user is viewing). The client sends
a node ID or relative path; the server determines which root applies. The client cannot
supply or influence `project_root`.

**Phoenix Channel surface:**

```elixir
# Client sends:
{"event": "fetch_file", "path": "lib/my_app/finance/wallet.ex"}
{"event": "fetch_document", "path": "docs/adrs/ADR-003-agent-context-strategy.md"}

# Server responds via push:
{"event": "file_content", "path": "...", "content": "...", "mime": "text/plain"}
{"event": "file_error",   "path": "...", "reason": "outside_boundary"}
```

Both events route through `Foundry.FileSystem.read/2`. The channel has no path logic.

### 4. Umbrella project support

An umbrella project is treated as **one Foundry project** — one spec-kit, one
`.foundry/manifest.exs`, one system map, one proposal namespace. The app boundary
is structural, not a governance boundary.

**Manifest declaration:**

```elixir
# .foundry/manifest.exs
project_type: :umbrella,
apps: [
  %{name: "igaming_core", path: "apps/igaming_core", layer: :domain},
  %{name: "igaming_web",  path: "apps/igaming_web",  layer: :web},
  %{name: "igaming",      path: "apps/igaming",      layer: :application}
]
```

`project_type: :standard` is the default and need not be declared for non-umbrella projects.

**`mix foundry.project.context` in umbrella mode:**
- Module scanner walks `apps/*/lib/` instead of `lib/`
- Node IDs are fully-qualified module names — app membership is encoded in the module
  name, not as a separate field (`IgamingCore.Finance.Wallet`, not `{app: "igaming_core", module: "Finance.Wallet"}`)
- System map organises nodes by domain first, app layer second
- Edges that cross app boundaries are rendered with a distinct `cross_app: true` flag
  so the studio can visually distinguish intra-app from inter-app relationships

**`Foundry.FileSystem` in umbrella mode:**
- Permitted roots expand to cover all declared apps:
  `apps/igaming_core/lib/`, `apps/igaming_web/lib/`, etc.
- Spec-kit roots remain at the umbrella root: `docs/`, `AGENTS.md`, `.foundry/`
- Path resolution: `Foundry.FileSystem.read(umbrella_root, "apps/igaming_core/lib/...")`

**Proposal branches in umbrella mode:**
- Default: one proposal branch namespace for the whole umbrella (`foundry/prop_<id>`)
- If a specific app declares `boundary: :isolated` in the manifest, it gets its own
  namespace (`foundry/prop_igaming_payments_<id>`) and its own approver list
- Isolation is a governance boundary only — the system map always shows all apps together

### 5. Related projects (multi-repo workspace)

Projects that are related but not in the same repo are declared in the manifest:

```elixir
related_projects: [
  %{name: "PaymentService", path: "../payment_service"},
  %{name: "ComplianceEngine", path: "../compliance_engine"}
]
```

Each related project is an independent Foundry context — its own `mix foundry.project.context`,
its own spec-kit, its own proposals. The studio loads the project list from the current
project's manifest on startup, then fetches each related project's context lazily when
the user navigates to it.

Cross-project edges are declared explicitly in the manifest (not inferred):

```elixir
cross_project_edges: [
  %{from: "MyApp.Finance.Wallet", to: "PaymentService.Gateway.Adapter", relation: "calls"}
]
```

The studio renders these as inter-cluster edges with a `cross_project: true` flag.
`Foundry.FileSystem` does not permit reads across project boundaries — each project's
channel session resolves its own `project_root`.

---

## Schema changes

Full schemas are in `docs/mix_task_summary_schemas.md` (updated alongside this ADR).
The new `mix foundry.project.context` schema is defined in `docs/project_context_schema.md` (new file).

---

## Migration

| Old | New | Action |
|---|---|---|
| `mix foundry.project.snapshot` | `mix foundry.project.status` | Rename command and module. Schema expands — see updated `mix_task_summary_schemas.md`. |
| `mix foundry.diagram.generate` (studio use) | `mix foundry.project.context` | Studio switches data source. CI staleness check moves to `mix foundry.project.context --check`. |
| `mix foundry.diagram.generate` (CI check) | `mix foundry.project.context --check` | Same enforcement pattern as `mix foundry.spec_kit.index --check`. |
| Direct `File.read!/1` in channels | `Foundry.FileSystem.read/2` | Any channel or controller reading files must route through `Foundry.FileSystem`. |
| `snapshot_at` field | `generated_at` field | Rename in status response. |

`mix foundry.context <Module>` is unchanged. `mix foundry.diagram.generate` may be retained
as an alias for backward compatibility but is no longer the canonical studio data source.

---

## Consequences

- The studio makes one subprocess call instead of N+1 to populate the system map
- File read security boundary is enforced in one module — channels contain no path logic
- Umbrella projects are first-class — no workarounds needed in the studio or copilot
- `mix foundry.project.status` token budget and Tier 2 role are unchanged; only the name
  and schema expand
- `Foundry.FileSystem` becomes a required dependency for any new channel or controller
  that reads project files — this is the intended constraint
- Related projects require explicit manifest declarations — cross-project edges are never
  inferred, only declared