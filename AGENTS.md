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

- _Foundry_ — this meta-platform
- _Target platform_ — a platform built using Foundry (e.g., an iGaming back office, a fintech ledger system)
- _Spec-kit_ — the canonical document families that capture what code cannot: ADRs, Regulations, Runbooks, AGENTS.md, and durable `docs/findings/*.md` technical findings captured from copilot sessions
- _Project context_ — the full system map produced by `mix foundry.project.context`:
  all nodes, edges, and spec-kit navigation metadata for the current project. **Included in Tier 2 LLM context**
  for agent discovery, governance validation, and change impact analysis.
- _Project status_ — the health summary produced by `mix foundry.project.status`:
  lint, migrations, proposals, compliance gaps. Also in Tier 2 LLM context. Replaces "project snapshot".

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

| Package                 | Role                                                                                                                                               | Used by Foundry via                                                                                     |
| ----------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| `spark_meta`            | Generic Spark DSL walker → struct tree. Opt-in `SparkMeta.Extension` hook for richer output; unknown extensions get a raw key-value fallback.      | `Foundry.Context.*` Mix tasks — powers `mix foundry.context`                                            |
| `spark_lint`            | Rule runner engine only: `SparkLint.Rule` behaviour, `SparkLint.Violation` struct, `mix spark_lint.check` task. Ships zero rules.                  | `Foundry.LintRules.*` plugs Foundry's INV-011..017 rule modules into it                                 |
| `ash_ai`                | MCP server (`AshAi.Mcp.Router`), tool declarations (`Foundry.Context` domain), optional prompt-backed internal reasoning actions. See ADR-024.     | Target platforms use `ash_ai` directly; Foundry uses MCP server endpoint for external agent integration |
| `ash_diagram`           | Ash DSL data extraction for ERD + policy flowcharts in `mix foundry.project.context`. Foundry implements `AshDiagram.Data.Extension`. See ADR-021. | `Foundry.AshDiagramExtension` annotates diagrams with governance metadata                               |
| `req_llm`               | LLM HTTP client used by `ash_ai` internally. Foundry configures a dedicated Finch pool. See ADR-001.                                               | Transitive via `ash_ai`                                                                                 |
| `Foundry.Copilot.Tools` | Declares the bash tool with shell constraint enforcement                                                                                           |

(permitted/blocked command list per ADR-010 §Shell Constraints). No other tool
schemas — the agent uses Mix tasks directly via bash for all retrieval. Internal
module, not a Hex package. | `Foundry.Copilot.Engine` dispatches all tool calls
through this module |

**What is NOT a separate package and why:**

- `Foundry.Diff` — ADR-005 change classifier using `Sourceror`. Logic is tightly coupled to the
  manifest sensitive-resources list and Foundry's classification ruleset. Too specific to extract.
- `Foundry.SpecKit` — spec-kit document parser using `MDEx` + `NimbleOptions`. "Spec-kit" is
  Foundry vocabulary; no external audience for the format yet.
- `Foundry.FileSystem` — validated file read boundary for all channel and controller reads.
  Enforces permitted root paths per project context (lib/, test/, config/, priv/repo/migrations/,
  spec-kit paths, mix.exs, .foundry/). Internal module, not a Hex package. All channels
  that read project files must call `Foundry.FileSystem.read/2` — direct `File.read!/1`
  in channels is forbidden. See ADR-020.
- `Foundry.Operations` — the two thin named wrappers (`Op.AddComplianceLink`,
  `Op.AddAgentStep`). All other generation uses raw Igniter directly. Extract only if a
  second tool needs the same wrapper protocol.
- `Foundry.Proposals` — proposal state machine (ADR-014). Coupled to git-backed storage
  (ADR-015) and git-branch stale detection (ADR-009). Extract when a second use case appears.
- `reactor_human_gate` and `reactor_agent_step` — **removed**. See ADR-019.
  Target platforms use `ash_ai` v0.5 `run prompt(model, tools: [...])` directly.
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

## Copilot Sub-Agent Architecture

The copilot orchestrator delegates bounded tasks to typed sub-agents. The orchestrator
owns intent classification, contradiction check, change classification, and plan
presentation. Sub-agents own scoped, tool-constrained retrieval and generation tasks.

