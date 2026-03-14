# AGENTS.md — Foundry

> This file is the primary context document for any AI agent working on the Foundry codebase.
> Read this before reading any other file. It tells you what this system is, what it must never do,
> and where to find authoritative answers to specific questions.

---

## What This System Is

**Foundry** is a governed build environment for complex domain platforms on the Elixir/Ash/Phoenix stack.

It is not an IDE. It is not a code generator. It is an environment where:
- Domain structure is declared once via Spark DSL
- Invariants are enforced by the compiler and linter
- AI agents propose changes; humans approve them
- Compliance requirements are linked to code and tests
- The system diagram is always generated from live code

The **target users** are teams building platforms in regulated domains (fintech, iGaming, healthcare, legal, insurance).

The **target stack** is Elixir + Ash Framework 3.x + Phoenix LiveView + Spark DSL extensions.

Foundry has two modes:
- `local` — runs as `mix foundry.studio` in a target project directory, reads files directly
- `cloud` — hosted service, connects to a git repo, runs Mix tasks via subprocess, streams results over WebSocket

**Terminology:**
- *Foundry* — this meta-platform
- *Target platform* — a platform built using Foundry (e.g., an iGaming back office, a fintech ledger system)
- *Spec-kit* — the four document types that capture what code cannot: ADRs, Regulations, Runbooks, AGENTS.md

---

## What Foundry Is NOT

- Not a general-purpose coding assistant — it only understands the Foundry-compatible stack
- Not an autonomous deployment tool — it never applies changes to production without human approval
- Not a documentation generator — it reads and validates documentation; it does not synthesize stale prose
- Not a compliance officer — it tracks coverage; humans interpret requirements

---

## Package Layer

Foundry is partially composed of independently-published Elixir packages.
These packages have no Foundry-specific assumptions — they are reusable primitives
that Foundry depends on. Rationale for each extraction decision is in ADR-019.

| Package | Role | Used by Foundry via |
|---|---|---|
| `spark_meta` | Generic Spark DSL walker → struct tree. Opt-in `SparkMeta.Extension` hook for richer output; unknown extensions get a raw key-value fallback. | `Foundry.Context.*` Mix tasks — powers `mix foundry.context` |
| `spark_lint` | Rule runner engine only: `SparkLint.Rule` behaviour, `SparkLint.Violation` struct, `mix spark_lint.check` task. Ships zero rules. | `Foundry.LintRules.*` plugs Foundry's INV-011..017 rule modules into it |
| `reactor_human_gate` | Human-in-the-loop gate primitive for any Ash Reactor. Ships `HumanGateTask` resource scaffold and `WaitForHumanStep`. Usable independently of agents. | `Op.AddAgentStep` scaffolds it into target platforms (Phase 8) |
| `reactor_agent_step` | Spark DSL extension for Reactor steps: declares `agent_type`, `model`, `confidence_threshold`, `on_low_confidence`, `tools`, `telemetry_prefix`. Depends on `reactor_human_gate`. | Phase 8 agent injection; extraction confirmed alongside `reactor_human_gate` |

**What is NOT a separate package and why:**
- `Foundry.Diff` — ADR-005 change classifier using `Sourceror`. Logic is tightly coupled to the
  manifest sensitive-resources list and Foundry's classification ruleset. Too specific to extract.
- `Foundry.SpecKit` — spec-kit document parser using `MDEx` + `NimbleOptions`. "Spec-kit" is
  Foundry vocabulary; no external audience for the format yet.
- `Foundry.Operations` — the 20-operation catalogue. The describe/validate/run protocol lives
  here. Extract only if a second tool needs the same protocol.
- `Foundry.Proposals` — proposal state machine (ADR-014). Coupled to git-backed storage
  (ADR-015) and blob-hash stale detection (ADR-009). Extract when a second use case appears.
- A DSL annotation extension for sensitive resources (`ash_governed`) — not needed for v1.
  `manifest.sensitive_resources` list is sufficient. Future enhancement only.

**Telemetry:**
Ash and Reactor already emit telemetry for all actions and steps. Foundry adds exactly three
custom spans via `:telemetry.span/3`, no macros, no mandatory behaviour:
- `[:foundry, :llm, :call]` — each LLM API call (model, task_type, prompt_tokens, latency_ms)
- `[:foundry, :context, :subprocess]` — each `mix foundry.context` invocation (module, cached, latency_ms)
- `[:foundry, :proposal, :transition]` — each proposal state transition (proposal_id, from, to, change_class)

