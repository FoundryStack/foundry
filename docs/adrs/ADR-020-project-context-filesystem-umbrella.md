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

Replace the two-command pattern (`mix foundry.diagram.generate` + per-module
`mix foundry.context`) with a single command:

```
mix foundry.project.context [<Module>]
```

Called with no arguments, this command performs one pass over all compiled modules and
returns the full node corpus, edge list, and spec-kit index in a single response. It
supersedes `mix foundry.diagram.generate` as the canonical studio data source and
supersedes `mix foundry.context.all` as the bulk module enumeration endpoint.

Called with a module argument (`mix foundry.project.context MyApp.Finance.Wallet`), it
returns the single NodeEntry for that module. This is the copilot's lazy per-turn lookup
tool — it shares the same ETS cache as the bulk form. Same command, two access patterns,
one cache.

**Output storage:** The command output lives in ETS (Nebulex L1), not in a committed
JSON file. The studio reads from cache; CI uses the lockfile check described below.

**Cache strategy:** Single entry keyed on
`{:project_context, project_root, max_mtime_across_all_source_files}`. Invalidated when
any `lib/` or `test/` file changes. In umbrella projects, mtime scan covers all
`apps/*/lib/` trees.

**Node ordering:** Nodes are ordered alphabetically by fully-qualified module name.
Edges are ordered by `from` FQN, then `to` FQN. Ordering is deterministic and
git diff-stable.

**Token budget:** Raw `mix foundry.project.context` JSON is not included in the LLM
context directly. It is the authoritative data source for the studio UI and for
`Foundry.Copilot.ContextBuilder`.

The orchestrator chat model receives an LLM-optimized full project map derived from
this cached context: all nodes, edges, and the spec-kit index rendered by
`Foundry.Context.LLMFormatter`. This gives the orchestrator enough topology to classify
intent, detect likely impact, and choose the right follow-up retrieval without reading
source files wholesale. Per-module `mix foundry.project.context <Module>` remains the
lazy precision lookup for code-derived details.

Spec-kit navigation is rendered inside this full map, not injected again as a separate
Tier 1 block. `mix foundry.project.status` remains the compact health view.

### 2. CI staleness check via lockfile

```
mix foundry.project.context --check
```

Computes `sha256(lib/**/*.ex + test/**/*.ex)` and compares against
`.foundry/context.lock`. Exits 1 if they differ or if the lock file is absent. The lock
file contains only the hash — ~50 bytes, committed to the repository. This is the same
pattern as `mix.lock` and `package-lock.json`: a small committed artifact that proves
the computed output is still valid for the current inputs, without committing the full
output.

To update the lockfile after source changes:
```bash
mix foundry.project.context    # recomputes and updates .foundry/context.lock
```

CI runs `--check` to enforce freshness. The check does not require the application to
be running — it is a pure hash comparison.

### 3. Rename snapshot → status

Replace `mix foundry.project.snapshot` with:

```
mix foundry.project.status
```

The output is a `ProjectStatus` struct. "Status" correctly names what the data
describes: the current condition of the project at this moment. The word "snapshot"
is retired.

**No token cap at the data layer.** `mix foundry.project.status` returns the complete
runtime health picture — all lint violations, all compliance gaps, all open proposals,
pending migrations, CI state, test coverage, stack versions, manifest summary.
`Foundry.Copilot.ContextBuilder` applies its own ~400-token truncation view when
assembling Tier 2. The data model and the rendering concern are separated.

`mix foundry.project.status` includes a `compiled_at` field (sourced from `_build/`
max mtime) so consumers can detect whether the compiled state is stale relative to
source files. The studio shows a recompilation banner when this condition is detected.

### 4. File system access via `Foundry.FileSystem`

All file reads from the studio UI and the copilot shell go through a single validated
module: `Foundry.FileSystem`. Direct `File.read!/1` calls from channels or controllers
are forbidden.

```elixir
Foundry.FileSystem.read(project_root :: String.t(), relative_path :: String.t())
:: {:ok, String.t()} | {:error, :outside_boundary} | {:error, :not_found}
```

**Implementation requirement:** Path resolution must use `Path.expand/1` before prefix
comparison. Naive string prefix matching fails on traversal variants such as
`lib/../../.env` and `lib/../lib/../.env`. The implementation is:

```elixir
expanded = Path.expand(Path.join(project_root, relative_path))
if String.starts_with?(expanded, allowed_root), do: File.read(expanded), ...
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
{"event": "fetch_file",     "path": "lib/my_app/finance/wallet.ex"}
{"event": "fetch_document", "path": "docs/adrs/ADR-003-agent-context-strategy.md"}

# Server responds via push:
{"event": "file_content",   "path": "...", "content": "...", "mime": "text/plain"}
{"event": "document",       "path": "...", "document": %SpecKitDocument{}}
{"event": "file_error",     "path": "...", "reason": "outside_boundary"}
```