### SpecKitNavigator

**Purpose:** Deep-read the constraint graph rooted at the affected NodeEntry and produce
a compact constraint summary.
**Spawned:** Always for `change` intent. For `question` when ADR citation is needed.
**Inputs:** NodeEntry (from CodeContextGatherer) + Tier 2 system map spec references/tag match.
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
- When a turn uncovers durable technical knowledge that future sessions should remember,
  append a hidden `foundry-memory` JSON block so Foundry can persist it automatically as a
  canonical `docs/findings/*.md` artifact. Do not emit this block for transient progress notes.
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
decision with no associated code change) — those produce an Activity Feed card for human
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

**INV-008: Project context must not be stale at CI**
`.foundry/context.lock` must match the current source file hash at CI time. CI runs
`mix foundry.project.context --check` — exits 1 if the lock is absent or stale.
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
Paths outside these roots return `{:error, :outside_boundary}` — they are never surfaced
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

Every proposed change must be classified. The four classes are **domain-agnostic** —
the examples use a fintech/iGaming context but the model applies to any regulated domain.

| Class         | Trigger pattern                                                                                               | Approver                          | Auto-apply   | Audit logged      |
| ------------- | ------------------------------------------------------------------------------------------------------------- | --------------------------------- | ------------ | ----------------- |
| `:structural` | New resource, attribute, relationship, description updates, test skeletons                                    | Any developer                     | Configurable | No                |
| `:behavioral` | New Rule, Transfer step, Blueprint, Reactor, Oban job, state machine transition                               | Domain lead                       | Never        | Yes               |
| `:sensitive`  | Resources/attributes marked `:sensitive` in the manifest — ledger entries, PII, audit records, access control | Sensitive lead + one other (dual) | Never        | Yes, mandatory    |
| `:compliance` | Changes to `compliance:` declarations, policy modules, requirement links                                      | Compliance officer                | Never        | Yes, ADR required |

**The `:sensitive` class is configured per project, not hardcoded.**
A healthcare platform marks `:phi` resources as sensitive. A legal platform marks `:privileged`
documents. The classification engine reads the manifest's `sensitive_resources:` list.
iGaming uses ledger and wallet resources — that is a project-level configuration, not a
Foundry-level assumption.

**When in doubt, classify upward.** A `:behavioral` change misclassified as `:structural`
and auto-applied is a governance failure. The reverse is merely inconvenient.

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
□ @moduledoc or description: field drafted for all new resources, reactors, blueprints,
  jobs, and adapters (these appear as > descriptions in the system map — required for
  LLM context quality; missing descriptions degrade vocabulary alignment across sessions)
□ All side effects on new Reactor steps declared via annotation (INV-019/INV-020)
□ No resource action introduces more than one side effect (INV-019)
□ @description fields on touched attributes are consistent with proposed change
□ Interface assessment confirmed by human for new modules and :behavioral/:compliance changes
  (public surface named, hidden complexity identified, shallow-module warning resolved if present)
□ Policy compatibility verified for all generated UI actions via Ash.Resource.Info.policies/1
   (do not generate UI actions the current actor cannot authorize — check before generating)
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
1.  Read system map spec overview (Tier 2) — identify relevant ADRs/INVs/regulations by node link or tag
2.  Read those documents via bash — follow cross-references
3.  Run pre-generation checklist — identify missing spec-kit items
4.  Read module context: mix foundry.project.context <Module>
5.  Fetch closest pattern example: mix foundry.pattern.find <type> --domain <D>
6.  Check @description fields on all touched attributes against proposed change
7.  Run contradiction check — BLOCKED if violated, else proceed
8.  Classify whether spec-kit drafting is required:
      :behavioral or :compliance → ADR draft required, included as first file
                                    in the proposal branch
      :structural with new concept → ADR draft offered, not required
      :structural modification → no spec-kit step
