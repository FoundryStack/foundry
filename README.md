# Foundry

A governed build environment for Elixir/Ash/Phoenix platforms.
Foundry extracts a typed system map from your project, enforces invariants
via a lint suite, and provides a structured runtime health picture for CI
and the Foundry Studio UI.

---

## What Foundry Does

- **System map extraction** — `mix foundry.project.context` walks all compiled Ash/Spark
  modules and emits a typed JSON graph of nodes (resources, reactors, domains) and edges
  (writes, reads, async, references).
- **Governance lint** — `mix foundry.lint.all` runs the invariant suite against all modules
  and the project manifest. Exits non-zero on `:error` violations, passes with warnings.
- **Runtime health picture** — `mix foundry.project.status` composes lint results, pending
  migrations, stack versions, CI state, and compliance coverage into a single JSON snapshot.

---

## Requirements

- Elixir ~> 1.15
- Ash ~> 3.20 (**Ash 2.x is not supported**)
- A `.foundry/manifest.exs` in your target project root

---

## Installation

Add to your `mix.exs` dependencies:

```elixir
{:foundry_stack, "~> 0.1", only: [:dev, :test]}
```

For umbrella projects, add to the specific app that owns the build tooling.
Foundry does not need to be in every umbrella app's deps.

Run:

```bash
mix deps.get
```

---

## Quickstart

**1. Create your project manifest:**

```bash
mkdir -p .foundry
```

