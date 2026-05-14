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

## Copilot Sub-Agent Architecture

The copilot orchestrator delegates bounded tasks to typed sub-agents. The orchestrator
owns intent classification, contradiction check, change classification, and plan
presentation. Sub-agents own scoped, tool-constrained retrieval and generation tasks.

### SpecKitNavigator

**Purpose:** Deep-read the constraint graph rooted at the affected NodeEntry and produce
a compact constraint summary.
**Spawned:** Always for `change` intent. For `question` when ADR citation is needed.
**Inputs:** NodeEntry (from CodeContextGatherer) + Tier 1 spec-kit index tag match.
**Tools:** `bash` (cat, grep) — read-only.
**Execution:**
1. Read each ADR identified by Tier 1 tag match + NodeEntry `adrs` field
2. Follow `Extends:` headers — read those ADRs too
3. Read regulation files from NodeEntry `compliance` field; follow requirement → ADR links
4. Read runbook from NodeEntry `runbook` field if a Reactor is in scope
5. Check all INV-001..INV-018 against the proposed change
**Returns:** Applicable constraints, contradiction result (`blocked: bool, rule: string`),
spec-kit gap list.

---

### CodeContextGatherer

**Purpose:** Gather live code-level facts about affected modules.
**Spawned:** In parallel with SpecKitNavigator for all `change` intents.
**Inputs:** Target module names (inferred from message), inferred construct type.
**Tools:** `bash` (mix foundry.project.context, mix foundry.pattern.find, mix foundry.exdoc).
**Execution:**
1. `mix foundry.project.context <Module>` — live NodeEntry (source of truth)
2. `mix foundry.pattern.find <type> --domain <D>` — closest existing example
3. `mix foundry.exdoc <Module> --function <fn>` — only when a specific DSL option
   is unresolved after reading the pattern
**Returns:** NodeEntry struct, pattern example source, current `@description` field values,
`pending_migrations` status.

---

### PlanArchitect

**Purpose:** Construct the ordered session plan given gathered context.
**Spawned:** After SpecKitNavigator and CodeContextGatherer both complete, contradiction
check passes.
**Inputs:** Change class, constraint summary, code context, spec-kit gap list.
**Tools:** None — pure reasoning from inputs.
**Returns:** Ordered plan (spec → tests → code → migration) with per-step rationale.

---

### SpecKitDrafter

**Purpose:** Draft ADR / runbook / regulation stubs as the first committed files in the
proposal branch.
**Spawned:** During generation, before CodeGenerator, when change class requires it.
**Inputs:** Change class, plan, related existing docs for format reference.
**Tools:** `bash` (cat existing spec-kit docs), branch write.
**Returns:** Markdown stubs committed on `foundry/prop_<id>` — before any code file.

---

### CodeGenerator

**Purpose:** Execute Igniter operations and run the verification sequence on the proposal
branch.
**Spawned:** After SpecKitDrafter completes (or immediately if no spec-kit required).
**Inputs:** Confirmed plan, prop_id, pattern example from CodeContextGatherer.
**Tools:** `bash` (Igniter raw API, mix ash.codegen, mix compile, mix test).
**Returns:** Diff, compile result, test result, lint violations.

---

### Parallel Execution Map

```
classify(intent) [orchestrator — inline, from Tier 1]
         │
         ├────────────────────────────────────┐
         ▼                                    ▼
  SpecKitNavigator                  CodeContextGatherer
  reads ADR graph from              reads live NodeEntry
  NodeEntry entry points            finds pattern example
  checks INV-001..018               collects @description fields
         │                                    │
         └────────────────────────────────────┘
                          │
                  orchestrator synthesizes:
                  contradiction check → BLOCKED or proceed
                  change classification
                          │
                          ▼  [sequential from here — each step depends on previous]
                    PlanArchitect
                          │
                          ▼  [human confirmation]
                    SpecKitDrafter → CodeGenerator → mix compile → mix test → diff
```

Parallelism ends at synthesis. Nothing in the generation phase runs concurrently.

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
For `:behavioral` and `:compliance` changes, the agent drafts required spec-kit documents
(ADRs, runbooks, regulation entries) as the first files in the proposal branch, alongside
the code they govern. Spec-kit files and Elixir source files are reviewed and committed
together in one proposal. The human never touches git manually for governed changes.
The one exception is standalone `speckit` intent requests (documenting an already-made
decision with no associated code change) - those produce an Activity Feed card for human
review and manual commit, as no proposal branch is warranted.

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
- Always: content -> Igniter pipeline -> formatted, AST-valid output -> git branch -> diff -> review

All generation writes to a `foundry/prop_<id>` git branch, not the working tree.
The branch is merged on approval and discarded on rejection or failure.

Igniter ensures formatting and AST correctness. The compiler and linter are the
verification layer - not any catalogue boundary.

**INV-004: Infrastructure is proposal-only**
Kubernetes, Postgres config, GitHub Actions base pipelines - agents produce structured
proposals rendered as diffs in the review panel. A human with infrastructure context applies them.
There is no `Op.ApplyInfrastructure` operation and there never will be.

**INV-005: One clarifying question maximum - grounded in spec-kit quality**
Before generating a proposal for ambiguous intent, ask at most one clarifying question.
The rationale is not just UX. If the spec-kit (AGENTS.md, ADRs, DSL declarations) is
complete, the agent should rarely need to ask at all - context should resolve ambiguity.
Frequent clarifying questions are a symptom of an incomplete spec-kit or thin `@description`
coverage, not a normal operating condition. When a clarifying question is necessary, it
exposes a gap that should be closed in the spec-kit or DSL declarations.
If the answer is still ambiguous: state the two interpretations explicitly and ask the user
to choose. Never ask a third question. Never generate on unresolved ambiguity.
The clarifying question UX (binary-choice buttons, not free-text) is specified in ADR-013.

**INV-006: Stack versions always in system prompt**
Every agent session includes the current `mix.exs` dependency versions in the Tier 1
system prompt - injected by `Foundry.Copilot.ContextBuilder` before the agent loop
starts. Structurally impossible to start the agent loop without them. This prevents
Ash 2.x vs 3.x confusion - the most common and most damaging hallucination class.
When in doubt about a DSL option: `bash("mix foundry.exdoc <Module> --function <fn>")`.
When in doubt about a pattern: `bash("mix foundry.pattern.find <type>")`.
When in doubt about an operation: `bash("cat .foundry/usage_rules/foundry_operations.md")`.
Never generate code from training memory alone when the current API surface is retrievable.