9.  Construct ordered session plan:
      [spec]  ADR / runbook stub (if required by step 8) — always first
      [tests] Test skeletons from DSL declarations + ADR boundary conditions
      [code]  Implementation constrained by test structure
      [migration] mix ash.codegen if schema changes

    For `:behavioral`, `:compliance`, and `:structural` changes introducing a new module:
    [interface] Interface assessment produced by PlanArchitect (see above).
      Presented at step 10 alongside the plan. Confirmed surface is binding for CodeGenerator.

    Ordering rationale — why spec before tests before code:

    Spec first: A reviewer reading code cannot govern what they do not understand.
    The ADR records why this approach was chosen over alternatives. Without it,
    approval is a rubber stamp on implementation, not a governance decision.
    The runbook records what happens when this Reactor fails. Without it, the
    reviewer cannot assess operational risk. Spec-kit files and code are reviewed
    together in one diff — the spec makes the code legible to a non-author.
    This is an epistemology requirement, not a workflow preference.

    Tests before code: Test skeletons are derived from DSL declarations and ADR
    boundary conditions — they define what "correct" means before any implementation
    exists. Code written before the tests know what to assert may satisfy its author
    but cannot satisfy the spec. The tests constrain the implementation, not the
    reverse.

    Migration last: Schema changes require a compiled Ash resource to generate
    correct migration SQL. `mix ash.codegen` must run after all code is written
    and compiles. It is always the final generation step.
10. Present plan for human confirmation
      Human refines via conversation until satisfied — plan only, not code
11. On confirmation: single generation pass on foundry/prop_<id> branch
      → Write spec-kit files first (Markdown, direct branch write)
      → Generate test skeletons
         [COMMIT point: test skeletons committed before any implementation — INV-023]
      → Generate implementation
         → if {:error, :spec_gap, description} raised during generation:
             abort branch (git branch -D foundry/prop_<id>)
             do NOT retry — spec gaps do not resolve by regenerating
             surface BLOCKER response (ADR-013 §spec_gap_escalation format)
             route to speckit.clarify with gap description as input
             apply INV-005: one clarifying question maximum
      → Run mix ash.codegen (if migration needed)
      → Run mix compile (must pass)
      → Run mix test <new-test-file> — must pass (INV-023)
          max 3 self-corrections at compile level
          max 1 self-correction at assertion logic level — fix implementation, never assertions
          if still failing: surface APPLY_FAILED; do not weaken tests
      → Compute graph_delta from operation parameters
12. Surface diff to review panel — review panel Impact tab includes:
      → Epistemic marker annotations on all substantive claims (INV-021)
      → Pre-mortem block if proposal touches Reactor/Transfer with external side effects
         (ADR-022 §Pre-Mortem Block — RaceConditionCheck, IdempotencyCheck,
          PolicyContradictionCheck, CompensationCheck)
      → human reviews, approves, or requests changes
```

This sequence applies to all `change` intents. When `change_generation_enabled: false`
(Phase 3), step 11 is replaced by a plain prose description of what would be generated.

---

## Where to Find Authoritative Information

| Question                                        | Where to look                                                                                                      |
| ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| What does resource X do?                        | `mix foundry.context MyApp.Domain.Resource`                                                                        |
| What compliance requirements affect feature Y?  | `mix foundry.compliance.check --filter=Y`                                                                          |
| What changed in the system recently?            | `git log` + `mix foundry.diagram.diff`                                                                             |
| Full system map (all nodes + edges)?            | `mix foundry.project.context` — Tier 2 LLM context (always available to agents)                                    |
| Current project health (lint, proposals, gaps)? | `mix foundry.project.status` — Tier 2 context                                                                      |
| Which spec-kit document covers a concept?       | Spec-kit overview inside full project context (Tier 2) — agent reads summaries and tags, then `bash("cat <path>")` |
| Correct DSL syntax for X?                       | `bash("mix foundry.exdoc <Module>")` or `bash("cat .foundry/usage_rules/<lib>.md")`                                |
| Pattern for a new construct type?               | `bash("mix foundry.pattern.find <type> --domain <D>")`                                                             |
| Operation parameter schema?                     | `bash("cat .foundry/usage_rules/foundry_operations.md")` or `bash("mix foundry.operation.schema <Op>")`            |
| Read a source file or spec-kit document?        | `Foundry.FileSystem.read/2` via FoundryChannel `fetch_file` / `fetch_document`                                     |
| Spec-kit task postures?                         | §Spec-Kit Tasks above                                                                                              |

### System Map vs Bash — The Decision Rule

**The system map answers "which?" — bash answers "what?"**

| Answer comes from full project context (already in Tier 2 prompt) | Answer requires bash                           |
| ----------------------------------------------------------------- | ---------------------------------------------- |
| Which ADRs are relevant to this topic?                            | What does ADR-013 §Confidence actually say?    |
| Which modules exist in the Finance domain?                        | What attributes does Wallet currently have?    |
| Which INV rules apply to `:sensitive` resources?                  | Full text of a specific regulation requirement |
| Does a pattern exist for `transfer` type?                         | The actual pattern source code                 |
| Which spec-kit files exist?                                       | Contents of a specific spec-kit file           |

Never run bash to answer a question the system map already resolves. Never trust a
system-map summary as the full constraint text for a contradiction check — always fetch
the full document. Fetching a document the system map says doesn't exist is always wrong.

---

## Project Discovery — Igniter API

When the agent needs to discover all resources and domains in the project (e.g., for
generating a new resource that must be registered in its domain), use the Igniter API:

```elixir
# Programmatic — inside Igniter.Mix.Task callback
{igniter, resource_modules} = Ash.Resource.Igniter.list_resources(igniter)
{igniter, domain_modules}   = Ash.Domain.Igniter.list_domains(igniter)