Event name constants live in `Foundry.Telemetry`. Call sites use `:telemetry.span/3` directly
with those constants. Grep for `Foundry.Telemetry` to find every instrumented site.

---

## The Three Layers (do not conflate them)

```
Layer 1: Project Visualization (read-only)
  System map, compliance matrix, operations board, test coverage map.
  No changes happen here. This is for understanding and navigation.

Layer 2: Copilot (propose only, never auto-apply for behavioral/sensitive/compliance changes)
  Activity Feed. Proposes diffs. Shows lint + impact. Waits for approval.
  Auto-apply is only permitted for :structural changes when explicitly configured.

Layer 3: Domain Builder (form-driven scaffold, developer review required)
  Blueprint Builder, Resource Builder.
  Generates Igniter operations. Proposal always shown before apply.
```

---

## Hard Invariants — Never Violate These

These are constraints the system enforces and agents must respect. Not guidelines.

**INV-001: No autonomous changes to sensitive domain resources**
Any change touching resources designated `:sensitive` in the project manifest (typically:
ledger entries, wallets, transfer amounts, PII-bearing resources, audit records) requires
the approval class declared in the manifest before the change is applied. An agent must
never auto-apply such a change regardless of lint result.

**INV-002: No direct filesystem writes from agent**
All code changes go through Igniter operations executed by the Foundry backend.
The mechanism: the copilot engine calls `Foundry.Operations.run/2` which uses Igniter
internally and streams the resulting diff back over WebSocket. The agent never calls
`File.write!/2`, `File.stream!/2`, or any direct IO on source files.
For `docs/` (ADRs, runbooks, regulations), the agent proposes plain-text content;
a human commits it. The compiler cannot validate prose — humans must.

**INV-003: Prefer structured scaffold operations; raw Igniter for genuinely novel patterns**
The scaffold operations catalogue covers the common 90%. For the remaining 10% — a custom
migration, a novel module type, a one-off script — agents may use raw Igniter operations
(e.g., `Igniter.create_new_file/3`, `Igniter.Project.Module.create_module/3`).
What is never acceptable: string interpolation to build Elixir source, then writing that
string to disk. Igniter generates valid, formatted, AST-correct code. String interpolation
does not. The prohibition is on the *mechanism*, not on whether an operation exists in the catalogue.

**INV-004: Infrastructure is proposal-only**
Kubernetes, Postgres config, GitHub Actions base pipelines — agents produce structured
proposals rendered as diffs in the review panel. A human with infrastructure context applies them.
There is no `Op.ApplyInfrastructure` operation and there never will be.

**INV-005: One clarifying question maximum — grounded in spec-kit quality**
Before generating a proposal for ambiguous intent, ask at most one clarifying question.
The rationale is not just UX. If the spec-kit (AGENTS.md, ADRs, DSL declarations) is
complete, the agent should rarely need to ask at all — context should resolve ambiguity.
Frequent clarifying questions are a symptom of an incomplete spec-kit or thin `@description`
coverage, not a normal operating condition. When a clarifying question is necessary, it
exposes a gap that should be closed in the spec-kit or DSL declarations.
If the answer is still ambiguous: state the two interpretations explicitly and ask the user
to choose. Never ask a third question. Never generate on unresolved ambiguity.
The clarifying question UX (binary-choice buttons, not free-text) is specified in ADR-013.

**INV-006: Stack versions always in every LLM prompt**
Every LLM call includes the current `mix.exs` dependency versions as the first item.
This prevents Ash 2.x vs 3.x confusion — the most common and most damaging hallucination class.
When in doubt about a DSL option, retrieve the ExDoc JSON for that specific element.
Never generate code from training memory alone when the current API surface is retrievable.

**INV-007: Approved dependency policy governs additions**
Category-based. See ADR-004-dependency-governance.md. The `:ecto` forbidden rule targets
direct application-level usage; `ecto_sql` and `postgrex` as transitive dependencies of
`ash_postgres` are permitted.

**INV-008: Generated diagrams must be committed**
The system diagram generated by `mix foundry.diagram.generate` must not have an uncommitted
diff at CI time. CI runs `mix foundry.diagram.generate` and checks for unstaged changes.
An uncommitted diagram means the diagram no longer reflects the current codebase — a
violation of the "always current" guarantee. See `docs/regulations/platform_invariants.md`.

