# docs/mix_task_summary_schemas.md — Project Status Schema

> **Status:** Active — governs `mix foundry.project.status` output format.
> **Supersedes:** `mix foundry.project.snapshot` (renamed per ADR-020).
> `Foundry.Copilot.ContextBuilder` includes the status in Tier 2 session context,
> refreshed on every copilot request.
>
> **Rule:** All output must stay within declared token bounds regardless of project
> size. Each component is responsible for its own truncation.

---

## `mix foundry.project.status`

**Token bound:** ≤ 400 tokens total.
**Cache TTL:** 60 seconds (stale enough to be cheap, fresh enough to reflect recent changes).
**Used by:** `Foundry.Copilot.ContextBuilder` — assembled into Tier 2 session context.

Single command that composes all health and orientation signals into one JSON object.
The agent reads this from Tier 2 and uses it for orientation before calling any shell commands.

The name reflects what the data describes: the current *condition* of the project.
"Snapshot" was retired in ADR-020 because it implied a frozen point-in-time record
rather than a live health signal.

```json
{
  "generated_at": "2026-03-21T10:00:00Z",
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
        "message": "Agent step missing telemetry_prefix declaration"
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
    "gaps": [
      {
        "requirement": "RG-UK-022",
        "module": "MyApp.Identity.SpendingLimit",
        "reason": "No scenario or e2e tests covering limit enforcement"
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
    "diagram_current": true,
    "spec_kit_index_current": true
  },

  "stack": {
    "elixir": "1.17",
    "ash": "3.4.1",
    "phoenix": "1.7.x",
    "reactor": "0.9",
    "oban": "2.x"
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

### `domains`
All domain names from compiled Ash domain modules. No truncation — domain count is bounded
by project structure.

### `sensitive_modules`
Short names only (last module segment). Maximum 8.
If more: `["Wallet", "LedgerEntry", "+N more"]`.

### `lint`
Composed from `mix foundry.lint.all --json`.

`violations` contains the first 5 violations only — enough for the agent to diagnose
the issue without blowing the token budget. Full list available via
`bash("mix foundry.lint.all --json")`.

Truncation: if more than 5 violations, append `{ "truncated": N }` as the last item.

### `migrations`
Composed from `mix foundry.context.all --pending-migrations`.

`pending` lists up to 5 pending migrations. If more: append `{ "truncated": N }`.

### `proposals`
Scanned from `.foundry/proposals/` — `PENDING_REVIEW` state only.

`items` lists up to 5 open proposals. If more: append `{ "truncated": N }`.

`adr_linked: false` on a `:compliance` proposal is a signal the agent surfaces
explicitly in the Activity Feed — a compliance change cannot be approved without an ADR link.

### `compliance`
Composed from `mix foundry.compliance.check --summary`.

`gaps` lists requirement IDs with the first affected module and a brief reason string.
Maximum 5. If more: append `{ "truncated": N }`.

### `test_coverage`
`overall_pct` is the aggregate across all modules with declared compliance links.
`modules_with_gaps` lists modules where all three coverage flags are false.
Maximum 5. If more: append `{ "truncated": N }`.

### `ci`
Reflects the last recorded CI run. All boolean flags default to `null` if CI has not
yet run or if the CI integration is not configured.

`diagram_current` maps to the `mix foundry.project.context --check` result (renamed from
`mix foundry.diagram.generate --check` per ADR-020).
`spec_kit_index_current` maps to `mix foundry.spec_kit.index --check`.

### `stack`
Core dependencies only: elixir, ash, phoenix, reactor, oban.
Full version strings. Strip test-only and build tool dependencies.
Full dependency list available via `bash("cat mix.exs")`.

### `manifest`
Domain type, sensitive resource short names (max 5), and `domain_lead` email only.
Full manifest available via `bash("cat .foundry/manifest.exs")`.

---

## Underlying commands

The status is composed from these commands internally. They are not directly called by
the agent — they are implementation details of `mix foundry.project.status`.

| Command | Contributes to |
|---|---|
| `mix foundry.context.all --summary` | `domains`, `sensitive_modules` |
| `mix foundry.lint.all --json` | `lint` |
| `mix foundry.compliance.check --summary` | `compliance` |
| `mix foundry.context.all --pending-migrations` | `migrations` |
| `.foundry/proposals/` scan | `proposals` |
| `find lib/ -type d` + module scan | implied by domains/sensitive |
| `mix.exs` parse | `stack` |
| `.foundry/manifest.exs` parse | `manifest` |

In umbrella mode, `find lib/` expands to `find apps/*/lib/`.

---

## Session context refresh policy

The status is refreshed on every copilot request — not cached between requests beyond
the 60-second TTL. It must reflect current project state.

**Staleness note:** If `mix compile` has not been run since the last source change,
lint and context summaries reflect stale compiled state. The Studio shell shows a
recompilation banner — the agent is not responsible for detecting this condition.

---

## What is NOT in the status

Available via bash when needed — not in the status to preserve the token budget:

```bash
cat mix.exs                                      # full dependency list
cat .foundry/manifest.exs                        # full manifest
mix foundry.compliance.check --json              # full compliance matrix
mix foundry.lint.all --json                      # full violation list
mix foundry.context MyApp.Finance.Wallet --json  # full module context
cat .foundry/proposals/prop_<id>.json            # specific proposal detail
mix foundry.project.context                      # full system map with all nodes and edges
```

The system map (`mix foundry.project.context`) is never included in the Tier 2 LLM context —
it is studio UI data, not agent orientation data. The agent navigates via per-module
`mix foundry.context <Module>` calls, not by scanning the full graph.