# Duplicate check before generating a new relationship
{igniter, exists?} = Ash.Resource.Igniter.defines_relationship(igniter, TargetMod, :name)
```

`mix igniter.list_resources` does NOT exist as a standalone command. The API is
programmatic only. `Ash.Resource.Info` (compiled DSL runtime) provides semantic truth
(relationships, actions, policies) after compilation. `Ash.Resource.Igniter` provides
project traversal (finding resource modules) before compilation.

---

## Tidewave — Dev-Time Runtime Intelligence

Target projects scaffolded by `mix foundry.spec_kit.init` include Tidewave as a
`:dev` dependency. This gives external agents (Claude Code, Cursor) runtime intelligence
about the target project without Foundry providing it:

| Tidewave tool       | What it provides                                    | Relationship to Foundry                                         |
| ------------------- | --------------------------------------------------- | --------------------------------------------------------------- |
| `get_docs`          | Version-exact documentation for any module/function | Supplements `mix foundry.exdoc` for interactive sessions        |
| `get_ash_resources` | Text list of Ash resources with their domains       | Complements `get_module_context` (text vs structured JSON)      |
| `project_eval`      | Live code evaluation in app runtime                 | Lets agents validate Igniter output before submitting proposals |
| `execute_sql_query` | Direct database queries                             | Lets agents verify migration results post-approval              |
| `get_logs`          | Application logs                                    | Lets agents diagnose runtime errors in context                  |

Tidewave is dev-only. It is not present in production. It is not Foundry's MCP server.
The two MCP surfaces are additive and non-overlapping (ADR-024).

---

## Agent Steps (ash_ai v0.5)

Target platform agent steps use `ash_ai` v0.5 `run prompt(...)` syntax directly.
`reactor_agent_step` DSL is no longer used. The INV-014..017 lint rules check for
`ash_ai` prompt action configuration on `step_kind: :agent` steps in NodeEntry.

```elixir
# In a target platform Reactor — the 2026 canonical form
step :risk_score, MyApp.AI.RiskScorer do
  run prompt(
    fn _input, _context -> ReqLLM.model!("anthropic:claude-sonnet-4-6") end,
    tools: [:read_player_history, :check_velocity],
    confidence_threshold: 0.7,
    on_low_confidence: :escalate_human,
    telemetry_prefix: [:my_app, :risk, :withdrawal, :risk_score]
  )
