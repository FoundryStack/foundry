# docs/mix_task_summary_schemas.md — Project Snapshot and Summary Schemas

> **Status:** Active — governs `mix foundry.project.snapshot` output and the
> underlying `--summary` flag variants it composes. `Foundry.Copilot.ContextBuilder`
> includes the snapshot in Tier 2 session context, refreshed on every copilot request.
>
> **Rule:** All output must stay within declared token bounds regardless of project
> size. Each component is responsible for its own truncation.

---

## `mix foundry.project.snapshot`

**Token bound:** ≤ 400 tokens total.
**Cache TTL:** 60 seconds (stale enough to be cheap, fresh enough to reflect recent changes).
**Used by:** `Foundry.Copilot.ContextBuilder` — assembled into Tier 2 session context.

Single command that composes all session context into one JSON object. The agent reads
this from Tier 2 and uses it for orientation before calling any shell commands.

```json
{
  "snapshot_at": "2026-03-16T10:00:00Z",
  "domains": ["Finance", "Compliance", "Players", "Promotions"],
  "sensitive_modules": ["Wallet", "LedgerEntry", "WithdrawalTransfer"],
  "structure": {
    "lib_web": {
      "live_views": 14,
      "controllers": 3,
      "router": "lib/my_app_web/router.ex"
    },
    "workers": ["PaymentProcessor", "KycPoller", "NotificationDispatcher"],
    "integrations": ["SafechargeAdapter", "SumsubAdapter", "TwilioAdapter"],
    "telemetry": "lib/my_app/telemetry.ex"
  },
  "health": {
    "lint_errors": 0,
    "lint_warnings": 2,
    "pending_migrations": 0,
    "open_proposals": 1,
    "open_proposal_modules": ["MyApp.Finance.BonusAward"],
    "compliance_gaps": ["RG-UK-022"]
  },
  "key_files": {
    "mix_exs": "elixir ~> 1.17, ash ~> 3.4, phoenix ~> 1.7, reactor ~> 0.9",
    "manifest": "domain_type: igaming, sensitive: [Wallet, LedgerEntry], domain_lead: platform@co.com"
  },
  "priv": {
    "migration_count": 47,
    "latest_migration": "20260315120000_add_withdrawal_limit"
  },
  "test_support": ["DataCase", "ConnCase", "Factory"]
}
```

### Why this replaces eight separate Tier 2 components

Earlier drafts assembled domain map, compliance summary, lint status, open proposals,
pending migrations, project structure, `mix.exs`, and `manifest.exs` as separate
components totalling ≤ 900 tokens. The snapshot consolidates them:

- One cache entry instead of eight
- One assembly call instead of eight subprocess calls
- ~400 tokens instead of ≤ 900 — more headroom for conversation history
- Agent gets the same orientation signal with less latency

The snapshot is a summary of summaries. When the agent needs depth on any component,
it uses bash: `cat mix.exs`, `mix foundry.compliance.check --json`,
`mix foundry.lint.all --json`, `cat .foundry/manifest.exs`.

---

## Truncation Rules

**`domains`:** All domain names. No truncation — domain count is bounded by project structure.

**`sensitive_modules`:** Short names only (last module segment). Maximum 8.
If more: `["Wallet", "LedgerEntry", "+N more"]`.

**`structure.workers` / `structure.integrations`:** Module short names. Maximum 8 each.
If more: append `"+N more"`.

**`health.open_proposal_modules`:** Maximum 5. If more: `["+N more"]`.

**`health.compliance_gaps`:** Requirement IDs only. Maximum 5. If more: `["+N more"]`.

**`key_files.mix_exs`:** Core dependencies only — elixir, ash, phoenix, reactor, oban.
Full version strings. Strip test-only and build tool dependencies.

**`key_files.manifest`:** Domain type, sensitive resource short names (max 3), and
approver email for domain_lead only. Full manifest available via
`bash("cat .foundry/manifest.exs")`.

---

## Underlying summary commands

The snapshot is composed from these commands internally. They are not directly
called by the agent — they are implementation details of `mix foundry.project.snapshot`.
They are documented here for implementors.

| Command | Contributes to | Notes |
|---|---|---|
| `mix foundry.context.all --summary` | `domains`, `sensitive_modules` | |
| `mix foundry.compliance.check --summary` | `health.compliance_gaps` | |
| `mix foundry.lint.all --summary` | `health.lint_errors`, `health.lint_warnings` | |
| `mix foundry.context.all --pending-migrations` | `health.pending_migrations`, `priv` | |
| `.foundry/proposals/` scan | `health.open_proposals`, `health.open_proposal_modules` | PENDING_REVIEW state only |
| `find lib/ -type d` + module scan | `structure` | |
| `mix.exs` parse | `key_files.mix_exs` | |
| `.foundry/manifest.exs` parse | `key_files.manifest` | |

---

## Session Context Refresh Policy

The snapshot is refreshed on every copilot request — not cached between requests
beyond the 60-second TTL. It must reflect current project state: a lint error fixed
30 seconds ago should not appear as an error on the current request.

The 60-second TTL is a pragmatic bound. In practice, the agent loop itself takes
several seconds, so back-to-back requests will usually see a fresh snapshot.

**Staleness note:** If `mix compile` has not been run since the last source change,
the lint and context summaries reflect stale compiled state. The Studio shell shows
a recompilation banner — the agent is not responsible for detecting this condition.

---

## What Is NOT in the Snapshot

Available via bash when needed — not in the snapshot to preserve token budget:

```bash
cat mix.exs                                    # full dependency list
cat .foundry/manifest.exs                      # full manifest
mix foundry.compliance.check --json            # full compliance matrix
mix foundry.lint.all --json                    # full violation list with messages
mix foundry.context MyApp.Finance.Wallet --json  # full module struct
cat .foundry/proposals/prop_<id>.json          # specific proposal detail
```