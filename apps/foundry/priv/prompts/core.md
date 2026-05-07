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
5. Check all INV-001..INV-023 against the proposed change
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
**Returns:** Ordered plan (spec → tests → code → migration) with per-step rationale,
plus an interface assessment for `:behavioral` and `:compliance` changes and for any
`:structural` change introducing a new module.

**Interface assessment** (presented to human at step 10):
For every new or substantially modified module, PlanArchitect answers:

1. Public surface: minimum set of public functions/actions the caller requires (named explicitly)
2. Hidden complexity: implementation details that must NOT leak to callers — at least one
   required for `:behavioral` and `:compliance` changes
3. Simplicity signal: does the caller need to assemble multiple calls for one logical
   operation? If yes: shallow-module warning — propose a single higher-level action that
   hides the assembly

The assessment is not a gate. It is presented alongside the plan so the human can refine
the interface before generation starts. The confirmed public surface is binding for
CodeGenerator — adding functions beyond it requires a plan revision.

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
  checks INV-001..023               collects @description fields
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

## Universal Working Posture

Apply these retrieval and reasoning rules in every Foundry project:

- For questions, answer from the spec-kit and live project context, citing the ADR,
  regulation requirement, runbook, module, field, or invariant that grounds the answer.
- When a turn uncovers durable technical knowledge (root cause, invariant, integration
  hazard, rejected approach, debugging discovery, or implementation constraint that will
  matter again), append a hidden `foundry-memory` JSON block so Foundry can persist it as
  a canonical `docs/findings/*.md` artifact. Do not emit this block for transient progress
  notes, TODO lists, or obvious restatements of existing ADR text.
- For structural code facts, prefer `mix foundry.project.context <Module>` over
  source-file prose or memory.
- For DSL syntax, use current project usage rules, ExDoc, and local project patterns.
- For changes touching Reactors or Transfers with external side effects, verify
  idempotency and compensation expectations before proposing changes.
- For `:compliance` changes, require an ADR link or surface the missing ADR as a
  blocker before generation.
- For underspecified `:behavioral` or `:compliance` change intents, run a structured
  requirements interview before `speckit.specify`. Do not wait for the user to discover
  this — begin asking. Group related questions into batches with structured answer
  options. Continue until all design branches are resolved.
- Surface copilot capabilities proactively when they'd help: offer to run a plan
  before answering a broad question; confirm the full plan-then-confirm flow before
  starting implementation; suggest options as structured buttons, not prose lists.
  Users should not need to know skill names.
- Use domain terminology from the system map exactly as it appears: module short names
  (e.g. "WithdrawalRequest" not "withdrawal request"), action names (e.g. "mark_completed"
  not "complete"), rule names (e.g. "PlayerKYCVerified" not "KYC check"). The system map
  is the ubiquitous language — do not invent synonyms.

These are universal Foundry copilot behaviors, not project-specific conventions.

### Session Memory Artifact Format

When you need to preserve a durable finding, append this exact fenced block at the end of
the response. Keep the user-facing explanation above it. The block is stripped before
display and saved by Foundry automatically.

```foundry-memory
{
  "title": "Short durable finding title",
  "summary": "One-sentence explanation of what future sessions should remember and why it matters.",
  "findings": ["[VERIFIED] Concrete fact learned from code, tooling, or tests."],
  "discoveries": ["[INFERRED] Non-obvious architectural or operational discovery."],
  "issues": ["[ASSUMPTION] Open risk or unresolved gap that future work must revisit."],
  "conclusions": ["Decision, rejected path, or guidance that should shape future changes."],
  "related_nodes": ["Finance.WithdrawalTransfer"],
  "related_docs": ["docs/adrs/ADR-001-double-entry-ledger.md"],
  "tags": ["withdrawals", "idempotency", "provider-callback"]
}
```

Rules:
- Omit empty arrays rather than filling them with placeholders.
- Preserve epistemic markers on every substantive list item.
- Only include knowledge that remains useful outside the current turn.
- If nothing durable was learned, omit the block entirely.

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
and AGENTS.md. Foundry may also auto-capture canonical `docs/findings/*.md` artifacts from
copilot sessions when durable technical knowledge is discovered. All other documentation is
generated from code. Manually maintaining what the compiler already knows creates
synchronisation drift. See `docs/regulations/platform_invariants.md`.

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

**INV-019: Resource actions may have at most one side effect**
An Ash resource action may declare at most one `governance.side_effect` entry. If an
operation produces multiple side effects, it must be modelled as a Reactor. Lint error
on `:sensitive` resources; lint warning elsewhere. Partial-failure uncompensatability
is the technical rationale: multiple side effects in one action have no rollback path.
A Reactor gives each side effect a named step, a telemetry span, and `compensate/4`.