**INV-009: The spec-kit is the only manual documentation**
The only documentation that requires manual authorship is: ADRs, regulation files, runbooks,
and AGENTS.md. All other documentation is generated from code. Manually maintaining what the
compiler already knows creates synchronisation drift. See `docs/regulations/platform_invariants.md`.

**INV-010: Staleness conditions must have notification channels**
The project manifest must declare notification targets for three staleness conditions:
`runbook_stale`, `adapter_verify_failed`, `compliance_test_failed`. Staleness is never
silently ignored. See `docs/regulations/platform_invariants.md` for the manifest syntax
and the full enforcement specification.

**INV-011: Sensitive resources must have change history**
All `:sensitive` resources must use `AshPaperTrail`. Lint error. Exemptions are `:compliance` class changes.

**INV-012: Sensitive resources must use soft delete**
All `:sensitive` resources must use `AshArchival`. Hard deletion prohibited without exemption.

**INV-013: Compliance-gated feature flags must have ADR links**
Any `fun_with_flags` flag gating a compliance control must declare an ADR link.
Adding or toggling a compliance-gated flag is a `:compliance` class change.

**INV-014: Agent steps require declared confidence thresholds**
Any Reactor step implemented by a module using `Foundry.AgentStep` with `agent_type`
of `decision` or `scorer` must declare an explicit `confidence_threshold` and an
`on_low_confidence` handler. The only permitted handler in v1 is `escalate_human`, which
creates a review task and halts the step pending human resolution. A `decision` or `scorer`
agent step without a confidence threshold is a lint error. Adding or changing the threshold
value is a `:behavioral` class change.

**INV-015: Human-in-the-loop gates on compliance-gated flows**
Any Transfer or Reactor that contains an `agent` step of type `decision` which gates a
compliance-controlled action (spending limit change, withdrawal approval, KYC override) must
declare an explicit `human_gate` in the Reactor DSL. The gate defines the review queue,
SLA, and escalation path. Removing a `human_gate` from a compliance-gated decision step
is a `:compliance` class change requiring ADR linkage.

**INV-016: Agent steps must declare tool access explicitly**
An `agent` step must declare the complete set of Ash actions it may invoke as tools via
the `tools` declaration in the AshAI domain DSL. An agent step that reads resources not
declared in its `tools` list is a lint error. Expanding an agent's tool access on a
compliance-gated resource is a `:compliance` change.

**INV-017: Agent steps must emit telemetry**
All `agent` steps must emit telemetry spans with the `agent_type`, `model`, `confidence`,
and `latency_ms` fields. The telemetry prefix follows the same convention as other steps:
`[app_name, domain_name, reactor_name, step_name]`. Missing telemetry on an agent step
is a lint error. These spans are the source of data for the Agent Health panel in Phase 8.

---

## Change Classification

Every proposed change must be classified. The four classes are **domain-agnostic** —
the examples use a fintech/iGaming context but the model applies to any regulated domain.

| Class | Trigger pattern | Approver | Auto-apply | Audit logged |
|---|---|---|---|---|
| `:structural` | New resource, attribute, relationship, description updates, test skeletons | Any developer | Configurable | No |
| `:behavioral` | New Rule, Transfer step, Blueprint, Reactor, Oban job, state machine transition | Domain lead | Never | Yes |
| `:sensitive` | Resources/attributes marked `:sensitive` in the manifest — ledger entries, PII, audit records, access control | Sensitive lead + one other (dual) | Never | Yes, mandatory |
| `:compliance` | Changes to `compliance:` declarations, policy modules, requirement links | Compliance officer | Never | Yes, ADR required |

**The `:sensitive` class is configured per project, not hardcoded.**
A healthcare platform marks `:phi` resources as sensitive. A legal platform marks `:privileged`
documents. The classification engine reads the manifest's `sensitive_resources:` list.
iGaming uses ledger and wallet resources — that is a project-level configuration, not a
Foundry-level assumption.

**When in doubt, classify upward.** A `:behavioral` change misclassified as `:structural`
and auto-applied is a governance failure. The reverse is merely inconvenient.

---

## Where to Find Authoritative Information

| Question | Where to look |
|---|---|
| What does resource X do? | `mix foundry.context MyApp.Domain.Resource` |
| What compliance requirements affect feature Y? | `mix foundry.compliance.check --filter=Y` |
| What changed in the system recently? | `git log` + `mix foundry.diagram.diff` |
| Correct DSL syntax for X? | ExDoc JSON for the exact library version in mix.exs |
| Pattern for a new Rule/Transfer/Blueprint? | Closest existing example in lib/ — via Foundry.Context.PatternFinder |
| Which ADR covers this decision? | ADR index below |
| Copilot behaviour in edge cases? | ADR-013 |
| Manifest field schema? | `docs/manifest-schema-draft.md` (pre-ADR-011) |

