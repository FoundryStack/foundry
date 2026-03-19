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
| `Foundry.Copilot.Tools` | Declares the bash tool with shell constraint enforcement
  (permitted/blocked command list per ADR-010 §Shell Constraints). No other tool
  schemas — the agent uses Mix tasks directly via bash for all retrieval. Internal
  module, not a Hex package. | `Foundry.Copilot.Engine` dispatches all tool calls
  through this module |

**What is NOT a separate package and why:**
- `Foundry.Diff` — ADR-005 change classifier using `Sourceror`. Logic is tightly coupled to the
  manifest sensitive-resources list and Foundry's classification ruleset. Too specific to extract.
- `Foundry.SpecKit` — spec-kit document parser using `MDEx` + `NimbleOptions`. "Spec-kit" is
  Foundry vocabulary; no external audience for the format yet.
- `Foundry.Operations` — the two thin named wrappers (`Op.AddComplianceLink`,
  `Op.AddAgentStep`). All other generation uses raw Igniter directly. Extract only if a
  second tool needs the same wrapper protocol.
- `Foundry.Proposals` — proposal state machine (ADR-014). Coupled to git-backed storage
  (ADR-015) and git-branch stale detection (ADR-009). Extract when a second use case appears.
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

> **Numbering note:** These INV-001..017 govern agent behaviour and Foundry's build rules.
> `docs/regulations/platform_invariants.md` uses an overlapping but **distinct** INV
> numbering for target-platform domain requirements (its INV-004 = idempotency, INV-005 =
> runbook links, INV-006 = description coverage — different from below). Do not conflate
> the two sets. When an ADR cites "INV-NNN", check which document it is referencing.

| INV | Statement | Detail |
|---|---|---|
| INV-001 | No autonomous changes to `:sensitive` resources — dual approval required | ADR-005 |
| INV-002 | No direct filesystem writes — all writes via `Foundry.Operations.run/2` / Igniter | ADR-002 |
| INV-003 | All Elixir generation via raw Igniter API; string interpolation to source forbidden | ADR-002 |
| INV-004 | Infrastructure changes are proposal-only; no `Op.ApplyInfrastructure` exists | ADR-006 |
| INV-005 | One clarifying question maximum per turn; UX: binary-choice buttons (ADR-013) | ADR-013 §Clarifying Question UX |
| INV-006 | Stack versions always in Tier 1 system prompt — structurally enforced by `ContextBuilder` | ADR-010 §Tier 1 |
| INV-007 | Dependency additions governed by ADR-004 category policy | ADR-004 |
| INV-008 | Committed diagram must always match live code; CI enforces via diff-check | ADR-010 §Spec-Kit Index |
| INV-009 | Only ADRs, runbooks, regulations, and AGENTS.md require manual authorship | ADR-003 |
| INV-010 | Manifest must declare notification channels for `runbook_stale`, `adapter_verify_failed`, `compliance_test_failed` | ADR-001 §Notifications |
| INV-011 | All `:sensitive` resources must use `AshPaperTrail` — lint error if absent | ADR-001 §Ash Ecosystem |
| INV-012 | All `:sensitive` resources must use `AshArchival` — hard deletion prohibited | ADR-001 §Ash Ecosystem |
| INV-013 | `fun_with_flags` flags gating compliance controls must declare an ADR link | ADR-001 §Feature Flags |
| INV-014 | `decision` and `scorer` agent steps must declare `confidence_threshold` and `on_low_confidence` | ADR-017 |
| INV-015 | `decision` agent steps on compliance-gated flows must declare `human_gate` | ADR-017 |
| INV-016 | Agent steps must declare complete `tools` list; undeclared tool usage is a lint error | ADR-017 |
| INV-017 | All agent steps must emit telemetry spans with `agent_type`, `model`, `confidence`, `latency_ms` | ADR-017 |

**INV-006 lookup guidance** (not in platform_invariants.md — agent operational behaviour):
When in doubt about a DSL option: `bash("mix foundry.exdoc <Module> --function <fn>")`.
When in doubt about a pattern: `bash("mix foundry.pattern.find <type>")`.
When in doubt about an operation: `bash("cat .foundry/usage_rules/foundry_operations.md")`.
Never generate code from training memory alone when the current API surface is retrievable.

---

## Change Classification

Full classification rules, trigger patterns, and migration classification: ADR-005.

**When in doubt, classify upward.** `:behavioral` misclassified as `:structural` and
auto-applied is a governance failure. The reverse is merely inconvenient.
`:sensitive` is configured per project via `manifest.sensitive_resources` — not hardcoded.

---

## Spec-Kit Tasks

`copilot.max_tool_calls` in the manifest controls the circuit breaker (default 20).

The pre-generation checklist below governs how the agent interacts with the spec-kit
before writing any code. It is not a separate mode — it is the agent's default
reasoning obligation. The agent runs it internally before constructing the session plan.

### Pre-generation checklist

```
□ ADR covers this design decision, or it is a :structural change
□ All touched Reactors with >3 steps have @runbook declarations
□ All new compliance links reference existing regulation entries
□ New sensitive resources will have paper_trail + archival
□ New Reactors with external side effects declare idempotency keys
□ @description drafted for all new attributes
□ @moduledoc drafted for the new module
□ @description fields on touched attributes are consistent with proposed change
```

