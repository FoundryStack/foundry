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

**INV-003: All writes go through Igniter. The agent generates Elixir source for everything.**
There is no catalogue of pre-built operation modules. The agent uses raw Igniter API
(`Igniter.create_new_file/3`, `Igniter.Project.Module.create_module/3`,
`Igniter.Project.Module.find_and_update_module/3`) guided by:
- The closest existing project example (`mix foundry.pattern.find <type>`)
- Foundry conventions (`cat .foundry/usage_rules/foundry_conventions.md`)
- Exact DSL API (`mix foundry.exdoc <Module>`)

Two thin named wrappers exist where the logic is Foundry-specific metadata, not just
Igniter calls: `Op.AddComplianceLink` (pure compliance registry update, no Igniter
equivalent) and `Op.AddAgentStep` (Phase 8 governance scaffold with dual-proposal
cascade). All other generation uses raw Igniter directly.

**The prohibition is on the mechanism, not the capability:**
- Never: `File.write!/2`, `File.stream!/2`, or any direct IO on source files
- Never: string interpolation assembled into source and written to disk directly
- Always: content → Igniter pipeline → formatted, AST-valid output → git branch → diff → review

All generation writes to a `foundry/prop_<id>` git branch, not the working tree.
The branch is merged on approval and discarded on rejection or failure.

Igniter ensures formatting and AST correctness. The compiler and linter are the
verification layer — not any catalogue boundary.

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

**INV-006: Stack versions always in system prompt**
Every agent session includes the current `mix.exs` dependency versions in the Tier 1
system prompt — injected by `Foundry.Copilot.ContextBuilder` before the agent loop
starts. Structurally impossible to start the agent loop without them. This prevents
Ash 2.x vs 3.x confusion — the most common and most damaging hallucination class.
When in doubt about a DSL option: `bash("mix foundry.exdoc <Module> --function <fn>")`.
When in doubt about a pattern: `bash("mix foundry.pattern.find <type>")`.
When in doubt about an operation: `bash("cat .foundry/usage_rules/foundry_operations.md")`.
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

## Spec-Kit Tasks

All spec-kit tasks are enabled by default. No manifest configuration required.
`copilot.max_tool_calls` in the manifest controls the circuit breaker (default 8).

The five postures below govern how the agent interacts with the spec-kit. They are
not separate modes — they are the agent's default reasoning obligations before writing
any code. The agent runs them internally and surfaces results in the reasoning trace
and the session plan.

---

### `speckit.analyze` — Default pre-generation posture

Before generating any proposal, the agent identifies which spec-kit documents cover
the requested change and whether any are missing. This analysis is emitted in every
reasoning trace under `speckit_analysis`:

```json
"speckit_analysis": {
  "covering_adrs": ["ADR-005", "ADR-002"],
  "covering_invs": ["INV-001", "INV-011"],
  "covering_regulations": ["RG-UK-014"],
  "missing_adr": false,
  "missing_runbook": false,
  "missing_regulation": false,
  "gaps": []
}
```

If `missing_adr: true` or `gaps` is non-empty, the agent includes spec-kit drafts
as the first step(s) of the session plan — before any code proposals.

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

---

### `speckit.plan` — Ordered plan for multi-step changes

For any change involving more than one file or more than one concern, the agent
produces an explicit ordered plan before generating anything:

```
Plan for: Add withdrawal limit rule with compliance link

Step 1 [spec-kit]  Draft ADR-020: WithdrawalLimitRule design
  → Why: new jurisdiction clause pattern not covered by existing ADRs
  → Proposal type: plain text, human commits
  → Change class: :structural (spec-kit doc update)

Step 2 [code]      Add IgamingRef.Finance.Rules.WithdrawalLimitRule
  → Igniter: new rule module + test stub on git branch
  → Change class: :behavioral — domain lead approval

Step 3 [code]      Wire rule into WithdrawalTransfer
  → Change class: :behavioral — batch with Step 2

Step 4 [tests]     Property test: amounts above limit always block
  → Change class: :structural — instant

Step 5 [compliance] Add compliance link RG-UK-014
  → Change class: :compliance — compliance officer + ADR-020 link
```