`fetch_file` returns raw string content — used for Elixir source, config, and
migration files in the diff viewer and module inspector.

`fetch_document` returns a parsed `SpecKitDocument` struct — used for ADRs, runbooks,
regulations, and AGENTS.md in the spec-kit overlay panel. The struct has sections,
compliance_refs, and module_refs extracted from the MDEx AST. The underlying MDEx
parse is cached in ETS by `{:spec_kit, file_path, mtime}` and shared with the index
builder — one parse, two views.

The diff view of a spec-kit document (in the proposal review panel) uses the raw
unified git diff output rendered as colored lines, not the parsed sections. The parsed
`SpecKitDocument` is for the read/navigation view only.

Both events route through `Foundry.FileSystem.read/2`. The channel has no path logic.

### 5. Session state for system map preview

`Foundry.Context.SessionState` captures the system map state (all node IDs and edge
hashes) at the start of an editing session — the first user interaction after Studio
mount or after a proposal is committed. Stored in ETS keyed by session ID.

When a proposal branch exists, `mix foundry.project.context` can be run against the
proposal branch and compared to the session-start state. The delta
(`graph_delta: %{added_nodes: [], changed_nodes: [], removed_nodes: [], added_edges: [],
removed_edges: []}`) is returned alongside the full context. The studio uses this to
render the system map in preview mode: new nodes highlighted green, changed nodes amber,
removed nodes dimmed red.

The session state is captured once and held until the proposal is committed or
discarded — it is the stable baseline against which all edits are compared.

### 6. Umbrella project support

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

`project_type: :standard` is the default and need not be declared for non-umbrella
projects.

**`mix foundry.project.context` in umbrella mode:**
- Module scanner walks `apps/*/lib/` instead of `lib/`
- Node IDs are fully-qualified module names — app membership is encoded in the module
  name, not as a separate field (`IgamingCore.Finance.Wallet`, not
  `{app: "igaming_core", module: "Finance.Wallet"}`)
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

### 7. Related projects (multi-repo workspace)

Projects that are related but not in the same repo are declared in the manifest:

```elixir
related_projects: [
  %{name: "PaymentService", path: "../payment_service"},
  %{name: "ComplianceEngine", path: "../compliance_engine"}
]
```

Each related project is an independent Foundry context — its own
`mix foundry.project.context`, its own spec-kit, its own proposals. The studio loads
the project list from the current project's manifest on startup, then fetches each
related project's context lazily when the user navigates to it.

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
The `mix foundry.project.context` schema is defined in `docs/project_context_schema.md`.

---

## Migration

| Old | New | Action |
|---|---|---|
| `mix foundry.project.snapshot` | `mix foundry.project.status` | Rename command and module. Schema expands — see updated `mix_task_summary_schemas.md`. `snapshot_at` field → `generated_at`. |
| `mix foundry.diagram.generate` (studio use) | `mix foundry.project.context` | Studio switches data source. |
| `mix foundry.diagram.generate` (CI check) | `mix foundry.project.context --check` | Lockfile check replaces committed JSON diff. |
| `mix foundry.context <Module>` | `mix foundry.project.context <Module>` | Same namespace as bulk command. Backward-compat alias retained. |
| `mix foundry.context.all` | `mix foundry.project.context` (bulk, no arg) | Absorbed — project.context is a strict superset. |
| `mix foundry.versions.check` | Lint rules + `project.status` stack field | Version data in status; enforcement in `Foundry.LintRules.VersionRule`. |
| `mix foundry.compliance.check` | `project.status` compliance field | Full compliance matrix is a field in status. |
| Direct `File.read!/1` in channels | `Foundry.FileSystem.read/2` | Any channel or controller reading files must route through `Foundry.FileSystem`. |
| `snapshot_at` field | `generated_at` field | Rename in status response. |
| 400-token cap in status | No cap at data layer | ContextBuilder applies truncation view for Tier 2. |

`mix foundry.context <Module>` is retained as a backward-compat alias.
`mix foundry.diagram.generate` is retained as a backward-compat alias.
Neither is documented as canonical going forward.

---

## Consequences

- The studio makes one call instead of N+1 to populate the system map; the call hits
  ETS cache on every request after the first
- File read security boundary is enforced in one module — channels contain no path logic
- Umbrella projects are first-class — no workarounds needed in the studio or copilot
- `mix foundry.project.status` is unbounded at the data layer; ContextBuilder owns
  the truncation decision for Tier 2
- `Foundry.FileSystem` becomes a required dependency for any new channel or controller
  that reads project files — this is the intended constraint
- Related projects require explicit manifest declarations — cross-project edges are
  never inferred, only declared
- The `.foundry/context.lock` file (50 bytes) is the only committed artifact from the
  context pipeline; the full context lives in ETS only
