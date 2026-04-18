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
Paths outside these roots return `{:error, :outside_boundary}` — they are never surfaced
to the client. `project_root` is always resolved server-side from the session context;
the client cannot supply or influence it.

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
□ @description fields on touched attributes are consistent with proposed change
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
      [spec]  ADR / runbook stub (if required by step 8) — always first
      [tests] Test skeletons from DSL declarations + ADR boundary conditions
      [code]  Implementation constrained by test structure
      [migration] mix ash.codegen if schema changes

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

### Tier 1 vs Bash — The Decision Rule

**Tier 1 answers "which?" — bash answers "what?"**

| Answer comes from Tier 1 (already in system prompt) | Answer requires bash                           |
| --------------------------------------------------- | ---------------------------------------------- |
| Which ADRs are relevant to this topic?              | What does ADR-013 §Confidence actually say?    |
| Which modules exist in the Finance domain?          | What attributes does Wallet currently have?    |
| Which INV rules apply to `:sensitive` resources?    | Full text of a specific regulation requirement |
| Does a pattern exist for `transfer` type?           | The actual pattern source code                 |
| Which spec-kit files exist?                         | Contents of a specific spec-kit file           |

Never run bash to answer a question Tier 1 already resolves. Never trust a Tier 1
summary as the full constraint text for a contradiction check — always fetch the full
document. Fetching a document the Tier 1 index says doesn't exist is always wrong.