Human confirms the plan before execution. The agent does not proceed to Step 2
until Step 1's ADR draft has been reviewed in the Activity Feed.

---

### `speckit.clarify` — Naming the gap before asking

When the spec-kit is silent on a case, the agent names the specific gap before
consuming the one permitted clarifying question (INV-005):

> "I'm about to [describe action]. I couldn't find an ADR covering [specific decision].
> My interpretation is [X] because [reasoning from nearest ADR]. Before I proceed:
> is this interpretation correct, or should I draft an ADR for this case first?"

This is grounded in a specific spec-kit gap — not a general disambiguation question.

---

### `speckit.checklist` — Pre-generation invariant check

Internal checklist run before emitting any code proposal. A failed item becomes
a plan step that precedes the code step:

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

---

### `speckit.constitution` — Bootstrap posture for uncovered territory

When a feature has no spec-kit coverage and is not a simple structural change:

> "This is new territory for this project's spec-kit. I'll include spec-kit
> initialization in the plan:
> - ADR stub (context + decision + rationale skeleton — you complete the rationale)
> - Regulation stub if this touches a compliance area
> - Runbook stub if this introduces a Reactor with external effects
>
> These are plain text files proposed first. You review them, then I generate code
> that references them. The code is never written without its spec-kit anchor."

---

### Agent reasoning sequence for `change` intents

The complete sequence the agent follows before emitting any code proposal:

```
1. Read spec-kit index (Tier 1) — identify relevant ADRs/INVs/regulations by tag
2. Read those documents via bash — follow cross-references
3. Run speckit.checklist — identify any missing spec-kit items
4. If gaps: include spec-kit steps first in the session plan
5. Read module context: mix foundry.context <Module> --json
6. Fetch closest pattern example: mix foundry.pattern.find <type> --domain <D>
7. Check @description fields on all touched attributes against proposed change
8. Run contradiction check — BLOCKED if violated, else proceed
9. Construct ordered session plan (spec-kit first, code second, tests third)
10. Present plan for human confirmation
11. On confirmation: execute in order, writing to git branch foundry/prop_<id>
```

This sequence applies to all `change` intents. Steps 3–5 distinguish it from the
Phase 3 CHANGE_PREVIEW path, where generation is disabled and the plan describes
without producing a diff.

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

The copilot does not call an HTTP server. It calls `Foundry.Operations.run/2` directly
(local mode) or sends a WebSocket message to the Foundry backend (cloud mode), which runs it.
No intermediate HTTP service.

```
Copilot intent → Foundry.Copilot.Engine
  → assemble Tier 1 + Tier 2 context (ContextBuilder)
  → agent loop begins (first step classifies intent inline):
      → classify intent: question | change | speckit | ambiguous
      → if question: answer with source citations, done
      → if speckit: produce plain-text spec-kit draft proposal, done
      → if ambiguous: clarifying question (INV-005), done
      → if change:
          → run speckit.checklist (§Spec-Kit Tasks)
          → bash tool calls: read ADRs, read module context, fetch pattern example
          → check @description fields on touched attributes
          → contradiction check via reasoning
          → if BLOCKED: cite ADR/INV, done
          → construct ordered session plan
          → present plan for human confirmation
  → on plan confirmation:
      → git checkout -b foundry/prop_<id>          [isolate writes]
      → Igniter apply to branch                    [raw Igniter + pattern example]
      → mix ash.codegen on branch                  [migration, if needed]
      → mix compile on branch
          → fail: git branch -D foundry/prop_<id>  [clean discard]
                  → APPLY_FAILED state, agent retry (max 3)
          → pass: capture diff with git diff main..foundry/prop_<id>
      → git checkout main                          [working tree untouched]
      → diff + lint result + session plan streamed to review panel
      → system map enters preview mode
  → user approves
      → git merge --ff-only foundry/prop_<id>
      → git branch -D foundry/prop_<id>
      → git commit created, CI triggered
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
    igniter_operation_failure.md
    project_reader_unavailable.md
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