**INV-007: Approved dependency policy governs additions**
Category-based. See ADR-004-dependency-governance.md. The `:ecto` forbidden rule targets
direct application-level usage; `ecto_sql` and `postgrex` as transitive dependencies of
`ash_postgres` are permitted.

**INV-008: Project context must not be stale at CI**
`.foundry/context.lock` must match the current source file hash at CI time. CI runs
`mix foundry.project.context --check` - exits 1 if the lock is absent or stale.
Update the lock locally by running `mix foundry.project.context` and committing
`.foundry/context.lock`. `mix foundry.diagram.generate` is a deprecated alias.
See ADR-020 and `docs/regulations/platform_invariants.md`.

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

**INV-018: All file reads from channels go through `Foundry.FileSystem`**
No Phoenix channel or controller may call `File.read!/1`, `File.stream!/2`, or any direct
filesystem IO on project source files. All reads route through `Foundry.FileSystem.read/2`,
which enforces the permitted root boundary for the current project context. The permitted
roots are: `lib/`, `test/`, `config/`, `priv/repo/migrations/`, `docs/adrs/`,
`docs/runbooks/`, `docs/regulations/`, `AGENTS.md`, `mix.exs`, `.foundry/manifest.exs`,
`.foundry/usage_rules/`. In umbrella projects the `lib/` root expands to `apps/*/lib/`.
Paths outside these roots return `{:error, :outside_boundary}` - they are never surfaced
to the client. `project_root` is always resolved server-side from the session context;
the client cannot supply or influence it.

---

## Change Classification

Every proposed change must be classified. The four classes are **domain-agnostic** -
the examples use a fintech/iGaming context but the model applies to any regulated domain.

| Class | Trigger pattern | Approver | Auto-apply | Audit logged |
|---|---|---|---|---|
| `:structural` | New resource, attribute, relationship, description updates, test skeletons | Any developer | Configurable | No |
| `:behavioral` | New Rule, Transfer step, Blueprint, Reactor, Oban job, state machine transition | Domain lead | Never | Yes |
| `:sensitive` | Resources/attributes marked `:sensitive` in the manifest - ledger entries, PII, audit records, access control | Sensitive lead + one other (dual) | Never | Yes, mandatory |
| `:compliance` | Changes to `compliance:` declarations, policy modules, requirement links | Compliance officer | Never | Yes, ADR required |

**The `:sensitive` class is configured per project, not hardcoded.**
A healthcare platform marks `:phi` resources as sensitive. A legal platform marks `:privileged`
documents. The classification engine reads the manifest's `sensitive_resources:` list.
iGaming uses ledger and wallet resources - that is a project-level configuration, not a
Foundry-level assumption.

**When in doubt, classify upward.** A `:behavioral` change misclassified as `:structural`
and auto-applied is a governance failure. The reverse is merely inconvenient.

---

## Spec-Kit Tasks

`copilot.max_tool_calls` in the manifest controls the circuit breaker (default 20).

The pre-generation checklist below governs how the agent interacts with the spec-kit
before writing any code. It is not a separate mode - it is the agent's default
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
□ Policy compatibility verified for all generated UI actions via Ash.Resource.Info.policies/1
   (do not generate UI actions the current actor cannot authorize - check before generating)
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
1.  Read spec-kit index (Tier 1) - identify relevant ADRs/INVs/regulations by tag
2.  Read those documents via bash - follow cross-references
3.  Run pre-generation checklist - identify missing spec-kit items
4.  Read module context: mix foundry.context <Module> --json
5.  Fetch closest pattern example: mix foundry.pattern.find <type> --domain <D>
6.  Check @description fields on all touched attributes against proposed change
7.  Run contradiction check - BLOCKED if violated, else proceed
8.  Classify whether spec-kit drafting is required:
      :behavioral or :compliance -> ADR draft required, included as first file
                                    in the proposal branch
      :structural with new concept -> ADR draft offered, not required
      :structural modification -> no spec-kit step
9.  Construct ordered session plan:
      [spec]  ADR / runbook stub (if required by step 8) - always first
      [tests] Test skeletons from DSL declarations + ADR boundary conditions
      [code]  Implementation constrained by test structure
      [migration] mix ash.codegen if schema changes

    Ordering rationale - why spec before tests before code:

    Spec first: A reviewer reading code cannot govern what they do not understand.
    The ADR records why this approach was chosen over alternatives. Without it,
    approval is a rubber stamp on implementation, not a governance decision.
    The runbook records what happens when this Reactor fails. Without it, the
    reviewer cannot assess operational risk. Spec-kit files and code are reviewed
    together in one diff - the spec makes the code legible to a non-author.
    This is an epistemology requirement, not a workflow preference.

    Tests before code: Test skeletons are derived from DSL declarations and ADR
    boundary conditions - they define what "correct" means before any implementation
    exists. Code written before the tests know what to assert may satisfy its author
    but cannot satisfy the spec. The tests constrain the implementation, not the
    reverse.

    Migration last: Schema changes require a compiled Ash resource to generate
    correct migration SQL. `mix ash.codegen` must run after all code is written
    and compiles. It is always the final generation step.
10. Present plan for human confirmation
      Human refines via conversation until satisfied - plan only, not code
11. On confirmation: single generation pass on foundry/prop_<id> branch
      -> Write spec-kit files first (Markdown, direct branch write)
      -> Generate test skeletons
      -> Generate implementation
      -> Run mix ash.codegen (if migration needed)
      -> Run mix compile (must pass)
      -> Run mix test <new-test-file> - pre-surface quality gate;
        max 3 self-corrections at compile level; never iterates on assertion values
      -> Compute graph_delta from operation parameters