The final item is critical: the agent treats existing `@description` fields as
invariant declarations. A proposed change that contradicts a description is
surfaced in the contradiction check, the same as an ADR conflict.

**ADR required when:** a design decision is being made that the code does not explain
(why this approach vs alternatives); a new compliance requirement is introduced; a
dependency is added (ADR-004); an existing ADR is being contradicted or extended;
any `:compliance` class change (ADR link is required before approval).

**ADR not required when:** adding an attribute with a clear `description:` (Ash is
the spec for structural facts); bug fixes to existing behaviour; test additions;
`:structural` description improvements.

**Runbook required when:** any Reactor with more than 3 steps (INV-005, lint-enforced);
a new external integration is introduced; a background job is added.

**Regulation file required when:** a regulatory requirement is tracked for the first time
or an existing requirement is superseded.

When the spec-kit is silent on a case, the agent names the specific gap before
consuming the one permitted clarifying question (INV-005):

> "I'm about to [describe action]. I couldn't find an ADR covering [specific decision].
> My interpretation is [X] because [reasoning from nearest ADR]. Before I proceed:
> is this interpretation correct, or should I draft an ADR for this case first?"

---

### Agent reasoning sequence for `change` intents

The complete sequence the agent follows before emitting any proposal:

```
1.  Read spec-kit index (Tier 1) — identify relevant ADRs/INVs/regulations by tag
2.  Read those documents via bash — follow cross-references
3.  Run pre-generation checklist — identify missing spec-kit items
4.  Read module context: mix foundry.context <Module> --json
5.  Fetch closest pattern example: mix foundry.pattern.find <type> --domain <D>
6.  Check @description fields on all touched attributes against proposed change
7.  Run contradiction check — BLOCKED if violated, else proceed
8.  Classify whether spec-kit drafting is required:
      :behavioral or :compliance → ADR draft required, included as first file
                                    in the proposal branch
      :structural with new concept → ADR draft offered, not required
      :structural modification → no spec-kit step
9.  Construct ordered session plan:
      [spec]  ADR / runbook stub (if required by step 8)
      [tests] Test skeletons from DSL declarations + ADR boundary conditions
      [code]  Implementation constrained by test structure
      [migration] mix ash.codegen if schema changes
10. Present plan for human confirmation
      Human refines via conversation until satisfied — plan only, not code
11. On confirmation: single generation pass on foundry/prop_<id> branch
      → Write spec-kit files first (Markdown, direct branch write)
      → Generate test skeletons
      → Generate implementation
      → Run mix ash.codegen (if migration needed)
      → Run mix compile (must pass)
      → Run mix test <new-test-file> — pre-surface quality gate;
        max 3 self-corrections at compile level; never iterates on assertion values
      → Compute graph_delta from operation parameters
12. Surface diff to review panel — human reviews, approves, or requests changes
```

This sequence applies to all `change` intents. When `change_generation_enabled: false`
(Phase 3), step 11 is replaced by a plain prose description of what would be generated.

---

## Where to Find Authoritative Information

| Question | Where to look |
|---|---|
| What does resource X do? | `mix foundry.context MyApp.Domain.Resource` |
| What compliance requirements affect feature Y? | `mix foundry.compliance.check --filter=Y` |
| What changed in the system recently? | `git log` + `mix foundry.diagram.diff` |
| Which spec-kit document covers a concept? | Spec-kit index in Tier 1 context — agent reads summaries and tags, then `bash("cat <path>")` |
| Correct DSL syntax for X? | `bash("mix foundry.exdoc <Module>")` or `bash("cat .foundry/usage_rules/<lib>.md")` |
| Pattern for a new construct type? | `bash("mix foundry.pattern.find <type> --domain <D>")` |
| Operation parameter schema? | `bash("cat .foundry/usage_rules/foundry_operations.md")` or `bash("mix foundry.operation.schema <Op>")` |
| Spec-kit task postures? | §Spec-Kit Tasks above |

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

Full engine flow, git branch lifecycle, and apply mechanics: ADR-010 §How the Scaffold
Mechanism Works and ADR-014 §The Apply Step. Mix tasks are the data interface — read-only,
idempotent, callable from UI backend, CI, and CLI.

---

## What the Context Mix Task Returns

Schema: ADR-003 §`mix foundry.context` Schema. Do not invent fields.
`agent_steps` is `[]` when no AshAI declarations are present; requires AshAI v2+ (ADR-017).
The task warns (never fails) if AshAI is present but version is undetermined.

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
  spec_kit_index_schema.md                   ← index format contract
  mix_task_summary_schemas.md                ← project snapshot schema
  phase3-acceptance-questions.md             ← Gap #70 (to be written)
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
    compliance_test_failure.md
    approval_queue_blocked.md
    studio_ux_degradation.md
.foundry/
  spec_kit_index.json                        ← generated by mix foundry.spec_kit.index
  usage_rules/                               ← generated by mix foundry.usage_rules.fetch
    ash.md
    reactor.md
    phoenix_live_view.md
    foundry_operations.md                    ← all 20 operations with parameter schemas
    (one file per dependency with usage guidance)
  logs/
    copilot_trace.jsonl                      ← gitignored, dev-mode only
```

The Ash resources and Reactor code are the specification for everything else.
This spec-kit captures decisions and constraints not expressible in code.
Do not duplicate what the code says.