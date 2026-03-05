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

## The Three Layers (do not conflate them)

```
Layer 1: Project Visualization (read-only)
  System map, compliance matrix, operations board, test coverage map.
  No changes happen here. This is for understanding and navigation.

Layer 2: Copilot (propose only, never auto-apply for behavioral/sensitive/compliance changes)
  Conversation panel. Proposes diffs. Shows lint + impact. Waits for approval.
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

**INV-006: Stack versions always in every LLM prompt**
Every LLM call includes the current `mix.exs` dependency versions as the first item.
This prevents Ash 2.x vs 3.x confusion — the most common and most damaging hallucination class.
When in doubt about a DSL option, retrieve the ExDoc JSON for that specific element.
Never generate code from training memory alone when the current API surface is retrievable.

**INV-007: Approved dependency policy governs additions**
Category-based. See ADR-004-dependency-governance.md.

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

---

## ADR Index

| ID | Slug | Decision summary |
|---|---|---|
| ADR-001 | stack-selection | Elixir/Ash 3.x/Phoenix/Spark — not negotiable |
| ADR-002 | code-generation | Igniter operations (structured or raw) — no string interpolation |
| ADR-003 | agent-context-strategy | Structured retrieval over live DSL introspection, not RAG over code |
| ADR-004 | dependency-governance | Category-based approval, forbidden list, ADR for sensitive categories |
| ADR-005 | change-approval-model | Four-class classification, dual approval for :sensitive, audit log always |
| ADR-006 | infrastructure-governance | Proposal-only from agents, human apply, base CI pipeline owned by platform |
| ADR-007 | test-generation-strategy | DSL declarations drive skeleton generation, compliance reqs drive E2E |
| ADR-008 | visualization-paradigm | Read-only system map, copilot is the only change interface |
| ADR-009 | concurrent-proposals | Optimistic locking via git blob hashes — stale proposals are surfaced, not silently applied |
| ADR-010 | llm-model-and-context | Claude Sonnet, bounded context budgets, structured retrieval never raw file dumps |

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
  }
}
```

Use this schema exactly. Do not invent fields.

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
  regulations/
    platform_invariants.md                   ← INV-001 through INV-010
  runbooks/
    studio_copilot_failure.md
    igniter_operation_failure.md
    project_reader_unavailable.md
    compliance_test_failure.md
    approval_queue_blocked.md
```

The Ash resources and Reactor code are the specification for everything else.
This spec-kit captures decisions and constraints not expressible in code.
Do not duplicate what the code says.