12. Surface diff to review panel - human reviews, approves, or requests changes
```

This sequence applies to all `change` intents. When `change_generation_enabled: false`
(Phase 3), step 11 is replaced by a plain prose description of what would be generated.

---

## Spec-Kit Skill Orchestration

The copilot internally orchestrates a set of spec-kit skills. These are transparent to
the user - they interact only with the copilot conversation and the review panel.
The copilot decides which skills to invoke, in what order, synthesizes results, and
surfaces only the finished output: a confirmed plan, a review diff, or a BLOCKED message.

### Skill invocation map

| Skill | When copilot invokes | What it produces | Feeds into |
|---|---|---|---|
| `speckit.specify` | `change` intent describes a feature without an existing spec | Feature spec from natural language | `speckit.plan` |
| `speckit.clarify` | Intent confidence below threshold - before the one permitted question | Up to 5 targeted gaps identified | Copilot distills to the single most critical (INV-005) |
| `speckit.plan` | After spec exists; before session plan is presented to human | Design artifacts: approach, alternatives, trade-offs | PlanArchitect sub-agent |
| `speckit.tasks` | After plan is confirmed by human | Dependency-ordered task list | CodeGenerator execution queue |
| `speckit.analyze` | After task list is generated; before plan is shown to human | Cross-artifact consistency report (spec ↔ plan ↔ tasks) | Copilot resolves conflicts before surfacing plan |
| `speckit.implement` | On human confirmation (Phase 4+) | Executes tasks in dependency order | Igniter + branch operations |
| `speckit.constitution` | When AGENTS.md or a project constitution would change | Keeps all dependent templates in sync | SpecKitDrafter (constitution update is first file on branch) |
| `speckit.taskstoissues` | When user requests GitHub issue creation from a confirmed proposal | Dependency-ordered GitHub issues from tasks.md | External (GitHub) |

### Invocation rules

**`speckit.specify` is a prerequisite for `speckit.plan`.** A plan without a spec is a
solution without a problem statement. The copilot runs `speckit.specify` whenever the
intent describes what to build but no written spec exists. Plan generation is blocked
until the spec is produced.

**`speckit.clarify` feeds the single permitted question.** The skill may identify up to
5 underspecified areas. The copilot distills this to the one most critical ambiguity and
presents it per INV-005 UX (binary buttons, not free text). Remaining gaps are resolved
after clarification or surfaced in `speckit.analyze`.

**`speckit.analyze` always runs before the plan is presented to the human.** The human
never sees a plan with cross-artifact inconsistencies. If `speckit.analyze` finds
conflicts (spec says X, tasks say Y), the copilot resolves them silently and runs
`speckit.analyze` again. It never surfaces an analysis failure to the user as-is.

**`speckit.constitution` is never user-invoked.** It runs automatically on the proposal
branch when a change would modify AGENTS.md, a project constitution, or a template that
dependent docs reference. The constitution sync is the first file SpecKitDrafter commits
- before any ADR, runbook, or code. This ensures dependent templates are in sync before
the rest of the spec-kit is written against them.

**`speckit.implement` drives CodeGenerator.** It processes `tasks.md` in dependency
order, invoking Igniter for each task. Failures follow the existing max-3-retry
compile-level correction rule. It does not iterate on assertion values.

### What the user never sees

Between a user message and the copilot response, any number of spec-kit skills may
have run: specify, clarify, analyze, plan, tasks. Their intermediate outputs are not
surfaced. The user sees:

- The session plan (built by `speckit.plan` + `speckit.tasks`, confirmed before generation)
- The review diff (code + spec-kit files together in the review panel)
- Source citations in question answers ("Source: ADR-013 §Confidence")
- The BLOCKED message if a contradiction was found

The Activity Feed shows the proposal card and approval status. Not skill traces.

---

### Tier 1 vs Bash - The Decision Rule

**Tier 1 answers "which?" - bash answers "what?"**

| Answer comes from Tier 1 (already in system prompt) | Answer requires bash |
|---|---|
| Which ADRs are relevant to this topic? | What does ADR-013 §Confidence actually say? |
| Which modules exist in the Finance domain? | What attributes does Wallet currently have? |
| Which INV rules apply to `:sensitive` resources? | Full text of a specific regulation requirement |
| Does a pattern exist for `transfer` type? | The actual pattern source code |
| Which spec-kit files exist? | Contents of a specific spec-kit file |

Never run bash to answer a question Tier 1 already resolves. Never trust a Tier 1
summary as the full constraint text for a contradiction check - always fetch the full
document. Fetching a document the Tier 1 index says doesn't exist is always wrong.


---

# AGENTS.md - iGaming Reference Project

This file is the primary project-specific entry point for agents working inside
`reference_projects/igaming`. It is loaded together with Foundry's core copilot
prompt: Foundry supplies the universal governance model, while this file supplies
the target platform context.

Keep this document compact. Durable domain knowledge belongs in the spec-kit:
ADRs for decisions, regulations for compliance requirements, and runbooks for
operational procedures. Live code facts belong in `mix foundry.project.context`
and `mix foundry.project.status`, not in prose.

---

## What This Project Is

`IgamingRef` is a regulated iGaming reference platform used to exercise Foundry's
governed project-context, compliance, proposal, and Studio workflows.

The platform models:

- Player identity, KYC, account lifecycle, and self-exclusion
- Wallets, ledger entries, withdrawals, and financial transfers
- Bonus campaigns, bonus event evaluation, and bonus grants
- Gaming provider configuration, game catalog sync, and RTP certification
- PII vaulting, audit evidence, and operator/compliance policy checks

This is a reference target platform, not the Foundry meta-platform. Work from this
project root.

---

## Context Loading Model

Foundry and project context are both required:

- Foundry core context defines the universal agent rules, proposal lifecycle,
  change classes, and invariants.
- This `AGENTS.md` defines the igaming project orientation and retrieval posture.
- The spec-kit index points to ADRs, regulations, and runbooks that must be read
  before answering or changing governed areas.
- `mix foundry.project.status` gives current health, stack, lint, compliance, and
  sensitive-resource summary.
- `mix foundry.project.context [Module]` gives live code-derived facts for modules,
  resources, Reactors, Transfers, policies, relationships, and compliance links.

Do not duplicate the full system map here. Use the generated project context for
topology and source-derived details.

---

## Source Of Truth Order

When sources overlap, use this order:

1. Live structured context from compiled code for attributes, actions, policies,
   relationships, state machines, side effects, telemetry, and runbook links.
2. Regulations for compliance requirements and test tags.
3. ADRs for accepted architectural and domain decisions.
4. Runbooks for operational recovery, idempotency, and failure handling.
5. This file for project orientation and where to look next.

If a change needs a decision that is not covered by an ADR or regulation, surface a
spec-kit gap before proposing implementation.

---

## High-Scrutiny Areas

Treat these areas as governed and high-risk:

- Finance: `Wallet`, `LedgerEntry`, `Transfer`, `WithdrawalRequest`, and
  `WithdrawalTransfer`
- Players: `Player`, `SelfExclusionRecord`, KYC resources, and PII-bearing data
- Promotions: `BonusEvent`, bonus evaluation, bonus grants, wagering requirements,
  and wallet-crediting bonus flows
- Gaming: provider adapters, provider configuration, RTP certification, and catalog
  sync
- Ops: PII vault and audit evidence

The manifest declares sensitive resources and approvers. Do not infer sensitivity
from domain names alone; verify it through project status or project context. Use
the full system map's `Spec-Kit` section to choose the exact ADR, runbook, or
regulation to read before planning.

---

## Project-Specific Working Rules

- For questions, answer from the spec-kit and live project context, citing the file,
  requirement, ADR, runbook, module, or field that grounds the answer.
- For changes touching financial movement, player eligibility, KYC, self-exclusion,
  provider certification, bonus awards, PII, or audit evidence, read the relevant
  regulation and runbook before planning.
- For structural code facts, prefer `mix foundry.project.context <Module>` over
  source-file prose.
- For DSL syntax, use current project usage rules, ExDoc, and existing local patterns.
- For external side effects in Reactors or Transfers, verify idempotency and
  compensation expectations before proposing changes.
- For compliance changes, require an ADR link or surface the missing ADR as a blocker.

---

## Known Spec-Kit Gaps

The reference project intentionally keeps the spec-kit small. Current coverage is
enough for Foundry acceptance testing, but not every domain decision has its own ADR.

Likely gaps to surface when relevant:

- Provider certification and adapter versioning decisions are mostly represented by
  regulations and runbooks, not ADRs.
- Bonus engine design is represented by code and runbooks; a dedicated ADR should be
  drafted before changing the campaign evaluation model.
- Player KYC and self-exclusion policy is represented by regulations and resource
  descriptions; a dedicated ADR should be drafted before changing lifecycle semantics.
- Withdrawal idempotency and provider submission behavior are documented in the
  runbook; a dedicated ADR should be drafted before changing orchestration strategy.


## Dependency Versions

```elixir
[
      # Core Ash stack — upgraded to 3.20 for Foundry compatibility
      {:ash, "~> 3.20"},
      {:ash_postgres, "~> 2.0"},
      {:spark, "~> 2.0"},
      {:ecto_sql, "~> 3.11"},
      {:postgrex, ">= 0.0.0"},

      # Phoenix
      {:phoenix, "~> 1.7"},
      {:phoenix_live_view, "~> 1.0"},
      {:bandit, "~> 1.2"},

      # Ash extensions
      {:ash_authentication, "~> 4.0"},
      {:ash_authentication_phoenix, "~> 2.0"},
      {:ash_state_machine, "~> 0.2"},
      {:ash_paper_trail, "~> 0.1"},
      {:ash_archival, "~> 2.0"},
      {:ash_json_api, "~> 1.0"},

      # Reactor — upgraded to 1.0 (stable release) from 0.10
      {:reactor, "~> 1.0"},

      # Money
      {:ash_money, "~> 0.1"},
      {:ex_money, "~> 5.15"},
      {:ex_money_sql, "~> 1.7"},
      {:ex_cldr, "~> 2.0"},

      # Feature flags (runtime: false — no Redis; configure Ecto persistence when needed)
      {:fun_with_flags, "~> 1.11", runtime: false},
      {:fun_with_flags_ui, "~> 1.0", runtime: false},

      # Background jobs
      {:oban, "~> 2.17"},
      {:ash_oban, "~> 0.2"},

      # Rate limiting (runtime: false — configure when needed)
      {:hammer, "~> 7.0", runtime: false},

      # Observability
      {:opentelemetry, "~> 1.3"},
      {:opentelemetry_exporter, "~> 1.6"},

      # Igniter — upgraded for Ash 3.20 compatibility
      {:igniter, "~> 0.6"},

      # Foundry — meta-framework for governance
      {:foundry, path: "../../apps/foundry"},

      # Serialisation
      {:jason, "~> 1.4"},

      # Testing
      {:stream_data, "~> 1.0"},
      {:bypass, "~> 2.1", only: :test},
      {:mox, "~> 1.1", only: :test},
      {:ex_machina, "~> 2.7", only: :test},

      # Dependency conflict resolution
      {:plug, "~> 1.7", override: true},

      # Transitive dependencies for Swoosh email client
      {:hackney, "~> 1.9"}
    ]