end
```

The pre-generation checklist items INV-014..017 apply to this syntax:

- INV-014: `confidence_threshold` required on `:decision` and `:scorer` steps
- INV-015: `human_gate` or `on_low_confidence: :escalate_human` required on compliance-gated flows
- INV-016: `tools:` list must be explicitly declared
- INV-017: `telemetry_prefix:` must follow `[app_name, domain_name, reactor_name, step_name]` convention

---

## ADR Index

| ID      | Slug                                         | Decision summary                                                                                                                                                                                                                                                                                       |
| ------- | -------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| ADR-001 | stack-selection                              | Elixir/Ash 3.x/Phoenix/Spark — full ecosystem including ash_postgres, money stack, auth, observability                                                                                                                                                                                                 |
| ADR-002 | code-generation                              | Igniter operations (structured or raw) — no string interpolation; migration generation included                                                                                                                                                                                                        |
| ADR-003 | agent-context-strategy                       | Structured retrieval over live DSL introspection, not RAG over code; full context schema                                                                                                                                                                                                               |
| ADR-004 | dependency-governance                        | Category-based approval, forbidden list, ecto direct-only rule, test tool assignments                                                                                                                                                                                                                  |
| ADR-005 | change-approval-model                        | Four-class classification, dual approval for :sensitive, migration classification, audit log always                                                                                                                                                                                                    |
| ADR-006 | infrastructure-governance                    | Proposal-only from agents, human apply, base CI pipeline owned by platform                                                                                                                                                                                                                             |
| ADR-007 | test-generation-strategy                     | DSL declarations drive skeleton generation, compliance reqs drive E2E, tool assignments                                                                                                                                                                                                                |
| ADR-008 | visualization-paradigm                       | Read-only system map, Activity Feed is the only change interface                                                                                                                                                                                                                                       |
| ADR-009 | concurrent-proposals                         | Optimistic locking via git blob hashes — stale proposals are surfaced, not silently applied                                                                                                                                                                                                            |
| ADR-010 | llm-model-and-context                        | Claude Sonnet, bounded context budgets, full ecosystem version manifest, structured retrieval                                                                                                                                                                                                          |
| ADR-011 | project-manifest                             | **Deferred** — write when `Foundry.Manifest` Ash resource is defined; pre-ADR schema in `docs/manifest-schema-draft.md`                                                                                                                                                                                |
| ADR-012 | studio-ux-specification                      | Command palette (Cmd+K), review panel, panel interactions, approval tracking UI, performance budgets, data retention                                                                                                                                                                                   |
| ADR-013 | copilot-agent-behavior                       | Epistemic contract, confidence states, clarifying question UX, error recovery, phase-gated behaviour                                                                                                                                                                                                   |
| ADR-014 | proposal-lifecycle                           | Proposal state machine, dual approval mechanics, ADR linking for :compliance, apply step, compilation failure path                                                                                                                                                                                     |
| ADR-015 | storage-model                                | Git-backed files + ETS only — no Postgres dependency for Foundry itself                                                                                                                                                                                                                                |
| ADR-016 | visualization-paradigm-v2                    | Four C4 levels, 11 node types, 8 edge types, authorization matrix view, agent node type (⊕). Data source: `mix foundry.project.context` (amended by ADR-020). JS architecture: `CytoscapeGraph` (pure wrapper) + `FoundryGraph` (Foundry config layer). Amended by ADR-027 (LiveView node extensions). |
| ADR-017 | agent-injection-governance                   | AshAI integration model, 10 agent types, human-in-the-loop gate spec, change classification for agent constructs                                                                                                                                                                                       |
| ADR-020 | project-context-filesystem-umbrella          | Unified `mix foundry.project.context` command, `Foundry.FileSystem` read boundary, umbrella and related-project support, `snapshot` → `status` rename                                                                                                                                                  |
| ADR-022 | side-effect-governance-and-copilot-precision | `SideEffectEntry` in NodeEntry/StepEntry; INV-019/020/021; BLOCKER/REFUSE distinction; epistemic markers; pre-mortem block; spec-gap escalation                                                                                                                                                        |
| ADR-024 | mcp-server-architecture                      | Foundry IS the MCP server; external agents connect to it; AshAi.Mcp.Router; Tidewave complement; optional internal LLM                                                                                                                                                                                 |
| ADR-027 | ui-surface-nodes                             | LiveView (▣) node extended with SDUI subtype, router-inferred routes, Sourceror action call scanning, `calls_action`+`feature_flagged_by` edges, dev server preview, igaming web layer                                                                                                                 |
| ADR-028 | new-project-onboarding                       | Folder-open UX, one-click dependency install (nvm/homebrew), native Phoenix umbrella scaffolding, agent skills in `.agents/skills/` project directory, copilot-first seeding, no manual file editing                                                                                                  |

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

### Constraint Graph Traversal

The NodeEntry fields `compliance`, `adrs`, and `runbook` are not metadata — they are
the constraint graph entry points. The SpecKitNavigator sub-agent must follow them:

```
NodeEntry.compliance → docs/regulations/*.md  → requirement IDs → linked ADRs
NodeEntry.adrs       → docs/adrs/ADR-XXX.md   → Extends: headers → more ADRs
NodeEntry.runbook    → docs/runbooks/*.md      → referenced Reactor steps
NodeEntry.sensitive  → INV-001, INV-011, INV-012 always apply
```

Traversal is deterministic and bounded: read exactly the documents the module declares,
follow `Extends:` headers in ADRs one level, follow requirement IDs in regulation files
to their linked ADRs. Stop when no new documents are referenced. The orchestrator never
reads ADRs speculatively — only those reachable from the affected NodeEntry.

`agent_steps` is an empty list `[]` when the module has no AshAI agent step declarations.
A non-empty list requires AshAI v2 or later (see ADR-017). The `mix foundry.context` task
will warn (not fail) if AshAI is present but the version cannot be determined — this
follows the same pattern as the v1 ignore-and-warn stance in ADR-001, which is superseded
by ADR-017 for projects that opt in to agent support.

The per-module schema above is also the NodeEntry schema within `mix foundry.project.context`
output — the project context is a bulk projection of per-module context into a single graph
document. The two schemas are kept in sync. See `docs/project_context_schema.md`.

---

## Spec-Kit Skill Orchestration

The copilot internally orchestrates a set of spec-kit skills. These are transparent to
the user — they interact only with the copilot conversation and the review panel.
The copilot decides which skills to invoke, in what order, synthesizes results, and
surfaces only the finished output: a confirmed plan, a review diff, or a BLOCKED message.

### Skill invocation map

| Skill                   | When copilot invokes                                                  | What it produces                                        | Feeds into                                                   |
| ----------------------- | --------------------------------------------------------------------- | ------------------------------------------------------- | ------------------------------------------------------------ |
| `speckit.specify`       | `change` intent describes a feature without an existing spec          | Feature spec from natural language                      | `speckit.plan`                                               |
| `speckit.clarify`       | Intent confidence below threshold — before the one permitted question | Up to 5 targeted gaps identified                        | Copilot distills to the single most critical (INV-005)       |
| `speckit.plan`          | After spec exists; before session plan is presented to human          | Design artifacts: approach, alternatives, trade-offs    | PlanArchitect sub-agent                                      |
| `speckit.tasks`         | After plan is confirmed by human                                      | Dependency-ordered task list                            | CodeGenerator execution queue                                |
| `speckit.analyze`       | After task list is generated; before plan is shown to human           | Cross-artifact consistency report (spec ↔ plan ↔ tasks) | Copilot resolves conflicts before surfacing plan             |
| `speckit.implement`     | On human confirmation (Phase 4+)                                      | Executes tasks in dependency order                      | Igniter + branch operations                                  |
| `speckit.constitution`  | When AGENTS.md or a project constitution would change                 | Keeps all dependent templates in sync                   | SpecKitDrafter (constitution update is first file on branch) |
| `speckit.taskstoissues` | When user requests GitHub issue creation from a confirmed proposal    | Dependency-ordered GitHub issues from tasks.md          | External (GitHub)                                            |

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
— before any ADR, runbook, or code. This ensures dependent templates are in sync before
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
_this_ AGENTS.md, apply _these_ ADRs. The copilot does not need a special mode for
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
  mix_task_summary_schemas.md                ← project status schema (renamed from snapshot per ADR-020)
  project_context_schema.md                  ← schema for mix foundry.project.context output
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
    ADR-027-ui-surface-nodes.md
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
  project_context.json                       ← generated by mix foundry.project.context, committed
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