---

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
{
  "ci": {
    "branch": null,
    "commit": null,
    "context_lock_current": false,
    "last_run_at": null,
    "lint_passed": null,
    "tests_passed": null
  },
  "compiled_at": "2026-04-18T10:44:58Z",
  "compliance": {
    "covered_count": 0,
    "planned_count": 14,
    "requirements": [
      { "coverage": 0, "id": "RG-MGA-001", "status": "planned" },
      { "coverage": 0, "id": "RG-MGA-002", "status": "planned" },
      { "coverage": 0, "id": "RG-MGA-003", "status": "planned" },
      { "coverage": 0, "id": "RG-MGA-005", "status": "planned" },
      { "coverage": 0, "id": "RG-MGA-006", "status": "planned" },
      { "coverage": 0, "id": "RG-MGA-007", "status": "planned" },
      { "coverage": 0, "id": "RG-MGA-009", "status": "planned" },
      { "coverage": 0, "id": "RG-MMA-005", "status": "planned" },
      { "coverage": 0, "id": "RG-UK-002", "status": "planned" },
      { "coverage": 0, "id": "RG-UK-003", "status": "planned" },
      { "coverage": 0, "id": "RG-UK-007", "status": "planned" },
      { "coverage": 0, "id": "RG-UK-008", "status": "planned" },
      { "coverage": 0, "id": "RG-UK-011", "status": "planned" },
      { "coverage": 0, "id": "RG-UK-014", "status": "planned" }
    ],
    "total_requirements": 14
  },
  "domain_type": "igaming",
  "domains": [
    "Accounts",
    "Finance",
    "Gaming",
    "Infrastructure",
    "Ops",
    "Players",
    "Policies",
    "Promotions"
  ],
  "generated_at": "2026-04-18T10:45:06.027735Z",
  "lint": { "errors": 71, "total_violations": 111, "warnings": 40 },
  "manifest": {
    "domain_type": "igaming",
    "sensitive_resources": [
      "Elixir.IgamingRef.Finance.Wallet",
      "Elixir.IgamingRef.Finance.LedgerEntry",
      "Elixir.IgamingRef.Finance.WithdrawalRequest",
      "Elixir.IgamingRef.Players.Player",
      "Elixir.IgamingRef.Players.SelfExclusionRecord"
    ]
  },
  "migrations": { "applied_count": 0, "pending_count": 0 },
  "project": "IgamingRef",
  "project_type": "standard",
  "proposals": { "open_count": 0, "recent": [] },
  "sensitive_modules": [
    "LedgerEntry",
    "Player",
    "SelfExclusionRecord",
    "Wallet",
    "WithdrawalRequest"
  ],
  "stack": {
    "ash": "3.24.3",
    "ash_postgres": "2.9.0",
    "elixir": null,
    "oban": "2.21.1",
    "phoenix": "1.8.5",
    "reactor": "1.0.1"
  },
  "test_coverage": { "e2e": 0, "integration": 0, "unit": 0 }
}
```

## System Architecture (Full Project Context)

All nodes, edges, and governance metadata. Required for agent discovery, scope validation, and impact analysis.

```json
{
  "nodes": [
    {
      "performs": null,
      "relationships": [],
      "adrs": [],
      "last_modified": "2026-04-18 10:42:56",
      "paper_trail": true,
      "telemetry_prefix": [],
      "data_layer": "Elixir.AshPostgres.DataLayer",
      "oban_queues": [],
      "steps": [],
      "module": "IgamingRef.Accounts.Token",
      "outputs": [],
      "rules": [],
      "attributes": [
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "updated_at",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UtcDatetimeUsec"
        },
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "created_at",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UtcDatetimeUsec"
        },
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "extra_data",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.Map"
        },
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "purpose",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.String"
        },
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "expires_at",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UtcDatetime"
        },
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "subject",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.String"
        },
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "jti",
          "pii": false,
          "sensitive": true,
          "type": "Elixir.Ash.Type.String"
        },
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "archived_at",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UtcDatetimeUsec"
        }
      ],
      "rate_limited": false,
      "pending_migrations": false,
      "type": "resource",
      "money_attributes": [],
      "archival": true,
      "api_routes": [],
      "app": null,
      "json_api_routes": [],
      "description": null,
      "id": "IgamingRef.Accounts.Token",
      "provider_behaviour": null,
      "provider_name": null,
      "actions": [
        {
          "description": null,
          "name": "get_token",
          "type": "read"
        },
        {
          "description": null,
          "name": "store_token",
          "type": "create"
        },
        {
          "description": null,
          "name": "store_confirmation_changes",
          "type": "create"
        },
        {
          "description": null,
          "name": "get_confirmation_changes",
          "type": "read"
        },
        {
          "description": null,
          "name": "revoked?",
          "type": "read"
        },
        {
          "description": null,
          "name": "revoke_all_stored_for_subject",
          "type": "update"
        },
        {
          "description": null,
          "name": "revoke_jti",
          "type": "create"
        },
        {
          "description": null,
          "name": "revoke_token",
          "type": "create"
        },
        {
          "description": null,
          "name": "read_expired",
          "type": "read"
        },
        {
          "description": null,
          "name": "expunge_expired",
          "type": "destroy"
        },
        {
          "description": null,
          "name": "destroy",
          "type": "destroy"
        },
        {
          "description": null,
          "name": "read",
          "type": "read"
        }
      ],
      "rule_compliance_links": [],
      "feature_flags": [],
      "vectorized": false,
      "scenario_origins": [],
      "graphql_mutations": [],
      "agent_steps": [],
      "authentication_subject": false,
      "sensitive": false,
      "auth_strategies": [],
      "compliance": [],
      "domain": "Accounts",
      "state_machine": {
        "default_initial_state": null,
        "initial_states": [],
        "present": false,
        "state_attribute": null,
        "states": [],
        "terminal_states": [],
        "transitions": []
      },
      "test_coverage": {
        "e2e_tests": false,
        "property_tests": false,
        "scenario_tests": false
      },
      "runbook": null
    },
    {
      "performs": null,
      "relationships": [],
      "adrs": [],
      "last_modified": "2026-04-18 10:42:56",
      "paper_trail": true,
      "telemetry_prefix": [],
      "data_layer": "Elixir.AshPostgres.DataLayer",
      "oban_queues": [],
      "steps": [],
      "module": "IgamingRef.Accounts.User",
      "outputs": [],
      "rules": [],
      "attributes": [
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "id",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UUID"
        },
        {
          "cldr_backend": null,
          "description": "User email address. Case-insensitive. Used as the authentication identity.",
          "money": false,
          "name": "email",
          "pii": false,
          "sensitive": true,
          "type": "Elixir.Ash.Type.CiString"
        },
        {
          "cldr_backend": null,
          "description": "Bcrypt-hashed password. Never returned in read actions.",
          "money": false,
          "name": "hashed_password",
          "pii": false,
          "sensitive": true,
          "type": "Elixir.Ash.Type.String"
        },
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "inserted_at",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UtcDatetimeUsec"
        },
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "updated_at",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UtcDatetimeUsec"
        },
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "archived_at",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UtcDatetimeUsec"
        }
      ],
      "rate_limited": false,
      "pending_migrations": false,
      "type": "resource",
      "money_attributes": [],
      "archival": true,
      "api_routes": [],
      "app": null,
      "json_api_routes": [],
      "description": null,
      "id": "IgamingRef.Accounts.User",
      "provider_behaviour": null,
      "provider_name": null,
      "actions": [
        {
          "description": null,
          "name": "request_magic_link",
          "type": "read"
        },
        {
          "description": null,
          "name": "sign_in_with_magic_link",
          "type": "read"
        },
        {
          "description": null,
          "name": "password_reset_with_password",
          "type": "update"
        },
        {
          "description": "Send password reset instructions to a user if they exist.",
          "name": "request_password_reset_with_password",
          "type": "read"
        },
        {
          "description": "Attempt to sign in using a short-lived sign in token.",
          "name": "sign_in_with_token",
          "type": "read"
        },
        {
          "description": "Attempt to sign in using a username and password.",
          "name": "sign_in_with_password",
          "type": "read"
        },
        {
          "description": "Register a new user with a username and password.",
          "name": "register_with_password",
          "type": "create"
        },
        {
          "description": null,
          "name": "get_by_subject",
          "type": "read"
        },
        {
          "description": null,
          "name": "read",
          "type": "read"
        }
      ],
      "rule_compliance_links": [],
      "feature_flags": [],
      "vectorized": false,
      "scenario_origins": [],
      "graphql_mutations": [],
      "agent_steps": [],
      "authentication_subject": true,
      "sensitive": false,
      "auth_strategies": [
        {
          "has_password_reset": false,
          "has_sign_in_tokens": false,
          "identity_field": "email",
          "strategy_name": "magic_link",
          "strategy_type": "magiclink",
          "token_resource": null
        },
        {
          "has_password_reset": false,
          "has_sign_in_tokens": false,
          "identity_field": "email",
          "strategy_name": "password",
          "strategy_type": "password",
          "token_resource": null
        }
      ],
      "compliance": [],
      "domain": "Accounts",
      "state_machine": {
        "default_initial_state": null,
        "initial_states": [],
        "present": false,
        "state_attribute": null,
        "states": [],
        "terminal_states": [],
        "transitions": []
      },
      "test_coverage": {
        "e2e_tests": false,
        "property_tests": false,
        "scenario_tests": false
      },
      "runbook": null
    },
    {
      "performs": null,
      "relationships": [
        {
          "description": "The wallet this ledger entry belongs to.",
          "destination_attribute": "id",
          "name": "wallet",
          "related_resource": "IgamingRef.Finance.Wallet",
          "source_attribute": "wallet_id",
          "type": "belongs_to"
        }
      ],
      "adrs": [],
      "last_modified": "2026-04-18 10:44:58",
      "paper_trail": true,
      "telemetry_prefix": [
        "igaming_ref",
        "finance",
        "ledger_entry"
      ],
      "data_layer": "Elixir.AshPostgres.DataLayer",
      "oban_queues": [],
      "steps": [],
      "module": "IgamingRef.Finance.LedgerEntry",
      "outputs": [],
      "rules": [],
      "attributes": [
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "id",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UUID"
        },
        {
          "cldr_backend": null,
          "description": "The wallet this entry belongs to.",
          "money": false,
          "name": "wallet_id",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UUID"
        },
        {
          "cldr_backend": null,
          "description": "The monetary amount of this movement. Always positive \x{2014} direction is conveyed by the :direction attribute.",
          "money": false,
          "name": "amount",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.AshMoney.Types.Money"
        },
        {
          "cldr_backend": null,
          "description": "Whether funds moved into (:credit) or out of (:debit) the wallet.",
          "money": false,
          "name": "direction",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.Atom"
        },
        {
          "cldr_backend": null,
          "description": "The business reason for this movement. Used for reporting and compliance categorisation.",
          "money": false,
          "name": "kind",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.Atom"
        },
        {
          "cldr_backend": null,
          "description": "Unique key preventing duplicate ledger entries for the same financial event. Provided by the calling Transfer.",
          "money": false,
          "name": "idempotency_key",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.String"
        },
        {
          "cldr_backend": null,
          "description": "External reference identifier \x{2014} e.g. the WithdrawalRequest ID or provider transaction reference.",
          "money": false,
          "name": "reference_id",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.String"
        },
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "inserted_at",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UtcDatetimeUsec"
        },
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "archived_at",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UtcDatetimeUsec"
        }
      ],
      "rate_limited": false,
      "pending_migrations": false,
      "type": "resource",
      "money_attributes": [],
      "archival": true,
      "api_routes": [],
      "app": null,
      "json_api_routes": [],
      "description": null,
      "id": "IgamingRef.Finance.LedgerEntry",
      "provider_behaviour": null,
      "provider_name": null,
      "actions": [
        {
          "description": null,
          "name": "read",
          "type": "read"
        },
        {
          "description": "Append a new ledger entry. Called exclusively by Transfer modules \x{2014} never called directly by application code.",
          "name": "record",
          "type": "create"
        }
      ],
      "rule_compliance_links": [],
      "feature_flags": [],
      "vectorized": false,
      "scenario_origins": [],
      "graphql_mutations": [],
      "agent_steps": [],
      "authentication_subject": false,
      "sensitive": true,
      "auth_strategies": [],
      "compliance": [
        "RG_MGA_001",
        "RG_MGA_002",
        "RG_UK_003"
      ],
      "domain": "Finance",
      "state_machine": {
        "default_initial_state": null,
        "initial_states": [],
        "present": false,
        "state_attribute": null,
        "states": [],
        "terminal_states": [],
        "transitions": []
      },
      "test_coverage": {
        "e2e_tests": false,
        "property_tests": false,
        "scenario_tests": false
      },
      "runbook": null
    },
    {
      "performs": null,
      "relationships": [],
      "adrs": [],
      "last_modified": "2026-04-18 10:44:58",
      "paper_trail": false,
      "telemetry_prefix": [],
      "data_layer": null,
      "oban_queues": [],
      "steps": [],
      "module": "IgamingRef.Finance.Rules.PlayerKYCVerified",
      "outputs": [],
      "rules": [],
      "attributes": [],
      "rate_limited": false,
      "pending_migrations": false,
      "type": "rule",
      "money_attributes": [],
      "archival": false,
      "api_routes": [],
      "app": null,
      "json_api_routes": [],
      "description": "Player must have verified KYC status",
      "id": "IgamingRef.Finance.Rules.PlayerKYCVerified",
      "provider_behaviour": null,
      "provider_name": null,
      "actions": [],
      "rule_compliance_links": [],
      "feature_flags": [],
      "vectorized": false,
      "scenario_origins": [],
      "graphql_mutations": [],
      "agent_steps": [],
      "authentication_subject": false,
      "sensitive": false,
      "auth_strategies": [],
      "compliance": [
        "RG_MGA_003"
      ],
      "domain": "Finance",
      "state_machine": {
        "default_initial_state": null,
        "initial_states": [],
        "present": false,
        "state_attribute": null,
        "states": [],
        "terminal_states": [],
        "transitions": []
      },
      "test_coverage": {
        "e2e_tests": false,
        "property_tests": false,
        "scenario_tests": false
      },
      "runbook": null
    },
    {
      "performs": null,
      "relationships": [],
      "adrs": [],
      "last_modified": "2026-04-18 10:44:58",
      "paper_trail": false,
      "telemetry_prefix": [],
      "data_layer": null,
      "oban_queues": [],
      "steps": [],
      "module": "IgamingRef.Finance.Rules.SufficientBalance",
      "outputs": [],
      "rules": [],
      "attributes": [],
      "rate_limited": false,
      "pending_migrations": false,
      "type": "rule",
      "money_attributes": [],
      "archival": false,
      "api_routes": [],
      "app": null,
      "json_api_routes": [],
      "description": "Wallet balance must cover the requested withdrawal amount",
      "id": "IgamingRef.Finance.Rules.SufficientBalance",
      "provider_behaviour": null,
      "provider_name": null,
      "actions": [],
      "rule_compliance_links": [],
      "feature_flags": [],
      "vectorized": false,
      "scenario_origins": [],
      "graphql_mutations": [],
      "agent_steps": [],
      "authentication_subject": false,
      "sensitive": false,
      "auth_strategies": [],
      "compliance": [
        "RG_MGA_001"
      ],
      "domain": "Finance",
      "state_machine": {
        "default_initial_state": null,
        "initial_states": [],
        "present": false,
        "state_attribute": null,
        "states": [],
        "terminal_states": [],
        "transitions": []
      },
      "test_coverage": {
        "e2e_tests": false,
        "property_tests": false,
        "scenario_tests": false
      },
      "runbook": null
    },
    {
      "performs": null,
      "relationships": [],
      "adrs": [],
      "last_modified": "2026-04-18 10:44:58",
      "paper_trail": false,
      "telemetry_prefix": [],
      "data_layer": null,
      "oban_queues": [],
      "steps": [],
      "module": "IgamingRef.Finance.Rules.WithdrawalLimitNotExceeded",
      "outputs": [],
      "rules": [],
      "attributes": [],
      "rate_limited": false,
      "pending_migrations": false,
      "type": "rule",
      "money_attributes": [],
      "archival": false,
      "api_routes": [],
      "app": null,
      "json_api_routes": [],
      "description": "Withdrawal amount must not exceed the player's daily limit",
      "id": "IgamingRef.Finance.Rules.WithdrawalLimitNotExceeded",
      "provider_behaviour": null,
      "provider_name": null,
      "actions": [],
      "rule_compliance_links": [],
      "feature_flags": [],
      "vectorized": false,
      "scenario_origins": [],
      "graphql_mutations": [],
      "agent_steps": [],
      "authentication_subject": false,
      "sensitive": false,
      "auth_strategies": [],
      "compliance": [
        "RG_UK_014",
        "RG_MGA_007"
      ],
      "domain": "Finance",
      "state_machine": {
        "default_initial_state": null,
        "initial_states": [],
        "present": false,
        "state_attribute": null,
        "states": [],
        "terminal_states": [],
        "transitions": []
      },
      "test_coverage": {
        "e2e_tests": false,
        "property_tests": false,
        "scenario_tests": false
      },
      "runbook": null
    },
    {
      "performs": null,
      "relationships": [],
      "adrs": [],
      "last_modified": "2026-04-18 10:44:58",
      "paper_trail": true,
      "telemetry_prefix": [
        "igaming_ref",
        "finance",
        "transfer"
      ],
      "data_layer": "Elixir.AshPostgres.DataLayer",
      "oban_queues": [],
      "steps": [],
      "module": "IgamingRef.Finance.Transfer",
      "outputs": [],
      "rules": [],
      "attributes": [
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "id",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UUID"
        },
        {
          "cldr_backend": null,
          "description": "Source wallet UUID. The wallet funds are debited from.",
          "money": false,
          "name": "from_wallet_id",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UUID"
        },
        {
          "cldr_backend": null,
          "description": "Destination wallet UUID. The wallet funds are credited to.",
          "money": false,
          "name": "to_wallet_id",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UUID"
        },
        {
          "cldr_backend": null,
          "description": "Amount transferred. Must be positive.",
          "money": false,
          "name": "amount",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.AshMoney.Types.Money"
        },
        {
          "cldr_backend": null,
          "description": "Transfer lifecycle state: :pending, :completed, :failed, :cancelled",
          "money": false,
          "name": "status",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.Atom"
        },
        {
          "cldr_backend": null,
          "description": "Reason for the transfer (e.g. 'withdrawal', 'bonus', 'correction')",
          "money": false,
          "name": "reason",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.String"
        },
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "inserted_at",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UtcDatetimeUsec"
        },
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "updated_at",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UtcDatetimeUsec"
        },
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "archived_at",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UtcDatetimeUsec"
        }
      ],
      "rate_limited": false,
      "pending_migrations": false,
      "type": "resource",
      "money_attributes": [],
      "archival": true,
      "api_routes": [],
      "app": null,
      "json_api_routes": [],
      "description": null,
      "id": "IgamingRef.Finance.Transfer",
      "provider_behaviour": null,
      "provider_name": null,
      "actions": [
        {
          "description": null,
          "name": "read",
          "type": "read"
        },
        {
          "description": "Record a new transfer between wallets.",
          "name": "record",
          "type": "create"
        },
        {
          "description": "Mark a transfer as completed.",
          "name": "mark_completed",
          "type": "update"
        },
        {
          "description": "Mark a transfer as failed.",
          "name": "mark_failed",
          "type": "update"
        }
      ],
      "rule_compliance_links": [],
      "feature_flags": [],
      "vectorized": false,
      "scenario_origins": [],
      "graphql_mutations": [],
      "agent_steps": [],
      "authentication_subject": false,
      "sensitive": false,
      "auth_strategies": [],
      "compliance": [
        "RG_MGA_001",
        "RG_UK_003"
      ],
      "domain": "Finance",
      "state_machine": {
        "default_initial_state": null,
        "initial_states": [],
        "present": false,
        "state_attribute": null,
        "states": [],
        "terminal_states": [],
        "transitions": []
      },
      "test_coverage": {
        "e2e_tests": false,
        "property_tests": false,
        "scenario_tests": false
      },
      "runbook": null
    },
    {
      "performs": null,
      "relationships": [
        {
          "description": "The player who owns this wallet.",
          "destination_attribute": "id",
          "name": "player",
          "related_resource": "IgamingRef.Players.Player",
          "source_attribute": "player_id",
          "type": "belongs_to"
        },
        {
          "description": "All financial movements recorded against this wallet.",
          "destination_attribute": "wallet_id",
          "name": "ledger_entries",
          "related_resource": "IgamingRef.Finance.LedgerEntry",
          "source_attribute": "id",
          "type": "has_many"
        },
        {
          "description": "All withdrawal requests initiated from this wallet.",
          "destination_attribute": "wallet_id",
          "name": "withdrawal_requests",
          "related_resource": "IgamingRef.Finance.WithdrawalRequest",
          "source_attribute": "id",
          "type": "has_many"
        }
      ],
      "adrs": [],
      "last_modified": "2026-04-18 10:44:58",
      "paper_trail": true,
      "telemetry_prefix": [
        "igaming_ref",
        "finance",
        "wallet"
      ],
      "data_layer": "Elixir.AshPostgres.DataLayer",
      "oban_queues": [],
      "steps": [],
      "module": "IgamingRef.Finance.Wallet",
      "outputs": [],
      "rules": [],
      "attributes": [
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "id",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UUID"
        },
        {
          "cldr_backend": null,
          "description": "The ID of the player who owns this wallet. References IgamingRef.Players.Player.",
          "money": false,
          "name": "player_id",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UUID"
        },
        {
          "cldr_backend": null,
          "description": "ISO 4217 currency code, e.g. 'GBP', 'EUR', 'USD'. Immutable after creation.",
          "money": false,
          "name": "currency",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.String"
        },
        {
          "cldr_backend": null,
          "description": "Current balance. Must never go negative \x{2014} enforced by the SufficientBalance rule on all debit Transfers (RG-MGA-001).",
          "money": false,
          "name": "balance",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.AshMoney.Types.Money"
        },
        {
          "cldr_backend": null,
          "description": "Lifecycle state of this wallet. Managed by AshStateMachine. :frozen wallets reject debit actions.",
          "money": false,
          "name": "status",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.Atom"
        },
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "inserted_at",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UtcDatetimeUsec"
        },
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "updated_at",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UtcDatetimeUsec"
        },
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "archived_at",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UtcDatetimeUsec"
        },
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "state",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.Atom"
        }
      ],
      "rate_limited": false,
      "pending_migrations": false,
      "type": "resource",
      "money_attributes": [],
      "archival": true,
      "api_routes": [],
      "app": null,
      "json_api_routes": [],
      "description": null,
      "id": "IgamingRef.Finance.Wallet",
      "provider_behaviour": null,
      "provider_name": null,
      "actions": [
        {
          "description": null,
          "name": "destroy",
          "type": "destroy"
        },
        {
          "description": null,
          "name": "read",
          "type": "read"
        },
        {
          "description": "Open a new wallet for a player in the given currency.",
          "name": "create",
          "type": "create"
        },
        {
          "description": "Add funds to the wallet balance. Creates a corresponding LedgerEntry.",
          "name": "credit",
          "type": "update"
        },
        {
          "description": "Remove funds from the wallet balance. Rejected if balance would go negative (RG-MGA-001) or wallet is frozen.",
          "name": "debit",
          "type": "update"
        },
        {
          "description": "Freeze the wallet. Debits are rejected while frozen.",
          "name": "freeze",
          "type": "update"
        },
        {
          "description": "Unfreeze a previously frozen wallet.",
          "name": "unfreeze",
          "type": "update"
        },
        {
          "description": "Permanently close the wallet. Irreversible. Requires zero balance.",
          "name": "close",
          "type": "update"
        }
      ],
      "rule_compliance_links": [],
      "feature_flags": [],
      "vectorized": false,
      "scenario_origins": [],
      "graphql_mutations": [],
      "agent_steps": [],
      "authentication_subject": false,
      "sensitive": true,
      "auth_strategies": [],
      "compliance": [
        "RG_MGA_001",
        "RG_UK_003"
      ],
      "domain": "Finance",
      "state_machine": {
        "default_initial_state": null,
        "initial_states": [],
        "present": false,
        "state_attribute": null,
        "states": [],
        "terminal_states": [],
        "transitions": []
      },
      "test_coverage": {
        "e2e_tests": false,
        "property_tests": false,
        "scenario_tests": false
      },
      "runbook": null
    },
    {
      "performs": null,
      "relationships": [
        {
          "description": "The player who made this withdrawal request.",
          "destination_attribute": "id",
          "name": "player",
          "related_resource": "IgamingRef.Players.Player",
          "source_attribute": "player_id",
          "type": "belongs_to"
        },
        {
          "description": "The wallet funds will be debited from.",
          "destination_attribute": "id",
          "name": "wallet",
          "related_resource": "IgamingRef.Finance.Wallet",
          "source_attribute": "wallet_id",
          "type": "belongs_to"
        }
      ],
      "adrs": [],
      "last_modified": "2026-04-18 10:44:58",
      "paper_trail": true,
      "telemetry_prefix": [
        "igaming_ref",
        "finance",
        "withdrawal_request"
      ],
      "data_layer": "Elixir.AshPostgres.DataLayer",
      "oban_queues": [],
      "steps": [],
      "module": "IgamingRef.Finance.WithdrawalRequest",
      "outputs": [],
      "rules": [],
      "attributes": [
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "id",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UUID"
        },
        {
          "cldr_backend": null,
          "description": "The player who initiated this withdrawal.",
          "money": false,
          "name": "player_id",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UUID"
        },
        {
          "cldr_backend": null,
          "description": "The wallet from which funds will be withdrawn.",
          "money": false,
          "name": "wallet_id",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UUID"
        },
        {
          "cldr_backend": null,
          "description": "The requested withdrawal amount. Validated against the player's daily limit by WithdrawalLimitNotExceeded rule.",
          "money": false,
          "name": "amount",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.AshMoney.Types.Money"
        },
        {
          "cldr_backend": null,
          "description": "Current lifecycle state. Managed by AshStateMachine.",
          "money": false,
          "name": "status",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.Atom"
        },
        {
          "cldr_backend": null,
          "description": "Payment provider identifier (e.g. 'stripe', 'paypal'). Set on approval.",
          "money": false,
          "name": "provider",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.String"
        },
        {
          "cldr_backend": null,
          "description": "Provider-assigned transaction ID. Set when processing begins.",
          "money": false,
          "name": "provider_reference",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.String"
        },
        {
          "cldr_backend": null,
          "description": "Human-readable reason for rejection. Required when status transitions to :rejected.",
          "money": false,
          "name": "rejection_reason",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.String"
        },
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "inserted_at",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UtcDatetimeUsec"
        },
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "updated_at",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UtcDatetimeUsec"
        },
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "archived_at",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UtcDatetimeUsec"
        },
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "state",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.Atom"
        }
      ],
      "rate_limited": false,
      "pending_migrations": false,
      "type": "resource",
      "money_attributes": [],
      "archival": true,
      "api_routes": [],
      "app": null,
      "json_api_routes": [],
      "description": null,
      "id": "IgamingRef.Finance.WithdrawalRequest",
      "provider_behaviour": null,
      "provider_name": null,
      "actions": [
        {
          "description": null,
          "name": "read",
          "type": "read"
        },
        {
          "description": "Submit a new withdrawal request. Initial state is :pending.",
          "name": "create",
          "type": "create"
        },
        {
          "description": "Approve the withdrawal request and record the chosen payment provider.",
          "name": "approve",
          "type": "update"
        },
        {
          "description": "Reject the withdrawal request. rejection_reason is required.",
          "name": "reject",
          "type": "update"
        },
        {
          "description": "Cancel a pending or approved withdrawal request.",
          "name": "cancel",
          "type": "update"
        },
        {
          "description": "Mark the withdrawal as in-flight with the provider. Records the provider reference.",
          "name": "mark_processing",
          "type": "update"
        },
        {
          "description": "Mark the withdrawal as successfully completed.",
          "name": "mark_completed",
          "type": "update"
        }
      ],
      "rule_compliance_links": [],
      "feature_flags": [],
      "vectorized": false,
      "scenario_origins": [],
      "graphql_mutations": [],
      "agent_steps": [],
      "authentication_subject": false,
      "sensitive": true,
      "auth_strategies": [],
      "compliance": [
        "RG_UK_014",
        "RG_MGA_007"
      ],
      "domain": "Finance",
      "state_machine": {
        "default_initial_state": null,
        "initial_states": [],
        "present": false,
        "state_attribute": null,
        "states": [],
        "terminal_states": [],
        "transitions": []
      },
      "test_coverage": {
        "e2e_tests": false,
        "property_tests": false,
        "scenario_tests": false
      },
      "runbook": null
    },
    {
      "performs": null,
      "relationships": [],
      "adrs": [],
      "last_modified": "2026-04-18 10:44:58",
      "paper_trail": false,
      "telemetry_prefix": [
        "igaming_ref",
        "finance",
        "withdrawal_transfer"
      ],
      "data_layer": null,
      "oban_queues": [],
      "steps": [
        {
          "confidence_threshold": null,
          "description": "Load and validate the withdrawal request. Fails fast if request is not in :approved state.",
          "has_compensation": false,
          "name": "load_request",
          "on_low_confidence": null,
          "rules_applied": [],
          "step_index": 0,
          "step_kind": "custom",
          "step_model": null,
          "step_telemetry_prefix": [],
          "step_tools": [],
          "target_action": null,
          "target_module": null,
          "target_resource": "LedgerEntry",
          "type": "step",
          "wait_for": []
        },
        {
          "confidence_threshold": null,
          "description": "Load the player and wallet records needed for rule evaluation.",
          "has_compensation": false,
          "name": "load_player_and_wallet",
          "on_low_confidence": null,
          "rules_applied": [],
          "step_index": 1,
          "step_kind": "custom",
          "step_model": null,
          "step_telemetry_prefix": [],
          "step_tools": [],
          "target_action": null,
          "target_module": null,
          "target_resource": "LedgerEntry",
          "type": "step",
          "wait_for": []
        },
        {
          "confidence_threshold": null,
          "description": "Run all three rules. Fails fast on first rejection \x{2014} no partial application.",
          "has_compensation": false,
          "name": "evaluate_rules",
          "on_low_confidence": null,
          "rules_applied": [],
          "step_index": 2,
          "step_kind": "custom",
          "step_model": null,
          "step_telemetry_prefix": [],
          "step_tools": [],
          "target_action": null,
          "target_module": null,
          "target_resource": "LedgerEntry",
          "type": "step",
          "wait_for": []
        },
        {
          "confidence_threshold": null,
          "description": "Debit the wallet. Atomic with the rule evaluation \x{2014} if this fails, no funds move.",
          "has_compensation": true,
          "name": "debit_wallet",
          "on_low_confidence": null,
          "rules_applied": [],
          "step_index": 3,
          "step_kind": "custom",
          "step_model": null,
          "step_telemetry_prefix": [],
          "step_tools": [],
          "target_action": null,
          "target_module": null,
          "target_resource": "LedgerEntry",
          "type": "step",
          "wait_for": []
        },
        {
          "confidence_threshold": null,
          "description": "Record the debit as an immutable ledger entry.",
          "has_compensation": false,
          "name": "create_ledger_entry",
          "on_low_confidence": null,
          "rules_applied": [],
          "step_index": 4,
          "step_kind": "custom",
          "step_model": null,
          "step_telemetry_prefix": [],
          "step_tools": [],
          "target_action": null,
          "target_module": null,
          "target_resource": "LedgerEntry",
          "type": "step",
          "wait_for": []
        },
        {
          "confidence_threshold": null,
          "description": "Submit the withdrawal to the payment provider. Provider module is determined by request.provider.",
          "has_compensation": false,
          "name": "submit_to_provider",
          "on_low_confidence": null,
          "rules_applied": [],
          "step_index": 5,
          "step_kind": "custom",
          "step_model": null,
          "step_telemetry_prefix": [],
          "step_tools": [],
          "target_action": null,
          "target_module": null,
          "target_resource": "LedgerEntry",
          "type": "step",
          "wait_for": []
        },
        {
          "confidence_threshold": null,
          "description": "Mark the WithdrawalRequest as :processing with the provider reference.",
          "has_compensation": false,
          "name": "update_withdrawal_status",
          "on_low_confidence": null,
          "rules_applied": [],
          "step_index": 6,
          "step_kind": "custom",
          "step_model": null,
          "step_telemetry_prefix": [],
          "step_tools": [],
          "target_action": null,
          "target_module": null,
          "target_resource": "LedgerEntry",
          "type": "step",
          "wait_for": []
        }
      ],
      "module": "IgamingRef.Finance.WithdrawalTransfer",
      "outputs": [],
      "rules": [],
      "attributes": [],
      "rate_limited": false,
      "pending_migrations": false,
      "type": "reactor",
      "money_attributes": [],
      "archival": false,
      "api_routes": [],
      "app": null,
      "json_api_routes": [],
      "description": null,
      "id": "IgamingRef.Finance.WithdrawalTransfer",
      "provider_behaviour": null,
      "provider_name": null,
      "actions": [],
      "rule_compliance_links": [],
      "feature_flags": [],
      "vectorized": false,
      "scenario_origins": [],
      "graphql_mutations": [],
      "agent_steps": [],
      "authentication_subject": false,
      "sensitive": false,
      "auth_strategies": [],
      "compliance": [
        "RG_UK_014",
        "RG_MGA_007"
      ],
      "domain": "Finance",
      "state_machine": {
        "default_initial_state": null,
        "initial_states": [],
        "present": false,
        "state_attribute": null,
        "states": [],
        "terminal_states": [],
        "transitions": []
      },
      "test_coverage": {
        "e2e_tests": false,
        "property_tests": false,
        "scenario_tests": false
      },
      "runbook": "docs/runbooks/withdrawal_transfer.md"
    },
    {
      "performs": null,
      "relationships": [],
      "adrs": [],
      "last_modified": "2026-04-18 10:44:58",
      "paper_trail": false,
      "telemetry_prefix": [
        "igaming_ref",
        "finance",
        "withdrawal_webhook"
      ],
      "data_layer": null,
      "oban_queues": [],
      "steps": [],
      "module": "IgamingRef.Finance.WithdrawalWebhook",
      "outputs": [],
      "rules": [],
      "attributes": [],
      "rate_limited": false,
      "pending_migrations": false,
      "type": "resource",
      "money_attributes": [],
      "archival": false,
      "api_routes": [],
      "app": null,
      "json_api_routes": [],
      "description": null,
      "id": "IgamingRef.Finance.WithdrawalWebhook",
      "provider_behaviour": null,
      "provider_name": null,
      "actions": [],
      "rule_compliance_links": [],
      "feature_flags": [],
      "vectorized": false,
      "scenario_origins": [],
      "graphql_mutations": [],
      "agent_steps": [],
      "authentication_subject": false,
      "sensitive": false,
      "auth_strategies": [],
      "compliance": [
        "RG_UK_014",
        "RG_MGA_007"
      ],
      "domain": "Finance",
      "state_machine": {
        "default_initial_state": null,
        "initial_states": [],
        "present": false,
        "state_attribute": null,
        "states": [],
        "terminal_states": [],
        "transitions": []
      },
      "test_coverage": {
        "e2e_tests": false,
        "property_tests": false,
        "scenario_tests": false
      },
      "runbook": null
    },
    {
      "performs": null,
      "relationships": [],
      "adrs": [],
      "last_modified": "2026-04-18 10:44:58",
      "paper_trail": false,
      "telemetry_prefix": [],
      "data_layer": null,
      "oban_queues": [],
      "steps": [],
      "module": "IgamingRef.Gaming.Adapters.PragmaticPlayV1",
      "outputs": [],
      "rules": [],
      "attributes": [],
      "rate_limited": false,
      "pending_migrations": false,
      "type": "provider",
      "money_attributes": [],
      "archival": false,
      "api_routes": [],
      "app": null,
      "json_api_routes": [],
      "description": null,
      "id": "IgamingRef.Gaming.Adapters.PragmaticPlayV1",
      "provider_behaviour": null,
      "provider_name": null,
      "actions": [],
      "rule_compliance_links": [],
      "feature_flags": [],
      "vectorized": false,
      "scenario_origins": [],
      "graphql_mutations": [],
      "agent_steps": [],
      "authentication_subject": false,
      "sensitive": false,
      "auth_strategies": [],
      "compliance": [
        "RG_MGA_006"
      ],
      "domain": "Gaming",
      "state_machine": {
        "default_initial_state": null,
        "initial_states": [],
        "present": false,
        "state_attribute": null,
        "states": [],
        "terminal_states": [],
        "transitions": []
      },
      "test_coverage": {
        "e2e_tests": false,
        "property_tests": false,
        "scenario_tests": false
      },
      "runbook": null
    },
    {
      "performs": null,
      "relationships": [],
      "adrs": [],
      "last_modified": "2026-04-18 10:44:58",
      "paper_trail": false,
      "telemetry_prefix": [],
      "data_layer": null,
      "oban_queues": [],
      "steps": [],
      "module": "IgamingRef.Gaming.Adapters.PragmaticPlayV2",
      "outputs": [],
      "rules": [],
      "attributes": [],
      "rate_limited": false,
      "pending_migrations": false,
      "type": "provider",
      "money_attributes": [],
      "archival": false,
      "api_routes": [],
      "app": null,
      "json_api_routes": [],
      "description": null,
      "id": "IgamingRef.Gaming.Adapters.PragmaticPlayV2",
      "provider_behaviour": null,
      "provider_name": null,
      "actions": [],
      "rule_compliance_links": [],
      "feature_flags": [],
      "vectorized": false,
      "scenario_origins": [],
      "graphql_mutations": [],
      "agent_steps": [],
      "authentication_subject": false,
      "sensitive": false,
      "auth_strategies": [],
      "compliance": [
        "RG_MGA_006"
      ],
      "domain": "Gaming",
      "state_machine": {
        "default_initial_state": null,
        "initial_states": [],
        "present": false,
        "state_attribute": null,
        "states": [],
        "terminal_states": [],
        "transitions": []
      },
      "test_coverage": {
        "e2e_tests": false,
        "property_tests": false,
        "scenario_tests": false
      },
      "runbook": null
    },
    {
      "performs": "IgamingRef.Gaming.ProviderSyncReactor",
      "relationships": [],
      "adrs": [],
      "last_modified": "2026-04-18 10:44:58",
      "paper_trail": false,
      "telemetry_prefix": [],
      "data_layer": null,
      "oban_queues": [],
      "steps": [],
      "module": "IgamingRef.Gaming.CatalogSyncJob",
      "outputs": [],
      "rules": [],
      "attributes": [],
      "rate_limited": false,
      "pending_migrations": false,
      "type": "job",
      "money_attributes": [],
      "archival": false,
      "api_routes": [],
      "app": null,
      "json_api_routes": [],
      "description": null,
      "id": "IgamingRef.Gaming.CatalogSyncJob",
      "provider_behaviour": null,
      "provider_name": null,
      "actions": [],
      "rule_compliance_links": [],
      "feature_flags": [],
      "vectorized": false,
      "scenario_origins": [],
      "graphql_mutations": [],
      "agent_steps": [],
      "authentication_subject": false,
      "sensitive": false,
      "auth_strategies": [],
      "compliance": [],
      "domain": "Gaming",
      "state_machine": {
        "default_initial_state": null,
        "initial_states": [],
        "present": false,
        "state_attribute": null,
        "states": [],
        "terminal_states": [],
        "transitions": []
      },
      "test_coverage": {
        "e2e_tests": false,
        "property_tests": false,
        "scenario_tests": false
      },
      "runbook": null
    },
    {
      "performs": null,
      "relationships": [],
      "adrs": [],
      "last_modified": "2026-04-18 10:44:58",
      "paper_trail": false,
      "telemetry_prefix": [
        "igaming_ref",
        "gaming",
        "game"
      ],
      "data_layer": "Elixir.AshPostgres.DataLayer",
      "oban_queues": [],
      "steps": [],
      "module": "IgamingRef.Gaming.Game",
      "outputs": [],
      "rules": [],
      "attributes": [
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "id",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UUID"
        },
        {
          "cldr_backend": null,
          "description": "The provider who owns this game.",
          "money": false,
          "name": "provider_id",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UUID"
        },
        {
          "cldr_backend": null,
          "description": "The unique game code as provided by the vendor.",
          "money": false,
          "name": "provider_game_code",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.String"
        },
        {
          "cldr_backend": null,
          "description": "Display name of the game.",
          "money": false,
          "name": "title",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.String"
        },
        {
          "cldr_backend": null,
          "description": "Game category: 'slot', 'table', 'live', 'bingo', etc.",
          "money": false,
          "name": "category",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.String"
        },
        {
          "cldr_backend": null,
          "description": "Return to Player percentage (e.g. 96.5 for 96.5%). Certified value.",
          "money": false,
          "name": "rtp",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.Decimal"
        },
        {
          "cldr_backend": null,
          "description": "Volatility rating: :low, :medium, :high",
          "money": false,
          "name": "volatility",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.Atom"
        },
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "synced_at",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UtcDatetimeUsec"
        },
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "archived_at",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UtcDatetimeUsec"
        }
      ],
      "rate_limited": false,
      "pending_migrations": false,
      "type": "resource",
      "money_attributes": [],
      "archival": true,
      "api_routes": [],
      "app": null,
      "json_api_routes": [],
      "description": null,
      "id": "IgamingRef.Gaming.Game",
      "provider_behaviour": null,
      "provider_name": null,
      "actions": [
        {
          "description": null,
          "name": "read",
          "type": "read"
        },
        {
          "description": "Sync a game from provider catalog. Internal use only.",
          "name": "sync",
          "type": "create"
        }
      ],
      "rule_compliance_links": [],
      "feature_flags": [],
      "vectorized": false,
      "scenario_origins": [],
      "graphql_mutations": [],
      "agent_steps": [],
      "authentication_subject": false,
      "sensitive": false,
      "auth_strategies": [],
      "compliance": [
        "RG_MGA_006",
        "RG_UK_007"
      ],
      "domain": "Gaming",
      "state_machine": {
        "default_initial_state": null,
        "initial_states": [],
        "present": false,
        "state_attribute": null,
        "states": [],
        "terminal_states": [],
        "transitions": []
      },
      "test_coverage": {
        "e2e_tests": false,
        "property_tests": false,
        "scenario_tests": false
      },
      "runbook": null
    },
    {
      "performs": null,
      "relationships": [],
      "adrs": [],
      "last_modified": "2026-04-18 10:44:58",
      "paper_trail": false,
      "telemetry_prefix": [
        "igaming_ref",
        "gaming",
        "game_catalog"
      ],
      "data_layer": "Elixir.AshPostgres.DataLayer",
      "oban_queues": [],
      "steps": [],
      "module": "IgamingRef.Gaming.GameCatalog",
      "outputs": [],
      "rules": [],
      "attributes": [
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "id",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UUID"
        },
        {
          "cldr_backend": null,
          "description": "The game in the catalog.",
          "money": false,
          "name": "game_id",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UUID"
        },
        {
          "cldr_backend": null,
          "description": "The currently active version of this game.",
          "money": false,
          "name": "current_version_id",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UUID"
        },
        {
          "cldr_backend": null,
          "description": "Comma-separated list of region codes where this game is available.",
          "money": false,
          "name": "available_regions",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.String"
        },
        {
          "cldr_backend": null,
          "description": "When this game was added to the catalog.",
          "money": false,
          "name": "published_at",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UtcDatetime"
        },
        {
          "cldr_backend": null,
          "description": "Whether the game is hidden from player-facing catalog.",
          "money": false,
          "name": "hidden",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.Boolean"
        },
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "inserted_at",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UtcDatetimeUsec"
        },
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "archived_at",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UtcDatetimeUsec"
        }
      ],
      "rate_limited": false,
      "pending_migrations": false,
      "type": "resource",
      "money_attributes": [],
      "archival": true,
      "api_routes": [],
      "app": null,
      "json_api_routes": [],
      "description": null,
      "id": "IgamingRef.Gaming.GameCatalog",
      "provider_behaviour": null,
      "provider_name": null,
      "actions": [
        {
          "description": null,
          "name": "read",
          "type": "read"
        },
        {
          "description": "Add a game to the catalog. Internal use only.",
          "name": "add_to_catalog",
          "type": "create"
        },
        {
          "description": "Hide a game from the player-facing catalog.",
          "name": "hide",
          "type": "update"
        },
        {
          "description": "Show a previously hidden game in the catalog.",
          "name": "show",
          "type": "update"
        }
      ],
      "rule_compliance_links": [],
      "feature_flags": [],
      "vectorized": false,
      "scenario_origins": [],
      "graphql_mutations": [],
      "agent_steps": [],
      "authentication_subject": false,
      "sensitive": false,
      "auth_strategies": [],
      "compliance": [
        "RG_UK_007",
        "RG_MGA_006"
      ],
      "domain": "Gaming",
      "state_machine": {
        "default_initial_state": null,
        "initial_states": [],
        "present": false,
        "state_attribute": null,
        "states": [],
        "terminal_states": [],
        "transitions": []
      },
      "test_coverage": {
        "e2e_tests": false,
        "property_tests": false,
        "scenario_tests": false
      },
      "runbook": null
    },
    {
      "performs": null,
      "relationships": [],
      "adrs": [],
      "last_modified": "2026-04-18 10:44:58",
      "paper_trail": false,
      "telemetry_prefix": [
        "igaming_ref",
        "gaming",
        "game_version"
      ],
      "data_layer": "Elixir.AshPostgres.DataLayer",
      "oban_queues": [],
      "steps": [],
      "module": "IgamingRef.Gaming.GameVersion",
      "outputs": [],
      "rules": [],
      "attributes": [
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "id",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UUID"
        },
        {
          "cldr_backend": null,
          "description": "The game this version belongs to.",
          "money": false,
          "name": "game_id",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UUID"
        },
        {
          "cldr_backend": null,
          "description": "Provider's version identifier (e.g. '1.2.3' or 'v5').",
          "money": false,
          "name": "version_code",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.String"
        },
        {
          "cldr_backend": null,
          "description": "Version status: :active, :deprecated, :testing",
          "money": false,
          "name": "status",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.Atom"
        },
        {
          "cldr_backend": null,
          "description": "When this version was released by the provider.",
          "money": false,
          "name": "release_date",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.Date"
        },
        {
          "cldr_backend": null,
          "description": "Whether this specific version is RTP-certified.",
          "money": false,
          "name": "rtp_certified",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.Boolean"
        },
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "synced_at",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UtcDatetimeUsec"
        },
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "archived_at",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UtcDatetimeUsec"
        }
      ],
      "rate_limited": false,
      "pending_migrations": false,
      "type": "resource",
      "money_attributes": [],
      "archival": true,
      "api_routes": [],
      "app": null,
      "json_api_routes": [],
      "description": null,
      "id": "IgamingRef.Gaming.GameVersion",
      "provider_behaviour": null,
      "provider_name": null,
      "actions": [
        {
          "description": null,
          "name": "read",
          "type": "read"
        },
        {
          "description": "Sync a game version from provider. Internal use only.",
          "name": "sync",
          "type": "create"
        },
        {
          "description": "Mark this version as the active version.",
          "name": "mark_active",
          "type": "update"
        },
        {
          "description": "Mark this version as deprecated.",
          "name": "mark_deprecated",
          "type": "update"
        }
      ],
      "rule_compliance_links": [],
      "feature_flags": [],
      "vectorized": false,
      "scenario_origins": [],
      "graphql_mutations": [],
      "agent_steps": [],
      "authentication_subject": false,
      "sensitive": false,
      "auth_strategies": [],
      "compliance": [
        "RG_UK_007",
        "RG_MGA_006"
      ],
      "domain": "Gaming",
      "state_machine": {
        "default_initial_state": null,
        "initial_states": [],
        "present": false,
        "state_attribute": null,
        "states": [],
        "terminal_states": [],
        "transitions": []
      },
      "test_coverage": {
        "e2e_tests": false,
        "property_tests": false,
        "scenario_tests": false
      },
      "runbook": null
    },
    {
      "performs": null,
      "relationships": [],
      "adrs": [],
      "last_modified": "2026-04-18 10:44:58",
      "paper_trail": true,
      "telemetry_prefix": [
        "igaming_ref",
        "gaming",
        "provider_config"
      ],
      "data_layer": "Elixir.AshPostgres.DataLayer",
      "oban_queues": [],
      "steps": [],
      "module": "IgamingRef.Gaming.ProviderConfig",
      "outputs": [],
      "rules": [],
      "attributes": [
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "id",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UUID"
        },
        {
          "cldr_backend": null,
          "description": "Name of the provider: 'pragmatic_play', 'netent', etc.",
          "money": false,
          "name": "provider_name",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.String"
        },
        {
          "cldr_backend": null,
          "description": "The base URL for provider API calls.",
          "money": false,
          "name": "api_endpoint",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.String"
        },
        {
          "cldr_backend": null,
          "description": "Encrypted API key or client ID for authentication.",
          "money": false,
          "name": "api_key",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.String"
        },
        {
          "cldr_backend": null,
          "description": "Configuration status: :active, :inactive, :testing",
          "money": false,
          "name": "status",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.Atom"
        },
        {
          "cldr_backend": null,
          "description": "Whether this provider's games are RTP-certified by jurisdiction.",
          "money": false,
          "name": "rtp_certified",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.Boolean"
        },
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "inserted_at",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UtcDatetimeUsec"
        },
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "updated_at",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UtcDatetimeUsec"
        },
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "archived_at",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UtcDatetimeUsec"
        }
      ],
      "rate_limited": false,
      "pending_migrations": false,
      "type": "resource",
      "money_attributes": [],
      "archival": true,
      "api_routes": [],
      "app": null,
      "json_api_routes": [],
      "description": null,
      "id": "IgamingRef.Gaming.ProviderConfig",
      "provider_behaviour": null,
      "provider_name": null,
      "actions": [
        {
          "description": null,
          "name": "read",
          "type": "read"
        },
        {
          "description": "Create a new provider configuration.",
          "name": "create",
          "type": "create"
        },
        {
          "description": "Update the configuration status.",
          "name": "update_status",
          "type": "update"
        },
        {
          "description": "Mark provider as RTP-certified.",
          "name": "mark_certified",
          "type": "update"
        }
      ],
      "rule_compliance_links": [],
      "feature_flags": [],
      "vectorized": false,
      "scenario_origins": [],
      "graphql_mutations": [],
      "agent_steps": [],
      "authentication_subject": false,
      "sensitive": false,
      "auth_strategies": [],
      "compliance": [
        "RG_MGA_006"
      ],
      "domain": "Gaming",
      "state_machine": {
        "default_initial_state": null,
        "initial_states": [],
        "present": false,
        "state_attribute": null,
        "states": [],
        "terminal_states": [],
        "transitions": []
      },
      "test_coverage": {
        "e2e_tests": false,
        "property_tests": false,
        "scenario_tests": false
      },
      "runbook": null
    },
    {
      "performs": null,
      "relationships": [],
      "adrs": [],
      "last_modified": "2026-04-18 10:44:58",
      "paper_trail": false,
      "telemetry_prefix": [
        "igaming_ref",
        "gaming",
        "provider_sync"
      ],
      "data_layer": null,
      "oban_queues": [],
      "steps": [
        {
          "confidence_threshold": null,
          "description": "Load and validate the provider configuration.",
          "has_compensation": false,
          "name": "load_provider",
          "on_low_confidence": null,
          "rules_applied": [],
          "step_index": 0,
          "step_kind": "custom",
          "step_model": null,
          "step_telemetry_prefix": [],
          "step_tools": [],
          "target_action": null,
          "target_module": null,
          "target_resource": "Game",
          "type": "step",
          "wait_for": []
        },
        {
          "confidence_threshold": null,
          "description": "Fetch the game list from the provider API.",
          "has_compensation": false,
          "name": "fetch_games",
          "on_low_confidence": null,
          "rules_applied": [],
          "step_index": 1,
          "step_kind": "custom",
          "step_model": null,
          "step_telemetry_prefix": [],
          "step_tools": [],
          "target_action": null,
          "target_module": null,
          "target_resource": "Game",
          "type": "step",
          "wait_for": []
        },
        {
          "confidence_threshold": null,
          "description": "Sync each game from the fetched list.",
          "has_compensation": false,
          "name": "sync_games",
          "on_low_confidence": null,
          "rules_applied": [],
          "step_index": 2,
          "step_kind": "custom",
          "step_model": null,
          "step_telemetry_prefix": [],
          "step_tools": [],
          "target_action": null,
          "target_module": null,
          "target_resource": "Game",
          "type": "step",
          "wait_for": []
        },
        {
          "confidence_threshold": null,
          "description": "Update GameCatalog entries for the synced games.",
          "has_compensation": false,
          "name": "update_catalog",
          "on_low_confidence": null,
          "rules_applied": [],
          "step_index": 3,
          "step_kind": "custom",
          "step_model": null,
          "step_telemetry_prefix": [],
          "step_tools": [],
          "target_action": null,
          "target_module": null,
          "target_resource": null,
          "type": "step",
          "wait_for": []
        }
      ],
      "module": "IgamingRef.Gaming.ProviderSyncReactor",
      "outputs": [],
      "rules": [],
      "attributes": [],
      "rate_limited": false,
      "pending_migrations": false,
      "type": "reactor",
      "money_attributes": [],
      "archival": false,
      "api_routes": [],
      "app": null,
      "json_api_routes": [],
      "description": null,
      "id": "IgamingRef.Gaming.ProviderSyncReactor",
      "provider_behaviour": null,
      "provider_name": null,
      "actions": [],
      "rule_compliance_links": [],
      "feature_flags": [],
      "vectorized": false,
      "scenario_origins": [],
      "graphql_mutations": [],
      "agent_steps": [],
      "authentication_subject": false,
      "sensitive": false,
      "auth_strategies": [],
      "compliance": [
        "RG_MGA_006",
        "RG_UK_007"
      ],
      "domain": "Gaming",
      "state_machine": {
        "default_initial_state": null,
        "initial_states": [],
        "present": false,
        "state_attribute": null,
        "states": [],
        "terminal_states": [],
        "transitions": []
      },
      "test_coverage": {
        "e2e_tests": false,
        "property_tests": false,
        "scenario_tests": false
      },
      "runbook": "docs/runbooks/provider_sync.md"
    },
    {
      "performs": null,
      "relationships": [],
      "adrs": [],
      "last_modified": "2026-04-18 10:44:58",
      "paper_trail": false,
      "telemetry_prefix": [],
      "data_layer": null,
      "oban_queues": [],
      "steps": [],
      "module": "IgamingRef.Gaming.Rules.GameRTPCertified",
      "outputs": [],
      "rules": [],
      "attributes": [],
      "rate_limited": false,
      "pending_migrations": false,
      "type": "rule",
      "money_attributes": [],
      "archival": false,
      "api_routes": [],
      "app": null,
      "json_api_routes": [],
      "description": "Game version must be RTP-certified",
      "id": "IgamingRef.Gaming.Rules.GameRTPCertified",
      "provider_behaviour": null,
      "provider_name": null,
      "actions": [],
      "rule_compliance_links": [],
      "feature_flags": [],
      "vectorized": false,
      "scenario_origins": [],
      "graphql_mutations": [],
      "agent_steps": [],
      "authentication_subject": false,
      "sensitive": false,
      "auth_strategies": [],
      "compliance": [
        "RG_UK_007"
      ],
      "domain": "Gaming",
      "state_machine": {
        "default_initial_state": null,
        "initial_states": [],
        "present": false,
        "state_attribute": null,
        "states": [],
        "terminal_states": [],
        "transitions": []
      },
      "test_coverage": {
        "e2e_tests": false,
        "property_tests": false,
        "scenario_tests": false
      },
      "runbook": null
    },
    {
      "performs": null,
      "relationships": [],
      "adrs": [],
      "last_modified": "2026-04-18 10:44:58",
      "paper_trail": false,
      "telemetry_prefix": [],
      "data_layer": null,
      "oban_queues": [],
      "steps": [],
      "module": "IgamingRef.Gaming.Rules.ProviderActive",
      "outputs": [],
      "rules": [],
      "attributes": [],
      "rate_limited": false,
      "pending_migrations": false,
      "type": "rule",
      "money_attributes": [],
      "archival": false,
      "api_routes": [],
      "app": null,
      "json_api_routes": [],
      "description": "Provider must be in active status",
      "id": "IgamingRef.Gaming.Rules.ProviderActive",
      "provider_behaviour": null,
      "provider_name": null,
      "actions": [],
      "rule_compliance_links": [],
      "feature_flags": [],
      "vectorized": false,
      "scenario_origins": [],
      "graphql_mutations": [],
      "agent_steps": [],
      "authentication_subject": false,
      "sensitive": false,
      "auth_strategies": [],
      "compliance": [
        "RG_MGA_006"
      ],
      "domain": "Gaming",
      "state_machine": {
        "default_initial_state": null,
        "initial_states": [],
        "present": false,
        "state_attribute": null,
        "states": [],
        "terminal_states": [],
        "transitions": []
      },
      "test_coverage": {
        "e2e_tests": false,
        "property_tests": false,
        "scenario_tests": false
      },
      "runbook": null
    },
    {
      "performs": null,
      "relationships": [],
      "adrs": [],
      "last_modified": "2026-04-18 10:44:58",
      "paper_trail": false,
      "telemetry_prefix": [
        "igaming_ref",
        "ops",
        "audit_entry"
      ],
      "data_layer": "Elixir.AshPostgres.DataLayer",
      "oban_queues": [],
      "steps": [],
      "module": "IgamingRef.Ops.AuditEntry",
      "outputs": [],
      "rules": [],
      "attributes": [
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "id",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UUID"
        },
        {
          "cldr_backend": null,
          "description": "The user or system actor performing the action.",
          "money": false,
          "name": "actor_id",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UUID"
        },
        {
          "cldr_backend": null,
          "description": "Type of actor: 'user', 'system', 'service', etc.",
          "money": false,
          "name": "actor_type",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.String"
        },
        {
          "cldr_backend": null,
          "description": "The action performed: 'create', 'update', 'delete', 'suspend', etc.",
          "money": false,
          "name": "action",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.String"
        },
        {
          "cldr_backend": null,
          "description": "The resource type affected: 'Player', 'Wallet', 'WithdrawalRequest', etc.",
          "money": false,
          "name": "resource_type",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.String"
        },
        {
          "cldr_backend": null,
          "description": "The specific resource affected.",
          "money": false,
          "name": "resource_id",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UUID"
        },
        {
          "cldr_backend": null,
          "description": "JSON map of attribute changes. Nil if no attributes changed.",
          "money": false,
          "name": "changes",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.Map"
        },
        {
          "cldr_backend": null,
          "description": "Why the action was performed. Audit evidence.",
          "money": false,
          "name": "reason",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.String"
        },
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "recorded_at",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UtcDatetimeUsec"
        },
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "archived_at",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UtcDatetimeUsec"
        }
      ],
      "rate_limited": false,
      "pending_migrations": false,
      "type": "resource",
      "money_attributes": [],
      "archival": true,
      "api_routes": [],
      "app": null,
      "json_api_routes": [],
      "description": null,
      "id": "IgamingRef.Ops.AuditEntry",
      "provider_behaviour": null,
      "provider_name": null,
      "actions": [
        {
          "description": null,
          "name": "read",
          "type": "read"
        },
        {
          "description": "Record an audit entry. Internal use only.",
          "name": "record",
          "type": "create"
        }
      ],
      "rule_compliance_links": [],
      "feature_flags": [],
      "vectorized": false,
      "scenario_origins": [],
      "graphql_mutations": [],
      "agent_steps": [],
      "authentication_subject": false,
      "sensitive": false,
      "auth_strategies": [],
      "compliance": [
        "RG_MGA_002"
      ],
      "domain": "Ops",
      "state_machine": {
        "default_initial_state": null,
        "initial_states": [],
        "present": false,
        "state_attribute": null,
        "states": [],
        "terminal_states": [],
        "transitions": []
      },
      "test_coverage": {
        "e2e_tests": false,
        "property_tests": false,
        "scenario_tests": false
      },
      "runbook": null
    },
    {
      "performs": null,
      "relationships": [
        {
          "description": "The player this PII belongs to.",
          "destination_attribute": "id",
          "name": "player",
          "related_resource": "IgamingRef.Players.Player",
          "source_attribute": "player_id",
          "type": "belongs_to"
        }
      ],
      "adrs": [],
      "last_modified": "2026-04-18 10:44:58",
      "paper_trail": true,
      "telemetry_prefix": [
        "igaming_ref",
        "ops",
        "pii_vault"
      ],
      "data_layer": "Elixir.AshPostgres.DataLayer",
      "oban_queues": [],
      "steps": [],
      "module": "IgamingRef.Ops.PIIVault",
      "outputs": [],
      "rules": [],
      "attributes": [
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "id",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UUID"
        },
        {
          "cldr_backend": null,
          "description": "The player this PII belongs to.",
          "money": false,
          "name": "player_id",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UUID"
        },
        {
          "cldr_backend": null,
          "description": "Type of PII stored: :name, :ssn, :phone, :address, :passport, :driver_license",
          "money": false,
          "name": "pii_type",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.Atom"
        },
        {
          "cldr_backend": null,
          "description": "The encrypted PII value. Never returned in queries unless explicitly unencrypted.",
          "money": false,
          "name": "encrypted_value",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.String"
        },
        {
          "cldr_backend": null,
          "description": "HMAC hash of the PII for duplicate detection without decryption.",
          "money": false,
          "name": "hash_digest",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.String"
        },
        {
          "cldr_backend": null,
          "description": "When this PII was last accessed. Nil if never accessed.",
          "money": false,
          "name": "last_accessed_at",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UtcDatetime"
        },
        {
          "cldr_backend": null,
          "description": "Number of times this PII has been accessed.",
          "money": false,
          "name": "access_count",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.Integer"
        },
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "inserted_at",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UtcDatetimeUsec"
        },
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "updated_at",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UtcDatetimeUsec"
        },
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "archived_at",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UtcDatetimeUsec"
        }
      ],
      "rate_limited": false,
      "pending_migrations": false,
      "type": "resource",
      "money_attributes": [],
      "archival": true,
      "api_routes": [],
      "app": null,
      "json_api_routes": [],
      "description": null,
      "id": "IgamingRef.Ops.PIIVault",
      "provider_behaviour": null,
      "provider_name": null,
      "actions": [
        {
          "description": null,
          "name": "read",
          "type": "read"
        },
        {
          "description": "Store encrypted PII in the vault.",
          "name": "store",
          "type": "create"
        },
        {
          "description": "Retrieve PII with decryption. Requires elevated permissions.",
          "name": "read_sensitive",
          "type": "read"
        },
        {
          "description": "Update last_accessed_at and increment access_count.",
          "name": "touch_accessed",
          "type": "update"
        }
      ],
      "rule_compliance_links": [],
      "feature_flags": [],
      "vectorized": false,
      "scenario_origins": [],
      "graphql_mutations": [],
      "agent_steps": [],
      "authentication_subject": false,
      "sensitive": false,
      "auth_strategies": [],
      "compliance": [
        "RG_MGA_002",
        "RG_UK_002"
      ],
      "domain": "Ops",
      "state_machine": {
        "default_initial_state": null,
        "initial_states": [],
        "present": false,
        "state_attribute": null,
        "states": [],
        "terminal_states": [],
        "transitions": []
      },
      "test_coverage": {
        "e2e_tests": false,
        "property_tests": false,
        "scenario_tests": false
      },
      "runbook": null
    },
    {
      "performs": null,
      "relationships": [
        {
          "description": "The player who submitted this document.",
          "destination_attribute": "id",
          "name": "player",
          "related_resource": "IgamingRef.Players.Player",
          "source_attribute": "player_id",
          "type": "belongs_to"
        }
      ],
      "adrs": [],
      "last_modified": "2026-04-18 10:44:58",
      "paper_trail": true,
      "telemetry_prefix": [
        "igaming_ref",
        "players",
        "kyc_document"
      ],
      "data_layer": "Elixir.AshPostgres.DataLayer",
      "oban_queues": [],
      "steps": [],
      "module": "IgamingRef.Players.KYCDocument",
      "outputs": [],
      "rules": [],
      "attributes": [
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "id",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UUID"
        },
        {
          "cldr_backend": null,
          "description": "The player who submitted this document.",
          "money": false,
          "name": "player_id",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UUID"
        },
        {
          "cldr_backend": null,
          "description": "Reference to the KYCUploadToken that authorized this upload.",
          "money": false,
          "name": "upload_token_id",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UUID"
        },
        {
          "cldr_backend": null,
          "description": "Type of document: :passport, :drivers_license, :national_id, :proof_of_address",
          "money": false,
          "name": "document_type",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.Atom"
        },
        {
          "cldr_backend": null,
          "description": "Path to the encrypted document in secure storage.",
          "money": false,
          "name": "storage_path",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.String"
        },
        {
          "cldr_backend": null,
          "description": "Verification status: :pending, :verified, :rejected",
          "money": false,
          "name": "status",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.Atom"
        },
        {
          "cldr_backend": null,
          "description": "If rejected, the reason why. Nil if status is not :rejected.",
          "money": false,
          "name": "rejection_reason",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.String"
        },
        {
          "cldr_backend": null,
          "description": "Timestamp of verification. Nil until verified.",
          "money": false,
          "name": "verified_at",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UtcDatetime"
        },
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "inserted_at",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UtcDatetimeUsec"
        },
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "archived_at",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UtcDatetimeUsec"
        }
      ],
      "rate_limited": false,
      "pending_migrations": false,
      "type": "resource",
      "money_attributes": [],
      "archival": true,
      "api_routes": [],
      "app": null,
      "json_api_routes": [],
      "description": null,
      "id": "IgamingRef.Players.KYCDocument",
      "provider_behaviour": null,
      "provider_name": null,
      "actions": [
        {
          "description": null,
          "name": "read",
          "type": "read"
        },
        {
          "description": "Upload a new KYC document.",
          "name": "upload",
          "type": "create"
        },
        {
          "description": "Mark document as verified after compliance review.",
          "name": "mark_verified",
          "type": "update"
        },
        {
          "description": "Mark document as rejected with a reason.",
          "name": "mark_rejected",
          "type": "update"
        }
      ],
      "rule_compliance_links": [],
      "feature_flags": [],
      "vectorized": false,
      "scenario_origins": [],
      "graphql_mutations": [],
      "agent_steps": [],
      "authentication_subject": false,
      "sensitive": false,
      "auth_strategies": [],
      "compliance": [
        "RG_MGA_003",
        "RG_UK_002"
      ],
      "domain": "Players",
      "state_machine": {
        "default_initial_state": null,
        "initial_states": [],
        "present": false,
        "state_attribute": null,
        "states": [],
        "terminal_states": [],
        "transitions": []
      },
      "test_coverage": {
        "e2e_tests": false,
        "property_tests": false,
        "scenario_tests": false
      },
      "runbook": null
    },
    {
      "performs": null,
      "relationships": [
        {
          "description": "The player authorized to upload with this token.",
          "destination_attribute": "id",
          "name": "player",
          "related_resource": "IgamingRef.Players.Player",
          "source_attribute": "player_id",
          "type": "belongs_to"
        }
      ],
      "adrs": [],
      "last_modified": "2026-04-18 10:44:58",
      "paper_trail": false,
      "telemetry_prefix": [
        "igaming_ref",
        "players",
        "kyc_upload_token"
      ],
      "data_layer": "Elixir.AshPostgres.DataLayer",
      "oban_queues": [],
      "steps": [],
      "module": "IgamingRef.Players.KYCUploadToken",
      "outputs": [],
      "rules": [],
      "attributes": [
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "id",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UUID"
        },
        {
          "cldr_backend": null,
          "description": "The player authorized to upload with this token.",
          "money": false,
          "name": "player_id",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UUID"
        },
        {
          "cldr_backend": null,
          "description": "The opaque token string. Used as authorization header in upload requests.",
          "money": false,
          "name": "token",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.String"
        },
        {
          "cldr_backend": null,
          "description": "Token expiration time. After this, uploads are rejected.",
          "money": false,
          "name": "expires_at",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UtcDatetime"
        },
        {
          "cldr_backend": null,
          "description": "When the token was used to upload a document. Nil if not yet consumed.",
          "money": false,
          "name": "consumed_at",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UtcDatetime"
        },
        {
          "cldr_backend": null,
          "description": "The KYCDocument that used this token. Nil if not yet consumed.",
          "money": false,
          "name": "consumed_by_document_id",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UUID"
        },
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "created_at",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UtcDatetimeUsec"
        },
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "archived_at",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UtcDatetimeUsec"
        }
      ],
      "rate_limited": false,
      "pending_migrations": false,
      "type": "resource",
      "money_attributes": [],
      "archival": true,
      "api_routes": [],
      "app": null,
      "json_api_routes": [],
      "description": null,
      "id": "IgamingRef.Players.KYCUploadToken",
      "provider_behaviour": null,
      "provider_name": null,
      "actions": [
        {
          "description": null,
          "name": "read",
          "type": "read"
        },
        {
          "description": "Generate a new upload token for a player.",
          "name": "generate",
          "type": "create"
        },
        {
          "description": "Mark the token as consumed by a KYC document upload.",
          "name": "mark_consumed",
          "type": "update"
        }
      ],
      "rule_compliance_links": [],
      "feature_flags": [],
      "vectorized": false,
      "scenario_origins": [],
      "graphql_mutations": [],
      "agent_steps": [],
      "authentication_subject": false,
      "sensitive": false,
      "auth_strategies": [],
      "compliance": [
        "RG_MGA_003",
        "RG_UK_002"
      ],
      "domain": "Players",
      "state_machine": {
        "default_initial_state": null,
        "initial_states": [],
        "present": false,
        "state_attribute": null,
        "states": [],
        "terminal_states": [],
        "transitions": []
      },
      "test_coverage": {
        "e2e_tests": false,
        "property_tests": false,
        "scenario_tests": false
      },
      "runbook": null
    },
    {
      "performs": null,
      "relationships": [
        {
          "description": "All wallets belonging to this player.",
          "destination_attribute": "player_id",
          "name": "wallets",
          "related_resource": "IgamingRef.Finance.Wallet",
          "source_attribute": "id",
          "type": "has_many"
        },
        {
          "description": "All withdrawal requests initiated by this player.",
          "destination_attribute": "player_id",
          "name": "withdrawal_requests",
          "related_resource": "IgamingRef.Finance.WithdrawalRequest",
          "source_attribute": "id",
          "type": "has_many"
        },
        {
          "description": "All self-exclusion events for this player.",
          "destination_attribute": "player_id",
          "name": "self_exclusion_records",
          "related_resource": "IgamingRef.Players.SelfExclusionRecord",
          "source_attribute": "id",
          "type": "has_many"
        }
      ],
      "adrs": [],
      "last_modified": "2026-04-18 10:44:58",
      "paper_trail": true,
      "telemetry_prefix": [
        "igaming_ref",
        "players",
        "player"
      ],
      "data_layer": "Elixir.AshPostgres.DataLayer",
      "oban_queues": [],
      "steps": [],
      "module": "IgamingRef.Players.Player",
      "outputs": [],
      "rules": [],
      "attributes": [
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "id",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UUID"
        },
        {
          "cldr_backend": null,
          "description": "Player's email address. Case-insensitive unique identifier.",
          "money": false,
          "name": "email",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.CiString"
        },
        {
          "cldr_backend": null,
          "description": "Player's chosen display name. Unique.",
          "money": false,
          "name": "username",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.String"
        },
        {
          "cldr_backend": null,
          "description": "Player's date of birth. Used for age verification (RG-UK-002).",
          "money": false,
          "name": "date_of_birth",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.Date"
        },
        {
          "cldr_backend": null,
          "description": "ISO 3166-1 alpha-2 country code. Determines applicable regulations.",
          "money": false,
          "name": "country_code",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.String"
        },
        {
          "cldr_backend": null,
          "description": "Know-Your-Customer verification status. Players must reach :verified before withdrawals are permitted (RG-MGA-003).",
          "money": false,
          "name": "kyc_status",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.Atom"
        },
        {
          "cldr_backend": null,
          "description": "Operator-assigned risk classification. Used for transaction monitoring thresholds.",
          "money": false,
          "name": "risk_level",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.Atom"
        },
        {
          "cldr_backend": null,
          "description": "Account lifecycle state. Managed by AshStateMachine.",
          "money": false,
          "name": "status",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.Atom"
        },
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "inserted_at",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UtcDatetimeUsec"
        },
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "updated_at",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UtcDatetimeUsec"
        },
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "archived_at",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UtcDatetimeUsec"
        },
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "state",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.Atom"
        }
      ],
      "rate_limited": false,
      "pending_migrations": false,
      "type": "resource",
      "money_attributes": [],
      "archival": true,
      "api_routes": [],
      "app": null,
      "json_api_routes": [],
      "description": null,
      "id": "IgamingRef.Players.Player",
      "provider_behaviour": null,
      "provider_name": null,
      "actions": [
        {
          "description": null,
          "name": "read",
          "type": "read"
        },
        {
          "description": "Register a new player account. Initial kyc_status is :unverified.",
          "name": "register",
          "type": "create"
        },
        {
          "description": "Update the KYC verification status. Called by the KYC provider integration.",
          "name": "update_kyc_status",
          "type": "update"
        },
        {
          "description": "Suspend a player account. Blocks login and financial activity.",
          "name": "suspend",
          "type": "update"
        },
        {
          "description": "Reinstate a suspended player.",
          "name": "reinstate",
          "type": "update"
        },
        {
          "description": "Record a player's self-exclusion request. Creates a SelfExclusionRecord and transitions status (RG-UK-008).",
          "name": "self_exclude",
          "type": "update"
        },
        {
          "description": "Permanently close a player account.",
          "name": "close",
          "type": "update"
        }
      ],
      "rule_compliance_links": [],
      "feature_flags": [],
      "vectorized": false,
      "scenario_origins": [],
      "graphql_mutations": [],
      "agent_steps": [],
      "authentication_subject": false,
      "sensitive": true,
      "auth_strategies": [],
      "compliance": [
        "RG_UK_002",
        "RG_MGA_003",
        "RG_UK_008"
      ],
      "domain": "Players",
      "state_machine": {
        "default_initial_state": null,
        "initial_states": [],
        "present": false,
        "state_attribute": null,
        "states": [],
        "terminal_states": [],
        "transitions": []
      },
      "test_coverage": {
        "e2e_tests": false,
        "property_tests": false,
        "scenario_tests": false
      },
      "runbook": null
    },
    {
      "performs": null,
      "relationships": [],
      "adrs": [],
      "last_modified": "2026-04-18 10:44:58",
      "paper_trail": false,
      "telemetry_prefix": [],
      "data_layer": null,
      "oban_queues": [],
      "steps": [],
      "module": "IgamingRef.Players.Rules.PlayerNotSelfExcluded",
      "outputs": [],
      "rules": [],
      "attributes": [],
      "rate_limited": false,
      "pending_migrations": false,
      "type": "rule",
      "money_attributes": [],
      "archival": false,
      "api_routes": [],
      "app": null,
      "json_api_routes": [],
      "description": "Player must not have an active self-exclusion",
      "id": "IgamingRef.Players.Rules.PlayerNotSelfExcluded",
      "provider_behaviour": null,
      "provider_name": null,
      "actions": [],
      "rule_compliance_links": [],
      "feature_flags": [],
      "vectorized": false,
      "scenario_origins": [],
      "graphql_mutations": [],
      "agent_steps": [],
      "authentication_subject": false,
      "sensitive": false,
      "auth_strategies": [],
      "compliance": [
        "RG_UK_008",
        "RG_MGA_009"
      ],
      "domain": "Players",
      "state_machine": {
        "default_initial_state": null,
        "initial_states": [],
        "present": false,
        "state_attribute": null,
        "states": [],
        "terminal_states": [],
        "transitions": []
      },
      "test_coverage": {
        "e2e_tests": false,
        "property_tests": false,
        "scenario_tests": false
      },
      "runbook": null
    },
    {
      "performs": null,
      "relationships": [
        {
          "description": "The player this exclusion record belongs to.",
          "destination_attribute": "id",
          "name": "player",
          "related_resource": "IgamingRef.Players.Player",
          "source_attribute": "player_id",
          "type": "belongs_to"
        }
      ],
      "adrs": [],
      "last_modified": "2026-04-18 10:44:58",
      "paper_trail": true,
      "telemetry_prefix": [
        "igaming_ref",
        "players",
        "self_exclusion_record"
      ],
      "data_layer": "Elixir.AshPostgres.DataLayer",
      "oban_queues": [],
      "steps": [],
      "module": "IgamingRef.Players.SelfExclusionRecord",
      "outputs": [],
      "rules": [],
      "attributes": [
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "id",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UUID"
        },
        {
          "cldr_backend": null,
          "description": "The player who is self-excluding.",
          "money": false,
          "name": "player_id",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UUID"
        },
        {
          "cldr_backend": null,
          "description": "Timestamp of the self-exclusion event.",
          "money": false,
          "name": "excluded_at",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UtcDatetime"
        },
        {
          "cldr_backend": null,
          "description": ":temporary exclusions have a duration_days; :permanent exclusions are indefinite.",
          "money": false,
          "name": "exclusion_type",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.Atom"
        },
        {
          "cldr_backend": null,
          "description": "For :temporary exclusions: the number of days the exclusion lasts. Nil for :permanent.",
          "money": false,
          "name": "duration_days",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.Integer"
        },
        {
          "cldr_backend": null,
          "description": "When the player was reinstated after a temporary exclusion. Nil while exclusion is active.",
          "money": false,
          "name": "reinstated_at",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UtcDatetime"
        },
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "inserted_at",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UtcDatetimeUsec"
        },
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "archived_at",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UtcDatetimeUsec"
        }
      ],
      "rate_limited": false,
      "pending_migrations": false,
      "type": "resource",
      "money_attributes": [],
      "archival": true,
      "api_routes": [],
      "app": null,
      "json_api_routes": [],
      "description": null,
      "id": "IgamingRef.Players.SelfExclusionRecord",
      "provider_behaviour": null,
      "provider_name": null,
      "actions": [
        {
          "description": null,
          "name": "read",
          "type": "read"
        },
        {
          "description": "Record a new self-exclusion event. Called by the self_exclude action on Player.",
          "name": "record",
          "type": "create"
        },
        {
          "description": "Record the reinstatement timestamp when a temporary exclusion expires.",
          "name": "mark_reinstated",
          "type": "update"
        }
      ],
      "rule_compliance_links": [],
      "feature_flags": [],
      "vectorized": false,
      "scenario_origins": [],
      "graphql_mutations": [],
      "agent_steps": [],
      "authentication_subject": false,
      "sensitive": true,
      "auth_strategies": [],
      "compliance": [
        "RG_UK_008",
        "RG_MGA_009"
      ],
      "domain": "Players",
      "state_machine": {
        "default_initial_state": null,
        "initial_states": [],
        "present": false,
        "state_attribute": null,
        "states": [],
        "terminal_states": [],
        "transitions": []
      },
      "test_coverage": {
        "e2e_tests": false,
        "property_tests": false,
        "scenario_tests": false
      },
      "runbook": null
    },
    {
      "performs": null,
      "relationships": [],
      "adrs": [],
      "last_modified": "2026-04-18 10:43:11",
      "paper_trail": false,
      "telemetry_prefix": [],
      "data_layer": null,
      "oban_queues": [],
      "steps": [],
      "module": "IgamingRef.Policies.AuthenticatedSubject",
      "outputs": [],
      "rules": [],
      "attributes": [],
      "rate_limited": false,
      "pending_migrations": false,
      "type": "rule",
      "money_attributes": [],
      "archival": false,
      "api_routes": [],
      "app": null,
      "json_api_routes": [],
      "description": null,
      "id": "IgamingRef.Policies.AuthenticatedSubject",
      "provider_behaviour": null,
      "provider_name": null,
      "actions": [],
      "rule_compliance_links": [],
      "feature_flags": [],
      "vectorized": false,
      "scenario_origins": [],
      "graphql_mutations": [],
      "agent_steps": [],
      "authentication_subject": false,
      "sensitive": false,
      "auth_strategies": [],
      "compliance": [],
      "domain": "Policies",
      "state_machine": {
        "default_initial_state": null,
        "initial_states": [],
        "present": false,
        "state_attribute": null,
        "states": [],
        "terminal_states": [],
        "transitions": []
      },
      "test_coverage": {
        "e2e_tests": false,
        "property_tests": false,
        "scenario_tests": false
      },
      "runbook": null
    },
    {
      "performs": null,
      "relationships": [],
      "adrs": [],
      "last_modified": "2026-04-18 10:43:11",
      "paper_trail": false,
      "telemetry_prefix": [],
      "data_layer": null,
      "oban_queues": [],
      "steps": [],
      "module": "IgamingRef.Policies.ComplianceOrPlatformLead",
      "outputs": [],
      "rules": [],
      "attributes": [],
      "rate_limited": false,
      "pending_migrations": false,
      "type": "rule",
      "money_attributes": [],
      "archival": false,
      "api_routes": [],
      "app": null,
      "json_api_routes": [],
      "description": null,
      "id": "IgamingRef.Policies.ComplianceOrPlatformLead",
      "provider_behaviour": null,
      "provider_name": null,
      "actions": [],
      "rule_compliance_links": [],
      "feature_flags": [],
      "vectorized": false,
      "scenario_origins": [],
      "graphql_mutations": [],
      "agent_steps": [],
      "authentication_subject": false,
      "sensitive": false,
      "auth_strategies": [],
      "compliance": [],
      "domain": "Policies",
      "state_machine": {
        "default_initial_state": null,
        "initial_states": [],
        "present": false,
        "state_attribute": null,
        "states": [],
        "terminal_states": [],
        "transitions": []
      },
      "test_coverage": {
        "e2e_tests": false,
        "property_tests": false,
        "scenario_tests": false
      },
      "runbook": null
    },
    {
      "performs": null,
      "relationships": [],
      "adrs": [],
      "last_modified": "2026-04-18 10:43:11",
      "paper_trail": false,
      "telemetry_prefix": [],
      "data_layer": null,
      "oban_queues": [],
      "steps": [],
      "module": "IgamingRef.Policies.InternalSystemActor",
      "outputs": [],
      "rules": [],
      "attributes": [],
      "rate_limited": false,
      "pending_migrations": false,
      "type": "rule",
      "money_attributes": [],
      "archival": false,
      "api_routes": [],
      "app": null,
      "json_api_routes": [],
      "description": null,
      "id": "IgamingRef.Policies.InternalSystemActor",
      "provider_behaviour": null,
      "provider_name": null,
      "actions": [],
      "rule_compliance_links": [],
      "feature_flags": [],
      "vectorized": false,
      "scenario_origins": [],
      "graphql_mutations": [],
      "agent_steps": [],
      "authentication_subject": false,
      "sensitive": false,
      "auth_strategies": [],
      "compliance": [],
      "domain": "Policies",
      "state_machine": {
        "default_initial_state": null,
        "initial_states": [],
        "present": false,
        "state_attribute": null,
        "states": [],
        "terminal_states": [],
        "transitions": []
      },
      "test_coverage": {
        "e2e_tests": false,
        "property_tests": false,
        "scenario_tests": false
      },
      "runbook": null
    },
    {
      "performs": null,
      "relationships": [],
      "adrs": [],
      "last_modified": "2026-04-18 10:43:11",
      "paper_trail": false,
      "telemetry_prefix": [],
      "data_layer": null,
      "oban_queues": [],
      "steps": [],
      "module": "IgamingRef.Policies.OperatorOnly",
      "outputs": [],
      "rules": [],
      "attributes": [],
      "rate_limited": false,
      "pending_migrations": false,
      "type": "rule",
      "money_attributes": [],
      "archival": false,
      "api_routes": [],
      "app": null,
      "json_api_routes": [],
      "description": null,
      "id": "IgamingRef.Policies.OperatorOnly",
      "provider_behaviour": null,
      "provider_name": null,
      "actions": [],
      "rule_compliance_links": [],
      "feature_flags": [],
      "vectorized": false,
      "scenario_origins": [],
      "graphql_mutations": [],
      "agent_steps": [],
      "authentication_subject": false,
      "sensitive": false,
      "auth_strategies": [],
      "compliance": [],
      "domain": "Policies",
      "state_machine": {
        "default_initial_state": null,
        "initial_states": [],
        "present": false,
        "state_attribute": null,
        "states": [],
        "terminal_states": [],
        "transitions": []
      },
      "test_coverage": {
        "e2e_tests": false,
        "property_tests": false,
        "scenario_tests": false
      },
      "runbook": null
    },
    {
      "performs": null,
      "relationships": [],
      "adrs": [],
      "last_modified": "2026-04-18 10:43:11",
      "paper_trail": false,
      "telemetry_prefix": [],
      "data_layer": null,
      "oban_queues": [],
      "steps": [],
      "module": "IgamingRef.Policies.OwnerOrOperator",
      "outputs": [],
      "rules": [],
      "attributes": [],
      "rate_limited": false,
      "pending_migrations": false,
      "type": "rule",
      "money_attributes": [],
      "archival": false,
      "api_routes": [],
      "app": null,
      "json_api_routes": [],
      "description": null,
      "id": "IgamingRef.Policies.OwnerOrOperator",
      "provider_behaviour": null,
      "provider_name": null,
      "actions": [],
      "rule_compliance_links": [],
      "feature_flags": [],
      "vectorized": false,
      "scenario_origins": [],
      "graphql_mutations": [],
      "agent_steps": [],
      "authentication_subject": false,
      "sensitive": false,
      "auth_strategies": [],
      "compliance": [],
      "domain": "Policies",
      "state_machine": {
        "default_initial_state": null,
        "initial_states": [],
        "present": false,
        "state_attribute": null,
        "states": [],
        "terminal_states": [],
        "transitions": []
      },
      "test_coverage": {
        "e2e_tests": false,
        "property_tests": false,
        "scenario_tests": false
      },
      "runbook": null
    },
    {
      "performs": null,
      "relationships": [],
      "adrs": [],
      "last_modified": "2026-04-18 10:43:11",
      "paper_trail": false,
      "telemetry_prefix": [],
      "data_layer": null,
      "oban_queues": [],
      "steps": [],
      "module": "IgamingRef.Policies.SelfOnly",
      "outputs": [],
      "rules": [],
      "attributes": [],
      "rate_limited": false,
      "pending_migrations": false,
      "type": "rule",
      "money_attributes": [],
      "archival": false,
      "api_routes": [],
      "app": null,
      "json_api_routes": [],
      "description": null,
      "id": "IgamingRef.Policies.SelfOnly",
      "provider_behaviour": null,
      "provider_name": null,
      "actions": [],
      "rule_compliance_links": [],
      "feature_flags": [],
      "vectorized": false,
      "scenario_origins": [],
      "graphql_mutations": [],
      "agent_steps": [],
      "authentication_subject": false,
      "sensitive": false,
      "auth_strategies": [],
      "compliance": [],
      "domain": "Policies",
      "state_machine": {
        "default_initial_state": null,
        "initial_states": [],
        "present": false,
        "state_attribute": null,
        "states": [],
        "terminal_states": [],
        "transitions": []
      },
      "test_coverage": {
        "e2e_tests": false,
        "property_tests": false,
        "scenario_tests": false
      },
      "runbook": null
    },
    {
      "performs": null,
      "relationships": [
        {
          "description": "All bonus grants issued from this campaign.",
          "destination_attribute": "campaign_id",
          "name": "grants",
          "related_resource": "IgamingRef.Promotions.BonusGrant",
          "source_attribute": "id",
          "type": "has_many"
        }
      ],
      "adrs": [],
      "last_modified": "2026-04-18 10:44:58",
      "paper_trail": false,
      "telemetry_prefix": [
        "igaming_ref",
        "promotions",
        "bonus_campaign"
      ],
      "data_layer": "Elixir.AshPostgres.DataLayer",
      "oban_queues": [],
      "steps": [],
      "module": "IgamingRef.Promotions.BonusCampaign",
      "outputs": [],
      "rules": [],
      "attributes": [
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "id",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UUID"
        },
        {
          "cldr_backend": null,
          "description": "Human-readable campaign name. Shown to players in the promotions UI.",
          "money": false,
          "name": "name",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.String"
        },
        {
          "cldr_backend": null,
          "description": "Campaign type. Determines the award calculation logic.",
          "money": false,
          "name": "kind",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.Atom"
        },
        {
          "cldr_backend": null,
          "description": "Lifecycle state. Managed by AshStateMachine.",
          "money": false,
          "name": "status",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.Atom"
        },
        {
          "cldr_backend": null,
          "description": "Module name of the Rule that determines player eligibility. E.g. 'IgamingRef.Promotions.Rules.PlayerEligibleForCampaign'.",
          "money": false,
          "name": "eligibility_rule",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.String"
        },
        {
          "cldr_backend": null,
          "description": "Base bonus award amount. For :deposit_match campaigns, this is multiplied by the deposit (RG-UK-011 requires this to be disclosed at grant time).",
          "money": false,
          "name": "bonus_amount",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.AshMoney.Types.Money"
        },
        {
          "cldr_backend": null,
          "description": "Wagering requirement multiplier. A player must wager bonus_amount � wagering_multiplier before withdrawal (RG-UK-011).",
          "money": false,
          "name": "wagering_multiplier",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.Decimal"
        },
        {
          "cldr_backend": null,
          "description": "Maximum number of times this campaign can be redeemed across all players. Nil means unlimited.",
          "money": false,
          "name": "max_redemptions",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.Integer"
        },
        {
          "cldr_backend": null,
          "description": "When the campaign becomes eligible for redemption.",
          "money": false,
          "name": "starts_at",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UtcDatetime"
        },
        {
          "cldr_backend": null,
          "description": "When the campaign stops being eligible for redemption. Checked by CampaignNotExpired rule.",
          "money": false,
          "name": "expires_at",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UtcDatetime"
        },
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "inserted_at",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UtcDatetimeUsec"
        },
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "updated_at",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UtcDatetimeUsec"
        },
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "state",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.Atom"
        }
      ],
      "rate_limited": false,
      "pending_migrations": false,
      "type": "resource",
      "money_attributes": [],
      "archival": false,
      "api_routes": [],
      "app": null,
      "json_api_routes": [],
      "description": null,
      "id": "IgamingRef.Promotions.BonusCampaign",
      "provider_behaviour": null,
      "provider_name": null,
      "actions": [
        {
          "description": null,
          "name": "read",
          "type": "read"
        },
        {
          "description": "Create a new campaign in :draft state.",
          "name": "create",
          "type": "create"
        },
        {
          "description": "Update campaign configuration. Only permitted while in :draft state.",
          "name": "update",
          "type": "update"
        },
        {
          "description": "Activate the campaign. Validates starts_at is not in the past.",
          "name": "activate",
          "type": "update"
        },
        {
          "description": "Pause an active campaign temporarily.",
          "name": "pause",
          "type": "update"
        },
        {
          "description": "Resume a paused campaign.",
          "name": "resume",
          "type": "update"
        },
        {
          "description": "Expire the campaign. Called by a scheduled job when expires_at passes.",
          "name": "expire",
          "type": "update"
        }
      ],
      "rule_compliance_links": [],
      "feature_flags": [],
      "vectorized": false,
      "scenario_origins": [],
      "graphql_mutations": [],
      "agent_steps": [],
      "authentication_subject": false,
      "sensitive": false,
      "auth_strategies": [],
      "compliance": [
        "RG_MGA_005",
        "RG_UK_011"
      ],
      "domain": "Promotions",
      "state_machine": {
        "default_initial_state": null,
        "initial_states": [],
        "present": false,
        "state_attribute": null,
        "states": [],
        "terminal_states": [],
        "transitions": []
      },
      "test_coverage": {
        "e2e_tests": false,
        "property_tests": false,
        "scenario_tests": false
      },
      "runbook": null
    },
    {
      "performs": null,
      "relationships": [
        {
          "description": "The player who received this bonus.",
          "destination_attribute": "id",
          "name": "player",
          "related_resource": "IgamingRef.Players.Player",
          "source_attribute": "player_id",
          "type": "belongs_to"
        },
        {
          "description": "The campaign this bonus was issued from.",
          "destination_attribute": "id",
          "name": "campaign",
          "related_resource": "IgamingRef.Promotions.BonusCampaign",
          "source_attribute": "campaign_id",
          "type": "belongs_to"
        }
      ],
      "adrs": [],
      "last_modified": "2026-04-18 10:44:58",
      "paper_trail": false,
      "telemetry_prefix": [
        "igaming_ref",
        "promotions",
        "bonus_grant"
      ],
      "data_layer": "Elixir.AshPostgres.DataLayer",
      "oban_queues": [],
      "steps": [],
      "module": "IgamingRef.Promotions.BonusGrant",
      "outputs": [],
      "rules": [],
      "attributes": [
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "id",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UUID"
        },
        {
          "cldr_backend": null,
          "description": "The player who received this bonus.",
          "money": false,
          "name": "player_id",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UUID"
        },
        {
          "cldr_backend": null,
          "description": "The campaign this grant was issued from.",
          "money": false,
          "name": "campaign_id",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UUID"
        },
        {
          "cldr_backend": null,
          "description": "Total bonus amount awarded. Fixed at grant time (RG-UK-011).",
          "money": false,
          "name": "amount",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.AshMoney.Types.Money"
        },
        {
          "cldr_backend": null,
          "description": "Amount still to be wagered before the bonus can be withdrawn. Decremented by apply_wager.",
          "money": false,
          "name": "wagering_remaining",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.Decimal"
        },
        {
          "cldr_backend": null,
          "description": "Lifecycle state. Managed by AshStateMachine.",
          "money": false,
          "name": "status",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.Atom"
        },
        {
          "cldr_backend": null,
          "description": "When the bonus was awarded.",
          "money": false,
          "name": "granted_at",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UtcDatetime"
        },
        {
          "cldr_backend": null,
          "description": "When the bonus expires if wagering requirements are not met.",
          "money": false,
          "name": "expires_at",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UtcDatetime"
        },
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "inserted_at",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UtcDatetimeUsec"
        },
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "updated_at",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.UtcDatetimeUsec"
        },
        {
          "cldr_backend": null,
          "description": null,
          "money": false,
          "name": "state",
          "pii": false,
          "sensitive": false,
          "type": "Elixir.Ash.Type.Atom"
        }
      ],
      "rate_limited": false,
      "pending_migrations": false,
      "type": "resource",
      "money_attributes": [],
      "archival": false,
      "api_routes": [],
      "app": null,
      "json_api_routes": [],
      "description": null,
      "id": "IgamingRef.Promotions.BonusGrant",
      "provider_behaviour": null,
      "provider_name": null,
      "actions": [
        {
          "description": null,
          "name": "read",
          "type": "read"
        },
        {
          "description": "Issue a bonus grant. Called by BonusGrantTransfer after eligibility is confirmed.",
          "name": "grant",
          "type": "create"
        },
        {
          "description": "Decrement wagering_remaining. When it reaches zero, transitions to :wagered.",
          "name": "apply_wager",
          "type": "update"
        },
        {
          "description": "Forfeit the bonus. Called when a player violates bonus terms.",
          "name": "forfeit",
          "type": "update"
        },
        {
          "description": "Expire the bonus. Called by a scheduled job when expires_at passes.",
          "name": "expire",
          "type": "update"
        },
        {
          "description": "Mark the bonus as fully wagered. Called when wagering_remaining hits zero.",
          "name": "complete",
          "type": "update"
        }
      ],
      "rule_compliance_links": [],
      "feature_flags": [],
      "vectorized": false,
      "scenario_origins": [],
      "graphql_mutations": [],
      "agent_steps": [],
      "authentication_subject": false,
      "sensitive": false,
      "auth_strategies": [],
      "compliance": [
        "RG_MMA_005",
        "RG_UK_011"
      ],
      "domain": "Promotions",
      "state_machine": {
        "default_initial_state": null,
        "initial_states": [],
        "present": false,
        "state_attribute": null,
        "states": [],
        "terminal_states": [],
        "transitions": []
      },
      "test_coverage": {
        "e2e_tests": false,
        "property_tests": false,
        "scenario_tests": false
      },
      "runbook": "docs/runbooks/bonus_grant_transfer.md"
    },
    {
      "performs": null,
      "relationships": [],
      "adrs": [],
      "last_modified": "2026-04-18 10:44:58",
      "paper_trail": false,
      "telemetry_prefix": [
        "igaming_ref",
        "promotions",
        "bonus_grant_transfer"
      ],
      "data_layer": null,
      "oban_queues": [],
      "steps": [
        {
          "confidence_threshold": null,
          "description": "Load player, campaign, wallet, and existing grants for rule evaluation.",
          "has_compensation": false,
          "name": "load_context",
          "on_low_confidence": null,
          "rules_applied": [],
          "step_index": 0,
          "step_kind": "custom",
          "step_model": null,
          "step_telemetry_prefix": [],
          "step_tools": [],
          "target_action": null,
          "target_module": null,
          "target_resource": "LedgerEntry",
          "type": "step",
          "wait_for": []
        },
        {
          "confidence_threshold": null,
          "description": "Check self-exclusion, campaign expiry, and player eligibility.",
          "has_compensation": false,
          "name": "evaluate_rules",
          "on_low_confidence": null,
          "rules_applied": [],
          "step_index": 1,
          "step_kind": "custom",
          "step_model": null,
          "step_telemetry_prefix": [],
          "step_tools": [],
          "target_action": null,
          "target_module": null,
          "target_resource": "LedgerEntry",
          "type": "step",
          "wait_for": []
        },
        {
          "confidence_threshold": null,
          "description": "Credit the player's wallet with the bonus amount.",
          "has_compensation": true,
          "name": "credit_wallet",
          "on_low_confidence": null,
          "rules_applied": [],
          "step_index": 2,
          "step_kind": "custom",
          "step_model": null,
          "step_telemetry_prefix": [],
          "step_tools": [],
          "target_action": null,
          "target_module": null,
          "target_resource": "LedgerEntry",
          "type": "step",
          "wait_for": []
        },
        {
          "confidence_threshold": null,
          "description": "Record the bonus credit as an immutable ledger entry.",
          "has_compensation": false,
          "name": "create_ledger_entry",
          "on_low_confidence": null,
          "rules_applied": [],
          "step_index": 3,
          "step_kind": "custom",
          "step_model": null,
          "step_telemetry_prefix": [],
          "step_tools": [],
          "target_action": null,
          "target_module": null,
          "target_resource": "LedgerEntry",
          "type": "step",
          "wait_for": []
        },
        {
          "confidence_threshold": null,
          "description": "Create the BonusGrant record tracking wagering progress.",
          "has_compensation": false,
          "name": "create_bonus_grant",
          "on_low_confidence": null,
          "rules_applied": [],
          "step_index": 4,
          "step_kind": "custom",
          "step_model": null,
          "step_telemetry_prefix": [],
          "step_tools": [],
          "target_action": null,
          "target_module": null,
          "target_resource": "BonusGrant",
          "type": "step",
          "wait_for": []
        }
      ],
      "module": "IgamingRef.Promotions.BonusGrantTransfer",
      "outputs": [],
      "rules": [],
      "attributes": [],
      "rate_limited": false,
      "pending_migrations": false,
      "type": "reactor",
      "money_attributes": [],
      "archival": false,
      "api_routes": [],
      "app": null,
      "json_api_routes": [],
      "description": null,
      "id": "IgamingRef.Promotions.BonusGrantTransfer",
      "provider_behaviour": null,
      "provider_name": null,
      "actions": [],
      "rule_compliance_links": [],
      "feature_flags": [],
      "vectorized": false,
      "scenario_origins": [],
      "graphql_mutations": [],
      "agent_steps": [],
      "authentication_subject": false,
      "sensitive": false,
      "auth_strategies": [],
      "compliance": [
        "RG_MGA_005"
      ],
      "domain": "Promotions",
      "state_machine": {
        "default_initial_state": null,
        "initial_states": [],
        "present": false,
        "state_attribute": null,
        "states": [],
        "terminal_states": [],
        "transitions": []
      },
      "test_coverage": {
        "e2e_tests": false,
        "property_tests": false,
        "scenario_tests": false
      },
      "runbook": "docs/runbooks/bonus_grant_transfer.md"
    },
    {
      "performs": null,
      "relationships": [],
      "adrs": [],
      "last_modified": "2026-04-18 10:44:58",
      "paper_trail": false,
      "telemetry_prefix": [
        "igaming_ref",
        "promotions",
        "deposit_match_blueprint"
      ],
      "data_layer": null,
      "oban_queues": [],
      "steps": [],
      "module": "IgamingRef.Promotions.DepositMatchBlueprint",
      "outputs": [],
      "rules": [],
      "attributes": [],
      "rate_limited": false,
      "pending_migrations": false,
      "type": "blueprint",
      "money_attributes": [],
      "archival": false,
      "api_routes": [],
      "app": null,
      "json_api_routes": [],
      "description": null,
      "id": "IgamingRef.Promotions.DepositMatchBlueprint",
      "provider_behaviour": null,
      "provider_name": null,
      "actions": [],
      "rule_compliance_links": [],
      "feature_flags": [],
      "vectorized": false,
      "scenario_origins": [],
      "graphql_mutations": [],
      "agent_steps": [],
      "authentication_subject": false,
      "sensitive": false,
      "auth_strategies": [],
      "compliance": [
        "RG_MGA_005"
      ],
      "domain": "Promotions",
      "state_machine": {
        "default_initial_state": null,
        "initial_states": [],
        "present": false,
        "state_attribute": null,
        "states": [],
        "terminal_states": [],
        "transitions": []
      },
      "test_coverage": {
        "e2e_tests": false,
        "property_tests": false,
        "scenario_tests": false
      },
      "runbook": null
    },
    {
      "performs": null,
      "relationships": [],
      "adrs": [],
      "last_modified": "2026-04-18 10:44:58",
      "paper_trail": false,
      "telemetry_prefix": [],
      "data_layer": null,
      "oban_queues": [],
      "steps": [],
      "module": "IgamingRef.Promotions.Rules.CampaignNotExpired",
      "outputs": [],
      "rules": [],
      "attributes": [],
      "rate_limited": false,
      "pending_migrations": false,
      "type": "rule",
      "money_attributes": [],
      "archival": false,
      "api_routes": [],
      "app": null,
      "json_api_routes": [],
      "description": "Campaign must not have expired",
      "id": "IgamingRef.Promotions.Rules.CampaignNotExpired",
      "provider_behaviour": null,
      "provider_name": null,
      "actions": [],
      "rule_compliance_links": [],
      "feature_flags": [],
      "vectorized": false,
      "scenario_origins": [],
      "graphql_mutations": [],
      "agent_steps": [],
      "authentication_subject": false,
      "sensitive": false,
      "auth_strategies": [],
      "compliance": [
        "RG_MGA_005"
      ],
      "domain": "Promotions",
      "state_machine": {
        "default_initial_state": null,
        "initial_states": [],
        "present": false,
        "state_attribute": null,
        "states": [],
        "terminal_states": [],
        "transitions": []
      },
      "test_coverage": {
        "e2e_tests": false,
        "property_tests": false,
        "scenario_tests": false
      },
      "runbook": null
    },
    {
      "performs": null,
      "relationships": [],
      "adrs": [],
      "last_modified": "2026-04-18 10:44:58",
      "paper_trail": false,
      "telemetry_prefix": [],
      "data_layer": null,
      "oban_queues": [],
      "steps": [],
      "module": "IgamingRef.Promotions.Rules.PlayerEligibleForCampaign",
      "outputs": [],
      "rules": [],
      "attributes": [],
      "rate_limited": false,
      "pending_migrations": false,
      "type": "rule",
      "money_attributes": [],
      "archival": false,
      "api_routes": [],
      "app": null,
      "json_api_routes": [],
      "description": "Player must meet campaign eligibility criteria",
      "id": "IgamingRef.Promotions.Rules.PlayerEligibleForCampaign",
      "provider_behaviour": null,
      "provider_name": null,
      "actions": [],
      "rule_compliance_links": [],
      "feature_flags": [],
      "vectorized": false,
      "scenario_origins": [],
      "graphql_mutations": [],
      "agent_steps": [],
      "authentication_subject": false,
      "sensitive": false,
      "auth_strategies": [],
      "compliance": [
        "RG_MGA_005"
      ],
      "domain": "Promotions",
      "state_machine": {
        "default_initial_state": null,
        "initial_states": [],
        "present": false,
        "state_attribute": null,
        "states": [],
        "terminal_states": [],
        "transitions": []
      },
      "test_coverage": {
        "e2e_tests": false,
        "property_tests": false,
        "scenario_tests": false
      },
      "runbook": null
    },
    {
      "performs": null,
      "relationships": [],
      "adrs": [],
      "last_modified": null,
      "paper_trail": false,
      "telemetry_prefix": null,
      "data_layer": null,
      "oban_queues": [],
      "steps": [],
      "module": "external:postgres:Accounts",
      "outputs": [],
      "rules": [],
      "attributes": [],
      "rate_limited": false,
      "pending_migrations": false,
      "type": "external",
      "money_attributes": [],
      "archival": false,
      "api_routes": [],
      "app": null,
      "json_api_routes": [],
      "description": "PostgreSQL \x{2014} Accounts domain tables (AshPostgres)",
      "id": "external:postgres:Accounts",
      "provider_behaviour": null,
      "provider_name": null,
      "actions": [],
      "rule_compliance_links": [],
      "feature_flags": [],
      "vectorized": false,
      "scenario_origins": [],
      "graphql_mutations": [],
      "agent_steps": [],
      "authentication_subject": false,
      "sensitive": false,
      "auth_strategies": [],
      "compliance": [],
      "domain": "Infrastructure",
      "state_machine": null,
      "test_coverage": {
        "e2e_tests": false,
        "property_tests": false,
        "scenario_tests": false
      },
      "runbook": null
    },
    {
      "performs": null,
      "relationships": [],
      "adrs": [],
      "last_modified": null,
      "paper_trail": false,
      "telemetry_prefix": null,
      "data_layer": null,
      "oban_queues": [],
      "steps": [],
      "module": "external:postgres:Finance",
      "outputs": [],
      "rules": [],
      "attributes": [],
      "rate_limited": false,
      "pending_migrations": false,
      "type": "external",
      "money_attributes": [],
      "archival": false,
      "api_routes": [],
      "app": null,
      "json_api_routes": [],
      "description": "PostgreSQL \x{2014} Finance domain tables (AshPostgres)",
      "id": "external:postgres:Finance",
      "provider_behaviour": null,
      "provider_name": null,
      "actions": [],
      "rule_compliance_links": [],
      "feature_flags": [],
      "vectorized": false,
      "scenario_origins": [],
      "graphql_mutations": [],
      "agent_steps": [],
      "authentication_subject": false,
      "sensitive": false,
      "auth_strategies": [],
      "compliance": [],
      "domain": "Infrastructure",
      "state_machine": null,
      "test_coverage": {
        "e2e_tests": false,
        "property_tests": false,
        "scenario_tests": false
      },
      "runbook": null
    },
    {
      "performs": null,
      "relationships": [],
      "adrs": [],
      "last_modified": null,
      "paper_trail": false,
      "telemetry_prefix": null,
      "data_layer": null,
      "oban_queues": [],
      "steps": [],
      "module": "external:postgres:Gaming",
      "outputs": [],
      "rules": [],
      "attributes": [],
      "rate_limited": false,
      "pending_migrations": false,
      "type": "external",
      "money_attributes": [],
      "archival": false,
      "api_routes": [],
      "app": null,
      "json_api_routes": [],
      "description": "PostgreSQL \x{2014} Gaming domain tables (AshPostgres)",
      "id": "external:postgres:Gaming",
      "provider_behaviour": null,
      "provider_name": null,
      "actions": [],
      "rule_compliance_links": [],
      "feature_flags": [],
      "vectorized": false,
      "scenario_origins": [],
      "graphql_mutations": [],
      "agent_steps": [],
      "authentication_subject": false,
      "sensitive": false,
      "auth_strategies": [],
      "compliance": [],
      "domain": "Infrastructure",
      "state_machine": null,
      "test_coverage": {
        "e2e_tests": false,
        "property_tests": false,
        "scenario_tests": false
      },
      "runbook": null
    },
    {
      "performs": null,
      "relationships": [],
      "adrs": [],
      "last_modified": null,
      "paper_trail": false,
      "telemetry_prefix": null,
      "data_layer": null,
      "oban_queues": [],
      "steps": [],
      "module": "external:postgres:Ops",
      "outputs": [],
      "rules": [],
      "attributes": [],
      "rate_limited": false,
      "pending_migrations": false,
      "type": "external",
      "money_attributes": [],
      "archival": false,
      "api_routes": [],
      "app": null,
      "json_api_routes": [],
      "description": "PostgreSQL \x{2014} Ops domain tables (AshPostgres)",
      "id": "external:postgres:Ops",
      "provider_behaviour": null,
      "provider_name": null,
      "actions": [],
      "rule_compliance_links": [],
      "feature_flags": [],
      "vectorized": false,
      "scenario_origins": [],
      "graphql_mutations": [],
      "agent_steps": [],
      "authentication_subject": false,
      "sensitive": false,
      "auth_strategies": [],
      "compliance": [],
      "domain": "Infrastructure",
      "state_machine": null,
      "test_coverage": {
        "e2e_tests": false,
        "property_tests": false,
        "scenario_tests": false
      },
      "runbook": null
    },
    {
      "performs": null,
      "relationships": [],
      "adrs": [],
      "last_modified": null,
      "paper_trail": false,
      "telemetry_prefix": null,
      "data_layer": null,
      "oban_queues": [],
      "steps": [],
      "module": "external:postgres:Players",
      "outputs": [],
      "rules": [],
      "attributes": [],
      "rate_limited": false,
      "pending_migrations": false,
      "type": "external",
      "money_attributes": [],
      "archival": false,
      "api_routes": [],
      "app": null,
      "json_api_routes": [],
      "description": "PostgreSQL \x{2014} Players domain tables (AshPostgres)",
      "id": "external:postgres:Players",
      "provider_behaviour": null,
      "provider_name": null,
      "actions": [],
      "rule_compliance_links": [],
      "feature_flags": [],
      "vectorized": false,
      "scenario_origins": [],
      "graphql_mutations": [],
      "agent_steps": [],
      "authentication_subject": false,
      "sensitive": false,
      "auth_strategies": [],
      "compliance": [],
      "domain": "Infrastructure",
      "state_machine": null,
      "test_coverage": {
        "e2e_tests": false,
        "property_tests": false,
        "scenario_tests": false
      },
      "runbook": null
    },
    {
      "performs": null,
      "relationships": [],
      "adrs": [],
      "last_modified": null,
      "paper_trail": false,
      "telemetry_prefix": null,
      "data_layer": null,
      "oban_queues": [],
      "steps": [],
      "module": "external:postgres:Promotions",
      "outputs": [],
      "rules": [],
      "attributes": [],
      "rate_limited": false,
      "pending_migrations": false,
      "type": "external",
      "money_attributes": [],
      "archival": false,
      "api_routes": [],
      "app": null,
      "json_api_routes": [],
      "description": "PostgreSQL \x{2014} Promotions domain tables (AshPostgres)",
      "id": "external:postgres:Promotions",
      "provider_behaviour": null,
      "provider_name": null,
      "actions": [],
      "rule_compliance_links": [],
      "feature_flags": [],
      "vectorized": false,
      "scenario_origins": [],
      "graphql_mutations": [],
      "agent_steps": [],
      "authentication_subject": false,
      "sensitive": false,
      "auth_strategies": [],
      "compliance": [],
      "domain": "Infrastructure",
      "state_machine": null,
      "test_coverage": {
        "e2e_tests": false,
        "property_tests": false,
        "scenario_tests": false
      },
      "runbook": null
    },
    {
      "performs": null,
      "relationships": [],
      "adrs": [],
      "last_modified": null,
      "paper_trail": false,
      "telemetry_prefix": null,
      "data_layer": null,
      "oban_queues": [],
      "steps": [],
      "module": "external:pragmaticplayv1",
      "outputs": [],
      "rules": [],
      "attributes": [],
      "rate_limited": false,
      "pending_migrations": false,
      "type": "external",
      "money_attributes": [],
      "archival": false,
      "api_routes": [],
      "app": null,
      "json_api_routes": [],
      "description": "External API: Pragmaticplayv1",
      "id": "external:pragmaticplayv1",
      "provider_behaviour": null,
      "provider_name": null,
      "actions": [],
      "rule_compliance_links": [],
      "feature_flags": [],
      "vectorized": false,
      "scenario_origins": [],
      "graphql_mutations": [],
      "agent_steps": [],
      "authentication_subject": false,
      "sensitive": false,
      "auth_strategies": [],
      "compliance": [],
      "domain": "Infrastructure",
      "state_machine": null,
      "test_coverage": {
        "e2e_tests": false,
        "property_tests": false,
        "scenario_tests": false
      },
      "runbook": null
    },
    {
      "performs": null,
      "relationships": [],
      "adrs": [],
      "last_modified": null,
      "paper_trail": false,
      "telemetry_prefix": null,
      "data_layer": null,
      "oban_queues": [],
      "steps": [],
      "module": "external:pragmaticplayv2",
      "outputs": [],
      "rules": [],
      "attributes": [],
      "rate_limited": false,
      "pending_migrations": false,
      "type": "external",
      "money_attributes": [],
      "archival": false,
      "api_routes": [],
      "app": null,
      "json_api_routes": [],
      "description": "External API: Pragmaticplayv2",
      "id": "external:pragmaticplayv2",
      "provider_behaviour": null,
      "provider_name": null,
      "actions": [],
      "rule_compliance_links": [],
      "feature_flags": [],
      "vectorized": false,
      "scenario_origins": [],
      "graphql_mutations": [],
      "agent_steps": [],
      "authentication_subject": false,
      "sensitive": false,
      "auth_strategies": [],
      "compliance": [],
      "domain": "Infrastructure",
      "state_machine": null,
      "test_coverage": {
        "e2e_tests": false,
        "property_tests": false,
        "scenario_tests": false
      },
      "runbook": null
    }
  ],
  "domain_type": "igaming",
  "edges": [
    {
      "action_name": null,
      "compliance_ids": [],
      "cross_app": false,
      "cross_project": false,
      "from": "IgamingRef.Accounts.Token",
      "relation": "persists_to",
      "step_index": null,
      "step_name": null,
      "to": "external:postgres:Accounts"
    },
    {
      "action_name": null,
      "compliance_ids": [],
      "cross_app": false,
      "cross_project": false,
      "from": "IgamingRef.Accounts.User",
      "relation": "authenticates",
      "step_index": null,
      "step_name": null,
      "to": "IgamingRef.Accounts.Token"
    },
    {
      "action_name": null,
      "compliance_ids": [],
      "cross_app": false,
      "cross_project": false,
      "from": "IgamingRef.Accounts.User",
      "relation": "persists_to",
      "step_index": null,
      "step_name": null,
      "to": "external:postgres:Accounts"
    },
    {
      "action_name": null,
      "compliance_ids": [],
      "cross_app": false,
      "cross_project": false,
      "from": "IgamingRef.Finance.LedgerEntry",
      "relation": "references",
      "step_index": null,
      "step_name": null,
      "to": "IgamingRef.Finance.Wallet"
    },
    {
      "action_name": null,
      "compliance_ids": [],
      "cross_app": false,
      "cross_project": false,
      "from": "IgamingRef.Finance.LedgerEntry",
      "relation": "persists_to",
      "step_index": null,
      "step_name": null,
      "to": "external:postgres:Finance"
    },
    {
      "action_name": null,
      "compliance_ids": [],
      "cross_app": false,
      "cross_project": false,
      "from": "IgamingRef.Finance.Rules.PlayerKYCVerified",
      "relation": "guards",
      "step_index": null,
      "step_name": null,
      "to": "IgamingRef.Finance.WithdrawalTransfer"
    },
    {
      "action_name": null,
      "compliance_ids": [],
      "cross_app": false,
      "cross_project": false,
      "from": "IgamingRef.Finance.Rules.SufficientBalance",
      "relation": "guards",
      "step_index": null,
      "step_name": null,
      "to": "IgamingRef.Finance.WithdrawalTransfer"
    },
    {
      "action_name": null,
      "compliance_ids": [],
      "cross_app": false,
      "cross_project": false,
      "from": "IgamingRef.Finance.Rules.WithdrawalLimitNotExceeded",
      "relation": "guards",
      "step_index": null,
      "step_name": null,
      "to": "IgamingRef.Finance.WithdrawalTransfer"
    },
    {
      "action_name": null,
      "compliance_ids": [],
      "cross_app": false,
      "cross_project": false,
      "from": "IgamingRef.Finance.Transfer",
      "relation": "persists_to",
      "step_index": null,
      "step_name": null,
      "to": "external:postgres:Finance"
    },
    {
      "action_name": null,
      "compliance_ids": [],
      "cross_app": false,
      "cross_project": false,
      "from": "IgamingRef.Finance.Wallet",
      "relation": "referenced_by",
      "step_index": null,
      "step_name": null,
      "to": "IgamingRef.Finance.LedgerEntry"
    },
    {
      "action_name": null,
      "compliance_ids": [],
      "cross_app": false,
      "cross_project": false,
      "from": "IgamingRef.Finance.Wallet",
      "relation": "referenced_by",
      "step_index": null,
      "step_name": null,
      "to": "IgamingRef.Finance.WithdrawalRequest"
    },
    {
      "action_name": null,
      "compliance_ids": [],
      "cross_app": false,
      "cross_project": false,
      "from": "IgamingRef.Finance.Wallet",
      "relation": "references",
      "step_index": null,
      "step_name": null,
      "to": "IgamingRef.Players.Player"
    },
    {
      "action_name": null,
      "compliance_ids": [],
      "cross_app": false,
      "cross_project": false,
      "from": "IgamingRef.Finance.Wallet",
      "relation": "persists_to",
      "step_index": null,
      "step_name": null,
      "to": "external:postgres:Finance"
    },
    {
      "action_name": null,
      "compliance_ids": [],
      "cross_app": false,
      "cross_project": false,
      "from": "IgamingRef.Finance.WithdrawalRequest",
      "relation": "references",
      "step_index": null,
      "step_name": null,
      "to": "IgamingRef.Finance.Wallet"
    },
    {
      "action_name": null,
      "compliance_ids": [],
      "cross_app": false,
      "cross_project": false,
      "from": "IgamingRef.Finance.WithdrawalRequest",
      "relation": "references",
      "step_index": null,
      "step_name": null,
      "to": "IgamingRef.Players.Player"
    },
    {
      "action_name": null,
      "compliance_ids": [],
      "cross_app": false,
      "cross_project": false,
      "from": "IgamingRef.Finance.WithdrawalRequest",
      "relation": "persists_to",
      "step_index": null,
      "step_name": null,
      "to": "external:postgres:Finance"
    },
    {
      "action_name": null,
      "compliance_ids": [],
      "cross_app": false,
      "cross_project": false,
      "from": "IgamingRef.Gaming.Adapters.PragmaticPlayV1",
      "relation": "calls_provider",
      "step_index": null,
      "step_name": null,
      "to": "external:pragmaticplayv1"
    },
    {
      "action_name": null,
      "compliance_ids": [],
      "cross_app": false,
      "cross_project": false,
      "from": "IgamingRef.Gaming.Adapters.PragmaticPlayV1",
      "relation": "calls_provider",
      "step_index": null,
      "step_name": null,
      "to": "external:pragmaticplayv1"
    },
    {
      "action_name": null,
      "compliance_ids": [],
      "cross_app": false,
      "cross_project": false,
      "from": "IgamingRef.Gaming.Adapters.PragmaticPlayV2",
      "relation": "calls_provider",
      "step_index": null,
      "step_name": null,
      "to": "external:pragmaticplayv2"
    },
    {
      "action_name": null,
      "compliance_ids": [],
      "cross_app": false,
      "cross_project": false,
      "from": "IgamingRef.Gaming.Adapters.PragmaticPlayV2",
      "relation": "calls_provider",
      "step_index": null,
      "step_name": null,
      "to": "external:pragmaticplayv2"
    },
    {
      "action_name": null,
      "compliance_ids": [],
      "cross_app": false,
      "cross_project": false,
      "from": "IgamingRef.Gaming.CatalogSyncJob",
      "relation": "async",
      "step_index": null,
      "step_name": null,
      "to": "IgamingRef.Gaming.ProviderSyncReactor"
    },
    {
      "action_name": null,
      "compliance_ids": [],
      "cross_app": false,
      "cross_project": false,
      "from": "IgamingRef.Gaming.Game",
      "relation": "persists_to",
      "step_index": null,
      "step_name": null,
      "to": "external:postgres:Gaming"
    },
    {
      "action_name": null,
      "compliance_ids": [],
      "cross_app": false,
      "cross_project": false,
      "from": "IgamingRef.Gaming.GameCatalog",
      "relation": "persists_to",
      "step_index": null,
      "step_name": null,
      "to": "external:postgres:Gaming"
    },
    {
      "action_name": null,
      "compliance_ids": [],
      "cross_app": false,
      "cross_project": false,
      "from": "IgamingRef.Gaming.GameVersion",
      "relation": "persists_to",
      "step_index": null,
      "step_name": null,
      "to": "external:postgres:Gaming"
    },
    {
      "action_name": null,
      "compliance_ids": [],
      "cross_app": false,
      "cross_project": false,
      "from": "IgamingRef.Gaming.ProviderConfig",
      "relation": "persists_to",
      "step_index": null,
      "step_name": null,
      "to": "external:postgres:Gaming"
    },
    {
      "action_name": null,
      "compliance_ids": [],
      "cross_app": false,
      "cross_project": false,
      "from": "IgamingRef.Gaming.Rules.GameRTPCertified",
      "relation": "guards",
      "step_index": null,
      "step_name": null,
      "to": "IgamingRef.Gaming.ProviderSyncReactor"
    },
    {
      "action_name": null,
      "compliance_ids": [],
      "cross_app": false,
      "cross_project": false,
      "from": "IgamingRef.Gaming.Rules.ProviderActive",
      "relation": "guards",
      "step_index": null,
      "step_name": null,
      "to": "IgamingRef.Gaming.ProviderSyncReactor"
    },
    {
      "action_name": null,
      "compliance_ids": [],
      "cross_app": false,
      "cross_project": false,
      "from": "IgamingRef.Ops.AuditEntry",
      "relation": "persists_to",
      "step_index": null,
      "step_name": null,
      "to": "external:postgres:Ops"
    },
    {
      "action_name": null,
      "compliance_ids": [],
      "cross_app": false,
      "cross_project": false,
      "from": "IgamingRef.Ops.PIIVault",
      "relation": "references",
      "step_index": null,
      "step_name": null,
      "to": "IgamingRef.Players.Player"
    },
    {
      "action_name": null,
      "compliance_ids": [],
      "cross_app": false,
      "cross_project": false,
      "from": "IgamingRef.Ops.PIIVault",
      "relation": "persists_to",
      "step_index": null,
      "step_name": null,
      "to": "external:postgres:Ops"
    },
    {
      "action_name": null,
      "compliance_ids": [],
      "cross_app": false,
      "cross_project": false,
      "from": "IgamingRef.Players.KYCDocument",
      "relation": "references",
      "step_index": null,
      "step_name": null,
      "to": "IgamingRef.Players.Player"
    },
    {
      "action_name": null,
      "compliance_ids": [],
      "cross_app": false,
      "cross_project": false,
      "from": "IgamingRef.Players.KYCDocument",
      "relation": "persists_to",
      "step_index": null,
      "step_name": null,
      "to": "external:postgres:Players"
    },
    {
      "action_name": null,
      "compliance_ids": [],
      "cross_app": false,
      "cross_project": false,
      "from": "IgamingRef.Players.KYCUploadToken",
      "relation": "references",
      "step_index": null,
      "step_name": null,
      "to": "IgamingRef.Players.Player"
    },
    {
      "action_name": null,
      "compliance_ids": [],
      "cross_app": false,
      "cross_project": false,
      "from": "IgamingRef.Players.KYCUploadToken",
      "relation": "persists_to",
      "step_index": null,
      "step_name": null,
      "to": "external:postgres:Players"
    },
    {
      "action_name": null,
      "compliance_ids": [],
      "cross_app": false,
      "cross_project": false,
      "from": "IgamingRef.Players.Player",
      "relation": "referenced_by",
      "step_index": null,
      "step_name": null,
      "to": "IgamingRef.Finance.Wallet"
    },
    {
      "action_name": null,
      "compliance_ids": [],
      "cross_app": false,
      "cross_project": false,
      "from": "IgamingRef.Players.Player",
      "relation": "referenced_by",
      "step_index": null,
      "step_name": null,
      "to": "IgamingRef.Finance.WithdrawalRequest"
    },
    {
      "action_name": null,
      "compliance_ids": [],
      "cross_app": false,
      "cross_project": false,
      "from": "IgamingRef.Players.Player",
      "relation": "referenced_by",
      "step_index": null,
      "step_name": null,
      "to": "IgamingRef.Players.SelfExclusionRecord"
    },
    {
      "action_name": null,
      "compliance_ids": [],
      "cross_app": false,
      "cross_project": false,
      "from": "IgamingRef.Players.Player",
      "relation": "persists_to",
      "step_index": null,
      "step_name": null,
      "to": "external:postgres:Players"
    },
    {
      "action_name": null,
      "compliance_ids": [],
      "cross_app": false,
      "cross_project": false,
      "from": "IgamingRef.Players.Rules.PlayerNotSelfExcluded",
      "relation": "guards",
      "step_index": null,
      "step_name": null,
      "to": "IgamingRef.Finance.WithdrawalTransfer"
    },
    {
      "action_name": null,
      "compliance_ids": [],
      "cross_app": false,
      "cross_project": false,
      "from": "IgamingRef.Players.Rules.PlayerNotSelfExcluded",
      "relation": "guards",
      "step_index": null,
      "step_name": null,
      "to": "IgamingRef.Promotions.BonusGrantTransfer"
    },
    {
      "action_name": null,
      "compliance_ids": [],
      "cross_app": false,
      "cross_project": false,
      "from": "IgamingRef.Players.SelfExclusionRecord",
      "relation": "references",
      "step_index": null,
      "step_name": null,
      "to": "IgamingRef.Players.Player"
    },
    {
      "action_name": null,
      "compliance_ids": [],
      "cross_app": false,
      "cross_project": false,
      "from": "IgamingRef.Players.SelfExclusionRecord",
      "relation": "persists_to",
      "step_index": null,
      "step_name": null,
      "to": "external:postgres:Players"
    },
    {
      "action_name": null,
      "compliance_ids": [],
      "cross_app": false,
      "cross_project": false,
      "from": "IgamingRef.Promotions.BonusCampaign",
      "relation": "referenced_by",
      "step_index": null,
      "step_name": null,
      "to": "IgamingRef.Promotions.BonusGrant"
    },
    {
      "action_name": null,
      "compliance_ids": [],
      "cross_app": false,
      "cross_project": false,
      "from": "IgamingRef.Promotions.BonusCampaign",
      "relation": "persists_to",
      "step_index": null,
      "step_name": null,
      "to": "external:postgres:Promotions"
    },
    {
      "action_name": null,
      "compliance_ids": [],
      "cross_app": false,
      "cross_project": false,
      "from": "IgamingRef.Promotions.BonusGrant",
      "relation": "references",
      "step_index": null,
      "step_name": null,
      "to": "IgamingRef.Players.Player"
    },
    {
      "action_name": null,
      "compliance_ids": [],
      "cross_app": false,
      "cross_project": false,
      "from": "IgamingRef.Promotions.BonusGrant",
      "relation": "references",
      "step_index": null,
      "step_name": null,
      "to": "IgamingRef.Promotions.BonusCampaign"
    },
    {
      "action_name": null,
      "compliance_ids": [],
      "cross_app": false,
      "cross_project": false,
      "from": "IgamingRef.Promotions.BonusGrant",
      "relation": "persists_to",
      "step_index": null,
      "step_name": null,
      "to": "external:postgres:Promotions"
    },
    {
      "action_name": null,
      "compliance_ids": [],
      "cross_app": false,
      "cross_project": false,
      "from": "IgamingRef.Promotions.Rules.CampaignNotExpired",
      "relation": "guards",
      "step_index": null,
      "step_name": null,
      "to": "IgamingRef.Promotions.BonusGrantTransfer"
    },
    {
      "action_name": null,
      "compliance_ids": [],
      "cross_app": false,
      "cross_project": false,
      "from": "IgamingRef.Promotions.Rules.PlayerEligibleForCampaign",
      "relation": "guards",
      "step_index": null,
      "step_name": null,
      "to": "IgamingRef.Promotions.BonusGrantTransfer"
    }
  ],
  "project": "IgamingRef",
  "project_type": "standard",
  "generated_at": "2026-04-18T10:45:10.325731Z",
  "graph_delta": null,
  "spec_kit": {
    "adrs": [
      {
        "type": "adr",
        "path": "docs/adrs/ADR-001-double-entry-ledger.md",
        "title": "ADR-001-double-entry-ledger",
        "tags": [
          "001",
          "003",
          "008",
          "2024",
          "accepted",
          "account",
          "additional",
          "adoption",
          "adr",
          "always",
          "ash",
          "ashdoubleentry"
        ],
        "summary": "The iGaming domain requires immutable, auditable financial transaction records. Players make deposits, withdrawals, and earn bonuses."
      }
    ],
    "agents": [],
    "index_token_count": 534,
    "index_token_limit": 50000,
    "index_token_warn": false,
    "regulations": [
      {
        "type": "regulation",
        "path": "docs/regulations/ukgc_mga.md",
        "title": "ukgc_mga",
        "tags": [
          "001",
          "002",
          "003",
          "005",
          "007",
          "008",
          "009",
          "011",
          "014",
          "account",
          "activation",
          "balance"
        ],
        "summary": null
      }
    ],
    "runbooks": [
      {
        "type": "runbook",
        "path": "docs/runbooks/bonus_grant_transfer.md",
        "title": "bonus_grant_transfer",
        "tags": [
          "005",
          "according",
          "active",
          "amount",
          "audit",
          "awards",
          "bonus",
          "bonusgrant",
          "campaign",
          "campaignnotexpired",
          "checks",
          "compensation"
        ],
        "summary": "Awards a bonus to a player when campaign eligibility is confirmed. Credits the wallet and creates a tracking record for wagering."
      },
      {
        "type": "runbook",
        "path": "docs/runbooks/withdrawal_transfer.md",
        "title": "withdrawal_transfer",
        "tags": [
          "007",
          "014",
          "against",
          "approved",
          "atomically",
          "attempts",
          "audit",
          "balance",
          "checks",
          "compensation",
          "complete",
          "completed"
        ],
        "summary": "Handles the complete flow of processing an approved withdrawal request through to provider submission."
      },
      {
        "type": "runbook",
        "path": "docs/runbooks/provider_sync.md",
        "title": "provider_sync",
        "tags": [
          "006",
          "007",
          "active",
          "added",
          "agreements",
          "api",
          "approved",
          "atomic",
          "available",
          "calls",
          "catalog",
          "certification"
        ],
        "summary": "Synchronizes the game catalog from a provider's API and creates or updates local records. Fully idempotent."
      }
    ],
    "usage_rules": []
  }
}

```
