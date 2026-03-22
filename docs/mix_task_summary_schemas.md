# docs/mix_task_summary_schemas.md — Project Status Schema

> **Status:** Active — governs `mix foundry.project.status` output format.
> **Supersedes:** `mix foundry.project.snapshot` (renamed per ADR-020).
> `Foundry.Copilot.ContextBuilder` reads from this task for Tier 2 session context,
> refreshed on every copilot request. The token truncation is applied by ContextBuilder,
> not by this task — the task always returns complete current state.
>
> **Rule:** This task returns the full runtime health picture with no token cap.
> ContextBuilder applies its own ~400-token view when assembling the Tier 2 prompt.

---

## `mix foundry.project.status`

**Token cap:** None at the data layer. ContextBuilder applies truncation for Tier 2.
**Cache TTL:** 60 seconds (stale enough to be cheap, fresh enough to reflect recent changes).
**Used by:** `Foundry.Copilot.ContextBuilder` — truncated view assembled into Tier 2.
**Also used by:** Studio health panels, Operations Board (Phase 5).

Single command that composes all health and orientation signals into one JSON object.
The agent reads a ContextBuilder-truncated view of this from Tier 2 and uses it for
orientation before calling any shell commands. For full detail on any field, the agent
uses bash to call the appropriate Mix task or read the relevant file.

```json
{
  "generated_at": "2026-03-21T10:00:00Z",
  "compiled_at": "2026-03-21T09:55:00Z",
  "project": "MyApp",

  "domains": ["Finance", "Identity", "Compliance", "Game"],

  "sensitive_modules": ["Wallet", "LedgerEntry", "WithdrawalTransfer", "Player", "WithdrawalRequest"],

  "lint": {
    "errors": 0,
    "warnings": 2,
    "violations": [
      {
        "rule": "INV-017",
        "module": "MyApp.Finance.WithdrawalTransfer",
        "step": "w-approve",
        "message": "Agent step missing telemetry_prefix declaration",
        "severity": "warning"
      }
    ]
  },

  "migrations": {
    "pending_count": 1,
    "latest_applied": "20260315120000_add_withdrawal_limit",
    "pending": [
      {
        "module": "MyApp.Identity.SpendingLimit",
        "migration": "20260321000000_add_spending_limit_confirmed_at"
      }
    ]
  },

  "proposals": {
    "open_count": 1,
    "items": [
      {
        "id": "prop_a3f9",
        "module": "MyApp.Finance.BonusAward",
        "operation": "Op.AddAttribute",
        "change_class": "compliance",
        "state": "PENDING_REVIEW",
        "adr_required": true,
        "adr_linked": false
      }
    ]
  },

  "compliance": {
    "gap_count": 1,
    "requirements": [
      {
        "id": "RG-UK-022",
        "title": "Spending limit enforcement",
        "status": "gap",
        "module": "MyApp.Identity.SpendingLimit",
        "reason": "No scenario or e2e tests covering limit enforcement",
        "coverage": {
          "property_tests": false,
          "scenario_tests": false,
          "e2e_tests": false
        }
      }
    ]
  },

  "test_coverage": {
    "overall_pct": 74,
    "modules_with_gaps": [
      {
        "module": "MyApp.Identity.SpendingLimit",
        "property_tests": false,
        "scenario_tests": false,
        "e2e_tests": false,
        "coverage_pct": 30
      }
    ]
  },

  "ci": {
    "last_run_at": "2026-03-21T09:47:00Z",
    "commit": "a3f9d12",
    "branch": "main",
    "lint_passed": true,
    "tests_passed": true,
    "context_lock_current": true
  },

  "stack": {
    "elixir": "1.19",
    "ash": "3.4.1",
    "phoenix": "1.7.14",
    "reactor": "0.9.1",
    "oban": "2.18.0"
  },

  "manifest": {
    "domain_type": "igaming",
    "domain_lead": "platform@co.com",
    "sensitive_resources": ["Wallet", "LedgerEntry", "Player", "WithdrawalRequest"]
  }
}
```

---

## Field definitions

### `compiled_at`
Max mtime of files under `_build/dev/lib/<app>/ebin/`. Allows consumers to detect
whether the compiled state is stale relative to source files. The studio shows a
recompilation banner when `compiled_at < max(lib/**/*.ex mtime)`.

### `domains`
All domain names from compiled Ash domain modules. No truncation — domain count is
bounded by project structure.

### `sensitive_modules`
Short names (last module segment) of all resources declared in
`manifest.sensitive_resources`. No truncation — the manifest list is bounded.