```

---

## Project Status

```json
{"ci":{"branch":null,"commit":null,"context_lock_current":true,"last_run_at":null,"lint_passed":null,"tests_passed":null},"compiled_at":"2026-05-01T09:54:21Z","compliance":{"covered_count":0,"planned_count":13,"sample_requirements":[{"coverage":0,"id":"RG-MGA-001","status":"planned"},{"coverage":0,"id":"RG-MGA-002","status":"planned"},{"coverage":0,"id":"RG-MGA-003","status":"planned"},{"coverage":0,"id":"RG-MGA-005","status":"planned"},{"coverage":0,"id":"RG-MGA-006","status":"planned"}],"total_requirements":13,"truncated_count":8},"domain_type":"igaming","domains":["Accounts","Finance","Gaming","Infrastructure","Ops","Players","Policies","Promotions"],"generated_at":"2026-05-01T09:55:24.128976Z","lint":{"errors":0,"total_violations":49,"warnings":49},"manifest":{"domain_type":"igaming","sensitive_resources":["Elixir.IgamingRef.Finance.Wallet","Elixir.IgamingRef.Finance.LedgerEntry","Elixir.IgamingRef.Finance.WithdrawalRequest","Elixir.IgamingRef.Players.Player","Elixir.IgamingRef.Players.SelfExclusionRecord"]},"migrations":{"applied_count":0,"pending_count":0},"project":"IgamingRef","project_type":"standard","proposals":{"open_count":0,"recent":[]},"sensitive_modules":["LedgerEntry","Player","SelfExclusionRecord","Wallet","WithdrawalRequest"],"stack":{"ash":"3.24.3","ash_postgres":"2.9.0","elixir":null,"oban":"2.21.1","phoenix":"1.8.5","reactor":"1.0.1"}}
```

## System Architecture (Full Project Context)

# System Map: IgamingRef (standard · igaming)

Compact text format for LLM consumption.

## Legend

**Types:** auth=ash_authentication  pol=ash_policy  bp=blueprint  job=oban_job  pvr=provider  rxr=reactor  res=resource  txr=transfer
**Attrs:** pk=primary_key  pii=pii  s=sensitive  m=money  u=unique  req=required
**Edges:** async=async  ath=authenticates  cp=calls_provider  comp=compensation  cfg=configures  grd=guards  pers=persists_to  que=queues_via  r=reads  rb=referenced_by  ref=references  seq=sequence  w=writes


## Module Aliases

AC1=IgamingRef.Accounts.Emails.MagicLinkEmail  AC2=IgamingRef.Accounts.Emails.PasswordResetEmail  AC3=IgamingRef.Accounts.Token  AC4=IgamingRef.Accounts.User  FI1=IgamingRef.Finance.Jobs.ProcessWithdrawalWebhook
FI2=IgamingRef.Finance.LedgerEntry  FI3=IgamingRef.Finance.Rules.PlayerKYCVerified  FI4=IgamingRef.Finance.Rules.SufficientBalance  FI5=IgamingRef.Finance.Rules.WithdrawalLimitNotExceeded  FI6=IgamingRef.Finance.Transfer
FI7=IgamingRef.Finance.Wallet  FI8=IgamingRef.Finance.WithdrawalRequest  FI9=IgamingRef.Finance.WithdrawalTransfer  FI10=IgamingRef.Finance.WithdrawalWebhook  FI11=IgamingRef.Finance.WithdrawalWebhookEvent
GA1=IgamingRef.Gaming.Adapters.PragmaticPlayV1  GA2=IgamingRef.Gaming.Adapters.PragmaticPlayV2  GA3=IgamingRef.Gaming.CatalogSyncJob  GA4=IgamingRef.Gaming.Game  GA5=IgamingRef.Gaming.GameCatalog
GA6=IgamingRef.Gaming.GameVersion  GA7=IgamingRef.Gaming.ProviderConfig  GA8=IgamingRef.Gaming.ProviderSyncReactor  GA9=IgamingRef.Gaming.Rules.GameRTPCertified  GA10=IgamingRef.Gaming.Rules.ProviderActive
OP1=IgamingRef.Ops.AuditEntry  OP2=IgamingRef.Ops.PIIVault  PL1=IgamingRef.Players.KYCDocument  PL2=IgamingRef.Players.KYCUploadToken  PL3=IgamingRef.Players.Player
PL4=IgamingRef.Players.Rules.PlayerNotSelfExcluded  PL5=IgamingRef.Players.SelfExclusionRecord  PO1=IgamingRef.Policies.AuthenticatedSubject  PO2=IgamingRef.Policies.ComplianceOrPlatformLead  PO3=IgamingRef.Policies.InternalSystemActor
PO4=IgamingRef.Policies.OperatorOnly  PO5=IgamingRef.Policies.OwnerOrOperator  PO6=IgamingRef.Policies.SelfOnly  PR1=IgamingRef.Promotions.BonusCampaign  PR2=IgamingRef.Promotions.BonusCondition
PR3=IgamingRef.Promotions.BonusConditionGroup  PR4=IgamingRef.Promotions.BonusEvaluationReactor  PR5=IgamingRef.Promotions.BonusEvent  PR6=IgamingRef.Promotions.BonusExecution  PR7=IgamingRef.Promotions.BonusGrant
PR8=IgamingRef.Promotions.BonusGrantTransfer  PR9=IgamingRef.Promotions.BonusTrigger  PR10=IgamingRef.Promotions.Rules.CampaignNotExpired  PR11=IgamingRef.Promotions.Rules.PlayerEligibleForCampaign  RO1=external:oban_queue
RO2=external:postgres:Accounts  RO3=external:postgres:Finance  RO4=external:postgres:Gaming  RO5=external:postgres:Ops  RO6=external:postgres:Players
RO7=external:postgres:Promotions  RO8=external:pragmaticplayv1  RO9=external:pragmaticplayv2

## Nodes

[AC1] res · accounts
  > Stub for Magic Link Emails to satisfy AshAuthentication.Sender behaviour.

[AC2] res · accounts
  > Stub for Password Reset Emails to satisfy AshAuthentication.Sender behaviour.

[AC3] res · accounts
  > Authentication tokens - session, magic link, and password reset tokens.
  actions: get_token, store_token, store_confirmation_changes, get_confirmation_changes, revoked?, revoke_all_stored_for_subject, revoke_jti, revoke_token, read_expired, expunge_expired, destroy, read
  dl=postgres · paper_trail · archival

[AC4] res · accounts
  > Authentication subject for the platform. Linked to a Player record
post-registration.
  attrs: email:cistring:s, hashed_password:str:s
  actions: request_magic_link, sign_in_with_magic_link, password_reset_with_password, request_password_reset_with_password, sign_in_with_token, sign_in_with_password, register_with_password, get_by_subject, read
  dl=postgres · paper_trail · archival · auth_subject

[FI1] job · finance
  > Processes provider webhook events for withdrawal status updates.

[FI2] res · finance · **sensitive**
  > Immutable record of every financial movement against a wallet.
  attrs: wallet_id:uuid, amount:money, direction:atom, kind:atom, idempotency_key:str, reference_id:str
  actions: read, record
  compliance: RG_MGA_001, RG_MGA_002, RG_UK_003
  dl=postgres · paper_trail · archival

[FI3] rule · finance
  > Rule: the player must have verified KYC status before certain transactions.

Compliance: RG-MGA-003 (KYC requirements)
  compliance: RG_MGA_003

[FI4] rule · finance
  > Rule: the wallet balance must be sufficient to cover the requested debit amount.

Applied by: IgamingRef.Finance.Withdra
  compliance: RG_MGA_001

[FI5] rule · finance
  > Rule: the withdrawal amount must not exceed the player's configured daily limit.

The daily limit is read from the playe
  compliance: RG_UK_014, RG_MGA_007

[FI6] res · finance
  > Represents a financial transfer between accounts or wallets.
  attrs: from_wallet_id:uuid, to_wallet_id:uuid, amount:money, status:atom, reason:str
  actions: read, record, mark_completed, mark_failed
  compliance: RG_MGA_001, RG_UK_003
  dl=postgres · paper_trail · archival

[FI7] res · finance · **sensitive**
  > Holds a player's current balance across a single currency denomination.
  attrs: player_id:uuid, currency:str, balance:money, status:atom
  actions: destroy, read, create, credit, debit, freeze, unfreeze, close
  compliance: RG_MGA_001, RG_UK_003
  dl=postgres · paper_trail · archival

[FI8] res · finance · **sensitive**
  > A player's request to withdraw funds from their wallet.
  attrs: player_id:uuid, wallet_id:uuid, amount:money, status:atom, provider:str, provider_reference:str, rejection_reason:str
  actions: read, create, approve, reject, cancel, mark_processing, mark_completed
  compliance: RG_UK_014, RG_MGA_007
  dl=postgres · paper_trail · archival

[FI9] rxr · finance
  > Processes an approved withdrawal request through to provider submission.
  compliance: RG_UK_014, RG_MGA_007, RG_MGA_003

[FI10] trigger · finance
  > Payment provider webhook receiver for withdrawal status updates.
  compliance: RG_UK_014, RG_MGA_007

[FI11] res · finance
  > Inbound provider webhook event captured inside the Ash domain boundary.
  attrs: provider:str, provider_reference:str, event_type:str, status:atom, payload:map
  actions: read, receive
  compliance: RG_UK_014, RG_MGA_007
  dl=postgres

[GA1] pvr · gaming
  > Provider adapter for Pragmatic Play (V1 API).
  compliance: RG_MGA_006

[GA2] pvr · gaming
  > Provider adapter for Pragmatic Play (V2 API).
  compliance: RG_MGA_006

[GA3] job · gaming
  > Scheduled job that periodically syncs the game catalog from all providers.

[GA4] res · gaming
  > A game title offered by a provider.
  attrs: provider_id:uuid, provider_game_code:str, title:str, category:str, rtp:dec, volatility:atom
  actions: read, sync
  compliance: RG_MGA_006, RG_UK_007
  dl=postgres · archival

[GA5] res · gaming
  > Read-only view of available games.
  attrs: game_id:uuid, current_version_id:uuid, available_regions:str, published_at:utcdatetime, hidden:bool
  actions: read, add_to_catalog, hide, show
  compliance: RG_UK_007, RG_MGA_006
  dl=postgres · archival

[GA6] res · gaming
  > A specific version of a game.
  attrs: game_id:uuid, version_code:str, status:atom, release_date:date, rtp_certified:bool
  actions: read, sync, mark_active, mark_deprecated
  compliance: RG_UK_007, RG_MGA_006
  dl=postgres · archival

[GA7] res · gaming
  > Configuration for a gaming provider integration.
  attrs: provider_name:str, api_endpoint:str, api_key:str, status:atom, rtp_certified:bool
  actions: read, create, update_status, mark_certified
  compliance: RG_MGA_006
  dl=postgres · paper_trail · archival

[GA8] rxr · gaming
  > Synchronizes the game catalog from a provider.
  compliance: RG_MGA_006, RG_UK_007

[GA9] rule · gaming
  > Rule: the game version must have RTP certification.

Compliance: RG-UK-007 (game certification)
  compliance: RG_UK_007

[GA10] rule · gaming
  > Rule: the gaming provider must be in :active status.

Compliance: RG-MGA-006 (provider agreements)
  compliance: RG_MGA_006

[OP1] res · ops
  > Immutable audit trail entry.
  attrs: actor_id:uuid, actor_type:str, action:str, resource_type:str, resource_id:uuid, changes:map, reason:str
  actions: read, record
  compliance: RG_MGA_002
  dl=postgres · archival

[OP2] res · ops
  > Encrypted storage for personally identifiable information.
  attrs: player_id:uuid, pii_type:atom, encrypted_value:str, hash_digest:str, last_accessed_at:utcdatetime, access_count:int
  actions: read, store, read_sensitive, touch_accessed
  compliance: RG_MGA_002, RG_UK_002
  dl=postgres · paper_trail · archival

[PL1] res · players
  > Stores KYC documentation uploaded by players for identity verification.
  attrs: player_id:uuid, upload_token_id:uuid, document_type:atom, storage_path:str, status:atom, rejection_reason:str, verified_at:utcdatetime
  actions: read, upload, mark_verified, mark_rejected
  compliance: RG_MGA_003, RG_UK_002
  dl=postgres · paper_trail · archival

[PL2] res · players
  > Short-lived token that authorizes a player to upload KYC documents.
  attrs: player_id:uuid, token:str, expires_at:utcdatetime, consumed_at:utcdatetime, consumed_by_document_id:uuid
  actions: read, generate, mark_consumed
  compliance: RG_MGA_003, RG_UK_002
  dl=postgres · archival

[PL3] res · players · **sensitive**
  > A registered player account. The root of all player-scoped data.
  attrs: email:cistring, username:str, date_of_birth:date, country_code:str, kyc_status:atom, risk_level:atom, status:atom
  actions: read, register, update_kyc_status, suspend, reinstate, self_exclude, close
  compliance: RG_UK_002, RG_MGA_003, RG_UK_008
  dl=postgres · paper_trail · archival

[PL4] rule · players
  > Rule: the player must not have an active self-exclusion record.

Applied by: IgamingRef.Finance.WithdrawalTransfer,
    
  compliance: RG_UK_008, RG_MGA_009

[PL5] res · players · **sensitive**
  > Immutable record of a self-exclusion event. Append-only.
  attrs: player_id:uuid, excluded_at:utcdatetime, exclusion_type:atom, duration_days:int, reinstated_at:utcdatetime
  actions: read, record, mark_reinstated
  compliance: RG_UK_008, RG_MGA_009
  dl=postgres · paper_trail · archival

[PO1] rule · policies
  > Allows any authenticated user (has an actor).

Applied by: IgamingRef.Finance.Wallet,
            IgamingRef.Promotions.

[PO2] rule · policies
  > Allows compliance officers or platform leads.

Applied by: IgamingRef.Finance.Wallet

[PO3] rule · policies
  > Allows internal system actors (jobs, async processes).

Applied by: IgamingRef.Finance.LedgerEntry,
            IgamingR

[PO4] rule · policies
  > Allows only operator roles.

Applied by: IgamingRef.Gaming.ProviderConfig,
            IgamingRef.Finance.WithdrawalRequ

[PO5] rule · policies
  > Allows owner of the resource or any operator.

Applied by: IgamingRef.Finance.Wallet,
            IgamingRef.Finance.Led

[PO6] rule · policies
  > Allows only reading/modifying one's own record

[PR1] res · promotions
  > A configured bonus campaign. Declares eligibility rules, award amounts,
and wagering requirements.
  attrs: name:str, kind:atom, status:atom, eligibility_rule:str, bonus_amount:money, wagering_multiplier:dec, max_redemptions:int, starts_at:utcdatetime, expires_at:utcdatetime
  actions: read, create, update, activate, pause, resume, expire
  compliance: RG_MGA_005, RG_UK_011
  dl=postgres

[PR2] res · promotions
  > Atomic condition used by bonus rule trees.
  attrs: group_id:uuid, kind:atom, params:map, negated:bool, position:int
  actions: read, create, update
  compliance: RG_MGA_005, RG_UK_011
  dl=postgres

[PR3] res · promotions
  > Logical grouping node for campaign conditions.
  attrs: campaign_id:uuid, parent_group_id:uuid, combinator:atom, position:int
  actions: read, create, update
  compliance: RG_MGA_005, RG_UK_011
  dl=postgres

[PR4] rxr · promotions
  > Evaluates inbound bonus events against manager-configured triggers, conditions,
and executions.
  compliance: RG_MGA_005, RG_UK_011

[PR5] res · promotions
  > Runtime inbound event evaluated by the bonus engine.
  attrs: kind:atom, player_id:uuid, wallet_id:uuid, amount:money, currency:str, idempotency_key:str, payload:map, processed_at:utcdatetimeusec
  actions: read, ingest, mark_processed
  compliance: RG_MGA_005, RG_UK_011
  dl=postgres · paper_trail · archival

[PR6] res · promotions
  > Declarative execution step for a campaign.
  attrs: campaign_id:uuid, kind:atom, params:map, position:int, enabled:bool
  actions: read, create, update
  compliance: RG_MGA_005, RG_UK_011
  dl=postgres

[PR7] res · promotions
  > A specific bonus awarded to a player from a campaign.
  attrs: player_id:uuid, campaign_id:uuid, amount:money, wagering_remaining:dec, status:atom, granted_at:utcdatetime, expires_at:utcdatetime
  actions: read, grant, apply_wager, forfeit, expire, complete
  compliance: RG_MGA_005, RG_UK_011
  dl=postgres

[PR8] rxr · promotions
  > Awards a bonus to a player when campaign eligibility is confirmed.
Credits the player's wallet and creates the BonusGran
  compliance: RG_MGA_005

[PR9] res · promotions
  > Configurable trigger declaration for a bonus campaign.
  attrs: campaign_id:uuid, kind:atom, enabled:bool, params:map, position:int
  actions: read, create, update
  compliance: RG_MGA_005, RG_UK_011
  dl=postgres

[PR10] rule · promotions
  > Rule: the campaign's expires_at has not passed.

Evaluated at Transfer time, not at campaign read time - a campaign coul
  compliance: RG_MGA_005

[PR11] rule · promotions
  > Rule: the player meets the campaign's eligibility criteria.

Eligibility checks that the player has not already redeemed
  compliance: RG_MGA_005

[RO1] external · infrastructure
  > Oban background job queue

[RO2] external · infrastructure
  > PostgreSQL - Accounts domain tables (AshPostgres)

[RO3] external · infrastructure
  > PostgreSQL - Finance domain tables (AshPostgres)

[RO4] external · infrastructure
  > PostgreSQL - Gaming domain tables (AshPostgres)

[RO5] external · infrastructure
  > PostgreSQL - Ops domain tables (AshPostgres)

[RO6] external · infrastructure
  > PostgreSQL - Players domain tables (AshPostgres)

[RO7] external · infrastructure
  > PostgreSQL - Promotions domain tables (AshPostgres)

[RO8] external · infrastructure
  > External API: Pragmaticplayv1

[RO9] external · infrastructure
  > External API: Pragmaticplayv2

## Edges

AC3 --pers--> RO2
AC4 --ath--> AC3
AC4 --pers--> RO2
FI1 --async--> FI8
FI1 --que--> RO1
FI2 --ref--> FI7
FI2 --pers--> RO3
FI3 --grd--> FI9 [seq=2,step=evaluate_rules]
FI4 --grd--> FI9 [seq=2,step=evaluate_rules]
FI5 --grd--> FI9 [seq=2,step=evaluate_rules]
FI6 --pers--> RO3
FI7 --rb--> FI2
FI7 --rb--> FI8
FI7 --ref--> PL3
FI7 --pers--> RO3
FI8 --ref--> FI7
FI8 --ref--> PL3
FI8 --pers--> RO3
FI9 --r--> FI2 [seq=2,step=evaluate_rules]
FI9 --w--> FI2 [seq=4,step=create_ledger_entry,act=record]
FI9 --r--> FI7 [seq=1,step=load_player_and_wallet]
FI9 --r--> FI7 [seq=2,step=evaluate_rules]
FI9 --r--> FI7 [seq=3,step=debit_wallet,act=debit]
FI9 --w--> FI7 [seq=3,step=debit_wallet,act=debit]
FI9 --r--> FI8 [seq=0,step=load_request]
FI9 --r--> FI8 [seq=1,step=load_player_and_wallet]
FI9 --r--> FI8 [seq=2,step=evaluate_rules]
FI9 --r--> FI8 [seq=3,step=debit_wallet,act=debit]
FI9 --r--> FI8 [seq=4,step=create_ledger_entry,act=record]
FI9 --r--> FI8 [seq=5,step=submit_to_provider]
FI9 --r--> FI8 [seq=6,step=update_withdrawal_status,act=mark_processing]
FI9 --w--> FI8 [seq=6,step=update_withdrawal_status,act=mark_processing]
FI9 --r--> PL3 [seq=1,step=load_player_and_wallet]
FI9 --r--> PL3 [seq=2,step=evaluate_rules]
FI10 --enqueues--> FI1
FI11 --pers--> RO3
GA1 --cp--> RO8
GA1 --cp--> RO8
GA2 --cp--> RO9
GA2 --cp--> RO9
GA3 --async--> GA8
GA3 --que--> RO1
GA4 --pers--> RO4
GA5 --pers--> RO4
GA6 --pers--> RO4
GA7 --pers--> RO4
GA8 --w--> GA4 [seq=2,step=sync_games,act=sync]
GA8 --r--> GA7 [seq=0,step=load_provider]
GA8 --r--> GA7 [seq=1,step=fetch_games]
GA8 --r--> GA7 [seq=2,step=sync_games,act=sync]
GA10 --grd--> GA8 [seq=0,step=load_provider]
OP1 --pers--> RO5
OP2 --ref--> PL3
OP2 --pers--> RO5
PL1 --ref--> PL3
PL1 --pers--> RO6
PL2 --ref--> PL3
PL2 --pers--> RO6
PL3 --rb--> FI7
PL3 --rb--> FI8
PL3 --rb--> PL5
PL3 --pers--> RO6
PL4 --grd--> FI9 [seq=2,step=evaluate_rules]
PL4 --grd--> PR8 [seq=1,step=evaluate_rules]
PL5 --ref--> PL3
PL5 --pers--> RO6
PO1 --grd--> FI7 [act=debit]
PO1 --grd--> FI8 [act=create]
PO1 --grd--> PR1 [act=read]
PO1 --grd--> PR2 [act=read]
PO1 --grd--> PR3 [act=read]
PO1 --grd--> PR6 [act=read]
PO1 --grd--> PR9 [act=read]
PO2 --grd--> FI7 [act=close]
PO3 --grd--> FI2 [act=record]
PO3 --grd--> FI11 [act=receive]
PO3 --grd--> PL3 [act=update_kyc_status]
PO3 --grd--> PL5 [act=record]
PO3 --grd--> PR5 [act=ingest]
PO3 --grd--> PR5 [act=mark_processed]
PO3 --grd--> PR7 [act=grant]
PO3 --grd--> PR7 [act=apply_wager]
PO4 --grd--> FI8 [act=approve]
PO4 --grd--> FI8 [act=reject]
PO4 --grd--> FI11 [act=read]
PO4 --grd--> PL3 [act=suspend]
PO4 --grd--> PR1 [act=create]
PO4 --grd--> PR1 [act=update]
PO4 --grd--> PR1 [act=activate]
PO4 --grd--> PR2 [act=create]
PO4 --grd--> PR2 [act=update]
PO4 --grd--> PR3 [act=create]
PO4 --grd--> PR3 [act=update]
PO4 --grd--> PR5 [act=read]
PO4 --grd--> PR6 [act=create]
PO4 --grd--> PR6 [act=update]
PO4 --grd--> PR9 [act=create]
PO4 --grd--> PR9 [act=update]
PO5 --grd--> FI2 [act=read]
PO5 --grd--> FI7 [act=read]
PO5 --grd--> FI8 [act=read]
PO5 --grd--> PL3 [act=read]
PO5 --grd--> PL3 [act=self_exclude]
PO5 --grd--> PL5 [act=read]
PO5 --grd--> PR7 [act=read]
PO6 --grd--> AC4 [act=request_magic_link]
PO6 --grd--> AC4 [act=sign_in_with_magic_link]
PO6 --grd--> AC4 [act=request_password_reset_with_password]
PO6 --grd--> AC4 [act=sign_in_with_token]
PO6 --grd--> AC4 [act=sign_in_with_password]
PO6 --grd--> AC4 [act=get_by_subject]
PO6 --grd--> AC4 [act=read]
PR1 --rb--> PR3
PR1 --rb--> PR6
PR1 --rb--> PR7
PR1 --rb--> PR9
PR1 --pers--> RO7
PR2 --ref--> PR3
PR2 --pers--> RO7
PR3 --ref--> PR1
PR3 --rb--> PR2
PR3 --ref--> PR3
PR3 --pers--> RO7
PR4 --r--> PL3 [seq=1,step=load_player]
PR4 --r--> PR1 [seq=2,step=load_active_campaigns]
PR4 --r--> PR1 [seq=3,step=find_matching_campaigns]
PR4 --r--> PR5 [seq=0,step=load_event]
PR4 --r--> PR5 [seq=1,step=load_player]
PR4 --r--> PR5 [seq=3,step=find_matching_campaigns]
PR4 --r--> PR5 [seq=4,step=execute_campaigns]
PR4 --r--> PR5 [seq=5,step=mark_processed,act=mark_processed]
PR4 --w--> PR5 [seq=5,step=mark_processed,act=mark_processed]
PR4 --r--> PR6 [seq=4,step=execute_campaigns]
PR5 --pers--> RO7
PR6 --ref--> PR1
PR6 --pers--> RO7
PR7 --ref--> PL3
PR7 --ref--> PR1
PR7 --pers--> RO7
PR8 --w--> FI2 [seq=3,step=create_ledger_entry,act=record]
PR8 --r--> FI7 [seq=0,step=load_context]
PR8 --r--> FI7 [seq=1,step=evaluate_rules]
PR8 --r--> FI7 [seq=2,step=credit_wallet,act=credit]
PR8 --w--> FI7 [seq=2,step=credit_wallet,act=credit]
PR8 --r--> FI7 [seq=3,step=create_ledger_entry,act=record]
PR8 --r--> FI7 [seq=4,step=create_bonus_grant,act=grant]
PR8 --r--> PL3 [seq=0,step=load_context]
PR8 --r--> PL3 [seq=1,step=evaluate_rules]
PR8 --r--> PL3 [seq=2,step=credit_wallet,act=credit]
PR8 --r--> PL3 [seq=3,step=create_ledger_entry,act=record]
PR8 --r--> PL3 [seq=4,step=create_bonus_grant,act=grant]
PR8 --r--> PR1 [seq=0,step=load_context]
PR8 --r--> PR1 [seq=1,step=evaluate_rules]
PR8 --r--> PR1 [seq=2,step=credit_wallet,act=credit]
PR8 --r--> PR1 [seq=3,step=create_ledger_entry,act=record]
PR8 --r--> PR1 [seq=4,step=create_bonus_grant,act=grant]
PR8 --r--> PR7 [seq=0,step=load_context]
PR8 --r--> PR7 [seq=1,step=evaluate_rules]
PR8 --r--> PR7 [seq=2,step=credit_wallet,act=credit]
PR8 --r--> PR7 [seq=3,step=create_ledger_entry,act=record]
PR8 --r--> PR7 [seq=4,step=create_bonus_grant,act=grant]
PR8 --w--> PR7 [seq=4,step=create_bonus_grant,act=grant]
PR9 --ref--> PR1
PR9 --pers--> RO7
PR10 --grd--> PR8 [seq=1,step=evaluate_rules]
PR11 --grd--> PR8 [seq=1,step=evaluate_rules]

## Spec-Kit

### Overview

Counts: AGENTS=1  ADRs=1  Runbooks=4  Regulations=1
Navigation: Prefer direct node links (`adrs`, `compliance`, `runbook`) before tag-based lookup.
Token estimate: 1007 (warn: false)
Themes: 007, 001, 003, 005, 008, 014, account, active

### AGENTS

- AGENTS · AGENTS.md - iGaming Reference Project :: This file is the primary project-specific entry point for agents working inside
`reference_projects/igaming`. It is l...

### ADRs

- ADR-001 · accepted · Double-Entry Ledger for Financial Transactions :: The iGaming domain requires immutable, auditable financial transaction records. Players make deposits, withdrawals, a...

### Runbooks

- bonus_grant_transfer · Bonus Grant Transfer Runbook :: Awards a bonus to a player when campaign eligibility is confirmed. Credits the wallet and creates a tracking record f...
- bonus_evaluation_reactor · BonusEvaluationReactor Runbook :: `IgamingRef.Promotions.BonusEvaluationReactor` evaluates inbound `BonusEvent` rows
against configured `BonusTrigger`,...
- withdrawal_transfer · Withdrawal Transfer Runbook :: Handles the complete flow of processing an approved withdrawal request through to provider submission.
- provider_sync · Provider Sync Runbook :: Synchronizes the game catalog from a provider's API and creates or updates local records. Fully idempotent.

### Regulations

- ukgc_mga · planned · IgamingRef Regulations - UKGC & MGA :: 001, 002, 003, 005, 007