Create `.foundry/manifest.exs` — see [The Manifest](#the-manifest-foundrymanifestexs) below.

**2. Generate the system map:**

```bash
mix foundry.project.context
```

Emits a JSON graph of all Ash/Spark modules to stdout and writes `.foundry/context.lock`.

**3. Check project health:**

```bash
mix foundry.project.status
```

**4. Run the lint suite:**

```bash
mix foundry.lint.all
```

---

## The Manifest (`.foundry/manifest.exs`)

Foundry reads `.foundry/manifest.exs` from the project root. This file is committed to
your project repository. It is a plain Elixir keyword list.

**Minimum required manifest:**

```elixir
# .foundry/manifest.exs
[
  project_name: "MyApp",
  domain_type: :other,  # :igaming | :fintech | :healthcare | :legal | :insurance | :other

  approvers: [
    sensitive_lead:     "lead@company.com",
    compliance_officer: "compliance@company.com"
  ],

  sensitive_resources: [
    MyApp.Finance.LedgerEntry,
    MyApp.Finance.Wallet
    # ash_authentication User and Token resources are always treated as sensitive —
    # do not list them here; Foundry detects them automatically.
  ]
]
```

The manifest is validated at startup. Invalid manifests prevent tasks from running.
Required fields: `project_name`, `approvers.sensitive_lead`, `approvers.compliance_officer`.

Full schema reference: [`docs/manifest-schema-draft.md`](../../docs/manifest-schema-draft.md)

---

## Mix Tasks

### `mix foundry.project.context`

Generates the project system map.

```bash
mix foundry.project.context                         # full graph — all modules
mix foundry.project.context MyApp.Finance.Wallet    # single module NodeEntry
mix foundry.project.context --check                 # CI staleness check
```

**Bulk output** emits JSON to stdout:

```json
{
  "generated_at": "2026-03-22T10:00:00Z",
  "project": "MyApp",
  "project_type": "standard",
  "domain_type": "igaming",
  "nodes": [ "..." ],
  "edges": [ "..." ],
  "spec_kit": { "..." },
  "graph_delta": null
}
```

Also writes `.foundry/context.lock` — a SHA256 hash of all `lib/**/*.ex` and
`test/**/*.ex` files. Use `--check` in CI to verify the lock is current.

**Exit codes:**

- `0` — success
- `1` — lock stale or absent (only with `--check`)

Schema: [`docs/project_context_schema.md`](../../docs/project_context_schema.md)

---

### `mix foundry.project.status`

Emits a runtime health snapshot as JSON.

```bash
mix foundry.project.status
mix foundry.project.status --json   # compact output (no pretty-print)
```

Output includes: compilation timestamp, stack versions, lint summary, pending migrations,
open proposals, compliance matrix, CI state, and manifest metadata.

Schema: [`docs/mix_task_summary_schemas.md`](../../docs/mix_task_summary_schemas.md)

---

### `mix foundry.lint.all`

Runs the full Foundry lint suite. Emits a JSON report and exits non-zero if any `:error`
violations are found.

```bash
mix foundry.lint.all                # JSON output (default)
mix foundry.lint.all --format=text  # human-readable summary
```

**Exit codes:**

- `0` — no `:error` violations (warnings and info are non-blocking)
- `1` — one or more `:error` violations
- `2` — lint runner crash (rule bug)

**Output shape:**

```json
{
  "passed": false,
  "error_count": 1,
  "warning_count": 2,
  "info_count": 0,
  "violations": [
    {
      "rule_id": "missing_paper_trail",
      "severity": "error",
      "message": "MyApp.Finance.Wallet is sensitive but does not use AshPaperTrail.Resource",
      "module": "MyApp.Finance.Wallet"
    }
  ],
  "generated_at": "2026-03-22T10:00:00Z"
}
```

---

## Lint Rules

The following rules run in `mix foundry.lint.all`.
Full catalogue including planned rules: [`docs/lint-catalogue.md`](../../docs/lint-catalogue.md)

| Rule ID                              | INV     | Severity   | Description                                                   |
| ------------------------------------ | ------- | ---------- | ------------------------------------------------------------- |
| `missing_paper_trail`                | INV-011 | `:error`   | Sensitive resource missing `AshPaperTrail.Resource` extension |
| `missing_archival`                   | INV-012 | `:error`   | Sensitive resource missing `AshArchival.Resource` extension   |
| `missing_runbook`                    | INV-005 | `:error`   | Reactor with >3 steps missing `@runbook` declaration          |
| `missing_idempotency`                | INV-004 | `:error`   | Reactor with side-effect steps missing idempotency key        |
| `missing_description`                | INV-006 | `:error`   | Ash resource attribute missing `description:` value           |
| `ash_version_outdated`               | —       | `:error`   | Resolved `ash` version in `mix.lock` is below 3.x             |
| `elixir_version_unsupported`         | —       | `:error`   | Elixir version below minimum required for Ash 3.x             |
| `adapter_version_not_active`         | —       | `:warning` | Provider adapter registered but not active                    |
| `manifest_missing_required_approver` | —       | `:error`   | `approvers.sensitive_lead` or `compliance_officer` absent     |
| `manifest_invalid_coverage_weights`  | —       | `:error`   | `coverage_weights` values do not sum to 1.0                   |
| `manifest_missing_cldr_backend`      | —       | `:error`   | `:ash_money` declared but no CLDR backend discoverable        |

Rules are registered in `Foundry.LintRules.Registry`. New rules must be added there
explicitly — accidental registration is worse than deliberate omission.

---

## CI Integration

Add to your CI pipeline (GitHub Actions example):

```yaml
- name: Check context lock
  run: mix foundry.project.context --check

- name: Run lint suite
  run: mix foundry.lint.all
```

**Context lock check:** `mix foundry.project.context --check` computes
`sha256(lib/**/*.ex + test/**/*.ex)` and compares it against `.foundry/context.lock`.
Fails if the lock is absent or stale.

Regenerate the lock whenever source files change:

```bash
mix foundry.project.context
git add .foundry/context.lock
```

**Optional — write CI status for the Studio health panel:**

After your CI run, write `.foundry/ci_status.json`:

```json
{
  "last_run_at": "2026-03-22T10:00:00Z",
  "commit": "a3f9d12",
  "branch": "main",
  "lint_passed": true,
  "tests_passed": true
}
```

`mix foundry.project.status` merges this file into the `ci` field of its output.
The file must live at exactly `.foundry/ci_status.json` in the project root.

---

## Change Classification

Every proposed change is classified into one of four classes. Classification determines
approval requirements.

| Class         | When                                                                       | Approver                                   | Auto-apply                             |
| ------------- | -------------------------------------------------------------------------- | ------------------------------------------ | -------------------------------------- |
| `:structural` | New resource, attribute, relationship, description, test skeleton          | Any developer                              | Configurable (`auto_apply_structural`) |
| `:behavioral` | New Rule, Transfer step, Reactor, Oban job, state machine transition       | Domain lead                                | Never                                  |
| `:sensitive`  | Changes to resources in `manifest.sensitive_resources`                     | Sensitive lead + one other (dual approval) | Never                                  |
| `:compliance` | Changes to compliance declarations, policy modules, compliance-gated flags | Compliance officer                         | Never — ADR link required              |

**When in doubt, classify upward.** A `:behavioral` change misclassified as `:structural`
and auto-applied is a governance failure. The reverse is merely inconvenient.

---

## Internal Architecture (Contributors)

### Module Map

| Module                                | Role                                                                                                    |
| ------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| `Foundry.FileSystem`                  | Validated read boundary — all file access routes through here; enforces permitted root paths            |
| `Foundry.SparkMeta`                   | Spark DSL walker — extracts typed information from compiled modules                                     |
| `SparkLint.Rule` (package)            | Behaviour for lint rules: `check/2 → {:ok, [violation]}`                                                |
| `SparkLint.Runner` (package)          | Executes rules across all modules, collects violations                                                  |
| `SparkLint.Violation` (package)       | Violation struct: `rule_id, module, message, severity, step, attribute`                                 |
| `Foundry.LintRules.*`                 | Rule implementations — one module per rule                                                              |
| `Foundry.LintRules.Registry`          | Explicit rule registration; `module_rules/0` and `manifest_validators/0`                                |
| `Foundry.Lint.Runner`                 | High-level orchestrator: discovers modules, runs registry rules, emits `LintReport`                     |
| `Foundry.Context.GraphBuilder`        | Assembles the full node+edge graph from all project modules                                             |
| `Foundry.Context.NodeBuilder`         | Constructs a `NodeEntry` from `SparkMeta` output                                                        |
| `Foundry.Context.NodeEntry`           | Core typed output struct for per-module context                                                         |
| `Foundry.Context.EdgeEntry`           | Typed edge between two nodes                                                                            |
| `Foundry.Context.LockFile`            | Writes and validates `.foundry/context.lock`                                                            |
| `Foundry.Context.ModuleDiscovery`     | Discovers all compiled project modules                                                                  |
| `Foundry.Context.SpecKitIndexBuilder` | Walks `docs/adrs/`, `docs/findings/`, `docs/runbooks/`, `docs/regulations/`; populates `spec_kit` field |
| `Foundry.Context.SessionState`        | Captures system map state for graph delta computation                                                   |
| `Foundry.Manifest`                    | Ash resource for manifest schema + validation (no database — Simple data layer)                         |
| `Foundry.Manifest.Parser`             | Reads and parses `.foundry/manifest.exs`                                                                |
| `Foundry.Status`                      | Composes the runtime health picture from all Phase 1 sources                                            |
| `Foundry.Status.StackVersions`        | Extracts resolved dependency versions from `mix.lock`                                                   |

### Adding a Lint Rule

**1.** Create `lib/foundry/lint_rules/your_rule.ex`:

```elixir
defmodule Foundry.LintRules.YourRule do
  @behaviour SparkLint.Rule

  def check(module, ctx) do
    # ctx.metadata[:sensitive_modules] — list of sensitive module atoms
    # ctx.modules                      — all discovered project modules
    # ctx.metadata[:manifest]          — parsed manifest keyword list
    violations = []
    {:ok, violations}
  end
end
```

**2.** Register it in `Foundry.LintRules.Registry`:

```elixir
@module_rules [
  ...,
  Foundry.LintRules.YourRule
]
```

**3.** Add the rule to [`docs/lint-catalogue.md`](../../docs/lint-catalogue.md) with
`status: planned` before implementing, `status: active` once shipped.

**4.** Write a test in `test/foundry/lint_rules/your_rule_test.exs`.

Rules must handle crashes gracefully. Use `rescue` around any Spark introspection calls —
Spark extensions may not be loaded for all modules in the project under test.