### `lint`
Composed from `mix foundry.lint.all`. Returns all violations — no truncation at the
data layer. ContextBuilder shows the first 5 violations in Tier 2.

`violations` includes all violations. Each entry has: `rule`, `module`, `message`,
`severity`. Version constraint violations (`:ash_version_outdated` etc.) appear here,
sourced from `Foundry.LintRules.VersionRule`.

### `migrations`
Composed from per-module pending migration detection (`mix ash.codegen --check`
per resource). Lists all pending migrations — no truncation at the data layer.

### `proposals`
Scanned from `.foundry/proposals/` — `PENDING_REVIEW` state only.
Lists all open proposals — no truncation at the data layer.

`adr_linked: false` on a `:compliance` proposal is a signal the agent surfaces
explicitly — a compliance change cannot be approved without an ADR link.

### `compliance`
Full compliance matrix — all declared RG-* requirements with status and coverage detail.
`status` is one of: `"covered"` (all three test types present), `"partial"` (some
tests present), `"gap"` (no tests), `"planned"` (requirement declared but no module
linked yet).

This field replaces the former `mix foundry.compliance.check` standalone task.

### `test_coverage`
`overall_pct` is the aggregate across all modules with declared compliance links.
`modules_with_gaps` lists modules where coverage is incomplete. No truncation at the
data layer.

### `ci`
Reflects the last recorded CI run. All boolean flags default to `null` if CI has not
yet run or if the CI integration is not configured.

`context_lock_current` maps to the `mix foundry.project.context --check` result —
`true` if `.foundry/context.lock` matches the current source hash.

### `stack`
All core runtime dependencies with resolved version strings sourced from `mix.lock`.
Version strings are exact resolved values, not constraints (e.g. `"3.4.1"` not `"~> 3.4"`).
Git-sourced dependencies emit their commit SHA as the version string.
Full dependency list available via `bash("cat mix.exs")`.

### `manifest`
Domain type, sensitive resource short names (all of them), and `domain_lead` email.
Full manifest available via `bash("cat .foundry/manifest.exs")`.

---

## Underlying data sources

The status is composed from these sources internally. They are implementation details
of `mix foundry.project.status` — not called directly by callers.

| Source | Contributes to |
|---|---|
| Compiled module scan | `domains`, `sensitive_modules` |
| `mix foundry.lint.all` | `lint` |
| Per-resource `mix ash.codegen --check` | `migrations` |
| `.foundry/proposals/` scan | `proposals` |
| Per-module compliance declarations | `compliance` |
| Per-module test file scan | `test_coverage` |
| CI integration record | `ci` |
| `mix.lock` parse | `stack` |
| `.foundry/manifest.exs` parse | `manifest` |
| `_build/` mtime scan | `compiled_at` |

In umbrella mode, module scan covers `apps/*/lib/`.

---

## ContextBuilder Tier 2 truncation policy

ContextBuilder applies these truncations when assembling the ~400-token Tier 2 view:

- `lint.violations` — first 5 by severity (errors before warnings)
- `migrations.pending` — first 5
- `proposals.items` — first 5
- `compliance.requirements` — first 5 gaps (status: "gap" or "partial")
- `test_coverage.modules_with_gaps` — first 5
- `stack` — all fields (small, bounded)
- `sensitive_modules` — first 8; if more: `[..., "+N more"]`

When truncating, append `{"truncated": N}` as the last item in the array so the agent
knows the full list is longer and can call `bash("mix foundry.project.status")` for
the complete view if needed.

---

## Status refresh policy

The status is refreshed on every copilot request — not cached between requests beyond
the 60-second TTL. It must reflect current project state.

**Staleness note:** If `mix compile` has not been run since the last source change,
lint and context summaries reflect stale compiled state. The studio shows a
recompilation banner when `compiled_at < max(lib/**/*.ex mtime)`. The agent is not
responsible for detecting this condition — the `compiled_at` field surfaces it.

---

## What is NOT in the status

Available via bash when needed:

```bash
cat mix.exs                                                   # full dependency list
cat .foundry/manifest.exs                                     # full manifest
mix foundry.lint.all --json                                   # full violation list
mix foundry.project.context MyApp.Finance.Wallet              # full module context
cat .foundry/proposals/prop_<id>.json                         # specific proposal detail
mix foundry.project.context                                   # full system map
```

The system map (`mix foundry.project.context`) is never included in the Tier 2 LLM
context — it is studio UI data and ETS cache data, not agent orientation data. The
agent navigates via per-module `mix foundry.project.context <Module>` calls, not by
scanning the full graph.