---

## ADR Index

| ID | Slug | Decision summary |
|---|---|---|
| ADR-001 | stack-selection | Elixir/Ash 3.x/Phoenix/Spark — full ecosystem including ash_postgres, money stack, auth, observability |
| ADR-002 | code-generation | Igniter operations (structured or raw) — no string interpolation; migration generation included |
| ADR-003 | agent-context-strategy | Structured retrieval over live DSL introspection, not RAG over code; full context schema |
| ADR-004 | dependency-governance | Category-based approval, forbidden list, ecto direct-only rule, test tool assignments |
| ADR-005 | change-approval-model | Four-class classification, dual approval for :sensitive, migration classification, audit log always |
| ADR-006 | infrastructure-governance | Proposal-only from agents, human apply, base CI pipeline owned by platform |
| ADR-007 | test-generation-strategy | DSL declarations drive skeleton generation, compliance reqs drive E2E, tool assignments |
| ADR-008 | visualization-paradigm | Read-only system map, Activity Feed is the only change interface |
| ADR-009 | concurrent-proposals | Optimistic locking via git blob hashes — stale proposals are surfaced, not silently applied |
| ADR-010 | llm-model-and-context | Claude Sonnet, bounded context budgets, full ecosystem version manifest, structured retrieval |
| ADR-011 | project-manifest | **Deferred** — write when `Foundry.Manifest` Ash resource is defined; pre-ADR schema in `docs/manifest-schema-draft.md` |
| ADR-012 | studio-ux-specification | Command palette (Cmd+K), review panel, panel interactions, approval tracking UI, performance budgets, data retention |
| ADR-013 | copilot-agent-behavior | Epistemic contract, confidence states, clarifying question UX, error recovery, phase-gated behaviour |
| ADR-014 | proposal-lifecycle | Proposal state machine, dual approval mechanics, ADR linking for :compliance, apply step, compilation failure path |
| ADR-015 | storage-model | Git-backed files + ETS only — no Postgres dependency for Foundry itself |
| ADR-016 | visualization-paradigm-v2 | Four C4 levels, 11 node types, 8 edge types, authorization matrix view, agent node type (⊕) |
| ADR-017 | agent-injection-governance | AshAI integration model, 10 agent types, human-in-the-loop gate spec, change classification for agent constructs |

---

## How the Scaffold Mechanism Works

The copilot does not call an HTTP server. It calls `Foundry.Operations.run/2` directly
(local mode) or sends a WebSocket message to the Foundry backend (cloud mode), which runs it.
No intermediate HTTP service.

```
Copilot intent → Foundry.Copilot.Engine
  → classify intent
  → fetch context via Mix tasks (subprocess, always current)
  → select Operation module
  → Foundry.Operations.run(op, params, dry_run: true)
      → Igniter pipeline executes (structured or raw, never string interpolation)
      → diff captured
      → lint runs against diff
      → semantic validation runs
  → diff + lint result + impact analysis streamed to UI review panel
  → user approves
  → Foundry.Operations.run(op, params, dry_run: false)
  → change applied, git commit created, CI triggered
```

The Mix tasks (`mix foundry.context`, `mix foundry.diagram.generate`, etc.) are the
**data interface** — read-only, always current, callable from the UI backend, CI, and CLI.
They are not a server. They are idempotent commands.

---

## What the Context Mix Task Returns

`mix foundry.context <Module>` returns:

```json
{
  "module": "MyApp.Finance.WithdrawalTransfer",
  "type": "transfer",
  "domain": "Finance",
  "description": "...",
  "steps": [...],
  "rules": ["SufficientBalance", "SameSource", "WithdrawalLimit"],
  "compliance": ["RG-UK-014", "RG-MGA-007"],
  "runbook": "docs/runbooks/withdrawal_transfer.md",
  "invariants": [...],
  "related_resources": ["Wallet", "LedgerEntry", "WithdrawalRequest"],
  "adrs": ["ADR-002"],
  "last_modified": "2026-03-01",
  "sensitive": true,
  "test_coverage": {
    "property_tests": true,
    "scenario_tests": true,
    "e2e_tests": false
  },
  "data_layer": "ash_postgres",
  "pending_migrations": false,
  "paper_trail": true,
  "archival": true,
  "state_machine": {
    "present": false,
    "states": [],
    "transitions": [],
    "state_attribute": null
  },
  "api_routes": [],
  "telemetry_prefix": ["my_app", "finance", "withdrawal_transfer"],
  "money_attributes": [
    { "name": "amount", "type": "Ash.Type.Money", "cldr_backend": "MyApp.Cldr" }
  ],
  "authentication_subject": false,
  "oban_queues": [],
  "rate_limited": false,
  "feature_flags": [],
  "agent_steps": [
    {
      "step_id": "risk_score",
      "agent_type": "scorer",
      "model": "claude-sonnet",
      "input_schema": "RiskInput",
      "output_schema": "RiskScore",
      "tools": ["read_player_history", "check_velocity"],
      "confidence_threshold": 0.7,
      "on_low_confidence": "escalate_human",
      "human_gate": {
        "queue": "compliance_review",
        "sla_hours": 4,
        "escalation_path": "compliance_officer"
      },
      "telemetry_prefix": ["my_app", "risk", "withdrawal", "risk_score"]
    }
  ]
}
```

Use this schema exactly. Do not invent fields. The full schema is defined in ADR-003.

`agent_steps` is an empty list `[]` when the module has no AshAI agent step declarations.
A non-empty list requires AshAI v2 or later (see ADR-017). The `mix foundry.context` task
will warn (not fail) if AshAI is present but the version cannot be determined — this
follows the same pattern as the v1 ignore-and-warn stance in ADR-001, which is superseded
by ADR-017 for projects that opt in to agent support.

---

## Foundry vs Target Platforms

Foundry is used to BUILD target platforms (iGaming, fintech, healthcare, etc.).

When working on **Foundry's own codebase**: the context above applies.
When helping a user **build a target platform with Foundry**: load that project's AGENTS.md,
use that project's compliance requirements, apply that project's ADRs.
Never mix the two codebases' invariants.

**Dogfooding — Foundry building Foundry:** Foundry's own codebase is a valid target for the
Foundry copilot. When the copilot is used to modify Foundry itself, the change approval
model still applies — Foundry's own `manifest.exs` declares its sensitive resources and
approvers. This is not a special case. The context-switching rule is the same: load
*this* AGENTS.md, apply *these* ADRs. The copilot does not need a special mode for
this — it simply operates on Foundry as it would on any other project.

**The bootstrap case:** A new target project has no spec-kit yet. Foundry runs in bootstrap
mode: it uses the stack template's default AGENTS.md and tells the user:
"No spec-kit found. Using template defaults. Run `mix foundry.spec_kit.init` to generate
a starter spec-kit from your current codebase."

Frequent clarifying questions during bootstrap are expected and normal — the spec-kit is
being written. Once it exists, clarifying questions should become rare. Their frequency
is a live signal of spec-kit completeness.

---

## Spec-Kit File Index

```
AGENTS.md                                    ← this file (project root)
docs/
  BUILD_SEQUENCE.md                          ← implementation phases and acceptance criteria
  REVIEW_AND_PLAN.md                         ← gap tracking and what belongs in code
  manifest-schema-draft.md                   ← pre-ADR-011 manifest field schema (consolidated)
  adrs/
    ADR-001-stack-selection.md
    ADR-002-code-generation.md
    ADR-003-agent-context-strategy.md
    ADR-004-dependency-governance.md
    ADR-005-change-approval-model.md
    ADR-006-infrastructure-governance.md
    ADR-007-test-generation-strategy.md
    ADR-008-visualization-paradigm.md
    ADR-009-concurrent-proposals.md
    ADR-010-llm-model-and-context.md
    ADR-012-studio-ux-specification.md
    ADR-013-copilot-agent-behavior.md
    ADR-014-proposal-lifecycle.md
    ADR-015-storage-model.md
    ADR-016-visualization-paradigm-v2.md
    ADR-017-agent-injection-governance.md
  regulations/
    platform_invariants.md
  runbooks/
    studio_copilot_failure.md
    igniter_operation_failure.md
    project_reader_unavailable.md
    compliance_test_failure.md
    approval_queue_blocked.md
    studio_ux_degradation.md
```

The Ash resources and Reactor code are the specification for everything else.
This spec-kit captures decisions and constraints not expressible in code.
Do not duplicate what the code says.