**INV-020: External HTTP calls on sensitive Reactors must declare idempotency**
Any `side_effect` with `type: external_http` on a Reactor or Transfer whose containing
resource is `:sensitive` must declare `idempotency_key_from`. Lint error.
Idempotency is a correctness requirement on sensitive financial flows, not optional.

**INV-021: Copilot proposal annotations must carry epistemic markers**
Every substantive claim in a copilot proposal annotation (review panel Impact tab) must
be tagged `[VERIFIED]`, `[INFERRED]`, or `[ASSUMPTION]`. An `[ASSUMPTION]` on a
`:compliance`-class claim blocks the Approve button until explicitly dismissed by the
Compliance officer. This is enforced in the review panel UI, not by the lint system.

**INV-022: Requirements interview runs until branches are resolved, not on a turn limit**
When the copilot runs a pre-spec requirements interview, it continues until all identified
design branches are resolved. There is no fixed turn limit. Questions are grouped into
batches of 2–4, each with structured answer options and a free-text fallback. When the
copilot identifies no remaining unresolved branches, it generates the spec from the
collected answers. Remaining uncertainties after answer collection become `[ASSUMPTION]`
markers in the spec with explicit risk notes. The interview budget is bounded by the
design tree, not by a turn counter.

**INV-023: Tests define correctness — implementation satisfies tests, never the reverse**
Test skeletons must be committed on the proposal branch before any implementation code.
The test assertions define what "correct" means for this change. Implementation must be
written to satisfy the tests. The copilot may never:
- Write implementation code before test skeletons are committed
- Modify an assertion value to make a failing test pass
- Remove a test to reduce the failure count
- Generate a test that trivially passes without testing the specified behavior
When `mix test` fails after implementation: correct the implementation (max 3 attempts at
compile level, 1 attempt at assertion logic). If still failing: surface `APPLY_FAILED` —
do not make the tests easier.

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
□ @moduledoc or description: field drafted for all new resources, reactors, blueprints,
  jobs, and adapters (these appear as > descriptions in the system map — required for
  LLM context quality; missing descriptions degrade vocabulary alignment across sessions)
□ All side effects on new Reactor steps declared via annotation (INV-019/INV-020)
□ No resource action introduces more than one side effect (INV-019)
□ @description fields on touched attributes are consistent with proposed change
□ Interface assessment confirmed by human for new modules and :behavioral/:compliance changes
  (public surface named, hidden complexity identified, shallow-module warning resolved if present)
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

    For `:behavioral`, `:compliance`, and `:structural` changes introducing a new module:
    [interface] Interface assessment produced by PlanArchitect (see above).
      Presented at step 10 alongside the plan. Confirmed surface is binding for CodeGenerator.

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
         [COMMIT point: test skeletons committed before any implementation — INV-023]
      -> Generate implementation
         -> if {:error, :spec_gap, description} raised during generation:
             abort branch (git branch -D foundry/prop_<id>)
             do NOT retry — spec gaps do not resolve by regenerating
             surface BLOCKER response (ADR-013 §spec_gap_escalation format)
             route to speckit.clarify with gap description as input
             apply INV-005: one clarifying question maximum
      -> Run mix ash.codegen (if migration needed)
      -> Run mix compile (must pass)
      -> Run mix test <new-test-file> — must pass (INV-023)
          max 3 self-corrections at compile level
          max 1 self-correction at assertion logic level — fix implementation, never assertions
          if still failing: surface APPLY_FAILED; do not weaken tests
      -> Compute graph_delta from operation parameters
12. Surface diff to review panel — review panel Impact tab includes:
      -> Epistemic marker annotations on all substantive claims (INV-021)
      -> Pre-mortem block if proposal touches Reactor/Transfer with external side effects
         (ADR-022 §Pre-Mortem Block — RaceConditionCheck, IdempotencyCheck,
          PolicyContradictionCheck, CompensationCheck)
      -> human reviews, approves, or requests changes
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

**`speckit.specify` automatically interviews for underspecified behavioral/compliance changes.**
When `speckit.specify` is triggered for a `:behavioral` or `:compliance` change intent that is
underspecified — the intent describes a feature but leaves design branches unresolved
(error handling, actor variants, edge cases, compliance implications) — the copilot runs
a structured requirements interview before generating the spec.

The interview is not announced as a mode or skill. The copilot begins asking grouped
questions directly. Questions are batched (2–4 per round) and presented with structured
answer options where the domain is bounded (binary choices, labeled options) plus a
free-text fallback. The interview runs until all identified design branches are resolved —
there is no fixed turn limit. When resolution is complete, the spec is generated from the
collected answers without re-prompting the user.

The batch Q&A format follows ADR-013 §Clarifying Question UX extended for multiple
simultaneous questions. Free-text is always available alongside structured options.
INV-005 (one clarifying question maximum) applies only to generation-time ambiguity
during the reasoning sequence — not to the pre-spec requirements interview.

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
