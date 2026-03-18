--- ./docs/BUILD_SEQUENCE.md ---
# BUILD_SEQUENCE.md — Foundry

> This document describes the implementation order for building Foundry itself.
> It is not a spec-kit artifact (it captures sequencing, not decisions or invariants).
> It lives alongside the spec-kit and should be updated as phases complete.
>
> Key principle: each phase must be independently useful before the next begins.
> No phase depends on work that hasn't shipped yet.

---

## Phase 1: Structured Data Layer (foundation for everything)

**Goal:** Every Mix task outputs stable JSON. Nothing is built on top of this yet — this is the foundation.

**Why first:** All visualization, all copilot context, all CI gates read from these tasks.
If the JSON schema is unstable, everything built on top breaks. Stabilize it before building on it.

**Deliverables:**
- `mix foundry.context <Module> --json` — DSL introspection for a single module (full schema per ADR-003)
- `mix foundry.context.all --json` — all modules in the project, indexed by domain
- `mix foundry.diagram.generate --json` — system map as graph (nodes, edges, clusters)
- `mix foundry.compliance.check --json` — requirement coverage status
- `mix foundry.lint.all --json` — lint results with structured violations (includes INV-011, INV-012, INV-013 rules).
  Rule engine: `spark_lint` package. Rule modules: `Foundry.LintRules.*` (internal). See ADR-019.
- `mix foundry.versions.check --json` — current stack versions from mix.exs (full ecosystem per ADR-001)

**Schema design review before freeze:** Before the Phase 1 schema is frozen, conduct a
review against the full ADR-001 ecosystem. The schema must include all fields defined in
ADR-003 (`data_layer`, `pending_migrations`, `paper_trail`, `archival`, `state_machine`,
`api_routes`, `telemetry_prefix`, `money_attributes`, `authentication_subject`, `oban_queues`,
`rate_limited`, `feature_flags`). Adding these fields after the freeze requires an ADR.

**JSON schemas are frozen** at the end of Phase 1. Breaking schema changes require an ADR.
The `mix foundry.context` schema in ADR-003 is the contract.

**Done when:** All six tasks run against the iGaming reference project and produce valid JSON
matching the full ADR-003 schema. CI uses `mix foundry.lint.all` and fails on violations.

---

## Phase 2: System Map Viewer (read-only, zero risk)

**Goal:** A live, accurate system diagram that any developer can open and navigate.

**Why second:** This is the highest-value, zero-risk deliverable. It requires only Phase 1.
Every team member immediately benefits. Builds trust in the platform before it can make changes.

**Deliverables:**
- Phoenix LiveView application (`mix foundry.studio`)
- System Map panel — D3 interactive graph from `diagram.generate --json`
- Node detail panel — moduledoc, attributes, actions, linked ADRs, test status (ADR-012 §System Map Interaction Details)
- System map table view alternative — required for WCAG 2.1 AA compliance (ADR-012 §Accessibility)
- Empty and loading states for all panels (ADR-012 §Empty and Loading States)
- Compliance Matrix panel — from `compliance.check --json`
- Bootstrap / onboarding overlay for projects with no spec-kit (ADR-012 §Onboarding)
- Command palette (`Cmd+K`) — navigation and operation preview, with phase-gate (ADR-012 §Command Palette)
- Notification inbox UI (ADR-012 §Notification Inbox)
- inotify file watcher → live reload on source change
- `mix foundry.diagram.generate` running in CI with diff check (INV-008)

**UX specification:** ADR-012. All interaction details, performance budgets, and accessibility
requirements in that document govern Phase 2 implementation.

**No copilot. No code generation. Read-only.**

**Done when:** The iGaming reference project's system map opens, shows all domains, all
resources clickable with correct detail panels (content matches `mix foundry.context` output),
updates within 2 seconds of a file save, passes WCAG 2.1 AA audit for all rendered panels,
and renders within the performance budgets defined in ADR-012 §Performance Budgets.

---

## Phase 3: Copilot — Questions Only (no code changes)

**Goal:** A domain-aware assistant that answers questions about the project accurately.

**Why third:** Builds trust in the copilot's knowledge before it can make changes.
The team learns what it knows, where it's uncertain, what its limits are.
Mis-answers to questions are recoverable. Mis-generated code changes are not.

**Deliverables:**

**Spec-kit indexing and usage rules:**
- `mix foundry.spec_kit.index` — generates `.foundry/spec_kit_index.json`.
  Schema: `docs/spec_kit_index_schema.md`. Warns at 380 tokens. Run in CI.
- `mix foundry.spec_kit.index --check` — CI staleness check, exits 1 if stale.
  Same enforcement pattern as `mix foundry.diagram.generate` + INV-008.
- `mix foundry.usage_rules.fetch` — copies `USAGE.md` / `AGENTS.md` from each
  dependency into `.foundry/usage_rules/<lib>.md` at `mix deps.get` time.
  Foundry maintains usage rules for core stack: Ash 3.x, Reactor, Phoenix LiveView,
  Ecto, Oban. Generates `.foundry/usage_rules/foundry_conventions.md` — Foundry-specific
  conventions every generated module must follow (see ADR-002 §Foundry Conventions File).

**Context assembly:**
- `mix foundry.project.snapshot` — single JSON object (≤ 400 tokens, 60s TTL)
  combining: domain list, sensitive modules, project structure shape, health signals
  (lint errors, open proposals, compliance gaps, pending migrations), key file digest.
  Schema: `docs/mix_task_summary_schemas.md`.
- `Foundry.Copilot.ContextBuilder` — assembles three-tier context:
  - Tier 1 (system prompt, per session): AGENTS.md + stack versions + spec-kit index,
    pre-warmed at startup, Nebulex mtime-cached
  - Tier 2 (session snapshot, per request): `mix foundry.project.snapshot`, 60s TTL
  - Tier 3 (shell): assembled dynamically by the agent during the loop

**Agent loop and tool interface:**
- `Foundry.Copilot.Engine` — agentic loop: assembles Tier 1 + 2 context, runs
  tool loop, dispatches bash calls, accumulates context, produces streaming response.
  Circuit breaker: `max_tool_calls` (default 8, manifest: `copilot.max_tool_calls`).
- `Foundry.Copilot.Tools` — declares the bash tool with shell constraint enforcement
  (permitted/blocked command list per ADR-010 §Shell Constraints). Enforces the
  permitted list at the adapter layer before execution.
- `mix foundry.pattern.find <type> [--domain D]` — deterministic DSL pattern finder,
  ranking criteria per ADR-010 §Pattern Selection. Called via bash.
- `mix foundry.exdoc <Module> [--function name]` — versioned ExDoc output at exact
  pinned version from mix.exs. Nebulex cached 24h. Called via bash.
- `mix foundry.operation.schema <Op>` — structured JSON parameter contract for a
  catalogue operation. Called via bash.

**Adapters and classification:**
- `Foundry.Copilot.LLMAdapter` behaviour — `run/3` callback, tool dispatch,
  streaming, response parsing
- `Foundry.Copilot.AnthropicAdapter` — production adapter
- `Foundry.Copilot.LMStudioAdapter` — test/CI/demo adapter, OpenAI-compatible
  tool calling. Validates tool calling support at startup; degrades gracefully
  (visualization panels functional, copilot degraded-mode banner)

**Agent behaviour:**
- Intent classification and confidence are first-step outputs of the agent loop —
  no separate pre-LLM call. The reasoning trace emits `intent_classification`
  (task, confidence) and `confidence_state` (HIGH/MEDIUM/LOW/BLOCKED) as structured
  fields from the loop's first reasoning step.
- Four confidence states: HIGH, MEDIUM, LOW, BLOCKED (ADR-013 §Confidence States)
- Change intent reasoning posture — system prompt instruction: run speckit.checklist
  → read ADRs + module context + pattern → check @description fields → emit
  contradiction check → BLOCKED or proceed (ADR-010 §Change Intent Reasoning Posture)
- `CHANGE_PREVIEW` handler — describes operation, change class, affected files
  without generating diff or code. Controlled by `change_generation_enabled: false`.
  This handler is Phase 3 only — in Phase 4 the agent goes directly to DRAFT.
- All five error recovery responses with exact format per ADR-013 §Error Recovery
  Responses format
- Reasoning trace in all CHANGE_PREVIEW responses — `shell_calls`, `contradiction_check`
  with non-empty `checked_adrs` and `checked_invs`, `session_snapshot`,
  `speckit_analysis` (see AGENTS.md §Spec-Kit Tasks)

**Spec-kit tasks (Phase 3 subset — all on by default):**
- `speckit.analyze`, `speckit.plan`, `speckit.clarify`, `speckit.checklist`,
  `speckit.constitution` — system prompt posture injections (AGENTS.md §Spec-Kit Tasks)

**UI and configuration:**
- Activity Feed panel — event stream, chat input, clarifying question button
  component (buttons primary, input always visible as escape hatch per ADR-013),
  CHANGE_PREVIEW card, error cards (ADR-012, ADR-013)
- `config :foundry_studio, change_generation_enabled: false` — Phase 3 config
- `config :foundry_studio, copilot_trace_log: true` — dev-mode trace log (ADR-015)
- LLM API key configuration

**Done when:**
- Copilot correctly answers all questions in `docs/phase3-acceptance-questions.md`
  (Gap #70, authored alongside `docs/reference-project-fixture.md` Gap #54),
  citing specific modules and ADRs, with no Ash 2.x syntax in any response
- All five error codes exercised in test environment with correct structured
  responses matching ADR-013 §Error Recovery Responses format
- Clarifying question UX renders option buttons as primary path with Activity
  Feed input visible below; free-text re-entry re-classifies correctly
- `CHANGE_PREVIEW` responses describe operation, change class, and affected files
  without generating any diff or code
- Reasoning trace present and correctly structured in all CHANGE_PREVIEW responses:
  non-empty `checked_adrs` and `checked_invs`, `shell_calls` reflecting actual reads
- `mix foundry.spec_kit.index --check` passes in CI
- `mix foundry.project.snapshot` produces output within 400-token bound for the
  iGaming reference project
- Shell constraint enforcement: blocked commands (git commit, mix deps.get,
  File.write!) are rejected with structured errors
- `LMStudioAdapter` startup validation detects and warns on non-tool-calling models
- `mix foundry.usage_rules.fetch` populates `.foundry/usage_rules/` including
  `foundry_conventions.md` with Foundry generation conventions documented

**Gap #70 (new):** `docs/phase3-acceptance-questions.md` — 10+ representative
questions about the iGaming reference project with expected citation format and
minimum acceptable response criteria. Author alongside `docs/reference-project-fixture.md`
(Gap #54). Both are prerequisites for Phase 3 done criteria. Estimated: ~2 hours each.

---

## Phase 4: Copilot — Proposals (diff shown, human applies)

**Goal:** The copilot generates real proposals. Humans still apply the diff manually.

**Why fourth:** Decouples "can it generate correctly" from "can it apply safely". If
generation quality is poor, the cost is a rejected diff, not a broken codebase.

**Deliverables:**
- Pattern-driven raw Igniter generation — agent fetches closest project example, reads
  `foundry_conventions.md`, generates via raw Igniter API (ADR-002). No pre-built
  operation catalogue.
- Git branch isolation — all generation writes to `foundry/prop_<id>` branch; working
  tree never touched during generation (ADR-009)
- Migration generation via `mix ash.codegen` on the proposal branch (ADR-002 §Migration Generation)
- Diff renderer in the review panel — code diff + migration diff + lint tab + impact tab
  (ADR-012 §Review Panel Rendering)
- System map preview mode — affected nodes highlighted, phantom new nodes, dimmed
  removed nodes while proposal is in DRAFT/PENDING_REVIEW state (ADR-012)
- Impact analysis via bash traversal of the system map graph — agent runs targeted
  `mix foundry.context.all` queries; no separate ImpactAnalyzer module
- Pre-approval validation: lint result + impact summary
- Change classifier (ADR-005) — tags every proposal with its class, including migration classification
- Approval routing to correct approver per manifest (ADR-005)
- Proposal state machine — DRAFT → PENDING_REVIEW → APPROVED → APPLIED → COMMITTED,
  plus REJECTED / STALE / SUPERSEDED / **APPLY_FAILED** (ADR-014 §Proposal State Machine)
- `APPLY_FAILED` state: on compile failure after branch write, branch is discarded
  cleanly; agent retries up to 3 times, each iteration requires re-approval of new diff
- Dual approval mechanics — two-slot tracking, revocation, audit records (ADR-014 §Dual Approval Mechanics)
- ADR link field for `:compliance` proposals — validation and warning states (ADR-014 §ADR Linking)
- Base-commit stale detection (ADR-009) — `git diff <base_commit>..HEAD -- <files>`
  at apply time; replaces blob hash map
- Stale proposal banner in review panel (ADR-012 §Stale Proposal Banner)
- Proposal visibility — PENDING_REVIEW and later visible to all project users; DRAFT private to requester (ADR-014 §Proposal Visibility)
- Approval tracking UI and notification inbox (ADR-012 §Approval Tracking UI, §Notification Inbox)
- Audit log for `:sensitive` and `:compliance` proposals
- `change_generation_enabled: true` set in Phase 4 deployment config

**Proposal lifecycle specification:** ADR-014. State machine, apply step, and failure paths
in that document govern Phase 4 implementation.

**The diff is shown. The human presses "Apply" in the review panel.**
No auto-apply in Phase 4. This is intentional — it validates diff quality before auto-apply is trusted.

**Done when:** The copilot generates correct, lint-passing diffs for representative
operation types against the iGaming reference project (at minimum: new resource with
migration, new Reactor rule, new compliance link, new attribute on sensitive resource),
using raw Igniter guided by project examples. Proposal state machine transitions are
correct including `APPLY_FAILED` → retry path. Dual approval blocks application until
both slots are filled. ADR link field blocks `:compliance` submission when empty. Audit
log records all `:sensitive` and `:compliance` approvals with timestamp, approver, and
base commit SHA. Stale detection correctly identifies proposals whose base commit has
been superseded by changes to affected files.

---

## Phase 5: Copilot — Auto-Apply (`:structural` only)

**Goal:** Approved `:structural` proposals are applied automatically.

**Why fifth:** By now the diff quality is validated (Phase 4). Auto-apply for `:structural`
changes (descriptions, new attributes, new read-only resources, test skeletons) is low-risk
and high-frequency. Starting here builds confidence before enabling auto-apply for higher classes.

**Deliverables:**
- `Foundry.Operations.run/2` with `dry_run: false` — executes Igniter
- Git commit creation with structured message format
- CI trigger on apply
- Stale proposal detection and UX (ADR-009)
- Auto-apply enabled only for `:structural` class (configurable per project in manifest)
- `:behavioral`, `:sensitive`, `:compliance` proposals still require manual apply

**Done when:** 20 consecutive `:structural` auto-applies in the iGaming reference project
produce lint-passing, CI-green results with no regressions.

---

## Phase 6: Operations Board + Test Coverage Map

**Goal:** Complete the four visualization panels. Make staleness visible and actionable.

**Deliverables:**
- Operations Board panel — runbook status, adapter verification, failed Reactors, alert preview
- Test Coverage Map panel — domain coverage formula (ADR-007), gaps clickable to copilot
- Staleness detection scheduled jobs
- Notification channel configuration in manifest (INV-010)
- `mix foundry.spec_kit.init` — bootstrap task for new projects

**Done when:** The iGaming reference project's operations board shows accurate runbook ages,
the test coverage map shows correct domain coverage scores, and a stale runbook notification
fires to the configured Slack channel.

---

## Phase 7: Domain Builder (Layer 3)

**Goal:** Form-driven scaffold for non-developer users (compliance managers, domain experts).

**Why last:** The Blueprint Builder and Resource Builder are useful only when the underlying
DSL is stable and proven. Building them on top of an unstable DSL wastes effort.

**Deliverables:**
- Blueprint Builder — form-driven campaign/bonus configuration (the Instance side)
- Resource Builder — form-driven Ash resource creation (for domain experts, not developers)
- Compliance Mapper — link RG-* requirements to modules via the UI

**Done when:** A compliance officer can configure a new bonus campaign without writing Elixir,
the configuration generates a valid Blueprint config, and the compliance officer can link a
new regulatory requirement to its implementing module without developer assistance.

---

## Phase 8: Agent Injection Support

**Goal:** First-class governance and observability for AshAI agent steps in target platform
Reactors. Makes the human-in-the-loop gate a managed system feature, not ad-hoc code.

**Why here:** Agent steps are `:behavioral` changes — they require Phases 4 and 5 (copilot
proposals and auto-apply) to already work. The Agent Health panel requires the Operations
Board (Phase 6) as its home. Phase 7 is not a prerequisite; Phase 8 can begin in parallel
with Phase 7 if resource permits.

**Opt-in only:** Phase 8 features activate only for target projects that declare
`extensions: [AshAi]` in a domain module. Projects without AshAI are unaffected and receive
no lint errors related to agent governance.

**Deliverables:**
- Foundry Spark DSL extension for `Ash.Reactor` step — adds `agent_type`, `model`,
  `confidence_threshold`, `on_low_confidence`, `human_gate`, `tools`, `telemetry_prefix`
  declarations to step syntax
- `Foundry.Lint.AgentStepChecker` — enforces INV-014 through INV-017 and the lint rules
  in ADR-017 §Lint Rules
- `agent_steps` field in `mix foundry.context` output — non-breaking addition; `[]` for
  non-AshAI projects
- `HumanGateTask` Ash resource — scaffolded into the *target platform* on first use by
  `Op.AddAgentStep`; always `:sensitive`; requires paper trail and soft delete; scaffold
  proposal is shown alongside the agent step proposal in the review panel with its own
  dual-approval requirement
- `Foundry.Operations.HumanGateReactor` — manages gate lifecycle: create task, wait for
  human decision, resume Reactor, write override audit record
- Agent step rendering in System Map — inline `⊕` step nodes in Transfer/Reactor
  swimlanes; type-specific detail drawer templates (ADR-016, ADR-017)
- Agent Health panel in Operations Board — per-agent-step: p95 latency, error rate,
  cost/call, confidence distribution, override rate
- Override rate lint warning — fires when override rate exceeds the project-configured
  threshold (manifest key: `agent_governance.override_rate_warn_threshold`, default 0.20)
  over a 7-day window; recommends prompt review; threshold deviation from default requires
  ADR documentation (ADR-017)
- `Op.AddAgentStep` catalogue operation — adds an agent step to an existing Reactor;
  classified `:behavioral`; prompts for `agent_type`, `model`, `confidence_threshold`,
  `tools`; includes lint check on generated step
- AshAI version check in `mix foundry.versions.check` — warns if AshAI < 2.x when agent
  steps are present

**Governance specification:** ADR-017 governs all Phase 8 implementation decisions.

**Done when:** A target project can add an agent step via `Op.AddAgentStep` and see two
proposals in the review panel — the `HumanGateTask` scaffold (`:sensitive`, dual approval)
and the agent step itself (`:behavioral`, domain lead approval). Both proposals apply
cleanly. The agent step renders in the System Map as an inline `⊕` step with correct
metadata. Telemetry is surfaced in the Agent Health panel. A human gate triggers correctly
on low-confidence output, resumes the Reactor on human approval, and writes the override
audit record with correct paper trail entries. The override rate lint warning fires in the
test environment when the threshold is exceeded.

---

## Phase Dependencies

```
Phase 1 (JSON tasks)
  └── Phase 2 (System Map)
        └── Phase 3 (Copilot: questions)
              └── Phase 4 (Copilot: proposals)
                    └── Phase 5 (Auto-apply)
                          └── Phase 6 (Ops + Tests) ──┐
                                └── Phase 7 (Builder)  │
                                Phase 8 (Agents) ──────┘
                                  (parallel with 7, requires 6)
```

Each phase is a strict prerequisite for the next. Do not start Phase N+1 until Phase N
is done by the definition above. The definitions are intentionally precise — "done" means
the acceptance criteria pass, not "the code is written."

---

## What Is Out of Scope (for Foundry v1)

These are explicitly deferred. They may become ADRs when the time comes.

- **Multi-tenant cloud hosting** — v1 is local mode + single-tenant cloud. Multi-tenant requires the manifest isolation and billing infrastructure to be designed separately.
- **Support for non-Ash Elixir projects** — raw Ecto, Absinthe-first, etc. The automation leverage is insufficient to justify the generalization cost.
- **Visual diff of the system map** — showing what the diagram looked like before vs after a change. Valuable, complex. Phase 2 ships diagram generation; the diff view is a later enhancement.
- **Multi-Foundry-copilot coordination** — multiple Foundry *copilot* agents coordinating
  on a large change proposal. This is distinct from AshAI agent steps in target platforms
  (which ARE supported via Phase 8). Coordinating multiple copilot instances requires the
  proposal model to handle compound proposals spanning multiple copilots. Deferred.
- **Agent step auto-tuning** — automatic adjustment of confidence thresholds or model
  selection based on observed override rates. Phase 8 surfaces the signal (override rate);
  acting on it automatically is a future capability requiring a separate governance model.
- **Ash 2.x compatibility** — not supported. ADR-001.
--- ./docs/CONTINUATION_PLAN.md ---
# Foundry — Continuation Plan

> **Context:** Spec-kit review complete. Suggestions applied. This document describes
> the recommended sequence for continuing from here toward Phase 1 implementation.
>
> Three open gaps remain before Phase 1 code can begin:
> Gap #53 (decorator lint signal), Gap #54 (reference project fixture), and
> Gap #1 (manifest schema — now partially closed, but ADR-011 still deferred).
> Two of these are small. One defines the acceptance criteria for everything.

---

## Immediate Next Steps (pre-implementation, spec-kit only)

These two items must be completed before writing any Elixir. Neither requires code.
Both are small. Do them in this order.

### Step 1: Write `docs/reference-project-fixture.md` (Gap #54) — ~2 hours

This is the highest-priority remaining gap. Every phase in BUILD_SEQUENCE.md says
"done when: runs against the iGaming reference project." Without this document,
those acceptance criteria cannot be evaluated.

The fixture document declares:

- Which Elixir modules exist in the reference project (`MyApp.Finance.Wallet`, `MyApp.Finance.LedgerEntry`, etc.)
- Which domains they belong to
- Which resources are in `sensitive_resources`
- Which RG-* compliance requirements exist and which modules implement them
- Which optional libraries are present (`:ash_money`, `:ash_state_machine`, `:fun_with_flags` at minimum)
- At least one Transfer module with compliance links and a state machine

This document becomes the target for Phase 1's JSON task outputs. It is also the
source for the actual reference project code that will live under `reference_projects/igaming/`
in the Foundry repository.

**Output:** `docs/reference-project-fixture.md`

---

### Step 2: Add `:decorated_transfer_step` lint rule stub to lint catalogue (Gap #53) — ~30 min

This is a spec decision, not an implementation task. Add a single entry to the lint
rule catalogue (wherever lint rules are being tracked) with status `planned`:

```
:decorated_transfer_step — warns when a Transfer step function is decorated via the
`decorator` library. The copilot cannot auto-classify the change class of decorated
Transfer steps. Manual review is required. Not a build failure; a warning surfaced
in the lint tab of the review panel.
```

Once this is documented, Gap #32 (decorator library) can be marked closed with the
resolution "governed by planned lint warning; no introspection in v1."

**Output:** Entry in the lint rule catalogue (wherever that lives — likely `Foundry.Lint.*` @moduledoc sketch or a lint catalogue section in ADR-002 or a new `docs/lint-catalogue.md`)

---

## Ash Domain Design

With the spec-kit complete and the two pre-implementation gaps closed, Ash domain
design can begin. This is the start of real implementation work.

### Design order (strict — each depends on the previous)

**1. `Foundry.Manifest` resource** — the load-bearing configuration resource

This is the first resource to design because everything else reads from it.
Use `docs/manifest-schema-draft.md` as the exact field target.

Key design decisions to make during Ash resource design (not spec-kit decisions — code decisions):
- How are `sensitive_resources` stored? List of module name strings, or a has-many relationship to a `SensitiveResource` embedded resource?
- How are `approvers` stored? Embedded resource with named role fields, or a polymorphic relationship?
- `conditional_libraries` — list of atoms or a has-many relationship?

Recommendation: favour embedded resources over nested keyword lists for anything that
has validation rules. `approvers` and `notifications` are good candidates for embedded resources.
`sensitive_resources` and `context_exclusions` can be simple lists of strings.

The manifest lives at `.foundry/manifest.exs` — it is read by `Foundry.Manifest.Reader`
(a plain module, not an Ash resource) and validated by the Ash resource's changesets.
The Ash resource is the schema + validation layer; the file is the storage layer.

**When the Ash resource is defined: write ADR-011.**

---

**2. `Foundry.Proposals.Proposal` resource** — the proposal state machine resource

The state machine is fully specified in ADR-014. The Ash resource maps directly:

- `ash_state_machine` for the DRAFT → PENDING_REVIEW → APPROVED → APPLIED → COMMITTED
  state machine (plus REJECTED, STALE, SUPERSEDED terminal states)
- `AshPaperTrail` required (INV-011 — Proposal is a sensitive resource in Foundry's own manifest)
- `AshArchival` required (INV-012)
- The proposal JSON file schema (ADR-014 §Proposal Storage) maps directly to Ash attributes

Key embedded resources to design alongside:
- `ApprovalSlot` — approver, approved_at, role
- `LintResult` — structured lint output
- `ImpactAnalysis` — structured impact output
- `BlobHash` — map of file paths to git blob hashes (ADR-009)

---

**3. `Foundry.Audit.Event` resource** — the append-only audit log entry

Simple resource. Maps to one JSONL line in `.foundry/audit.jsonl`.
Key constraint: no update or destroy actions. Append-only enforced by Ash policy.

---

**4. Mix task stubs** — Phase 1 deliverables, data contracts before implementation

Before implementing the six Mix tasks, define their output contracts as structs or
typed schemas. These are the interfaces that all of Phase 2 and 3 depend on.
Write the struct definitions first, verify they match the ADR-003 schema, then implement.

Tasks to stub:
- `mix foundry.context <Module> --json` → `Foundry.Context.ModuleContext` struct
- `mix foundry.context.all --json` → `%{domain => [ModuleContext]}`
- `mix foundry.diagram.generate --json` → `Foundry.Diagram.SystemMap` struct
- `mix foundry.compliance.check --json` → `Foundry.Compliance.CheckResult` struct
- `mix foundry.lint.all --json` → `Foundry.Lint.LintReport` struct
- `mix foundry.versions.check --json` → `Foundry.Versions.VersionManifest` struct

**The JSON schema for these structs is frozen at the end of Phase 1.** Breaking changes
require an ADR. Define them carefully.

---

## Phase 1 Implementation Sequence

Once domain design is complete and structs are stubbed, implement in this order:

```
1. mix foundry.versions.check    — simplest: reads mix.exs, outputs JSON
                                   Done first to unblock INV-006 (versions in every prompt)

2. mix foundry.context <Module>  — the core introspection task
                                   Implement against the reference project fixture
                                   Schema must match ADR-003 exactly

3. mix foundry.context.all       — calls foundry.context for all modules, aggregates

4. mix foundry.lint.all          — implements INV-001 through INV-013 lint rules
                                   Start with INV-006 (description coverage) and
                                   INV-011/INV-012 (paper_trail, archival) — highest value

5. mix foundry.compliance.check  — reads regulation files, checks implementation pointers

6. mix foundry.diagram.generate  — builds graph from foundry.context.all output
```

The **schema design review** (BUILD_SEQUENCE.md Phase 1) happens after task 2 is
working but before tasks 3–6 are started. Verify the full ADR-003 field list is
present in the live output before freezing.

---

## What Not to Do

- **Do not start Phase 2 (Studio UI) before Phase 1's JSON tasks are stable.** The system map is built from `diagram.generate` output. Building the UI against an unstable schema wastes effort.
- **Do not design the copilot engine modules as Ash resources.** `Foundry.Copilot.ContextBuilder`, `IntentClassifier`, `ConfidenceClassifier` are plain functional modules or GenServers. They have no persistent state requiring Ash.
- **Do not write ADR-011 before `Foundry.Manifest` Ash resource exists.** The manifest schema draft is the pre-ADR target — it is not a substitute for the ADR.
- **Do not begin the reference project implementation (code) before the fixture document is written.** Code the reference project from the fixture, not the other way around.

---

## Parallel Track: Can Anything Run in Parallel?

Yes. Two workstreams can run in parallel once domain design (steps 1–3 above) is complete:

**Track A — Phase 1 Mix tasks** (described above)

**Track B — Reference project scaffold**
Once `docs/reference-project-fixture.md` is written, a developer can scaffold the
reference project's Ash resources in `reference_projects/igaming/` using standard
`mix ash.gen.resource` (or manually). This track produces the live codebase that
Track A's Mix tasks will run against. The two tracks converge at the Phase 1
acceptance criteria check: "all six tasks run against the iGaming reference project."

These two tracks have no code dependency on each other. They only need to agree on
the fixture document, which is why the fixture document must come first.

---

## Summary Checklist

```
Pre-implementation (spec-kit only):
  [ ] docs/reference-project-fixture.md — declare reference project structure (Gap #54)
  [ ] Lint catalogue entry: :decorated_transfer_step (Gap #53)

Domain design:
  [ ] Foundry.Manifest Ash resource (use manifest-schema-draft.md as field target)
  [ ] Write ADR-011 immediately after Manifest resource is defined
  [ ] Foundry.Proposals.Proposal + embedded resources (ApprovalSlot, BlobHash, etc.)
  [ ] Foundry.Audit.Event resource
  [ ] Mix task output struct definitions (6 structs, schema frozen after Phase 1)

Phase 1 implementation (two parallel tracks):
  Track A: [ ] mix foundry.versions.check
           [ ] mix foundry.context <Module>
           [ ] Schema design review (verify full ADR-003 field coverage)
           [ ] mix foundry.context.all
           [ ] mix foundry.lint.all (INV rules)
           [ ] mix foundry.compliance.check
           [ ] mix foundry.diagram.generate
  Track B: [ ] Reference project scaffold in reference_projects/igaming/

Phase 1 done gate:
  [ ] All six tasks run against reference project, output matches fixture
  [ ] mix foundry.lint.all integrated into CI, fails on INV violations
  [ ] Schema frozen — any future breaking change requires ADR
```
--- ./docs/REVIEW_AND_PLAN.md ---
# Foundry — Design Review & Spec-Kit Status

## What's Solid (do not revisit)

- Structured retrieval over RAG for code — ADR-003
- Igniter for all generation, no string interpolation — ADR-002
- Four-class change approval, :sensitive configured per project — ADR-005
- No drag-and-drop, Activity Feed is the only change interface — ADR-008
- Spec-kit is decisions + constraints only, not code duplication — this document
- Git + ETS storage, no Postgres dependency for Foundry itself — ADR-015

---

## Gap Status

| # | Description | Status | Resolution |
|---|---|---|---|
| 1 | Project Manifest underspecified | Closed | `docs/manifest-schema-draft.md` consolidates all manifest fields. `lib/foundry/manifest.ex` Ash resource designed. ADR-011 to be written once resource is stable in production. |
| 2 | Copilot disambiguation failure modes | Closed | AGENTS.md INV-005 |
| 3 | ExDoc cache per-library key | Closed | ADR-003 consequences |
| 4 | Domain coverage formula missing | Closed | ADR-007 Domain Coverage Formula section |
| 5 | Bootstrap mode for new projects | Closed | AGENTS.md bootstrap case + BUILD_SEQUENCE Phase 6 |
| 6 | Concurrent proposals unspecified | Closed | ADR-009 |
| 7 | Staleness notification channels | Closed | INV-010 in platform_invariants.md |
| 8 | LLM model choice undocumented | Closed | ADR-010 |
| 9 | Build sequence absent from spec-kit | Closed | BUILD_SEQUENCE.md |
| 10 | Dogfooding (Foundry on Foundry) | Closed | AGENTS.md "Foundry vs Target Platforms" |
| 11 | ash_postgres + migration lifecycle absent | Closed | ADR-001, ADR-002, ADR-005 migration classification |
| 12 | Money stack underspecified | Closed | ADR-001 Money/Currency Stack section |
| 13 | ash_authentication / ash_authentication_phoenix absent | Closed | ADR-001 Authentication Scaffold; ADR-005 auth always :sensitive |
| 14 | ash_paper_trail governance absent | Closed | INV-011; ADR-005 classifier |
| 15 | ash_archival governance absent | Closed | INV-012; ADR-005 classifier |
| 16 | AshAI stance undocumented | Closed | ADR-001 Out of Scope — v1 ignores and warns |
| 17 | AshPyro + DaisyUI unaddressed | Closed | ADR-001 Conditionally Present; ADR-007 data-* note |
| 18 | Observability stack absent | Closed | ADR-001 Observability Stack section |
| 19 | fun_with_flags governance absent | Closed | ADR-001 Feature Flags; INV-013; ADR-005 classifier |
| 20 | nebulex cache implementation unspecified | Closed | ADR-003 (Nebulex L1 for spec-kit + ExDoc caches); ADR-010 |
| 21 | hammer / hammer_plug absent | Closed | ADR-001 Rate Limiting; ADR-005 classifier |
| 22 | swoosh unspecified | Closed | ADR-001 Email/Notifications section |
| 23 | libcluster absent for cloud mode | Closed | ADR-001 Clustering section |
| 24 | mix foundry.context schema incomplete | Closed | ADR-003 full schema; AGENTS.md updated |
| 25 | ADR-004 forbidden ecto rule ambiguous | Closed | ADR-004 clarification: direct-only, transitive permitted |
| 26 | Req/Finch pool governance unspecified | Closed | ADR-004 Req/Finch clarification |
| 27 | Test tool assignments missing from ADR-007 | Closed | ADR-007 Test Tool Assignments section |
| 28 | Admin UI security (oban_web, live_dashboard) unaddressed | Closed | ADR-001 Admin UI Libraries section; ADR-005 classifier |
| 29 | ash_state_machine underspecified | Closed | ADR-001 listed; ADR-002 Op.AddStateTransition; ADR-003 schema; ADR-005 classifier |
| 30 | ash_json_api governance gaps | Closed | ADR-001 listed; ADR-002 Op.AddApiRoute; ADR-003 schema; ADR-005 classifier |
| 31 | Migration governance absent | Closed | ADR-001 Migration Lifecycle; ADR-002 migration generation; ADR-005 migration classification |
| 32 | decorator library unaddressed | Closed | `docs/lint-catalogue.md` `:decorated_transfer_step` lint rule — warning on decorated Transfer steps, no introspection in v1. See Gap #53. |
| 33 | Beacon CMS stance | Closed | ADR-001 Out of Scope for v1 |
| 34 | jason implicit dependency | Closed | ADR-001 Core Stack table |
| 35 | bandit vs cowboy unspecified | Closed | ADR-001 Core Stack table (Bandit) |
| 36 | Asset pipeline (esbuild/tailwind) absent | Closed | ADR-001 Studio UI Asset Pipeline section |
| 37 | bypass test mechanism unspecified | Closed | ADR-004 Test Tool Specs; ADR-007 tool assignments |
| 38 | ADR-010 file contained ADR-001 content (duplicate) | Closed | ADR-010 rewritten with correct LLM/context content |
| 39 | No copilot agent behaviour spec (confidence, errors, clarifying question UX) | Closed | ADR-013 |
| 40 | No proposal lifecycle state machine | Closed | ADR-014 |
| 41 | No Studio UX specification (panels, palette, interactions) | Closed | ADR-012 |
| 42 | "Impact analysis" term used but never defined | Closed | ADR-012 §Impact Tab |
| 43 | Dual approval mechanics unspecified (revocation, timeouts, audit record) | Closed | ADR-014 §Dual Approval Mechanics |
| 44 | ADR linking UX for :compliance proposals unspecified | Closed | ADR-014 §ADR Linking for Compliance Changes |
| 45 | Phase-gate flag mechanics unspecified | Closed | ADR-010 §Phase-Gated Behaviour; ADR-013 §Phase-Gated Copilot Behaviour; ADR-014 §Phase-Gated Features |
| 46 | Performance budgets absent | Closed | ADR-012 §Performance Budgets |
| 47 | Data retention policy absent | Closed | ADR-012 §Data Retention |
| 48 | No Studio UX degradation runbook | Closed | docs/runbooks/studio_ux_degradation.md |
| 49 | Cmd+P shortcut incorrect (should be Cmd+K) | Closed | ADR-012 §Command Palette; AGENTS.md updated |
| 50 | Foundry incorrectly implied Postgres dependency for its own state | Closed | ADR-015: git-backed files + ETS; ADR-001 core stack table split; ADR-012 retention table updated; ADR-014 storage section updated |
| 51 | ADR-001 core stack table conflated Foundry and target platform dependencies | Closed | ADR-001 split into Foundry dependencies and target platform dependencies |
| 52 | AshAI stance changed: v1 ignore-and-warn superseded by ADR-017 opt-in model | Closed | ADR-017; ADR-001 Out of Scope table updated; Gap #16 superseded |
| 53 | Visualization paradigm finalized: C4 levels, node/edge taxonomy, agent node type | Closed | ADR-016 |
| 54 | Agent taxonomy absent — no canonical type list (classifier, scorer, decision, etc.) | Closed | ADR-017 §Agent Taxonomy |
| 55 | Human-in-the-loop gate unspecified for compliance-gated decision agents | Closed | INV-015; ADR-017 §Human Gate Specification |
| 56 | Agent step telemetry requirement absent | Closed | INV-017; ADR-017 §Lint Rules |
| 57 | Authorization matrix view absent from visualization spec | Closed | ADR-016 §Authorization Layer |
| 58 | mix foundry.context schema missing agent_steps field | Closed | AGENTS.md updated; ADR-017 §AshAI Version Requirement |
| 59 | Phase 8 (Agent Health panel, agent injection UI) absent from BUILD_SEQUENCE | Closed | BUILD_SEQUENCE.md Phase 8 added |
| 60 | BUILD_SEQUENCE out-of-scope list did not reflect agent-to-agent deferral accurately | Closed | BUILD_SEQUENCE.md updated |
| 61 | HumanGateTask resource ownership and scaffold cascade unspecified | Closed | ADR-017 §Human Gate Specification; BUILD_SEQUENCE Phase 8 Done When |
| 62 | Override rate lint warning threshold was hardcoded with no rationale | Closed | ADR-017 §Human Gate Specification; manifest key agent_governance.override_rate_warn_threshold |
| 63 | human_gate permitted on passive agent types (observer, summarizer, etc.) — semantically wrong | Closed | ADR-017 lint rule: human_gate_only_on_gatable_types |
| 64 | manifest-schema-draft.md missing agent_governance section | **Open** | Needs agent_governance.override_rate_warn_threshold field added when ADR-011 is written |
| 65 | Package layer undocumented — which parts of Foundry are extractable standalone libraries | Closed | AGENTS.md §Package Layer; ADR-001 updated with spark_meta, spark_lint, reactor_human_gate, reactor_agent_step, Sourceror, MDEx deps; ADR-019 reserved |
| 66 | DSL annotation extension for sensitive resources (ash_governed) — needed for v1? | Closed | Not needed for v1. manifest.sensitive_resources list is the declaration. No DSL annotation. Future enhancement only. |
| 67 | Telemetry design — custom spans vs reusing Ash/Reactor built-ins | Closed | Three custom spans only: llm_call, context_subprocess, proposal_transition. Constants in Foundry.Telemetry. See AGENTS.md §Package Layer. |

---

## What Belongs in Code, Not Spec-Kit

The following are intentionally absent from spec-kit. They live as `@moduledoc` and
`@description` on the Ash resources and modules that implement them.

| Topic | Module |
|---|---|
| Change classification logic | `Foundry.Diff` (uses Sourceror — AST parse of git diff against ADR-005 ruleset) |
| Scaffold operation contracts | `Foundry.Operations.*` |
| Lint rule implementations | `Foundry.LintRules.*` (rule modules plugged into `spark_lint` engine) |
| Manifest schema and validation | `Foundry.Manifest` Ash resource |
| Context assembly pipeline | `Foundry.Copilot.ContextBuilder` |
| Test generation rules | `Foundry.Testing.Generator` |
| ExDoc cache implementation | `Foundry.Context.DocCache` |
| Domain coverage calculation | `Foundry.Testing.CoverageCalculator` |
| Stale proposal detection | `Foundry.Operations.ProposalStore` (git base-commit diff, not blob hashes) |
| Notification dispatch | `Foundry.Notifications.Dispatcher` |
| Migration generation | via `mix ash.codegen` on proposal branch — no separate module |
| Feature flag governance metadata | `Foundry.FeatureFlags.GovernanceRegistry` |
| Proposal state machine | `Foundry.Proposals.StateMachine` |
| Impact analysis | bash traversal of `mix foundry.context.all` graph — no separate ImpactAnalyzer module |
| Intent classification and confidence | first reasoning step of `Foundry.Copilot.Engine` loop — no separate module |
| Prompt construction | `Foundry.Copilot.PromptBuilder` |
| Agent type renderer registry | `Foundry.Studio.AgentRenderers` |
| Agent telemetry aggregation | `Foundry.Telemetry.AgentAggregator` |
| Human gate task creation | `Foundry.Operations.HumanGateReactor` |
| Agent confidence threshold lint | `Foundry.Lint.AgentStepChecker` |
| Telemetry event name catalogue | `Foundry.Telemetry` (constants only — no macros, no behaviour) |
| Spec-kit document parser | `Foundry.SpecKit` (uses MDEx + NimbleOptions) |

---

## Deferred ADRs (write when the corresponding code exists)

- **ADR-011**: Project Manifest contract — when `Foundry.Manifest` Ash resource is defined
- **ADR-016**: Visualization paradigm v2 — **written**, see `ADR-016-visualization-paradigm-v2.md`
  (supersedes ADR-008; ADR-008 remains for historical record)
- **ADR-017**: Agent injection governance — **written**, see `ADR-017-agent-injection-governance.md`
  (activated when a target project declares `use AshAi` in a domain module)
- **ADR-018**: Bootstrap spec-kit generation — when `mix foundry.spec_kit.init` is built
  (previously listed as ADR-016 in the deferred list; renumbered)
- **ADR-019**: Package extraction — spark_meta, spark_lint, reactor_human_gate, reactor_agent_step,
  rejected candidates (ash_governed, spec_kit, igniter_typed, ash_diff), and what stays internal.
  **Write when the first package is published to Hex.**

Do not write new ADRs speculatively. The above are written because the design decisions
they capture are final; the corresponding code is the next step, not a prerequisite
for writing the ADR in this case.

---

## Open Items Requiring Future ADRs

- **Gap #64**: manifest-schema-draft.md missing `agent_governance.override_rate_warn_threshold` field — add when ADR-011 is written.
- **Gap #69 (pre-open)**: ADR-019 must document rejected extraction candidates with full reasoning. Confirm `reactor_agent_step` and `reactor_human_gate` scope at Phase 8 start.

---

## Current Spec-Kit File List

```
AGENTS.md                              ← primary agent context (updated: INV-008–010 added)
docs/
  BUILD_SEQUENCE.md                    ← implementation phases
  REVIEW_AND_PLAN.md                   ← this file (updated: all gaps closed)
  manifest-schema-draft.md             ← pre-ADR-011 manifest field schema
  reference-project-fixture.md         ← iGaming reference project declaration (Gap #54)
  lint-catalogue.md                    ← all planned lint rules (Gap #53, closes Gap #32)
  adrs/
    ADR-001-stack-selection.md         ← updated: full ecosystem
    ADR-002-code-generation.md         ← updated: migration generation, 20 operations
    ADR-003-agent-context-strategy.md  ← updated: full context schema
    ADR-004-dependency-governance.md   ← updated: ecto clarification, test tools
    ADR-005-change-approval-model.md   ← updated: migration classification, auth, feature flags
    ADR-006-infrastructure-governance.md
    ADR-007-test-generation-strategy.md ← updated: tool assignments, AshPyro note
    ADR-008-visualization-paradigm.md
    ADR-009-concurrent-proposals.md
    ADR-010-llm-model-and-context.md   ← rewritten: correct LLM/context content
    ADR-012-studio-ux-specification.md ← new
    ADR-013-copilot-agent-behavior.md  ← new
    ADR-014-proposal-lifecycle.md      ← new
    ADR-015-storage-model.md           ← new: git + ETS, no Postgres for Foundry
    ADR-016-visualization-paradigm-v2.md
    ADR-017-agent-injection-governance.md
  regulations/
    platform_invariants.md             ← INV-001 through INV-013
  runbooks/
    studio_copilot_failure.md
    igniter_operation_failure.md
    project_reader_unavailable.md
    compliance_test_failure.md
    approval_queue_blocked.md
    studio_ux_degradation.md           ← new
lib/foundry/
  manifest.ex                          ← Foundry.Manifest Ash resource + embedded resources
  proposals/
    proposal.ex                        ← Foundry.Proposals.Proposal + embedded resources
  audit/
    event.ex                           ← Foundry.Audit.Event (append-only)
  context/
    structs.ex                         ← Mix task output struct definitions (Phase 1 JSON contract)
```
--- ./docs/adrs/ADR-001-stack-selection.md ---
# ADR-001: Stack Selection — Elixir/Ash 3.x/Phoenix/Spark

**Status:** Accepted  
**Date:** 2026-03  
**Deciders:** Platform team

---

## Context

Foundry needs to read, validate, and generate code for a specific technology stack.
The choice of target stack determines the entire automation surface.
A general-purpose approach (language-agnostic) would have near-zero automation leverage.

We evaluated three options:
1. Language-agnostic meta-platform (like Backstage)
2. Elixir/raw Ecto/Phoenix
3. Elixir/Ash 3.x/Phoenix/Spark DSL extensions

## Decision

**Elixir/Ash 3.x/Phoenix LiveView/Spark DSL extensions.**

This ADR covers two distinct stacks:

- **The Foundry meta-platform** — the Studio UI, copilot engine, Mix tasks, and CLI
- **Target platforms** — platforms built *using* Foundry (iGaming, fintech, healthcare, legal, etc.)

Both stacks share the same core. Where they differ, this ADR says so explicitly.

---

## Core Stack

The core stack is split: Foundry's own dependencies are minimal. Target platforms carry
the full Ash/Postgres ecosystem. Foundry reads target platform code via Mix task subprocess
in the target project's environment — it does not load target platform dependencies into
its own process.

### Foundry meta-platform dependencies

| Library | Version constraint | Role |
|---|---|---|
| Ash Framework | 3.x only | Domain resource layer for Foundry's own internal resources (manifest, lint rules) |
| Spark DSL | bundled with Ash 3.x | DSL introspection foundation |
| Phoenix | 1.7.x+ | Studio UI web layer |
| Phoenix LiveView | 0.20.x+ | Studio UI components |
| Igniter | current stable | All code generation and AST manipulation |
| Jason | current stable | JSON serialisation — implicit in every Mix task output |
| Req | current stable | HTTP client for LLM API calls (see ADR-004: no HTTPoison) |
| Finch | current stable | HTTP connection pool (transitive via Req) |
| Bandit | current stable | HTTP server adapter (replaces Cowboy) |
| Nebulex | current stable | ETS-backed caches (spec-kit, ExDoc, version manifest) |
| Telemetry | current stable | Instrumentation events |
| telemetry_metrics | current stable | Metrics aggregation |
| telemetry_poller | current stable | VM and process metrics |
| spark_meta | current stable | Generic Spark DSL introspection → struct tree. Powers `mix foundry.context` via `Foundry.Context.*`. See ADR-019. |
| spark_lint | current stable | Lint rule runner engine. `Foundry.LintRules.*` provides the actual INV-011..017 rule modules. See ADR-019. |
| Sourceror | current stable | Elixir AST parsing for diff classification (`Foundry.Diff`). Used by `mix foundry.lint.all` and the change classifier. |
| MDEx | current stable | Markdown parsing for spec-kit documents (`Foundry.SpecKit`). Used by `mix foundry.context` spec-kit reader. |

**Foundry does not depend on `ash_postgres`, `ecto_sql`, or `postgrex`.** Foundry's own
persistent state uses git-backed files under `.foundry/` (ADR-015). There is no Foundry
database to provision. `mix foundry.studio` requires only Elixir and git.

### Target platform dependencies (required in every target platform)

| Library | Version constraint | Role |
|---|---|---|
| Ash Framework | 3.x only (not 2.x — APIs are incompatible) | Domain resource layer |
| ash_postgres | current stable | Postgres data layer for all Ash resources |
| Spark DSL | bundled with Ash 3.x | DSL introspection foundation |
| Phoenix | 1.7.x+ | Web layer |
| Phoenix LiveView | 0.20.x+ | UI components |
| Ecto SQL | current stable | Database adapter (transitive via ash_postgres — see ADR-004) |
| Postgrex | current stable | Postgres driver (transitive via ash_postgres — see ADR-004) |
| Igniter | current stable | All code generation and AST manipulation |
| Jason | current stable | JSON serialisation — implicit in every Mix task output |
| Req | current stable | HTTP client (see ADR-004: no HTTPoison) |
| Finch | current stable | HTTP connection pool (transitive via Req) |
| Bandit | current stable | HTTP server adapter (replaces Cowboy) |
| Telemetry | current stable | Instrumentation events |
| telemetry_metrics | current stable | Metrics aggregation |
| telemetry_poller | current stable | VM and process metrics |
| reactor_human_gate | current stable | Human-in-the-loop gate for Reactor agent steps. Scaffolded into target platforms by `Op.AddAgentStep` (Phase 8, opt-in). See ADR-019. |
| reactor_agent_step | current stable | Spark DSL extension for Reactor agent step declarations. Depends on `reactor_human_gate`. Phase 8 opt-in. See ADR-019. |

---

## Ash Ecosystem Extensions

### Always present in target platforms

| Library | Role | Classification notes |
|---|---|---|
| `ash_postgres` | Postgres data layer | Migration lifecycle — see below |
| `ash_state_machine` | Lifecycle-bearing resource states | Transitions are `:behavioral` class changes (ADR-005) |
| `ash_oban` | Background job integration | New workers are `:behavioral`; queue config is infrastructure (ADR-006) |
| `ash_double_entry` | Financial ledger resources | Resources are always `:sensitive` (ADR-005) |
| `ash_json_api` | JSON API routes | Route additions are `:behavioral`; auth-bearing routes may be `:sensitive` |
| `ash_paper_trail` | Change history / audit trail | Required on all `:sensitive` resources — see INV-011 |
| `ash_archival` | Soft delete | Required on all `:sensitive` resources — see INV-012 |
| `ash_authentication` | Authentication strategies | User credential resources are always `:sensitive` |
| `ash_authentication_phoenix` | Authentication LiveView routes/components | Generates routes via its own Igniter operations — not part of Foundry's LiveView generation |

### Conditionally present (project declares in manifest)

| Library | Role |
|---|---|
| `ash_money` | Monetary Ash attribute type (`Ash.Type.Money`) |
| `AshStateMachine` | Already listed above — present when lifecycle resources exist |
| `AshPyro` | Back-office LiveView component library (DaisyUI/Tailwind-based) |
| `Beacon` | CMS integration — explicitly out of scope for Foundry v1 (see below) |
| `AshAI` | AI/vector integration on Ash resources — Foundry v1 does not introspect AshAI DSL declarations; see below |

---

## Money / Currency Stack

When a target platform handles monetary values, the following libraries form an
interdependent group and must all be present together:

```
ex_money          — currency types, arithmetic, CLDR data
ex_money_sql      — Postgres composite type (money_with_currency)
ash_money         — Ash.Type.Money attribute type
ash_double_entry  — ledger resource DSL
```

**Bootstrap requirement:** `ex_money_sql` requires the `money_with_currency` Postgres composite
type to exist before migrations run. This is a one-time setup step (`mix money.gen.migration`)
that must run before `mix ash.migrate` on a new database. The scaffold operations that create
monetary attributes (type `Ash.Type.Money`) must include this check.

**Type authority:** Use `Ash.Type.Money` (from `ash_money`) as the attribute type, not
`Money.t()` directly. The Foundry linter checks for this.

**CLDR backend:** The project must declare a `Cldr` backend module. The copilot reads its
configuration to know which currencies are valid when generating monetary constraints.

---

## Migration Lifecycle

`ash_postgres` introduces a two-command lifecycle that is part of every structural code change
involving resources or attributes:

```
mix ash.codegen <migration_name>   — generates migration from DSL diff
mix ash.migrate                    — applies migrations to the database
```

**This lifecycle is in scope for Foundry.** Generated code that adds resources or attributes
must include a corresponding migration proposal in its diff output. The review panel shows
both the code change and the generated migration side by side.

**Migration governance:** Schema mutations on `:sensitive` resources carry the same approval
class as code mutations on those resources. A migration that adds a column to `LedgerEntry`
is a `:sensitive` change requiring dual approval, not a `:structural` change. The change
classifier (ADR-005) must inspect migration files for which tables they touch.

**Pending migration detection:** `mix foundry.context` returns `pending_migrations: true/false`
for each resource, sourced from whether `mix ash.codegen --check` exits non-zero.

---

## Authentication Scaffold

`ash_authentication_phoenix` generates LiveView routes and components via its own Igniter
operations. Foundry's agent uses these Igniter generators directly — no wrapper module.

Foundry's stance:
- Authentication resource creation (User, Token resources) uses `ash_authentication`'s
  own published Igniter generators. The agent reads `.foundry/usage_rules/ash_authentication.md`
  and the closest existing auth resource pattern before generating.
- Auth strategy configuration (password, OAuth2, magic link) is a `:behavioral` change.
- Token resource and session resource are always classified as `:sensitive`.
- `ash_authentication_phoenix` route generation is invoked via its own published Igniter task.

---

## Observability Stack

All platforms — Foundry itself and target platforms — must instrument with:

```
opentelemetry              — trace/span API
opentelemetry_exporter     — OTLP export to collector
telemetry                  — Elixir telemetry events (always present via Phoenix/Ash)
telemetry_metrics           — metric aggregations
telemetry_poller           — VM metrics
```

Ash and Reactor already emit telemetry for all actions and steps — Foundry does not
re-instrument those. Foundry adds three custom spans (defined as constants in
`Foundry.Telemetry`, applied point-wise via `:telemetry.span/3`):
`[:foundry, :llm, :call]`, `[:foundry, :context, :subprocess]`, and
`[:foundry, :proposal, :transition]`. These are the primary diagnostic signals for the runbooks.
See AGENTS.md §Package Layer for field definitions.

**Target platform requirement:** Generated Transfer and Oban job code must
automatically include telemetry span wrappers. This is not optional —
trace correlation across Reactors and Oban jobs is required for the audit chain in
regulated platforms.

The `mix foundry.context` schema includes `telemetry_prefix` for each module so the
Operations Board can correlate runbook events with live traces.

---

## Feature Flags

`fun_with_flags` (and optionally `fun_with_flags_ui`) provides feature flag infrastructure.

Foundry's governance stance on feature flags:
- A flag that gates a compliance control is a `:compliance` class change (ADR-005).
- A flag that gates a `:sensitive` operation is a `:sensitive` class change.
- Adding a new flag is `:behavioral` by default.
- The linter checks that flags on `:sensitive` operations are not removable without
  a corresponding ADR (INV-013).

`fun_with_flags_ui` is an admin dashboard. Its route must be behind authentication
(same requirement as `oban_web` and `phoenix_live_dashboard`).

---

## Rate Limiting

`hammer` (with `hammer_plug` for Plug integration) provides rate limiting.

Rate limit configuration on sensitive endpoints (withdrawal APIs, authentication endpoints,
bonus claim flows) is a `:behavioral` change. Removing or weakening a rate limit on a
compliance-relevant endpoint is a `:compliance` change.

The `mix foundry.context` schema surfaces `rate_limited: true/false` for resources that
declare `hammer_plug` middleware.

---

## Caching

`nebulex` is a Foundry dependency used for its internal ETS caches (ADR-015).

Foundry internal usage:
- `Foundry.Context.DocCache` — spec-kit document cache, keyed by `{file_path, mtime}` (ADR-003)
- `Foundry.Context.DocCache` — ExDoc API cache, keyed by `{library_name, version}` (ADR-003)
- Both caches use a simple L1 (in-process ETS via Nebulex) configuration

Target platform usage: project-level concern, not governed by Foundry directly.
Target platforms may use Nebulex independently — it is not imposed on them by Foundry.

---

## Email / Notifications

`swoosh` is the email delivery library. It backs the notification channels declared in
INV-010 (`channel: :email`).

Foundry's `Foundry.Notifications.Dispatcher` uses `swoosh` for email delivery and a
configurable Slack webhook adapter for Slack channels. The manifest declaration
(`channel: :slack` / `channel: :email`) routes to the appropriate dispatcher.

---

## Clustering (Cloud Mode)

In cloud mode, Foundry runs as a multi-node Phoenix cluster. `libcluster` manages node
discovery and mesh formation. The topology strategy is declared in `config/foundry.exs`
and is infrastructure configuration (governed by ADR-006).

WebSocket connections for the Studio UI use Phoenix PubSub for cross-node message delivery.
Mix task subprocesses are always run on the node that received the request — there is no
distributed Mix task execution.

---

## Admin UI Libraries

The following admin UI libraries expose sensitive internal state and must be secured:

| Library | What it exposes | Security requirement |
|---|---|---|
| `oban_web` | Job queue contents, worker state, failure reasons | Must be behind `ash_authentication` session check |
| `phoenix_live_dashboard` | VM metrics, ETS tables, process list | Must be behind `ash_authentication` session check, restricted to admin role |
| `fun_with_flags_ui` | Feature flag state and overrides | Must be behind `ash_authentication` session check, restricted to admin role |

Changes to the routes or access policies for these dashboards are `:behavioral` changes.
Removing authentication from any of these routes is a `:sensitive` change.

---

## Foundry Studio UI Asset Pipeline

The Studio UI (`mix foundry.studio`) uses:

```
tailwind      — CSS framework (via mix task, no Node dependency required)
esbuild       — JavaScript bundling (via mix task)
heroicons     — Icon set (included via the Phoenix component library)
```

When `AshPyro` is used in target platform back-office UIs:
- `AshPyro` builds on DaisyUI which builds on Tailwind — the same `tailwind` mix task
  compilation pipeline applies.
- `AshPyro`-generated components satisfy the `data-*` attribute convention in ADR-007
  because `AshPyro` generates standard LiveView components with data attributes.
  The linter verifies this at compile time.

---

## Out of Scope for Foundry v1

The following are explicitly excluded. Exclusion is a decision, not an oversight.

| Library / Feature | Reason for exclusion |
|---|---|
| `Beacon` CMS | Requires a separate content management governance model; deferred to v2 |
| `AshAI` DSL introspection | AshAI DSL is not yet stable enough to freeze in `mix foundry.context` schema; Foundry v1 will not fail on `AshAI` declarations — it will ignore them and warn |
| Ash 2.x projects | APIs differ significantly; mixing 2.x and 3.x patterns is a lint error |
| Raw Ecto resources | No Spark introspection surface; these get no automation value |
| Non-Elixir target stacks | Automation leverage requires Spark DSL |

---

## Consequences

- Every agent prompt includes the full version manifest from `mix foundry.versions.check` (INV-006 / ADR-010)
- Foundry itself has no `ash_postgres` dependency — it is a target platform dependency. `mix foundry.studio` requires only Elixir and git (ADR-015).
- `ash_postgres` migration lifecycle is in scope for all scaffold operations that add resources or attributes
- Monetary attributes use `Ash.Type.Money` exclusively; the linter rejects raw `Money.t()` declarations
- Authentication resources are always `:sensitive`; authentication scaffolding uses `ash_authentication`'s own Igniter generators directly
- `ash_paper_trail` and `ash_archival` are required on `:sensitive` resources (INV-011, INV-012)
- The forbidden dependency list in ADR-004 applies to direct application dependencies; `ecto_sql` and `postgrex` as transitive dependencies of `ash_postgres` are permitted
- Admin dashboards (`oban_web`, `phoenix_live_dashboard`, `fun_with_flags_ui`) require authentication — the linter checks route configuration

## What This Is Not

This ADR does not constrain what language the Studio UI itself is built in.
It constrains the **target stack** that Foundry reads, validates, and generates.
The Studio backend is also Elixir/Phoenix (same stack), but that is a consequence, not the decision.
--- ./docs/adrs/ADR-002-code-generation.md ---
# ADR-002: Code Generation — Igniter for All Code, No String Interpolation

**Status:** Accepted  
**Date:** 2026-03  
**Deciders:** Platform team

---

## Context

The copilot must generate and modify Elixir source code. There are three approaches:

1. **String interpolation**: build Elixir code as strings, write to disk
2. **Catalogue of pre-built operation modules**: every generation goes through a named Op.* module
3. **Pattern-driven raw Igniter**: agent reads an existing project example, then uses Igniter API directly

String interpolation is simpler to implement. It is wrong for this use case.
A pre-built catalogue requires maintaining 20+ modules that must track every Ash DSL version
change — and it encodes domain-specific assumptions (iGaming blueprints, money attributes)
at the platform level where they don't belong.

## Decision

**All code generation uses raw Igniter, guided by project examples and Foundry conventions.
String interpolation for Elixir source is forbidden. There is no pre-built operation catalogue.**

For every new construct, the agent:
1. Fetches the closest existing project example: `mix foundry.pattern.find <type> --domain <D>`
2. Reads Foundry conventions: `cat .foundry/usage_rules/foundry_conventions.md`
3. Reads exact DSL API if needed: `mix foundry.exdoc <Module>`
4. Generates via raw Igniter API, copying the pattern and applying conventions

For new files: `Igniter.create_new_file/3` or `Igniter.Project.Module.create_module/3`.
For modifying existing files: `Igniter.Project.Module.find_and_update_module/3` with `Sourceror.Zipper`.
For multi-file operations: composed Igniter pipelines, all writing to `foundry/prop_<id>` branch.

**Why examples beat a pre-built catalogue:** An example from the actual codebase encodes
every Foundry convention already — `@moduledoc`, domain wiring, telemetry prefix, test stub
co-location — at the exact current Ash version, without any maintenance overhead. One working
example is worth more than a catalogue module that may drift from the current DSL.

**Two named thin wrappers are retained** for cases where the logic is Foundry-specific
metadata with no Igniter equivalent:
- `Op.AddComplianceLink` — updates the compliance registry (not an AST change)
- `Op.AddAgentStep` (Phase 8) — governance scaffold with dual-proposal cascade

All other generation uses raw Igniter directly.

## Rationale

String-based generation has three failure modes that compound in regulated systems:

**Structural invalidity**: generated Elixir strings can be syntactically valid but semantically wrong (missing `do`/`end`, wrong module nesting, incorrect attribute types). The compiler catches this, but only after the file is written and reviewed, creating a confusing edit → reject → regenerate loop.

**Formatting instability**: string-generated code doesn't match the project's formatter configuration. This creates noisy diffs where formatting changes are mixed with actual logic changes, making review harder.

**Incremental unsafety**: when modifying an existing file, string interpolation can accidentally overwrite adjacent code. Igniter's zipper operations are scoped to specific AST nodes and cannot affect sibling nodes.

Igniter's AST manipulation is the published tool for exactly this use case. It handles formatting, idempotency (applying the same operation twice is safe), and provides dry-run output as a structured diff.

## Migration Generation

Scaffold operations that add or modify resources, attributes, or relationships must also
generate the corresponding `ash_postgres` migration. The mechanism:

```
Agent generates resource/attribute/relationship change:
  → git checkout -b foundry/prop_<id>
  → Igniter apply to branch              (code change only)
  → mix ash.codegen <auto_name>          (on branch — full project context present)
  → read generated migration file
  → git diff main..foundry/prop_<id>     (captures code diff + migration diff together)
  → both shown in review panel
  → git checkout main                    (working tree untouched)

On approval:
  → git merge --ff-only foundry/prop_<id>
  → mix ash.migrate
  → git branch -D foundry/prop_<id>
```

The branch contains the full project state, so `mix ash.codegen` runs correctly with
all dependencies and config. The migration is part of the branch diff and therefore
part of the stale detection mechanism (ADR-009): if `main` has diverged on affected
files since the branch was cut, the proposal is STALE.

For `:sensitive` resources: the migration is classified at the same level as the code change.
A migration touching a sensitive resource's table requires dual approval (ADR-005, INV-001).

## Authentication Scaffold

There is no `Op.AddAuthenticationResource` wrapper — authentication scaffolding uses
`ash_authentication`'s own published Igniter generators directly, the same way
the agent uses any other raw Igniter call. The agent fetches the `ash_authentication`
usage rules (`cat .foundry/usage_rules/ash_authentication.md`) and the closest
existing auth resource pattern before generating. The copilot does not synthesise
authentication code from training memory.

## Foundry Conventions File

`.foundry/usage_rules/foundry_conventions.md` is the replacement for the catalogue.
It documents what every new construct must include:

- Every new module: `@moduledoc` with purpose, sensitivity classification, compliance links
- Every new attribute: `description:` field stating the invariant it protects
- Every new Reactor: idempotency declaration, `@runbook` link, telemetry prefix
- Every new sensitive resource: `use AshPaperTrail.Resource`, `use AshArchival.Resource`
- Every new Transfer: steps list with types, rules list, compliance links

The agent reads this file as part of `speckit.checklist` before generating any new
construct. It is committed to the project repository and versioned alongside the code.

## Consequences

- All generation uses raw Igniter — no catalogue module to maintain or version
- The agent's pattern lookup (`mix foundry.pattern.find`) is the primary quality mechanism:
  idiomatic output comes from copying working project code, not from pre-built templates
- Agents must never use `File.write!/2` or `EEx.eval_string/2` on Elixir source files
- All generation writes to a `foundry/prop_<id>` git branch; the working tree is never
  touched until the proposal is approved and merged
- The diff for review is `git diff main..foundry/prop_<id>` — code and migration together
- Migration diffs are always included in proposals that touch resource structure
--- ./docs/adrs/ADR-003-agent-context-strategy.md ---
# ADR-003: Agent Context — Structured Retrieval, Not RAG Over Code

**Status:** Accepted  
**Date:** 2026-03  
**Deciders:** Platform team

---

## Context

The copilot needs accurate, current information about the project's domain model when generating
proposals. Two approaches:

1. **Classic RAG**: chunk all source files, embed them, vector-search for relevant chunks
2. **Structured retrieval**: query the live Spark DSL introspection directly

We also need library documentation to prevent hallucination on Ash 3.x APIs.

## Decision

**Structured retrieval over live DSL introspection for all code-derived information.**  
**Small event-driven RAG only for unstructured prose documents (ADRs, runbooks, regulations).**  
**Three-tier library documentation strategy for anti-hallucination.**

### What uses structured retrieval

Everything derivable from compiled modules:
- Resource attributes, actions, relationships, policies
- Transfer steps, rules, idempotency declarations
- Blueprint config schemas, eligibility rules
- Compliance links and requirement mappings
- Runbook links, alert declarations
- State machine states and transitions
- AshJsonApi routes and route options
- Paper trail and archival configuration
- Monetary attribute types and CLDR backend reference
- Authentication subject configuration
- Oban queue assignments
- Telemetry prefix declarations
- Pending migration status
- Feature flag usage

Source: `mix foundry.context --json <Module>` — re-runs on every request, always current.

### What uses full inclusion (not RAG)

The spec-kit documents — ADRs, runbooks, regulations — are included in full in the LLM
context on every request. No indexing, no embeddings, no vector search.

**Why not RAG:** At current and projected scale, the entire spec-kit fits comfortably in
a single context window (~4000 tokens at maturity, well within the ADR-010 budget).
RAG adds infrastructure complexity, staleness risk, and retrieval errors to solve a
problem that doesn't exist at this scale. Full inclusion is simpler, always current
(read from disk at request time), and more reliable — the copilot sees every constraint,
not just the ones a similarity search happened to surface.

**The corpus boundary is strict:** spec-kit docs only (`docs/adrs/`, `docs/runbooks/`,
`docs/regulations/`). Source files (`lib/`, `test/`) are never included wholesale —
those use structured DSL introspection. The combination of full spec-kit inclusion +
structured code retrieval gives the copilot complete context without the overhead of
a general-purpose embedding pipeline.

**Cache strategy:** The spec-kit is read from disk once per request cycle and cached
by file mtime. If no file has changed since the last request, the cached concatenation
is reused. This is a simple key-value store keyed on `{file_path, mtime}` — implemented
via Nebulex L1 (in-process ETS). No embedding pipeline, no vector index, no scheduled sync jobs.

### Three-tier library documentation

**Tier 1 (always in every LLM prompt):**
```
Current stack: ash 3.4.1, ash_double_entry 1.0.3, ash_postgres 2.x, phoenix 1.7.x, ...
```
This prevents Ash 2.x vs 3.x confusion, the most common hallucination class.

**Tier 2 (fetched on demand, cached 24h):**
ExDoc JSON for the specific DSL element being generated. When generating a resource attribute,
fetch `GET /api/docs/ash/Resource.Dsl.Attribute` — exact current options, types, defaults.
Not chunks. The exact API surface for the specific element.

The ExDoc cache uses per-library-per-version keys: `{library_name, version}` (e.g.,
`{"ash", "3.4.1"}`). When `mix.exs` changes, only entries for libraries whose versions
changed are evicted. Other libraries' cached docs remain valid. Implemented via Nebulex L1.

**Tier 3 (fetched on demand, no cache needed — it's in the project):**
The closest existing example of the pattern being generated, retrieved from the actual codebase.
When generating a new Rule, retrieve the simplest existing Rule. The agent copies a working
pattern from the same project instead of synthesizing from training memory.
Hallucination rate on Ash-specific syntax drops to near zero.

## Rationale

Classic RAG over code is wrong for this use case for three reasons:

**Staleness**: chunks indexed at a point in time. Ash resources change frequently during active development. A chunk about `BonusAward.wagering_progress_minor` that's 2 days old is wrong after a refactor.

**Wrong granularity**: vector search finds semantically similar paragraphs. The agent needs attribute-level precision. "What does `wagering_progress_minor` track?" needs the exact `@description` tag — not the surrounding module text.

**Hallucination amplification**: RAG retrieves plausible-looking text. With poor metadata quality, it confidently returns wrong context. Structured introspection fails explicitly when a module doesn't exist — it doesn't return something that looks like it might be right.

For spec-kit documents, RAG is equally unnecessary: the entire corpus fits in context.
Similarity search would add infrastructure complexity and retrieval failures to a problem
that full inclusion solves trivially. The copilot should see *all* constraints every time,
not a similarity-ranked subset that might miss the relevant ADR.

## Consequences

- The `mix foundry.context` task is the critical path — its JSON schema must be stable
- Every piece of information the copilot uses for code decisions must be traceable to a live source
- Spec-kit docs are read from disk per request — no indexing pipeline, no embedding model dependency
- There is no RAG infrastructure in Foundry. If the spec-kit grows beyond ~15,000 tokens, the context strategy should be revisited — but this is not a near-term concern and should not be optimised for prematurely
- Nebulex is used for both the spec-kit mtime cache and ExDoc cache — no additional cache infrastructure

## `mix foundry.context` Schema

This schema is the contract. Breaking changes require an ADR. Fields marked `(new)` were
added in the post-review pass to cover the full ecosystem.

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

  "feature_flags": []
}
```

Do not invent fields. If a field is absent from this schema, it does not exist.
--- ./docs/adrs/ADR-004-dependency-governance.md ---
# ADR-004: Dependency Governance — Category-Based Approval

**Status:** Accepted  
**Date:** 2026-03  
**Deciders:** Platform team

---

## Context

Agents can propose adding dependencies. An unconstrained approved-list approach requires
constant maintenance and becomes stale. We need a policy that scales without manual updates.

## Decision

**Category-based auto-approval with a precise forbidden list.**

```
:auto_approve (no ADR, no human approval needed):
  - :testing_tools       # stream_data, mox, bypass, ex_machina, faker
  - :dev_tools           # credo, dialyxir, sobelow, ex_doc

:require_adr (ADR explaining why, then routes to domain lead):
  - :http_clients        # adding a second HTTP client — use Req by default
  - :databases           # anything touching data storage layers
  - :auth                # authentication/authorization libraries
  - :payments            # payment provider SDKs
  - :feature_flags       # feature flag libraries (fun_with_flags is the standard — a second one requires ADR)
  - :caching             # caching libraries (nebulex is the standard — a second one requires ADR)
  - :email               # email delivery libraries (swoosh is the standard)
  - :clustering          # cluster topology libraries (libcluster is the standard)

:always_forbidden (compiler error, no override):
  - :httpoison           # use Req
  - {:ecto, direct: true}  # see clarification below — transitive via ash_postgres is permitted
  - {:oban, conflicts_with: :ash_oban}
  - any library not published to Hex (no git deps in production)
```

Anything not in any list above: classified as `:require_adr`.

## Clarification: `:ecto` Forbidden List Scope

The forbidden entry is `{:ecto, direct: true}` — meaning Ecto as a **direct application-level
dependency** is forbidden. The correct data layer is Ash, which uses `ash_postgres`, which
depends on `ecto_sql` and `postgrex` as transitive dependencies.

What is forbidden: adding `{:ecto, "~> 3.x"}` to your `mix.exs` directly and using
`Ecto.Repo` / `Ecto.Schema` directly in application code.

What is permitted: `ecto_sql` and `postgrex` appearing in your lockfile as transitive
dependencies of `ash_postgres`. An agent reading the lockfile must not flag these as violations.

The linter implements this distinction: it inspects `mix.exs` `deps` declarations, not the
lockfile. A direct `:ecto` declaration in `mix.exs` is a lint error; presence in the lockfile
is not.

## Clarification: `Req` and `Finch`

`Req` is the standard HTTP client. `Finch` is `Req`'s connection pool dependency — it
appears in the lockfile as a transitive dependency and is permitted.

Configuring `Finch` pool sizes directly (in `config/`) for performance tuning is permitted
as infrastructure configuration (ADR-006). Adding `finch` as a direct dependency is only
needed if you are bypassing `Req` and using `Finch`'s API directly — this requires an ADR
(`:http_clients` category).

Foundry's copilot engine uses `Req` for its LLM API calls (ADR-010). This uses the same
`Finch` instance as the application. If pool contention is observed, a dedicated `Finch`
pool for the copilot engine may be configured — this is an infrastructure concern (ADR-006),
not a dependency addition.

## Test Tool Specifications

The `:auto_approve` testing tools are used as follows in generated test modules (ADR-007):

| Library | Used for |
|---|---|
| `stream_data` | Property-based tests for Transfer rules and Blueprint boundaries |
| `mox` | Adapter contract test doubles |
| `bypass` | HTTP mock server for external adapter integration tests |
| `ex_machina` | Fixture factories in `<AppName>Test.Generators` module |
| `faker` | Realistic data in fixtures (names, emails, amounts) |

Generated test skeletons use these libraries by convention when the agent generates test modules.
The copilot reads the project's generator module to confirm what is available before referencing
a generator in a skeleton. It never references a generator that doesn't exist in the project.

## Consequences

- Agents may add testing and dev dependencies without ceremony
- Adding a payment SDK requires an ADR first — this is appropriate given the stakes
- The forbidden list stays small and precise; it's not a whitelist of allowed libraries
- The `:ecto` forbidden rule targets direct application usage, not transitive lockfile presence
- `Req` / `Finch` pool configuration is infrastructure, not a dependency addition
--- ./docs/adrs/ADR-005-change-approval-model.md ---
# ADR-005: Change Approval Model — Four-Class Classification

**Status:** Accepted  
**Date:** 2026-03  
**Deciders:** Platform team

---

## Context

Not all changes carry the same risk. A new `@description` tag on an attribute is structurally
different from adding a step to a Transfer that moves money. A single approval model is too
restrictive for low-risk changes and insufficiently safe for high-risk ones.

The risk classes are real but they are **domain-agnostic** — a healthcare platform has PHI
resources that need dual approval. A legal platform has privileged documents. An iGaming
platform has ledger entries. The model must not hardcode any one domain's terminology.

## Decision

**Four change classes with different approval requirements. The `:sensitive` class is configured per project.**

| Class | Definition | Approver | Auto-apply | Audit logged |
|---|---|---|---|---|
| `:structural` | New resource, attribute, relationship, description update, test skeleton | Any developer | Configurable per project | No |
| `:behavioral` | New Rule, Transfer step, Blueprint, Reactor, Oban job, state machine transition, API route, feature flag | Domain lead | Never | Yes |
| `:sensitive` | Resources/attributes listed in `manifest.sensitive_resources` — whatever the domain designates as requiring dual approval | Sensitive lead + one other (dual approval) | Never | Yes, mandatory |
| `:compliance` | Changes to `compliance:` declarations, policy modules, requirement links, compliance-gated feature flags | Compliance officer | Never | Yes, ADR required |

**When in doubt, classify upward.**

A `:behavioral` change misclassified as `:structural` and auto-applied is a governance failure.
A `:structural` change misclassified as `:behavioral` is merely inconvenient.

**Dual approval for `:sensitive`** means two distinct humans must approve before apply.
The copilot tracks approval state and will not trigger Igniter apply until both are recorded.

**ADR required for `:compliance`** means the proposal includes a link to an existing or new ADR
explaining why the compliance declaration is changing. A proposal without an ADR link is blocked.

## How `:sensitive` Resources Are Declared (project manifest)

```elixir
# Each target project's .foundry/manifest.exs
sensitive_resources: [
  # iGaming example:
  MyApp.Finance.LedgerEntry,
  MyApp.Finance.Wallet,
  # Healthcare example (different project):
  # MyApp.Records.PatientRecord,
  # MyApp.Records.ClinicalNote,
  # Authentication resources are always sensitive regardless of this list:
  # (MyApp.Accounts.User, MyApp.Accounts.Token — added automatically)
]

approvers: [
  sensitive_lead: "finance-lead@company.com",   # or :phi_lead, :data_lead, etc.
  domain_lead: "platform-lead@company.com",
  compliance_officer: "compliance@company.com"
]
```

The classifier reads this list. It does not hardcode module names or attribute patterns.

**Authentication resources are always `:sensitive`** regardless of the manifest list.
`ash_authentication` User and Token resources are added to the sensitive set automatically
by the classifier. This cannot be overridden.

## Migration Classification

Migrations generated by `ash.codegen` are classified at the same level as the code change
that triggered them. The classifier inspects the migration file for which tables it touches:

- A migration touching a table that backs a `:sensitive` resource → `:sensitive`
- A migration touching a table involved in a `compliance:` declaration → `:compliance`
- All other migrations → same class as their triggering code change

The approval workflow requires the migration and the code change to be approved together.
A migration cannot be approved independently of the code change that generated it.

## Classification Rules (for the copilot's classifier)

The classifier inspects the proposed diff in order:

```
1. Does the diff touch any module in manifest.sensitive_resources,
   OR any ash_authentication User or Token resource,
   OR any migration touching a sensitive resource's table?
   → :sensitive

2. Does the diff touch any compliance: declaration, docs/regulations/,
   requirement ID, or any feature flag that gates a compliance control?
   → :compliance

3. Does the diff contain any of:
   - New module using Ash.Resource.Change behaviour
   - New module using Ash.Policy.Authorizer behaviour
   - New custom Ash.Resource.Validation
   - New Reactor module
   - New Rule pattern module (implements evaluate/2)
   - New Blueprint pattern module (implements execute/2)
   - New non-:read action on existing resource
   - New Oban worker module
   - New AshStateMachine transition
   - New Ash.Notifier implementation
   - New ash_json_api route declaration
   - New fun_with_flags flag declaration
   - Modification to an existing rate limit configuration
   - Removal or weakening of a rate limit on a sensitive endpoint
   - Changes to existing action implementations (not just adding attributes)
   → :behavioral

4. Removal or weakening of authentication on oban_web, phoenix_live_dashboard,
   or fun_with_flags_ui routes
   → :sensitive (admin dashboard de-authentication is treated as sensitive)

5. Everything else → :structural
   Includes: new Ash resource with only :read actions, attribute additions,
   @description/@moduledoc changes, relationship additions (no action side effects),
   test file additions, config value changes, adding ash_paper_trail or ash_archival
   to a non-sensitive resource
```

Rules are evaluated in this order. The first match wins.

## Consequences

- The manifest declares sensitive resources and approver identities per project
- Authentication resources (User, Token) are always `:sensitive` without manifest declaration
- Migrations are classified by the tables they touch, not by their file type
- Feature flags on compliance controls are `:compliance` class changes
- Admin dashboard route de-authentication is `:sensitive`
- Foundry routes proposals to the correct approver queue — the copilot never decides routing
- Approvers receive: diff + lint result + impact analysis + change class + time estimate
- All `:sensitive` and `:compliance` approvals are stored with timestamp, approver identity, diff hash
- The audit log is append-only — approvals cannot be edited or deleted
- A project with no `sensitive_resources:` declared has no `:sensitive` class for custom resources — but authentication resources are still always `:sensitive`
--- ./docs/adrs/ADR-006-infrastructure-governance.md ---
# ADR-006: Infrastructure Governance — Proposal-Only from Agents

**Status:** Accepted  
**Date:** 2026-03  
**Deciders:** Platform team

---

## Context

Agents that understand code changes may also need to propose infrastructure changes
(Kubernetes resources, Postgres config, CI pipeline additions). The question is how much
autonomy agents have over infrastructure.

## Decision

**Agents propose infrastructure changes as structured diffs. Humans with infrastructure context apply them. No exceptions.**

The CI base pipeline is owned by the platform team. Projects extend it via overrides only:

```yaml
# .github/workflows/ci.yml — generated and owned by the platform
extends: foundry-studio/ci-base@v2
overrides:
  test_timeout: 10m
  additional_checks:
    - mix foundry.studio.compliance.check --strict
```

Agents may propose changes to the `overrides:` section.
Changes to the base pipeline require a platform-level PR, not a project-level approval.

When an agent determines infrastructure change is needed (e.g., new Oban queue requires
a Kubernetes ConfigMap change and a PgBouncer pool entry), it:
1. Generates the application code change as normal (Igniter, routes for approval)
2. Generates the infrastructure change as a PROPOSAL — a rendered diff in the review panel
3. Tags the proposal with `:infrastructure` so the manifest routes it to the infrastructure approver
4. The infrastructure approver reviews and applies manually

## Rationale

Infrastructure correctness cannot be verified by `mix foundry.studio.lint.all`. A wrong resource
limit affects all running pods. A wrong Postgres config affects all connections. The blast radius
extends far beyond what an agent can verify from the application codebase alone.

This is non-negotiable regardless of agent confidence level.

## Consequences

- The Studio review panel can render infrastructure diffs alongside code diffs in a single proposal
- Infrastructure proposals are never auto-applied even when all other parts of the change are `:structural`
- The audit log records infrastructure proposals with the same fidelity as code changes
--- ./docs/adrs/ADR-007-test-generation-strategy.md ---
# ADR-007: Test Generation — DSL Declarations Drive Skeletons, Compliance Requirements Drive E2E

**Status:** Accepted  
**Date:** 2026-03  
**Deciders:** Platform team

---

## Context

Testing a regulated platform has five distinct layers. The platform needs to generate
meaningful test skeletons, not empty files. The question is what information drives generation
and what requires human authorship.

## Decision

**DSL declarations generate structural test skeletons. Compliance requirements generate E2E scenarios.
Developers fill in expected values and generators. The platform never generates expected values.**

## Test Tool Assignments

Test tools and approval categories: ADR-004 §Test Tool Specifications. Usage patterns:
`mox` for adapter contract doubles (behaviour-level), `bypass` for HTTP mock server (request-level).
The copilot reads `<AppName>Test.Generators` to confirm generator availability before referencing any generator in a skeleton.

### What is generated automatically

| Source declaration | Generated test | Tool used |
|---|---|---|
| `Transfer` with `idempotency` | Property test: duplicate key never double-debits | `stream_data` |
| `Transfer` with `rules:` | Property test: each rule's rejection path | `stream_data` |
| `Rule` with `spec_invariants` | Property test skeleton per declared invariant | `stream_data` |
| `Blueprint` | Eligibility, calculation boundary, wagering, expiry, forfeiture skeletons | `stream_data` |
| `LiveResource` declaration | Renders correctly, filter tests, action tests | ExUnit + Wallaby |
| `AshJsonApi route` | Auth (401), multitenancy (403), validation tests | ExUnit + `bypass` |
| `AshStateMachine` | Transition guard tests, invalid transition rejection tests | ExUnit |
| Provider adapter module | HTTP contract test against `bypass` server | `bypass` + `mox` |
| RG-* requirement in regulation file | E2E browser test scenario stub with compliance tags | Wallaby + ExUnit tags |

### What is NOT generated

- Expected amounts or monetary values
- Business-specific assertions ("the fee is 2.5%")
- User journey steps for scenarios without a regulation source
- Test data generators (these live in `<AppName>Test.Generators` and are maintained by the team)

### The compliance → E2E link

Every RG-* requirement gets an E2E scenario stub tagged `:compliance, :rg_xx_nnn`.
`mix foundry.compliance.check` verifies that tagged tests exist AND pass.
The compliance dashboard shows: "RG-UK-002: ✅ PASS (last CI run: 2026-03-04)".

This closes the loop: requirement → implementation → test → evidence. All machine-linked.

### Generators are the shared foundation

Each target project maintains a `<AppName>Test.Generators` module providing the data generators
all tests share. Foundry provides a default implementation via `mix foundry.spec_kit.init`;
projects extend it. Generated test skeletons reference generators by convention name —
e.g., `entity_with_state/1`, `event_fixture/1`. The copilot reads the project's generator
module to know what's available and uses only generators that actually exist in the project.

## The `data-*` attribute convention (required for E2E stability)

Every generated LiveView component must include semantic `data-*` attributes:
- `data-action="suspend"` on action buttons
- `data-field="email"` on form inputs
- `data-player-id="{id}"` on row elements
- `data-column="status"` on table headers

E2E tests target these attributes, not CSS classes. This makes tests stable across UI redesigns.
The `LiveResource` macro enforces this in its generated output. The linter checks for it.

**AshPyro components:** When `AshPyro` is used as the back-office component library, its
generated components include `data-*` attributes in the same convention. The linter rule
that checks for `data-*` attributes understands `AshPyro`-generated component structure
and does not require manual attribute addition for components generated by `AshPyro`'s macros.

## Domain Coverage Formula

The Test Coverage Map panel shows domain coverage, not line coverage. The formula:

```
transfer_coverage     = transfers_with_property_test / total_transfers
rule_coverage         = rules_with_invariant_tests / total_rules
blueprint_coverage    = blueprints_with_scenario_tests / total_blueprints
compliance_coverage   = requirements_with_e2e_test / total_rg_requirements
ui_coverage           = live_resources_with_integration_test / total_live_resources

domain_coverage = weighted_mean([
  {transfer_coverage,   0.25},
  {rule_coverage,       0.20},
  {blueprint_coverage,  0.20},
  {compliance_coverage, 0.25},
  {ui_coverage,         0.10}
])
```

Weights are configurable per project in the manifest under `coverage_weights:`.
The defaults above reflect the relative risk of each layer in regulated platforms —
compliance E2E and Transfer property tests are the most critical to have.

A score below 0.8 triggers a warning in CI. Below 0.6 fails CI if the project manifest
has `coverage_gate: true` (default false for new projects, recommended true before go-live).

## Consequences

- Line coverage metrics are not the primary measure — domain coverage is (see Studio's Test Coverage Map panel)
- A Transfer with no property test is a lint warning
- A compliance requirement with no E2E scenario is flagged in the compliance dashboard
- The copilot can generate tests on demand: "generate tests for the withdrawal flow" → complete test module as diff
- `bypass` is the mechanism for adapter contract tests; the copilot knows to include it when generating adapter test modules
- The copilot reads the project's generator module before generating any test that references fixtures
--- ./docs/adrs/ADR-008-visualization-paradigm.md ---
# ADR-008: Visualization Paradigm — Read-Only Panels, Activity Feed Is the Only Change Interface

**Status:** Accepted  
**Date:** 2026-03  
**Deciders:** Platform team

---

## Decision

The system map and all visualization panels are **strictly read-only**. All changes flow
through the copilot engine via the Activity Feed. This is enforced by architecture —
there are no write paths in the visualization layer.

The five panels and their roles:

| Panel | Purpose |
|---|---|
| System Map | D3 graph — nodes are Ash resources, edges are relationships, clustered by domain. Click a node → left-side detail drawer with intent shortcuts. |
| Compliance Matrix | RG-* requirements × implementation status. Click a gap → pre-populates Activity Feed. |
| Operations Board | Runbook status, adapter contract results, Reactor failure log. |
| Test Coverage Map | Domain coverage (not line coverage) by type. Click a gap → pre-populates Activity Feed. |
| Activity Feed | Persistent right sidebar. Event stream + chat input. The only change interface. |

Full interaction spec: ADR-012. Storage model: ADR-015.

## Why Drag-and-Drop Was Rejected

Spatial editing fails for complex domain models: finding the right node in 50+ graphs
requires more effort than typing; spatial precision errors produce wrong connections with
no error signal; metadata like compliance links and rule applications have no natural
spatial representation; it implies the map is the model when the Ash code is the model.

Natural language intent through the Activity Feed is faster and auditable for every case
this tool targets.

## Consequences

- No write paths in System Map, Compliance Matrix, Operations Board, or Test Coverage Map
- `Cmd+K` palette is navigation-only — does not expose scaffold operations (ADR-012)
- Node detail drawer opens left to avoid spatial collision with Activity Feed (right) and review panel (bottom) — see ADR-012
--- ./docs/adrs/ADR-009-concurrent-proposals.md ---
# ADR-009: Concurrent Proposals — Git Branch Isolation and Base-Commit Stale Detection

**Status:** Accepted
**Date:** 2026-03
**Deciders:** Platform team

---

## Context

Multiple developers may use Foundry simultaneously and generate proposals that touch the
same source files. Without coordination, two approved proposals could produce conflicting
AST operations on the same file, resulting in a corrupted or inconsistent codebase.

Three approaches were considered:
1. **Pessimistic locking** — lock files when a proposal is generated, block others
2. **CRDT / operational transform** — merge concurrent edits automatically
3. **Optimistic locking** — detect conflicts at apply time, not generation time

## Decision

**Git branch isolation with base-commit stale detection.**

Every proposal writes to an isolated `foundry/prop_<id>` branch, never to the working
tree directly. The proposal stores the `base_commit` SHA at the time of generation.

**At apply time**, before merging:
```bash
# Check if affected files changed on main since the branch was cut
git diff <base_commit>..HEAD -- <affected_files>
```
- Empty output → fast-forward merge is safe → proceed
- Non-empty output → files changed on main since generation → **STALE**

Stale proposals are surfaced to the requester with the specific files that changed.
One-click regenerate re-cuts the branch from current HEAD and re-runs generation.

## Rationale

**Why git branches, not file hash maps:** The branch approach uses git's own ancestry
and diff machinery instead of reimplementing it. It provides complete isolation during
generation (the working tree is never touched), makes the diff artifact (`git diff
main..foundry/prop_<id>`) the natural review surface, and gives the compilation step
a valid full-project context. A hash map of individual files is a manual reimplementation
of what `git diff` already does correctly.

**Why not pessimistic locking:** Serialised bottlenecks for teams working on different
domains. Proposals that spend hours in approval queues would block all other generation
in the interim.

**Why not CRDT/OT:** AST merge is complex and produces changes that are hard to audit.
In a regulated system, every change needs a clear human decision chain.

**Branch cleanup:** Branches are deleted on proposal COMMITTED, REJECTED, or SUPERSEDED.
`mix foundry.proposals.gc` removes orphaned branches from crashed or abandoned proposals.

## The Stale Proposal UX

Stale banner rendering and regenerate interaction: ADR-012 §Stale Proposal Banner.

On detecting STALE: re-cut the branch from HEAD, re-run Igniter and `mix ash.codegen`,
re-compile. If the resulting diff is identical to the stale one, the conflict was in an
unrelated part of the codebase — the banner clears and the proposal proceeds. If the
diff differs, the new diff is shown for review.

## Proposal ID Generation

`"prop_" <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)` — e.g. `prop_3a7f1b2c`.
8 hex chars provide 4 billion combinations, sufficient for git-backed local storage.
The git branch is `foundry/prop_3a7f1b2c`.

## Consequences

- Proposals store `base_commit: "sha256..."` (one field) instead of a map of file hashes
- The apply step checks `git diff <base_commit>..HEAD -- <affected_files>` before merging
- Stale proposals are never silently applied — always surfaced to the requester
- The approval record stores the `base_commit` at the time of approval — providing a
  complete audit trail of what codebase state the approver reviewed
- No distributed locking infrastructure needed — git branches are the isolation mechanism
- The working tree is never modified during proposal generation; `mix foundry.studio`
  operates cleanly alongside active development
--- ./docs/adrs/ADR-010-llm-model-and-context.md ---
# ADR-010: LLM Selection — Claude Sonnet, Agentic Context Model

**Status:** Accepted
**Date:** 2026-03
**Deciders:** Platform team
**Supersedes:** ADR-010 v1 (fixed-slot budget model)

---

## Context

The copilot engine requires an LLM for three distinct tasks:
1. **Intent classification** — question, change, or ambiguous?
2. **Proposal generation** — structured parameters for an Igniter operation (Phase 4+)
3. **Question answering** — answer domain questions from context

The original ADR-010 specified a fixed 6-slot context assembly model. This has been
superseded by an agentic loop model: the agent has a shell, uses Mix tasks directly,
and fetches what it needs rather than receiving a pre-assembled fixed window.

---

## Decision

**Primary model: Claude Sonnet (latest stable) for all task types.**
**The agent operates in a single agentic loop with a bash tool.**
**Context is assembled in three tiers: system prompt, session snapshot, retrieved via shell.**

---

## Intent Classification

Classification is the **first reasoning step of the main agent loop** — not a separate
pre-LLM API call. The agent classifies the user's message as its opening reasoning step
before any tool calls.

**Four intent types:**

- `question` — user asks about current system state. Indicators: interrogative syntax,
  question marks, no imperative change verb.
- `change` — user wants to modify the system. Indicators: imperative verbs (add, create,
  update, remove, generate, link), description of desired future state.
- `speckit` — user asks to draft or update an ADR, runbook, or regulation. Indicators:
  "write an ADR", "update the runbook", "add a regulation entry". Produces a plain-text
  proposal; no Igniter call.
- `ambiguous` — message contains both question and change indicators, or neither.
  Routes to the one-clarifying-question path (INV-005).

**Confidence threshold:** When the agent's confidence in its classification is below 0.7,
it treats the intent as `ambiguous` regardless of which type it leans toward.

**Phase gate:** After classification, the agent checks `change_generation_enabled`.
If `false` and intent is `change`: produce a `CHANGE_PREVIEW` response describing the
operation without generating a diff (Phase 3 only — see §Phase-Gated Behaviour).

Classification and confidence are emitted in the reasoning trace:
```json
"intent_classification": {
  "task": "change",
  "confidence": 0.91
}
```

No separate API call. No `IntentClassifier` module.

---

## Context Model — Three Tiers

The copilot operates with a three-tier context model. Each tier has different
assembly timing, caching behaviour, and token characteristics.

---

### Tier 1 — System Prompt (assembled once per Studio session)

Loaded by `Foundry.Copilot.ContextBuilder` at Studio startup. Reloaded only on
Studio restart or stack version change detection.

| Component | Token bound | Source | Cache key |
|---|---|---|---|
| AGENTS.md | ~800 | File read | `{:spec_kit, path, mtime}` |
| Stack versions | ~200 | `mix foundry.versions.check` | `{:versions, mix_exs_mtime}` |
| Spec-kit index | ~400 | `.foundry/spec_kit_index.json` | `{:spec_kit_index, index_mtime}` |
| **Tier 1 total** | **~1400** | | |

AGENTS.md is the agent's constitution — invariants, orientation, spec-kit task postures,
shell constraints, key Mix task reference. It is never dropped or summarised.

The spec-kit index gives the agent a map of all spec-kit documents (ADRs, runbooks,
regulations, usage rules) with summaries and tags. The agent reads this directly from
context to decide which documents to read via bash. No search tool needed.

INV-006 is enforced at ContextBuilder initialisation — structurally impossible to start
the agent loop without stack versions in the system prompt.

---

### Tier 2 — Session Snapshot (refreshed per copilot request)

A single compact JSON object assembled by `Foundry.Copilot.ContextBuilder` at the
start of each request. 60-second TTL. Reflects current project state.

**Source:** `mix foundry.project.snapshot`
**Token bound:** ≤ 400 tokens
**Schema:** `docs/mix_task_summary_schemas.md`

Contains: domain list, sensitive module names, project structure shape (workers,
integrations, web layer), health signals (lint errors, open proposals, compliance gaps,
pending migrations), key file digest (core deps from mix.exs, approver from manifest).

**Why a snapshot replaces eight separate components:** Earlier drafts assembled domain
map, compliance summary, lint status, open proposals, pending migrations, project
structure, mix.exs, and manifest.exs separately (≤ 900 tokens total). The snapshot
gives the same orientation signal in ≤ 400 tokens with one assembly call and one
cache entry. When the agent needs depth on any component, it uses bash.

---

### Tier 3 — Shell and Tools (fetched on demand during the agent loop)

The agent has access to two interfaces for retrieving context during the loop:

**bash(command)** — a shell with a permitted command list (see §Shell Constraints).
This is the primary retrieval interface. The agent uses standard Unix tools and Mix
tasks to read files, search source, run the compiler, check lint, and fetch API docs.

```bash
# Read any file
cat docs/adrs/ADR-005-change-approval-model.md
cat lib/my_app/workers/payment_processor.ex
cat .foundry/usage_rules/ash.md

# Search across source
grep -rn "def handle_payment" lib/ --include="*.ex"
grep -B3 -A50 "defmodule.*Wallet" lib/my_app/finance/wallet.ex

# Navigate structure
ls lib/my_app/integrations/
find lib/ -name "*.ex" -path "*/workers/*"

# Semantic module introspection
mix foundry.context MyApp.Finance.Wallet --json

# API reference at pinned version
mix foundry.exdoc Ash.Resource.Attribute --function allow_nil?

# Pattern finding
mix foundry.pattern.find rule --domain Finance

# Verify writes
mix compile 2>&1
mix foundry.lint.all --json
mix test test/my_app/finance/wallet_test.exs 2>&1
```

**Two structured tools** for operations the shell cannot replicate with equivalent quality:

| Tool | Returns | Token bound | Rationale |
|---|---|---|---|
| `mix foundry.pattern.find <type> [--domain D]` (via bash) | Top-ranked existing DSL example — see §Pattern Selection | 400 | Ranking algorithm encodes domain logic: same type, same domain, most attributes, has tests, not sensitive. Deterministic and unit-testable. |
| `mix foundry.operation.schema <Op>` (via bash) | Parameter contract for a catalogue operation | 300 | Operations are documented in `.foundry/usage_rules/foundry_operations.md` but the Mix task provides structured JSON for programmatic use. |

Both are Mix tasks called via bash — not separate tool schemas. The agent calls them
like any other Mix task. The distinction from arbitrary bash is that their output
format is specced and stable.

**Circuit breaker:** `max_tool_calls` per request (default 8, manifest key
`copilot.max_tool_calls`). If reached without resolution: `:context_budget_exceeded`.
Safety valve against runaway loops — normal operations never approach this limit.

---

### Total context characteristics

| Tier | Bound |
|---|---|
| Tier 1 (system prompt) | ~1400 tokens |
| Tier 2 (session snapshot) | ≤ 400 tokens |
| Tier 3 (shell / tools, accumulated) | Grows during loop; circuit breaker at 8 calls |
| User message + 3-turn history | ~300 tokens |
| **Static total (Tier 1 + 2)** | **~1800 tokens** |

Well within any current model's context window. When static total approaches 3000
tokens, revisit this ADR.

---

## Shell Constraints

The bash tool operates with a permitted command list. This is enforced at the adapter
layer — blocked commands are rejected before execution with a structured error.

**Permitted:**

```
Read:      cat, ls, find, grep, head, tail, sed, wc, awk (read-only patterns)
Mix tasks: mix compile, mix foundry.*, mix test <specific-file>
Git read:  git log, git diff, git status, git show, git blame
```

**Blocked:**

```
Direct writes:   File.write!, cp/mv targeting lib/ or config/ — use Igniter
Git writes:      git commit, git push, git merge — Foundry manages commits
Deps:            mix deps.get, mix deps.compile — :compliance class, proposal-only
DB ops:          mix ecto.migrate, mix ash.migrate — proposal-only, never from agent
Network:         curl, wget, npm, pip, mix hex.* — no network from agent shell
Process:         kill, pkill, systemctl — no process management
```

The blocked list maps directly to INV-001 (no autonomous sensitive changes), INV-002
(no direct filesystem writes), INV-004 (infrastructure proposal-only), and the
principle that dependency and schema changes are governed changes, not agent actions.

---

## Change Intent Reasoning Posture

For `change` intents, the agent follows this posture before producing any output.
Enforced via system prompt instruction, not a separate API call.

1. Read the spec-kit index (already in Tier 1) — identify relevant ADRs and INVs by tag
2. Read those documents via `bash("cat <path>")` — follow cross-references with further reads
3. Read module context: `bash("mix foundry.context <Module> --json")`
4. Read a pattern example if creating a new construct: `bash("mix foundry.pattern.find <type>")`
5. Read the operation schema if using a catalogue operation: `bash("mix foundry.operation.schema <Op>")`
6. Reason about change classification and contradictions
7. Emit structured contradiction check block in reasoning trace (see §Reasoning Trace)
8. If contradiction: BLOCKED — cite ADR/INV, do not proceed
9. If no contradiction: CHANGE_PREVIEW (Phase 3) or proposal parameters (Phase 4+)

**The agent follows references, it does not preload.** The index in Tier 1 ensures all
ADR summaries are visible. References encountered during reading (e.g. "see ADR-005
§Migration Classification") trigger additional `cat` calls. Fetch on reference, not
on anticipation.

---

## Pattern Selection Criteria

`mix foundry.pattern.find <type> [--domain D]` returns the module whose Spark DSL
declarations most closely match what the agent is trying to generate.

**`type`** — required. One of: `rule`, `transfer`, `reactor`, `blueprint`, `resource`,
`oban_worker`.

**`domain`** — optional Ash domain module name. Scopes search; falls back to
cross-domain if no match found within the domain.

**Ranking (applied in order):**
1. Same construct type (required filter, not a tie-breaker)
2. Same domain as target (preferred)
3. Highest DSL attribute declaration count (richer example is more useful)
4. Has associated property tests (agent uses as model for test generation)
5. Not `:sensitive` in manifest (avoids leaking sensitive field names as scaffolding suggestions)

Output: full `mix foundry.context` struct for the top-ranked module, truncated at
400 tokens if necessary (truncation preserves module header and first 5–8 attributes).

Backed by `Foundry.Context.PatternFinder`. Deterministic and unit-testable — no fuzzy
matching.

---

## Usage Rules

`.foundry/usage_rules/` contains one Markdown file per dependency with agent-oriented
guidance: patterns, anti-patterns, idiomatic usage, version-specific gotchas. More
useful than ExDoc for agent consumption — written at the pattern level, not type level.

**Sources:**
- Packages that ship `USAGE.md` or `AGENTS.md` at package root — copied at `mix deps.get`
- Foundry-maintained rules for the core stack: Ash 3.x, Reactor, Phoenix LiveView, Ecto
- `foundry_conventions.md` — Foundry-specific generation conventions (module structure,
  required annotations, domain wiring, test co-location). See ADR-002 §Foundry Conventions File.

Generated by `mix foundry.usage_rules.fetch`. Output committed to `.foundry/usage_rules/`.
Indexed in the spec-kit index with type `usage_rules`. Agent reads via bash.

```bash
cat .foundry/usage_rules/ash.md
cat .foundry/usage_rules/foundry_operations.md
grep -A20 "Op.AddAttribute" .foundry/usage_rules/foundry_operations.md
```

`mix foundry.exdoc <Module> [--function name]` provides structured ExDoc output for
a specific module or function at the exact pinned version from `mix.exs`. Use when
usage rules are insufficient and precise API detail is needed. Cached by
`{:exdoc, library, version}` with 24h TTL.

---

## LLM Adapter

`Foundry.Copilot.Engine` is adapter-agnostic. Adapters implement the
`Foundry.Copilot.LLMAdapter` behaviour:

```elixir
defmodule Foundry.Copilot.LLMAdapter do
  @callback run(messages :: [map()], tools :: [map()], opts :: keyword()) ::
    {:ok, stream :: Enumerable.t()} | {:error, term()}
end
```

| Adapter | Use | Config |
|---|---|---|
| `Foundry.Copilot.AnthropicAdapter` | Production | `config/runtime.exs` |
| `Foundry.Copilot.LMStudioAdapter` | Local dev, CI, demos | `config/test.exs` |

```elixir
# config/runtime.exs
config :foundry_studio,
  llm_adapter: Foundry.Copilot.AnthropicAdapter,
  llm_model: "claude-sonnet-4-6"  # never hardcoded in source

# config/test.exs
config :foundry_studio,
  llm_adapter: Foundry.Copilot.LMStudioAdapter,
  llm_base_url: "http://localhost:1234/v1",
  llm_model: "local-model"
```

LM Studio uses the OpenAI-compatible tool calling API. `LMStudioAdapter` validates
tool calling support at startup with a minimal probe request:
- Tool calls present in response → confirmed, proceed normally
- Tool calls absent → log warning, Studio starts in degraded mode (visualization panels
  functional, copilot shows banner), do not crash

**Streaming is mandatory.** Both adapters stream token-by-token. Activity Feed LiveView
receives tokens via Phoenix PubSub. Performance budget: first streamed token ≤ 5 seconds
from message send (ADR-012 §Performance Budgets).

Model name from config (`:llm_model`), never hardcoded. Changing models requires
re-validating all catalogue operations against the iGaming reference project and an
ADR update.

---

## Reasoning Trace

Every CHANGE_PREVIEW and proposal response must include a structured reasoning trace.
This is the structured output of the agent's decision steps — not LLM prompt content
(privacy, per ADR-012 §Data Retention).

```json
"reasoning_trace": {
  "intent_classification": {
    "task": "change",
    "operation": "Op.AddRule",
    "confidence": 0.91
  },
  "shell_calls": [
    "cat docs/adrs/ADR-005-change-approval-model.md",
    "mix foundry.context MyApp.Finance.Wallet --json",
    "mix foundry.pattern.find rule --domain Finance"
  ],
  "contradiction_check": {
    "contradiction": false,
    "checked_adrs": ["ADR-005", "ADR-002"],
    "checked_invs": ["INV-001", "INV-011"],
    "summary": null
  },
  "change_class": ":behavioral",
  "confidence_state": "HIGH_CONFIDENCE",
  "session_snapshot": {
    "pending_migrations": 0,
    "open_proposals": 1,
    "lint_errors": 0
  }
}
```

`contradiction_check.checked_adrs` and `checked_invs` must be non-empty arrays.
An empty list means the check was skipped — test failure, not acceptable response.

For question responses (no proposal file): equivalent fields emitted as attributes
on the `[:foundry, :llm, :call]` telemetry span. Not persisted to disk.

**Dev-mode trace log:** `config :foundry_studio, copilot_trace_log: true` writes all
traces to `.foundry/logs/copilot_trace.jsonl` (gitignored). Local debugging only.
Set in `config/dev.exs` during Phase 3 development.

---

## Nebulex Cache Strategy

All caching via Nebulex L1 (ETS):

| Cache key | TTL | Invalidation trigger |
|---|---|---|
| `{:spec_kit, file_path, mtime}` | Mtime-based | inotify file watcher |
| `{:spec_kit_index, index_mtime}` | Mtime-based | `mix foundry.spec_kit.index` re-run |
| `{:project_snapshot, hash}` | 60 seconds | TTL expiry |
| `{:exdoc, library, version}` | 24 hours | TTL expiry |
| `{:versions, mix_exs_mtime}` | Mtime-based | mix.exs change |

**Pre-warming on startup:** `Foundry.Context.SpecKitReader` pre-warms the spec-kit index
and all indexed documents during application start (20–40 files typically — acceptable
for a local dev tool). First user request sees no cold-start delay.

**Cloud mode:** Pre-warming runs after git clone/pull, before WebSocket accepts connections.

**Session snapshot (Tier 2) uses TTL caching**, not mtime. The 60-second window means
the agent sees state that is at most 60 seconds old — acceptable for a human-in-the-loop
tool. A shorter TTL increases subprocess call frequency; a longer TTL risks stale health
signals during active development. 60 seconds is the right balance.

---

## Phase-Gated Behaviour

The `change_generation_enabled` flag governs the Phase 3 → Phase 4 transition.
Static config, not a `fun_with_flags` flag:

```elixir
# Phase 3:
config :foundry_studio, change_generation_enabled: false

# Phase 4:
config :foundry_studio, change_generation_enabled: true
```

When `false`: `change` intent routes to `CHANGE_PREVIEW` handler. Full classification,
context assembly, and contradiction check still run. The handler describes what the
operation would do without generating a diff. Validates classification quality before
trusting code output.

---

## Consequences

- The bash tool and agent loop in `Foundry.Copilot.Engine` are the highest-value
  components to test. Test shell constraint enforcement in isolation. Test the full
  loop against the iGaming reference project fixture.
- `Foundry.Copilot.ContextBuilder` Tier 2 assembly is the second-highest priority.
  A bug here produces subtle reasoning errors, not hard failures. Test that the
  snapshot is present and correctly formatted before any LLM call is made.
- There is no embedding model, no vector database, no similarity search. All retrieval
  is via shell (bash + Mix tasks) or direct file reads. No ML infrastructure dependency
  beyond the LLM API.
- INV-006 (stack versions always in system prompt) is enforced at ContextBuilder
  initialisation — structurally impossible to start the agent loop without stack
  versions in Tier 1.
- The two-write-path distinction (DSL operations via catalogue vs. plain Elixir via
  raw Igniter) is dissolved. One write path: agent generates content, Igniter applies,
  compiler and linter verify. The operations catalogue is a quality accelerator, not
  a capability boundary.
- If the LLM API is unavailable, all four visualization panels continue to function.
  They do not use the LLM.
- The phase gate makes Phase 3 ("questions only") and Phase 4 ("proposals") distinct
  deployments of the same codebase — only the config flag differs.
--- ./docs/adrs/ADR-012-studio-ux-specification.md ---
# ADR-012: Studio UX Specification

**Status:** Accepted  
**Date:** 2026-03  
**Deciders:** Platform team

---

## Context

ADR-008 establishes the read-only visualization paradigm and names the five panels and
command palette but does not specify how they render, what their empty and loading states
look like, how users navigate, how the approval and notification UX works, or what the
performance and accessibility requirements are. Without this specification, Phase 2 and
Phase 3 implementations diverge from intent.

This ADR also corrects a naming and layout decision implicit in ADR-008's framing:
what ADR-008 called the "Copilot Panel" is now the **Activity Feed** — a persistent right
sidebar combining a chronological event stream with a chat input at the bottom. This is a
naming and layout change only. The governance model (copilot engine is the only change
interface) is unchanged.

This ADR covers the Studio UI layer only. Copilot agent behaviour is ADR-013.
Proposal lifecycle and approval workflow mechanics are ADR-014.

---

## Decision: Command Palette

**Keyboard shortcut: `Cmd+K` (macOS) / `Ctrl+K` (Windows/Linux).**

> Note: ADR-008 referenced `Cmd+P`. That was incorrect. The canonical shortcut is `Cmd+K`.
> All documents referencing `Cmd+P` should be updated to `Cmd+K`.

Opens a floating modal overlay, centred, over the current view. Does not navigate away.

**The palette is a navigation tool, not an operation picker.** Operation selection is the
engine's responsibility (ADR-013 §Intent Classification). Users express intent as natural
language in the Activity Feed — they do not choose `Op.*` modules. Exposing the internal
operation catalogue in the palette would require users to understand Foundry's taxonomy
before they can use it, which defeats the purpose of intent-based interaction.

**Structure (top to bottom):**
1. Search input — autofocused on open
2. **Recent** — last 5 navigations or Activity Feed interactions (LiveView session state, not persisted across sessions)
3. **Navigate** — jump to module, domain, ADR, runbook, or compliance requirement by name or ID

Keyboard: `↑`/`↓` to move, `Enter` to select, `Escape` to dismiss. Typing filters both sections simultaneously.

**Navigate entries resolve to:**
- Module name → opens that node in the System Map with the detail drawer open
- Domain name → centres the System Map on that domain cluster
- ADR-XXX → opens ADR text overlay
- RG-XXX → scrolls Compliance Matrix to that requirement row
- Runbook name → opens runbook text overlay

**Phase availability:** Present from Phase 2. The Activity Feed (where changes are initiated)
is available from Phase 3.

---

## Decision: System Map Interaction Details

### Layout

Nodes are clustered by domain. Domain clusters are labeled with the domain name.
Node size is uniform — encoding data in node size creates cognitive overhead that
outweighs the information density benefit at 50+ nodes.

Nodes use colour to encode type:
- Resource → blue
- Transfer/Reactor → purple
- Rule → amber
- Blueprint → green
- Oban worker → grey

### Navigation and Selection

**Node click:** Opens a detail drawer from the **left edge of the map**, sliding over the
map content. Width: 360px. The selected node is highlighted with a ring indicator. The
drawer does not affect the Activity Feed sidebar on the right.

**Rationale for left-side drawer:** The Activity Feed occupies the right side permanently.
A right-side detail drawer would collide spatially with the feed and force users to shift
attention across the full screen width to relate node detail to ongoing conversation. Placing
the drawer on the left keeps the subject (node detail) proximate to the map it describes,
while the feed (ongoing commentary) remains stable on the right. This follows the
split-attention principle: related information grouped spatially reduces cognitive load.

**Detail drawer contents (top to bottom):**
1. Module name + type badge
2. `@moduledoc` text (truncated at 300 chars with "Show more" expansion)
3. Attributes table: name, type, `@description` (truncated), sensitive flag
4. Actions list with change class
5. Compliance requirements — each RG-* ID is a link that scrolls the Compliance Matrix to that row
6. Linked ADRs — each ADR-XXX is a link that opens the ADR text in a full-screen overlay
7. Test coverage badge: green (all present), amber (partial), red (missing)
8. Runbook link (if declared via `@runbook`)
9. **Contextual intent shortcuts** (bottom of drawer, above close button) — see §Contextual Intent Shortcuts

**Edge labels:** Relationship type shown on hover only. Default state is edges without labels to keep the map readable. Hovering an edge shows: source module → relationship type → target module.

### Search and Filter

Top-bar search field visible above the map. Accepts:
- Module name fragment (e.g., "Wallet")
- Domain name (e.g., "Finance")
- Compliance requirement ID (e.g., "RG-UK-014") — highlights all modules linked to that requirement
- Type filter (e.g., "transfers") — highlights all nodes of that type

Non-matching nodes dim to 20% opacity. Matching nodes remain at full opacity and are
brought to the foreground. Search is client-side (no round-trip) — the full graph data
is already loaded.

### Contextual Intent Shortcuts

The bottom of every node detail drawer shows a small set of intent shortcuts relevant to
that node type. These are not operation names — they are plain-language descriptions of
the most common next actions for this kind of module.

| Node type | Intent shortcuts |
|---|---|
| Resource | "Add attribute", "Add action", "Add policy", "Generate tests", "Link compliance requirement" |
| Transfer / Reactor | "Add rule", "Add step", "Generate tests", "View runbook" |
| Rule | "Add jurisdiction clause", "Generate tests", "Link compliance requirement" |
| Blueprint | "Add eligibility clause", "Generate tests" |
| Oban worker | "Generate tests", "View runbook" |
| Compliance gap (Matrix) | "Implement this requirement", "Add E2E test" |
| Test coverage gap | "Generate missing test" |

**Clicking a shortcut** sends a pre-formed intent message into the Activity Feed input —
the user sees it appear in the feed as if they had typed it. The engine receives structured
context (the module name is already known from the drawer) so classification confidence is
always HIGH and the clarifying question path is skipped (ADR-013).

The shortcuts are the primary entry point for routine development work. Natural language
in the Activity Feed input is the entry point for complex, multi-module, or ambiguous intent.
Both paths feed the same engine.

---

## Decision: Activity Feed (Persistent Right Sidebar)

The Activity Feed is the primary interface for interacting with the copilot engine and
monitoring system activity. It is visible by default and occupies the right side of the
Studio layout.

**What ADR-008 called "Copilot Panel" is now the Activity Feed.** The governance model
is unchanged — all changes still go through the copilot engine. The naming change reflects
that the surface is primarily an event stream with a chat input, not primarily a chat
interface with event notifications bolted on.

### Layout

```
┌──────────────────────────┐
│  Activity Feed      [×]  │  ← hide toggle (Cmd+\ restores)
├──────────────────────────┤
│                          │
│  [event card]            │
│  [event card]            │
│  [proposal card] ──────► │  click → opens review panel (bottom sheet)
│  [CI result card]        │
│  [copilot response card] │
│  [event card]            │
│                          │  ← scrollable, newest at bottom
├──────────────────────────┤
│  [input box]         [↑] │  ← always visible, autofocused on Studio load
└──────────────────────────┘
```

**Width:** 320px fixed. Not resizable — a fixed width keeps the map region stable and
predictable. If the user hides the feed, the map expands to fill the full width.

**Default state:** Visible. Persists across page navigations within the session.
Persists across sessions (hidden/visible preference stored in browser localStorage — this
is UI preference state, not application data, so localStorage is appropriate here).

### The Event Stream

The stream is a chronological list of cards, newest at the bottom. All system events appear
here in one place. The user never needs to check a separate notifications panel — the feed
is the single place for everything.

**Card types:**

| Event | Card appearance |
|---|---|
| Copilot response to a question | Text card with source citations. Compact — expandable on click. |
| Proposal ready for review | Proposal card: title, change class badge, "Review →" button. Clicking opens review bottom sheet. |
| Approval requested | "Your approval needed: [title]" card with "Review →" button. |
| Approval received | "[Approver] approved [title]" card. Green indicator. |
| Proposal applied + committed | "[title] applied. Commit: [sha]" card with CI link. |
| Proposal stale | "[title] is stale" card with "Regenerate" inline button. |
| CI result | Pass/fail card with link to CI run. |
| Compliance test failed | Red card: "[RG-XXX] failed in CI" with "View →" button linking to Compliance Matrix row. |
| Runbook stale | "[runbook] not tested in N days" amber card. |
| Error (any engine error code) | Error card with code, message, and runbook link. |

**Contextual shortcut submissions** appear in the stream as a user message card (showing
the pre-formed intent) followed by the copilot's response card. The user can see exactly
what was sent and what the engine understood.

**History:** The feed shows the last 200 events in the current session. Older events are
accessible via `mix foundry.audit.export`. The feed is not a permanent record — the audit
log (ADR-014) is the permanent record.

### The Chat Input

Always visible at the bottom of the feed. Autofocused when the Studio loads.

Single-line input that expands to multiline on Shift+Enter. Plain Enter sends.
Placeholder text: "Ask a question or describe a change…"

The input does not need to be "activated" — it is always ready. The user does not
select a mode before typing. The engine classifies intent from the message content (ADR-013).

**Relationship to contextual shortcuts:** Shortcuts write into this input and submit
automatically. The user sees the message appear in the feed stream as if they had typed it.
This means the feed is a complete record of all interactions — there is no hidden channel
where shortcuts bypass the visible history.

### Hiding the Feed

`Cmd+\` (macOS) / `Ctrl+\` (Windows/Linux) toggles the feed. A slim tab on the right
edge of the map area shows when the feed is hidden: a vertical label "Activity" with an
unread count badge if there are unseen events.

The hide state is appropriate during deep system map exploration where screen width matters.
The feed is not dismissable permanently — it is a hide/show toggle.

### Empty and Loading States

**Loading:** Skeleton graph showing domain cluster outlines and placeholder nodes without
content. Appears after a 200ms delay to avoid a flash on fast loads. Loading text:
"Reading project structure…"

**Empty (no compiled modules):**
```
No modules found.
Run `mix compile` in your project directory to populate the system map.
```
Copy-to-clipboard button on the command.

**Compile error state:** If `mix foundry.diagram.generate` returns non-zero, the map shows:
```
The project has compilation errors. Fix these before the system map can render:
[compiler error output, truncated to 20 lines with "Show full output" expansion]
```

---

## Decision: Review Panel Rendering

The review panel opens as a **bottom sheet** when a proposal is ready. It slides up from
the bottom of the viewport, defaulting to 50% of viewport height with a drag handle for
resizing. The System Map (or active panel) remains visible above it. The Activity Feed
sidebar remains visible to the right.

**Rationale for bottom sheet over right drawer:** Diffs require horizontal space. A right
drawer at 360–400px forces horizontal scrolling on any non-trivial diff. A full-width
bottom sheet gives the diff its natural reading direction. The map stays oriented above,
letting the user see which node the proposal relates to without closing the review panel.
Spatially: subject (map) above, diff (what would change) below, feed (commentary) to the
right — each in a stable, non-colliding region.

**The detail drawer (left) and review panel (bottom) can be open simultaneously.** A user
may want to read node detail while reviewing a proposal that touches it. These surfaces
serve different purposes and do not compete for the same screen region.

### Layout

```
┌──────────────────────────────────┬──────────────┐
│                                  │              │
│   System Map (or active panel)   │   Activity   │
│                                  │   Feed       │
│   ← detail drawer (if open)      │              │
│                                  │              │
├──────────────────────────────────┤              │
│ ▲ [drag handle]                  │              │
│ [Proposal title] [:behavioral]   │              │
│ Code Changes │ Migration │ Lint │ Impact        │
│                                  │              │
│  [diff renderer — full width]    │              │
│                                  │              │
│ Approvals: ⏳ domain-lead@…      │              │
│ [Request Approval][Regenerate]   │              │
└──────────────────────────────────┴──────────────┘
```

**Default height:** 50% of viewport. Minimum: 200px (shows header + one diff line).
Maximum: 80% (preserves some map context above). Height preference is persisted in
LiveView session state — not across sessions (avoids a user leaving it maximised and
forgetting on the next session).

**Dismiss:** Close button top-right of the sheet, or drag handle dragged to minimum height.
Dismissing does not reject the proposal — it returns the proposal to its current state
(DRAFT or PENDING_REVIEW). The proposal remains accessible from the Activity Feed.

**Migration tab:** Only shown when the proposal includes a migration diff. The migration
diff is rendered in the same diff renderer as code changes, with a header: "Database
migration — `priv/repo/migrations/[timestamp]_[name].exs`".

### Diff Renderer

Unified diff format. Line-level red/green backgrounds. Line numbers shown on both sides.
Syntax highlighting for Elixir. Long diffs (>200 lines visible) are collapsed with
"Show [N] more lines" inline expansion — the first 100 and last 100 lines are always shown.

The diff renderer is read-only. There is no inline editing. Changes to a proposal require
dismissing and regenerating.

### Lint Tab

Three sections rendered as collapsible groups:
- **Errors** (block apply — shown expanded by default if any exist): rule ID, file path, line number, message, link to the ADR or INV that defines the rule
- **Warnings** (non-blocking — shown collapsed by default): same structure
- **Info** (collapsed by default)

A green "All checks passed" state when no errors or warnings.

### Impact Tab — "Impact Analysis" Defined

**Impact analysis** is the computed set of side-effects a proposal has beyond the immediate
diff. It is deterministic — produced by the agent via targeted bash queries against the
system map graph (`mix foundry.context.all`), not LLM inference and not a separate module.

Impact analysis includes:
- **Recompile scope:** modules that import or alias the changed module (will recompile on next `mix compile`)
- **Test attention:** test files that reference the changed module directly
- **Compliance attention:** RG-* requirements linked to the changed module — reviewer should verify the requirement is still satisfied
- **Runbook attention:** runbooks that reference the changed module — may need updating
- **Pending migrations:** count of pending migrations after this proposal would be applied

Impact analysis is shown as a structured list, not prose. Each item links to the relevant
file or panel. An empty impact analysis (no side-effects) shows: "No downstream effects detected."

### Approval Footer

**`:structural` (auto-apply configured):** "Approved on apply." Apply button is active.

**`:structural` (auto-apply not configured):** "Awaiting approval from any developer."
"Approve and Apply" button visible to any authenticated user.

**`:behavioral`:** "Awaiting approval from: domain lead (domain-lead@company.com)."
The approver sees an "Approve" button in their approval queue. The requester sees
a "Notify Approver" button to resend the notification.

**`:sensitive`:** "Awaiting dual approval. (1/2) Sensitive lead (sl@company.com) ⏳.
(2/2) Any second approver ⏳." Each approver slot updates independently as approvals arrive.

**`:compliance`:** "Awaiting compliance officer (compliance@co.com). ADR link required."
The ADR link field is a text input accepting an ADR ID (e.g., "ADR-005") or a partial
title. Autocompletes against existing ADRs. Validated: the referenced file must exist at
`docs/adrs/ADR-XXX-*.md` before the "Submit for Approval" button activates.
If the ADR does not yet exist, the field shows a warning: "ADR not found. The compliance
officer must confirm the ADR will be created before approving." The proposal can still be
submitted — the compliance officer makes the final judgment.

There is no inline ADR creation in the review panel. ADRs are authored as files and committed.

### Stale Proposal Banner

Full-width amber banner pinned to the top of the review panel when a blob hash mismatch
is detected (ADR-009):

```
⚠ Stale — lib/my_app/finance/wallet.ex was modified since this proposal was generated.
[Regenerate]
```

"Regenerate" re-runs the original operation against the current codebase. If the resulting
diff is identical to the stale one, the banner clears and the proposal proceeds. If the
diff differs, a new diff is shown for review.

---

## Decision: Approval Tracking

Pending approvals appear in the Activity Feed as proposal cards. No separate Approvals
view is needed for the common case — the feed surfaces everything in real-time.

**For users who need a full queue view** (approvers managing multiple pending proposals):
`Cmd+K` → type "approvals" opens a secondary list view showing all PENDING_REVIEW proposals
sorted by SLA deadline. This is an overflow surface — most users will not need it.

**Queue view layout:** Table of all PENDING_REVIEW proposals.
Columns: Proposal title | Change class | Requester | Waiting | SLA status | Your action.

SLA status: green (within SLA), amber (>50% of SLA elapsed), red (SLA exceeded).
Visual indicators only — the system does not auto-escalate.

**"Review →" action:** Opens the review bottom sheet for that proposal. The approval
button is in the review panel footer, not in the queue row.

**Visibility:** All proposals in PENDING_REVIEW or later are visible to all project users.
DRAFT proposals are visible only to the requester. Non-approvers see proposals in
read-only mode without the approval button. This allows any developer to see what is
in-flight before starting work that might conflict (ADR-009, ADR-014 §Proposal Visibility).

---

## Decision: Notifications

All in-Studio notifications appear as event cards in the Activity Feed. There is no separate
notification inbox or bell dropdown — the feed is the inbox.

**Unread indicator:** When the Activity Feed is hidden (`Cmd+\`), the slim "Activity" tab
on the right edge shows an unread count badge. When the feed is visible, events are considered
read as they scroll into view.

**Notification types** (appear as feed cards per §Activity Feed card types above):

| Type | Card colour | External delivery (INV-010) |
|---|---|---|
| `approval_requested` | Blue | Slack / email per manifest |
| `approval_complete` | Green | None (in-feed only) |
| `proposal_stale` | Amber | None (in-feed only) |
| `sla_exceeded` | Red | Slack / email per manifest |
| `compliance_test_failed` | Red | Slack / email per manifest |
| `runbook_stale` | Amber | Slack / email per manifest |

External delivery (Slack/email) is configured per INV-010. In-Studio delivery is always
the Activity Feed. External notifications are fire-and-forget — they are not persisted.
In-feed event cards live in ETS (LiveView session state) — last 200 events visible.

---

## Decision: Onboarding / Bootstrap UX

When `mix foundry.studio` is run in a project with no spec-kit (no `AGENTS.md` at project root):

**Step 1 — Welcome overlay:** Full-screen overlay with two options:
- **"Initialize spec-kit"** — runs `mix foundry.spec_kit.init` in a terminal panel embedded in the overlay, shows generated files as they are created. On completion: "Done. Your spec-kit is ready." with a "Open Studio" button that dismisses the overlay and loads the system map.
- **"Continue without spec-kit"** — dismisses the overlay. Studio runs in reduced mode: no Compliance Matrix, no copilot ADR contradiction checking, no runbook links. A persistent amber banner at the top of the Studio indicates reduced mode: "No spec-kit found. Some features are disabled. Run `mix foundry.spec_kit.init` to enable them."

**Reduced mode limitations (no spec-kit):**
- System Map: functional
- Compliance Matrix: shows "No compliance requirements declared"
- Copilot: functional for questions; proposals allowed but ADR contradiction check is skipped; a warning is shown on every proposal: "No spec-kit. This proposal has not been checked against ADRs or invariants."
- Operations Board: functional
- Test Coverage Map: functional

**When spec-kit exists but project does not compile:**
System Map shows the compile error state (described above). All other panels show:
"System map unavailable — project has compilation errors."

---

## Decision: Empty and Loading States (All Five Panels)

| Panel | Loading state | Empty state |
|---|---|---|
| System Map | Skeleton cluster outlines + placeholder nodes. "Reading project structure…" | "No modules found. Run `mix compile`." |
| Compliance Matrix | Skeleton table rows. "Loading compliance data…" | "No compliance requirements declared. Add regulation files to `docs/regulations/` to populate this matrix." |
| Operations Board | Skeleton rows. "Loading operations data…" | "No runbook links found. Add `@runbook` declarations to Reactor modules to populate this board." |
| Test Coverage Map | Skeleton bar charts. "Loading coverage data…" | "No test results found. Run `mix test` to populate coverage data." |
| Activity Feed | Skeleton cards while initial context loads. "Connecting…" | Input ready immediately. Feed shows: "Ask a question or describe a change to get started." |

Loading states appear after a 200ms delay. Below 200ms, no loading indicator is shown.

---

## Decision: Performance Budgets

These are the target performance bounds. If a measure exceeds its bound, it is a bug to
be filed, not a design decision to be revisited.

| Metric | Budget |
|---|---|
| System Map initial render (≤50 modules) | ≤ 1 second from page load |
| System Map initial render (50–200 modules) | ≤ 3 seconds from page load |
| Node click → detail drawer open | ≤ 200ms (graph data already loaded) |
| `mix foundry.context` subprocess call | ≤ 2 seconds; show "Retrieving context…" if >500ms |
| Copilot first streamed token | ≤ 5 seconds from message send |
| Review panel diff render | ≤ 500ms for diffs up to 500 lines |
| Command palette open | ≤ 100ms |
| Panel-to-panel navigation | ≤ 200ms (LiveView navigation, no full reload) |

---

## Decision: Accessibility

WCAG 2.1 AA. Non-negotiable. Specific requirements:

- All interactive elements are keyboard-navigable in a logical tab order
- Color is never the sole state indicator. Every color-coded state also has an icon and text label (e.g., lint errors: red background + ⛔ icon + "Error" label, not red background alone)
- The diff renderer exposes `role="region"` with `aria-label="Code changes"` and `aria-label="Migration changes"` for screen reader navigation
- The system map D3 graph provides a table view alternative (togglable) that lists all nodes and edges in a navigable table — the SVG graph itself is not screen-reader accessible
- Focus is managed correctly when the command palette opens and closes (focus returns to the triggering element on close)
- The copilot response stream is announced to screen readers when complete via `aria-live="polite"`

---

## Decision: Responsive and Mobile

The Studio is a developer tool. Minimum supported viewport: **1280px wide**.

No mobile optimization in v1. On viewports below 1280px, the Studio displays:
"Foundry Studio requires a minimum viewport of 1280px. Please use a desktop browser."

This is an accepted constraint, not an oversight. The system map and review panel require
sufficient horizontal space to be usable. Revisit in v2.

---

## Decision: Data Retention

Storage implementation for all Foundry state is specified in ADR-015.
The retention periods below are the requirements; ADR-015 defines how they are met.

| Data type | Retention period | Storage | Notes |
|---|---|---|---|
| Approved proposal records | 7 years | `.foundry/proposals/` in git | Git history provides integrity |
| Rejected / dismissed proposals | 90 days | `.foundry/proposals/` in git | `mix foundry.proposals.purge` removes files older than 90 days and commits the deletion |
| Audit log (`:sensitive`, `:compliance` approvals) | Indefinite | `.foundry/audit.jsonl` in git | Append-only. Git history is the integrity record. Never purged. |
| Approval records (approver, timestamp, diff hash) | 7 years | `.foundry/audit.jsonl` in git | Part of the audit chain — each approval is one JSONL line |
| Activity Feed event history | Session only | ETS (LiveView state) | Not persisted. Feed shows last 200 events in session. |
| LLM prompts and responses | Not stored | — | Privacy. Only error codes and structured metadata are logged to telemetry. |

**Retention is git history.** There is no database to back up. The project's existing git
remote is the backup. Regulatory inspection uses `git log -p .foundry/audit.jsonl` or
`mix foundry.audit.export --from=<date> --to=<date>`.

**Draft proposals** are written to `.foundry/proposals/prop_<id>.draft.json` on disk but
are not committed. If the Studio process restarts before submission, the draft is lost.
Regeneration is cheap — this is acceptable.

**The `.foundry/` directory** is committed to the project repository. Draft files
(`.draft.json`) are gitignored. Committed proposal files (`.json`) are version-controlled.

---

## Decision: Studio Layout

The canonical Studio layout at 1280px+ viewport:

```
┌─────────────────────────────────────────────┬──────────────────────┐
│  [top bar: panel tabs + search + Cmd+K]     │                      │
├─────────────────────────────────────────────┤   Activity Feed      │
│                                             │   320px fixed        │
│   Main panel area                           │                      │
│   (System Map, Compliance Matrix,           │   [event stream]     │
│    Operations Board, Test Coverage Map)     │   [event stream]     │
│                                             │   [event stream]     │
│   ← left detail drawer (360px)             │   [event stream]     │
│     slides over map on node click           │                      │
│                                             │   ──────────────     │
│                                             │   [input box]    [↑] │
├─────────────────────────────────────────────┤                      │
│  ▲ Review Panel (bottom sheet, 50% default) │                      │
│  [proposal diff — full width of left area]  │                      │
└─────────────────────────────────────────────┴──────────────────────┘
```

Key spatial properties:
- **Left:** detail drawer — contextual info about the selected node, proximate to the map
- **Right:** Activity Feed — persistent, stable, never displaced by other surfaces
- **Bottom:** review panel — full-width diff reading space, map stays oriented above
- **Top:** panel navigation — global, always accessible

The three surfaces (detail drawer, review panel, Activity Feed) can all be open
simultaneously without collision. This is the target state during active development:
node detail visible left, diff being reviewed below, feed showing context right.

---

## Consequences

- `Cmd+K` is the canonical palette shortcut — navigation only, no operation picker
- The palette does not expose `Op.*` modules — operation selection is the engine's responsibility (ADR-013)
- The Activity Feed sidebar uses `localStorage` for hide/show persistence — this is UI preference state, not application data. This is the one permitted exception to the no-localStorage rule in artifacts; it applies only to this single boolean preference.
- The left detail drawer and bottom review panel can be open simultaneously — they occupy non-colliding regions
- The Activity Feed is the single surface for all in-Studio notifications — there is no separate bell dropdown or notification inbox
- The impact analysis is produced by the agent via bash traversal of `mix foundry.context.all` output — deterministic, not LLM-generated, no separate module
- The system map table view alternative is required for WCAG compliance — the D3 SVG graph alone is insufficient
- Data retention periods assume a financial/regulated platform target. Projects in other domains may override the defaults in `manifest.exs` under `data_retention:`
- The 7-year audit log retention is enforced at the application layer — infrastructure teams must ensure the underlying storage is not purged
- All references to "Copilot Panel" in other spec-kit documents should be read as "Activity Feed" — ADR-008 will be updated to reflect this rename
--- ./docs/adrs/ADR-013-copilot-agent-behavior.md ---
# ADR-013: Copilot Agent Behaviour

**Status:** Accepted  
**Date:** 2026-03  
**Deciders:** Platform team

---

## Context

ADR-010 covers model selection and context assembly. ADR-003 covers retrieval strategy.
Neither covers how the copilot behaves when it is uncertain, when a request contradicts
the spec-kit, when the infrastructure is degraded, or when INV-005's one-clarifying-question
rule must be applied in practice.

Without this specification, Phase 3's done criteria ("answers questions accurately, no Ash 2.x
syntax") cannot be evaluated consistently — the team has no agreed standard for what
"accurate" means at the edge cases.

This ADR covers agent behaviour. Context assembly mechanics are in ADR-010. Proposal lifecycle
is in ADR-014.

---

## Decision: The Epistemic Contract

The copilot operates under a strict epistemic contract. These are not aspirational — they are
behavioural requirements that the system prompt and test suite enforce.

**The copilot always:**
- Cites the specific ADR, INV rule, module, or field that grounds its answer
- States explicitly when it is inferring from context versus reading from structured retrieval
- Surfaces spec-kit contradictions before generating — never generates first and flags later
- Presents uncertainty as a confidence level (see §Confidence States), not as hedging prose

**The copilot never:**
- Asserts facts about the codebase without sourcing them from `mix foundry.context` output
- Generates DSL syntax from training memory when the ExDoc fragment is retrievable (INV-006)
- Presents two implementations as equally valid when the spec-kit prefers one
- Apologises. Blocked proposals get a factual explanation, not an apology.
- Asks a follow-up question after already asking one clarifying question in the same turn (INV-005)

---

## Decision: Intent Classification

Intent classification is the **first reasoning step of the agent loop** — not a separate
pre-LLM call. The agent classifies the user's message before making any tool calls.
See ADR-010 §Intent Classification for the full specification.

**`question`** — the user is asking about the current state of the system.
Indicators: interrogative syntax ("what does", "why does", "show me", "explain", "where is",
"how does", "which"), explicit question marks, no imperative verb directing a change.

**`change`** — the user wants to modify the system.
Indicators: imperative verbs ("add", "create", "update", "remove", "rename", "generate",
"link", "implement"), description of a desired future state ("I want", "we need",
"the resource should", "it should also").

**`speckit`** — the user asks to draft or update a spec-kit document.
Indicators: "write an ADR", "draft a runbook", "add a regulation entry", "update the ADR for",
"document this decision". Produces a plain-text proposal (no Igniter call, no git branch).
The human reviews the draft in the Activity Feed and commits it manually.

**`ambiguous`** — the message contains both question and change indicators, or neither.
Examples: "Can we add a rule for X?" (question form, change intent), "What about a Transfer
for Y?" (question form, but clearly describing an addition).

When `ambiguous`, the engine invokes the clarifying question path (INV-005).
Confidence below 0.7 on any classification → treat as `ambiguous`.

**Not overridable from the UI.** Unresolved ambiguity always goes to clarifying question path (INV-005).

---

## Decision: Confidence States

Four states govern how the copilot proceeds after context assembly:

### `HIGH_CONFIDENCE`
**Conditions:** Structured retrieval returned the requested module, ExDoc confirms the DSL
construct, a close pattern example exists in the codebase.

**Behaviour:** Proceed directly. For `question`: answer with source citations. For `change`:
run ADR contradiction check, then generate proposal parameters.

No note to the user about confidence level. High confidence is the normal operating state.

---

### `MEDIUM_CONFIDENCE`
**Conditions:** Module context was retrieved but no close pattern example exists for the
specific DSL construct being generated.

**Behaviour:** Generate and flag. For `change`: generate the proposal, include a note in
the review panel Impact tab: "No existing example of this pattern in the project. Generated
from ExDoc specification only. Human review of the generated code is recommended before apply."

Do not ask a clarifying question for medium confidence. The uncertainty is about *pattern
familiarity*, not about *intent* — the user's intent is clear, the copilot is just less
certain about the idiomatic form.

---

### `LOW_CONFIDENCE`
**Conditions:** One or more of:
- The requested module does not exist in `mix foundry.context` output
- The DSL version in the fetched ExDoc does not match the project's version in mix.exs
- The spec-kit is silent on this case and no pattern example exists

**Behaviour:** Surface the specific gap. Use the one permitted clarifying question (INV-005).
Do not generate on low confidence.

Example responses:
- "I can't find a module named `BonusPool` — did you mean `BonusAward`? (The closest match in the Finance domain is `BonusAward`.)"
- "The ExDoc I retrieved for `ash_state_machine` is for version 0.8.x, but your project uses 0.6.x. I'll use 0.6.x patterns — confirm before I proceed?"

---

### `BLOCKED`
**Conditions:** One or more of:
- The request contradicts an ADR or INV rule (contradiction check returned `true`)
- The request is a `:compliance` change but no ADR link was provided
- The request would produce a `:sensitive` change that cannot be auto-applied (INV-001)
- The project manifest has no `sensitive_resources:` declared but the request targets a resource type that is always `:sensitive` (e.g., authentication User resource)

**Behaviour:** State the specific rule violated and what must change to proceed. Do not generate.
No hedging. No "I'm sorry, but...". No workarounds. If the spec-kit blocks it, it's blocked.

Format:
```
This proposal cannot proceed. It contradicts [ADR/INV reference]:
[one sentence on the specific conflict].
To proceed: [one sentence on what must happen].
```

---

## Decision: Clarifying Question UX (INV-005 Implementation)

When a clarifying question is required (`LOW_CONFIDENCE` or `ambiguous` classification):

**Step 1 — State what was understood:**
A brief sentence: "I understand you want to [paraphrase of the request]."

**Step 2 — Name the specific ambiguity:**
One sentence identifying the gap: "I'm not certain whether [X] or [Y]."

**Step 3 — Present as a binary or small-choice selection:**
Rendered as clickable option buttons — two or three options maximum.
The Activity Feed input box remains visible and active below the buttons.

```
I understand you want to add a rule for withdrawal limits.
I'm not certain whether this should be a new Rule module or an additional
clause in the existing StakeLimitRule.

[New Rule module]   [Add clause to StakeLimitRule]

Or describe what you have in mind:
[_________________________________________________]
```

**Buttons are the primary path** — structured, unambiguous, guaranteed resolvable.
Clicking a button sends the option label as a structured message; the engine
does not re-classify it, it proceeds directly.

**The input box is always present** — never hidden or disabled when clarifying
buttons are shown. Free-text via the input re-enters the classification cycle:
- Resolves ambiguity → proceed
- Introduces new ambiguity → present two explicit interpretations (second question)

The engine never asks a third question regardless of path taken.

**What the copilot never does:**
- Asks three questions in sequence (two is the hard maximum across all paths)
- Asks an open-ended question without options — if asking, always present concrete
  choices alongside
- Hides or disables the Activity Feed input while clarifying buttons are shown
- Guesses and generates on unresolved ambiguity
- Embeds the clarifying question inside a longer prose paragraph where it might be missed

---

## Decision: Error Recovery Responses

When the engine encounters a recoverable failure, it emits a structured response in the
copilot panel. The response always includes: what failed, why (if known), and what the user
can do. Links to the relevant runbook.

### `:context_build_failed`
```
I couldn't read context for [module]. The project may have a compilation error.

Run `mix compile` to see the error. Once it compiles, I can proceed.
See runbook: docs/runbooks/project_reader_unavailable.md
```

### `:igniter_operation_failed`
```
The scaffold operation failed before generating a diff.
Error: [Igniter error message, verbatim]

This is typically a syntax issue in the target module. See:
docs/runbooks/igniter_operation_failure.md
```

### `:llm_api_error`
```
The LLM service is temporarily unavailable.
The visualization panels and CLI tools are still functional:
  mix foundry.context <Module>
  mix foundry.lint.all
  mix foundry.compliance.check

See: docs/runbooks/studio_copilot_failure.md
```

### `:version_mismatch`
```
I couldn't detect the current stack versions. My responses may use incorrect
API syntax until this is resolved.

Run: mix foundry.versions.refresh
Then reload the Studio.
```

### `:adr_contradiction`
Covered under §Confidence States → BLOCKED. The contradiction check result becomes the
blocking explanation.

### `:context_budget_exceeded`
```
This request requires more context than fits in a single operation.
Try narrowing the scope — specify a single module or domain rather than multiple.

Example: instead of "add tests for the entire Finance domain", try
"add tests for the WithdrawalTransfer".
```

### `:clarification_required`
Not an error — the clarifying question UX described above is the response.

---

## Decision: Phase-Gated Copilot Behaviour

**Phase 3 (`change_generation_enabled: false`):** `change` intent routes to the
`CHANGE_PREVIEW` handler. The full classification, spec-kit check, context assembly,
and ADR contradiction check still run. No git branch is created. The handler produces:

```
I would propose the following change (code generation is not yet enabled):

Operation: new rule module
Module: MyApp.Finance.WithdrawalLimitRule
Change class: :behavioral (requires domain lead approval)
Files that would be touched:
  - lib/my_app/finance/withdrawal_limit_rule.ex (new)
  - test/my_app/finance/withdrawal_limit_rule_test.exs (new)

The rule would check [summary of what the rule would enforce based on intent].

No diff has been generated. When code generation is enabled, this operation
will produce a full diff for review.
```

The copilot does not explain why generation is disabled — that is visible in the Studio
status bar. The response shows only what it understood.

**Phase 4 (`change_generation_enabled: true`):** `CHANGE_PREVIEW` is not used. The agent
proceeds directly to DRAFT creation. No intermediate preview step. The review panel bottom
sheet is the preview — it shows the actual diff and the system map enters preview mode
(amber rings on affected nodes, phantom outlines on new nodes, dimmed removed nodes).

`CHANGE_PREVIEW` is a Phase 3-only response format. It does not appear in Phase 4+.

---

## Decision: Response Format Contract

Every copilot response must be structured as follows. The structure is enforced by the
system prompt — the model is instructed to follow these patterns, not to produce free-form prose.

**For `question` responses:**
1. Direct answer (1–3 sentences)
2. Source citation: "Source: `mix foundry.context MyApp.Finance.Wallet` → `archival: true`" or "Source: ADR-005 §Migration Classification"
3. Optional follow-up suggestion (one, not a question): "You might also want to check the compliance links on this resource — the Compliance Matrix has the current status."

**For `speckit` responses:**
A plain-text draft of the requested spec-kit document (ADR, runbook, or regulation stub)
rendered as a copyable card in the Activity Feed. Header shows the proposed file path.
No diff, no git branch, no Igniter call. The human reviews, edits as needed, and commits
the file manually via `git add docs/adrs/ADR-XXX... && git commit`.

**For `change` responses (Phase 4+):**
The diff is sent to the review panel out-of-band. The inline copilot message is:
```
Proposal ready in the review panel.
Change class: :behavioral
Awaiting: domain lead approval
```
Never paste the diff inline in the conversation. The diff belongs in the review panel.

**For `CHANGE_PREVIEW` responses (Phase 3):**
Structured description as shown above. No diff, no code.

**For `BLOCKED` responses:**
As specified under §Confidence States → BLOCKED. No code, no diff, no workarounds.

**For clarifying question responses:**
The question structure as specified under §Clarifying Question UX. Nothing else — do not
pre-answer your own question or add context after the buttons.

---

## Consequences

- The system prompt enforces the response format contract — a model response that deviates is a test failure, not an acceptable variation
- All five error codes are logged with structured metadata (not the full prompt) to the telemetry pipeline — this is the diagnostic signal for `studio_copilot_failure.md`
- The clarifying question button UI is a LiveView component that sends a structured message on click, bypassing the text input — the engine receives the option label, not the button's click event
- Phase 3 done criteria must include verifying that each of the five error codes is exercised in the test environment, not just happy-path question answering
- The `BLOCKED` response format is deliberately terse. If users find it too abrupt, that is feedback that an ADR may be too restrictive — it is not feedback to soften the copilot's response
--- ./docs/adrs/ADR-014-proposal-lifecycle.md ---
# ADR-014: Proposal Lifecycle

**Status:** Accepted  
**Date:** 2026-03  
**Deciders:** Platform team

---

## Context

ADR-005 specifies change classification and approval requirements. ADR-009 specifies stale
proposal detection. Neither specifies the complete proposal state machine, the mechanics of
dual approval (timeouts, revocation, audit), how `:compliance` ADR linking is enforced in
the workflow, how the apply step handles failure, or how proposals become superseded.

Phase 4's done criteria require all of this to be implemented and validated. This ADR is
the contract that implementation follows.

---

## Decision: Proposal State Machine

```
DRAFT ──────────────────────────► PENDING_REVIEW
  │                                      │
  │ (dismissed before submit)            ├──► APPROVED ──► APPLIED ──► COMMITTED
  ▼                                      │
DISMISSED                                ├──► REJECTED
                                         │
                                         ├──► STALE (blob hash mismatch at apply time)
                                         │
                                         └──► SUPERSEDED (another proposal for same module applied first)
```

**DRAFT**
Proposal has been generated (Igniter dry-run complete, diff captured, blob hashes recorded
per ADR-009). Not yet submitted. The requester may view it in the review panel and either
submit or dismiss.

A DRAFT is not visible to other users. Only the requester sees it.

**PENDING_REVIEW**
Submitted for approval. Notification sent to designated approver(s). The proposal is
visible to all project users — read-only for non-approvers.

Once in PENDING_REVIEW, only an approver or the requester can dismiss (transitions to REJECTED
with a reason). The requester cannot recall and re-draft without the approver being notified.

**APPROVED**
All required approvals received. For `:structural` with auto-apply configured: transitions
to APPLIED immediately without further user action. For all other classes: waits for a human
to press "Apply" in the review panel.

An APPROVED proposal that is not applied within 24 hours is flagged in the operations board
(amber indicator). It is not auto-applied — the 24h flag is informational only.

**APPLIED**
Igniter has run in non-dry-run mode. Code has been written to disk. Pre-apply blob hash
check has passed. `mix ash.codegen` and `mix ash.migrate` have run (if the proposal
includes a migration). `mix compile` has confirmed no compilation errors.

**COMMITTED**
Git commit created with structured message. CI triggered. Terminal success state.

**REJECTED**
Any approver, or the requester, may reject. Rejection requires a reason (text field, minimum
10 characters — enforced). Reason is stored in the audit log. The requester is notified.
A rejected proposal can be revised by regenerating (which creates a new DRAFT).

**STALE**
Blob hash mismatch at apply time (ADR-009). Transitions from APPROVED back to pending.
Requester notified with the specific file that changed. One-click regenerate in stale banner (ADR-012).

**SUPERSEDED**
A different proposal touching the same files was applied first. Requester notified to regenerate.

---

## Decision: Dual Approval Mechanics

For `:sensitive` proposals, two distinct human approvals are required before APPLIED.

### Approval Slots

- `approval_slot_1` — the `sensitive_lead` named in the manifest
- `approval_slot_2` — any other named approver in the manifest (`domain_lead`, `platform_lead`, or `compliance_officer`)

**Constraint:** The same person cannot fill both slots. If the `sensitive_lead` and `domain_lead`
are the same individual, only the `compliance_officer` qualifies as the second approver.

**Order:** Either approver may act first. The proposal enters APPROVED when both slots
are filled.

**Visibility:** Both approvers see the full diff, lint results, and impact analysis.
Each approver can see whether the other has approved — the review panel footer shows
both slots and their current state (pending / approved / revoked).

### Timeouts

After the SLA window (default: 4 hours for `:sensitive`, configurable in manifest), the
proposal is flagged as SLA-exceeded in the operations board. The INV-010 notification
fires to the configured channel. There is no auto-escalation and no auto-rejection.
The flag is informational — it surfaces the blockage so a human can act (see
`runbooks/approval_queue_blocked.md`).

### Revocation

An approver may revoke their approval at any time before the proposal transitions to
APPLIED. Revocation:
1. Returns the proposal to PENDING_REVIEW
2. Clears the revoked approval slot
3. Notifies both the other approver and the requester
4. Requires a reason (text field, minimum 10 characters)
5. Records the revocation in the audit log: `{proposal_id, approver_email, action: :revoked, reason, timestamp}`

A proposal that has been revoked once and then re-approved by the same approver carries
both events in the audit log. The audit log is append-only.

### Audit Record

Per approval event, the audit log stores:

```json
{
  "proposal_id": "...",
  "event": "approved" | "revoked",
  "approver_email": "...",
  "approver_role": "sensitive_lead" | "domain_lead" | "platform_lead" | "compliance_officer",
  "approval_slot": 1 | 2,
  "timestamp": "2026-03-04T14:22:00Z",
  "diff_hash_at_event": "sha256:...",
  "proposal_change_class": ":sensitive"
}
```

`diff_hash_at_event` records the state of the diff at the time of the approval decision.
If the diff is later found to differ from what was applied (integrity check), the audit
record shows what the approver actually reviewed.

---

## Decision: ADR Linking for Compliance Changes

When the change classifier tags a proposal as `:compliance`, the ADR link field in the
review panel footer is required before "Submit for Approval" activates.

### Validation Rules

- The field accepts an ADR ID: `"ADR-005"`, `"ADR-013"`, etc.
- On input, the system checks whether `docs/adrs/ADR-XXX-*.md` exists at the declared ID.
- **If the file exists:** green checkmark. "Submit for Approval" activates.
- **If the file does not exist:** amber warning: "ADR-XXX not found. The compliance officer must confirm the ADR will be created before approving. You may still submit." "Submit for Approval" activates with the warning persisting.

The compliance officer makes the final judgment on whether a non-existent ADR is acceptable.
The system does not block submission on a non-existent ADR — it surfaces the gap and
delegates the decision to the human approver.

### No Inline ADR Creation

There is no flow to create an ADR from within the review panel. ADRs are authored as
Markdown files in `docs/adrs/`, reviewed as prose, and committed by a human. The copilot
may draft ADR content in the copilot panel when asked ("Draft an ADR for this change"), but
the file is committed manually. The ADR link field in the review panel only references
ADRs that already exist (or will exist at approval time, per the compliance officer's judgment).

---

## Decision: Proposal Visibility

All proposals in PENDING_REVIEW or later states are visible to all authenticated project users.
DRAFT proposals are visible only to the requester.

**What all users can see:**
- Proposal title, change class, requester identity, current state, affected modules
- SLA status
- The diff (read-only)
- Lint and impact analysis results

**What only approvers and the requester can see:**
- Approval deliberation notes and revocation reasons
- The full conversation context that generated the proposal

**Concurrent conflict warning:**
When a user generates a new proposal and there is already a PENDING_REVIEW proposal
touching any of the same files, the Studio shows a non-blocking warning in the copilot panel:
"[User] has a pending proposal that also touches [module]. Your proposal may become stale if
theirs is applied first. This is not an error — proceed if your changes are independent."

This is purely informational. The optimistic locking mechanism (ADR-009) handles the actual
conflict at apply time if it arises.

---

## Decision: The Apply Step

The apply step is a two-phase operation. Both phases must succeed; failure in Phase B is
surfaced to the user and requires manual resolution.

### Phase A — Pre-Apply Checks (must all pass before Phase B begins)

1. Re-read blob hash for every file in the proposal. Compare to stored hashes.
   → Mismatch: transition to STALE. Notify requester. Abort.

2. Verify all required approval slots are filled and no slot has been revoked.
   → Not satisfied: block. Show current approval state in review panel.

3. For `:compliance` proposals: verify the ADR link field is populated.
   → Not populated: block. The field is required.

4. Re-run lint against the stored diff.
   → Lint errors: block. Show updated lint results. The proposal must be regenerated if
   the lint rules changed since generation.

5. Verify the proposal is not in SUPERSEDED state (a concurrent check — the state machine
   should have caught this, but a final check before execution is prudent).

### Phase B — Apply Execution

1. `Foundry.Operations.run(op, params, dry_run: false)` — executes the Igniter pipeline.

2. If the proposal includes a migration:
   a. Run `mix ash.codegen <auto_name>`
   b. Verify the generated migration file matches the migration diff stored in the proposal
      (blob hash check on the migration file — if the DSL changed since generation, the
      migration may differ from what was approved)
   c. If migration hash differs: abort. Surface: "The migration diff changed since this
      proposal was approved. Regenerate the proposal to capture the current migration."
   d. Run `mix ash.migrate`

3. Run `mix compile`. Verify exit code is 0.
   → Non-zero: **compilation failure path** (see below).

4. Create git commit:
   ```
   [FOUNDRY] :behavioral: Add WithdrawalLimitRule

   Approved by: domain-lead@company.com (2026-03-04T14:22:00Z)
   Proposal ID: prop_abc123
   Change class: :behavioral
   ```

5. Trigger CI.

6. Transition proposal to COMMITTED.

### Compilation Failure Path

If `mix compile` returns non-zero after Igniter apply:

The changes have been written to disk and cannot be automatically rolled back — Igniter
does not provide undo. This is an exceptional state.

The Studio surfaces:
```
⚠ Apply partially failed — compilation error after writing changes.
The following files were written:
  - lib/my_app/finance/withdrawal_limit_rule.ex (new)

Compiler error:
[error output, full, not truncated]

Next steps:
1. Fix the compilation error manually in your editor
2. Run `mix compile` to verify
3. Run `mix foundry.proposals.mark-applied --id prop_abc123` to close this proposal
```

The `mix foundry.proposals.mark-applied` CLI command closes the proposal lifecycle manually.
It requires `mix compile` to pass before it accepts the command — it will not mark a
proposal applied while the project is broken.

**Why this path exists:** Pre-apply lint should catch any errors that would cause a
compilation failure. If a compilation failure occurs, it indicates either a gap in the
lint rules or a race condition where the codebase changed between lint and apply. Both
are bugs to be filed against the lint rule coverage.

---

## Decision: Proposal Lifecycle for `:structural` Auto-Apply

When the project manifest has auto-apply configured for `:structural` changes and the
proposal passes all Phase A checks, Phase B executes immediately on approval without a
separate "Apply" button press.

**The approval action IS the apply trigger for `:structural` auto-apply.**

This is the only class where approval and apply are a single action. For all other classes,
the "Apply" button is a deliberate separate step after approval — it forces a human to
actively initiate the code change, not just approve it.

---

## Decision: Proposal Storage

Each proposal is stored as a single JSON file at `.foundry/proposals/prop_<id>.json`
in the target project's repository. Storage implementation and commit lifecycle are
specified in ADR-015. The schema below is the file's content.

```json
{
  "proposal_id": "prop_abc123",
  "state": "PENDING_REVIEW",
  "change_class": ":behavioral",
  "operation": "Op.AddRule",
  "operation_params": { ... },
  "diff": "...",
  "migration_diff": "..." | null,
  "blob_hashes": {
    "lib/my_app/finance/wallet.ex": "sha256:abc...",
    "test/my_app/finance/wallet_test.exs": "sha256:def..."
  },
  "lint_result": { ... },
  "impact_analysis": { ... },
  "adr_link": "ADR-005" | null,
  "requester": "dev@company.com",
  "created_at": "2026-03-04T14:00:00Z",
  "submitted_at": "2026-03-04T14:05:00Z",
  "approval_slot_1": { "approver": null, "approved_at": null },
  "approval_slot_2": { "approver": null, "approved_at": null },
  "applied_at": null,
  "committed_at": null,
  "git_commit_sha": null | "abc123..."
}
```

**DRAFT proposals** use the filename `prop_<id>.draft.json` and are not committed to git.
All other states use `prop_<id>.json` and are committed on each state transition (ADR-015).

This schema is owned by `Foundry.Proposals.ProposalStore`. Do not reference fields not
listed here from outside that module — the schema is an internal implementation detail.

---

## Consequences

- The DRAFT → PENDING_REVIEW transition is the point at which other users gain visibility — not proposal generation
- Compilation failure after apply is a recoverable exceptional state, not a rollback path. Lint coverage is the primary defence against it
- For `:structural` auto-apply: approval and apply are a single action. For all other classes, they are two separate deliberate steps.
- The `mix foundry.proposals.mark-applied` command is a safety valve — it should rarely be needed and its use should be logged as a platform issue to investigate
- `approval_slot_2` for `:sensitive` proposals can be filled by `domain_lead`, `platform_lead`, or `compliance_officer` — the manifest determines who qualifies. This means a project with no `domain_lead` declared still has a valid second approver path via `platform_lead`.
- Proposal files and the audit log are stored in `.foundry/` as git-committed files — there is no database. Storage implementation and commit conventions are in ADR-015.
- The audit log is `.foundry/audit.jsonl` — each approval event appends one JSONL line and commits it. `git log -p .foundry/audit.jsonl` is the authoritative inspection tool.
--- ./docs/adrs/ADR-015-storage-model.md ---
# ADR-015: Foundry Storage Model — Git and ETS, No Database Requirement

**Status:** Accepted  
**Date:** 2026-03  
**Deciders:** Platform team

---

## Context

The original spec-kit referenced "Project database" as the storage location for proposals,
audit logs, and approval records without justifying the choice. Foundry is a dev tool that
runs against an Elixir project. Requiring a Postgres instance as a prerequisite for
`mix foundry.studio` creates significant installation friction and contradicts the goal
of zero-infrastructure local operation.

The question: does Foundry need a database of its own, or can its state live in git and ETS?

## Decision

**Foundry requires no database of its own. All persistent state uses git-backed files.
All ephemeral state uses ETS. Postgres is a target platform concern, not a Foundry concern.**

---

## Two-Tier Storage Model

### Tier 1 — Git-backed files (persistent, both modes)

All state that must survive process restarts or be auditable lives as files under `.foundry/`
in the target project's repository.

```
.foundry/
  proposals/
    prop_<id>.json          ← one file per proposal, all lifecycle state
  audit.jsonl               ← append-only audit log, one JSON record per line
  manifest.exs              ← project manifest (approvers, sensitive_resources, etc.)
```

**Why git for persistence:**
- Git is already present — every Foundry project is a git repository
- Git commits are cryptographically integrity-checked — the audit log cannot be silently modified
- `git log .foundry/audit.jsonl` gives a human-readable history of every audit event with author and timestamp
- Blob hash coordination (ADR-009) already uses git — proposals and git are already coupled
- No infrastructure to provision, no connection strings, no migration lifecycle separate from the application

**`.foundry/` is committed to the repository.** Proposals in DRAFT state are not committed
(they are written to disk but not staged). Proposals from PENDING_REVIEW onward are committed
on every state transition. The audit log is committed on every approval event.

**Committer identity:** Foundry commits to `.foundry/` using the git user configured in the
project's git config. In cloud mode, a dedicated `foundry-bot` git identity is configured
per deployment. The committer is always distinct from the approver — the approval action
records the human approver's identity in the audit record; the commit records that Foundry
wrote it.

### Tier 2 — ETS (ephemeral, in-process)

All state that is session-scoped or derivable on restart lives in ETS via Nebulex L1.

| State | ETS key | Lost on restart? | Recovery |
|---|---|---|---|
| Spec-kit document cache | `{:spec_kit, path, mtime}` | Yes | Re-read from disk — cheap |
| ExDoc API cache | `{:exdoc, library, version}` | Yes | Re-fetch from ExDoc — cheap |
| Version manifest cache | `{:versions, mix_exs_mtime}` | Yes | Re-run mix task — cheap |
| Active WebSocket sessions | LiveView process state | Yes | Client reconnects automatically |
| DRAFT proposals (pre-submit) | LiveView assigns | Yes | User regenerates — DRAFTs are not committed |

Nothing in Tier 2 is irreplaceable. Restart recovery is automatic and cheap.

---

## Proposal File Format

Each proposal is a single JSON file at `.foundry/proposals/prop_<id>.json`.
The schema matches ADR-014 §Proposal Storage exactly — the file is the record.

**Reasoning trace field** — added at DRAFT creation, committed with the proposal.
Contains structured metadata of the engine's decision steps. Not LLM prompt content
(never stored — ADR-012 §Data Retention).

```json
"reasoning_trace": {
  "intent_classification": {
    "task": "change",
    "operation": "Op.AddRule",
    "confidence": 0.91
  },
  "shell_calls": [
    "cat docs/adrs/ADR-005-change-approval-model.md",
    "mix foundry.context MyApp.Finance.Wallet --json",
    "mix foundry.pattern.find rule --domain Finance"
  ],
  "contradiction_check": {
    "contradiction": false,
    "checked_adrs": ["ADR-005", "ADR-002"],
    "checked_invs": ["INV-001", "INV-011"],
    "summary": null
  },
  "change_class": ":behavioral",
  "confidence_state": "HIGH_CONFIDENCE",
  "session_snapshot": {
    "pending_migrations": 0,
    "open_proposals": 1,
    "lint_errors": 0
  }
}
```

`checked_adrs` and `checked_invs` must be non-empty. An empty list means the
contradiction check was skipped — test failure, not acceptable.

`shell_calls` records the actual bash commands the agent called during the loop.
Used for debugging misclassifications and auditing agent behaviour.

`session_snapshot` captures the Tier 2 state at proposal creation — whether the
agent was aware of pending migrations or conflicting open proposals.

For **question responses** (no proposal file): equivalent fields emitted as attributes
on the `[:foundry, :llm, :call]` telemetry span. Not persisted to disk.

**Dev-mode trace log:** `config :foundry_studio, copilot_trace_log: true` writes
all reasoning traces (including question responses) to
`.foundry/logs/copilot_trace.jsonl` (gitignored, never committed).

Format: one JSON object per line, same schema as proposal `reasoning_trace` plus
`"response_type": "question" | "change_preview" | "blocked" | "clarification"`.

Primary debugging surface during Phase 3 development before the Operations Board
(Phase 6) surfaces telemetry. Set `true` in `config/dev.exs` during active Phase 3
development. Not rotated automatically — clear manually.

State transitions write to the file and commit it:

```
DRAFT created        → file written to disk, NOT committed
PENDING_REVIEW       → file committed: "foundry: proposal prop_<id> submitted for review"
APPROVED             → file updated + committed: "foundry: proposal prop_<id> approved"
APPLIED              → file updated + committed: "foundry: proposal prop_<id> applied"
COMMITTED            → file updated + committed: "foundry: proposal prop_<id> committed [sha]"
REJECTED             → file updated + committed: "foundry: proposal prop_<id> rejected"
STALE                → file updated, NOT committed (ephemeral state, user will regenerate)
```

**Concurrent write safety:** Two simultaneous state transitions on the same proposal file
are resolved by git. The second writer rebases on the first commit. If the rebase fails
(genuine conflict on the same field), Foundry surfaces: "This proposal was modified
concurrently. Refresh to see current state." This is the same optimistic locking principle
as ADR-009, applied to the proposal file itself.

---

## Audit Log Format

`.foundry/audit.jsonl` is an append-only file. Each line is a complete JSON record.
New records are appended and the file is committed after each append.

```jsonl
{"event":"approved","proposal_id":"prop_abc","approver":"sl@co.com","role":"sensitive_lead","slot":1,"timestamp":"2026-03-04T14:22:00Z","diff_hash":"sha256:abc...","change_class":":sensitive"}
{"event":"approved","proposal_id":"prop_abc","approver":"pl@co.com","role":"platform_lead","slot":2,"timestamp":"2026-03-04T14:31:00Z","diff_hash":"sha256:abc...","change_class":":sensitive"}
{"event":"applied","proposal_id":"prop_abc","applied_by":"foundry-bot","timestamp":"2026-03-04T14:32:00Z","commit_sha":"abc123"}
```

**Integrity:** Because the file is committed to git, `git log -p .foundry/audit.jsonl`
shows every append with the committer identity, timestamp, and exact content added.
A record cannot be deleted without that deletion appearing in git history.

**Export:** `mix foundry.audit.export --from=<date> --to=<date>` reads the JSONL file,
filters by timestamp, and outputs a formatted JSON array. For regulatory inspection,
the git history of the file is the primary evidence — the export is a convenience format.

---

## Cloud Mode: Coordination Without a Database

In cloud mode, multiple Studio nodes serve requests. Proposal files live in the git
repository that the cloud instance is connected to. State transitions commit to that
repository. Cross-node coordination uses the git remote as the coordination point:

- Node A writes and commits a state transition → pushes to remote
- Node B reads proposal state → pulls from remote (or reads from its local clone, which is refreshed on file-watch events)
- PubSub (Phoenix, in-process Erlang distribution) handles real-time UI updates — when Node A commits a state transition, it broadcasts the event via PubSub so all connected clients see the update without polling

**Latency:** A git commit + push adds ~100–500ms to a state transition in cloud mode.
This is acceptable for approval workflows (humans are in the loop) but would be unacceptable
for request-per-second operations. Foundry has no request-per-second state transition
requirements — proposals are approved on the order of minutes to hours.

**No git push conflicts in practice:** State transitions on a single proposal are sequential
(a proposal cannot be approved by two people simultaneously for the same slot — the UI
disables the second approval button once the first is recorded). The only genuine concurrent
write case is two different proposals being approved simultaneously, which write to different
files and never conflict.

---

## What Changes From the Previous Spec

The following references in other documents meant "Postgres" implicitly. They now mean
the git-backed file storage described here:

| Document | Old implied meaning | Corrected meaning |
|---|---|---|
| ADR-012 §Data Retention | "Project database" | `.foundry/` files in git |
| ADR-014 §Proposal Storage | "stored in database" | `.foundry/proposals/prop_<id>.json` |
| ADR-014 §Audit Log | "append-only database table" | `.foundry/audit.jsonl` appended and committed |
| AGENTS.md dogfooding note | Foundry uses its own Ash/Postgres stack for its state | Foundry uses git-backed files for its own state; Ash/Postgres is for target platform resources only |

---

## Scope Boundary

Foundry's git-backed storage is for Foundry's own operational state (proposals, audit log).
Target platform domain resources still use `ash_postgres` — Foundry introspects those via
Mix task subprocess and does not own their database. Nebulex caches were already ETS.
ADR-001 is updated to reflect that `ash_postgres` is a target platform dependency, not a Foundry dependency.

---

## Consequences

- `mix foundry.studio` has zero infrastructure prerequisites beyond Elixir and git
- `.foundry/` directory must be added to the project's `.gitignore` exclusion list for DRAFT proposals: `.foundry/proposals/prop_*.draft.json` — committed proposals use `.json` extension
- The audit log is the git history of `.foundry/audit.jsonl` — `git log -p .foundry/audit.jsonl` is a valid regulatory inspection tool
- Cloud mode adds ~100–500ms latency to state transitions due to git commit + push — acceptable for human-in-the-loop approval workflows
- Foundry's own `mix.exs` does not include `ash_postgres` — the Core Stack table in ADR-001 is corrected to reflect this
- `mix foundry.audit.export` reads `.foundry/audit.jsonl` directly — no database query
- DRAFT proposals are not committed — if the Studio process restarts while a user has an unsaved draft, the draft is lost. This is acceptable: DRAFTs are pre-submission and regeneration is cheap.
--- ./docs/adrs/ADR-016-visualization-paradigm-v2.md ---
# ADR-016: Visualization Paradigm v2

**Status:** Accepted  
**Date:** 2026-03  
**Deciders:** Platform team  
**Supersedes:** ADR-008 (retained for historical record)

---

## Context

ADR-008 established the read-only system map paradigm and the Activity Feed as the only
change interface. That decision stands. This ADR refines and finalizes the visual model:
the four C4 levels, the complete node and edge taxonomy, the authorization layer, and the
agent node type added in ADR-017. ADR-008 is not wrong — it is incomplete.

The design was arrived at through explicit rejection of two failure modes:
1. Mermaid-only output — loses all compliance signal; diagrams become documentation, not governance instruments
2. Over-engineered abstraction — renderer registries, semantic schema contracts, adapter layers. These are correct for a multi-stack product. Foundry is single-stack. The abstraction cost is not justified.

The right model is: Cytoscape.js canvas consuming a simple JSON contract produced by
`mix foundry.diagram.generate --json`, with Foundry-specific styling applied via a direct
`switch` on node type. No framework. No registry. A well-organized frontend module.

---

## Decision

### Four C4 Levels — All Present, Different Surfaces

**Level 1 — System Context (outermost zoom)**  
Shows the system boundary, user personas, and external systems. Rendered as the fully
zoomed-out state of the main canvas. User personas and non-Elixir external system
descriptions are hand-authored in the spec-kit manifest YAML (`foundry.exs` or
`docs/system-context.yml`). Provider nodes (`⬚`) and API entry points are auto-derived.
This level is not a separate diagram — it is what the canvas shows at maximum zoom-out.

**Level 2 — Containers**  
For monolithic Phoenix applications (Foundry's primary target), Level 2 is incorporated
into Level 1. Relevant external containers (Postgres, Redis, Oban queue, external providers)
appear as Provider nodes. Multi-service architectures are not a v1 target.

**Level 3 — Components (primary operating level)**  
Domains as Cytoscape compound nodes. Resources, Transfers, Reactors, Rules, LiveViews as
node-level components inside domain clusters. This is the ambient canvas state at normal
zoom. All governance signal — compliance posture, test coverage, sensitivity — is expressed
here. This level drives all copilot navigation.

**Level 4 — Code detail (detail drawer)**  
Full attribute list with types and sensitivity flags, action signatures with accept/return
types, policy logic with actor/condition/outcome, FSM transition conditions, step
input/output types. Level 4 is not a separate diagram; it is the content rendered in the
detail drawer when any Level 3 node is clicked. `mix foundry.context <Module>` is the
data source.

### Node Taxonomy — Final, 11 Types

| Type | Icon | Source | Represents |
|---|---|---|---|
| Resource | ⬡ | Ash.Resource | Persistent entity, data at rest |
| Transfer | ⇄ | Ash.Reactor + Transfer DSL | Multi-step saga with compensation |
| Reactor | ◈ | Ash.Reactor (standalone) | Async orchestration / background |
| Rule | ◆ | Custom Rule module | Guard / policy / constraint |
| Job | ⚡ | Oban.Worker | Background job, queue worker |
| LiveView | ▣ | Phoenix.LiveView | User-facing page or back-office UI |
| LiveResource | ⊞ | AshPyro / AshAdmin | Auto-generated back-office CRUD UI |
| Blueprint | ◇ | Custom config resource | Configuration template / operational params |
| Provider | ⬚ | External adapter module | External system boundary |
| Trigger | ▶ | api_routes / webhook / scheduler | Entry point — how flow starts |
| Terminal | ⟐ | Reactor return / error path | How flow ends (success / error / compensated) |

Agent steps are NOT a top-level node type on the canvas. They are rendered as inline step
nodes (⊕ icon, `agent` kind) inside the swimlane of the containing Transfer or Reactor.
See ADR-017 for the agent step visual specification.

No additional node types will be added without an ADR. The 11 above are sufficient for
the complete surface of a Foundry-built Elixir/Ash/Phoenix system.

### Edge Taxonomy — Final, 8 Types

| Edge | Meaning | When used |
|---|---|---|
| `──────▶` | Triggers / sequence flow | Trigger→Transfer, step→step |
| `- - -▶` | Async / message | Step spawns Job, crosses boundary |
| `·····▶` | Guards / constrains | Rule applied to step or resource |
| `══════▶` | Compensation / undo | Undo path in saga |
| `◇─────` | Reads (non-mutating) | Step reads Resource |
| `◆─────` | Writes (mutating) | Step creates/updates/deletes Resource |
| `──────○` | Renders / serves | LiveView serves Resource data |
| `──────▷` | Configured by | Reactor reads Blueprint at runtime |

### Status Indicators on Nodes

Every node carries a compact status badge row. The exact indicators:

| Indicator | Meaning |
|---|---|
| ◉ | Compliance-covered — all declared requirements have linked tests |
| ○ | Compliance gap — one or more requirements untested |
| ⬡ | Policy present — node has declared policies or rules |
| PSE | paper_trail + soft_delete + ecto — rendered only on `sensitive: true` nodes; shows which of the three are present (e.g. `PS·` means paper_trail and soft_delete present, ecto data layer absent or non-postgres) |
| ~ | Has runbook linked |
| 📖 | Has ADR linked |
| ↻ | Has pending migration |
| ⚠ | Active lint violation |

### Authorization Layer — Detail View Only

The authorization matrix is not rendered on the ambient canvas. It appears as a dedicated
tab in the detail drawer for any Resource node that has declared policies.

The matrix rows are actor roles; columns are actions; cells show authorized/forbidden
with conditions. Data is derived from `Ash.Policy.Authorizer` introspection, which exposes
the full policy structure including `action`, `actor`, `policies`, `resource`, `domain`,
and `scenarios`.

The drawer tab also shows policy test coverage: which actor/action combinations have
corresponding test cases in the test suite, and which are untested.

An "Authorization Trace" scenario mode (accessible from the canvas toolbar) draws
authorization edges between the actor-identity Resource and the Resources it can access,
labeled with the permitted actions. This mode is not on by default — it is available on
demand for security audits. It is not ambient because a system with 10 resources and
4 actor roles produces 40+ potential edges, overwhelming the canvas.

### Canvas Modes

The canvas supports four modes, selectable from the toolbar:

| Mode | Description |
|---|---|
| Default | Standard domain/component view — ambient operating mode |
| Scenario trace | Highlights the execution path for a selected scenario — shows which nodes and edges activate for a given request |
| Authorization | Shows auth edges between actor-identity resources and the resources they can access |
| Config view | Highlights Blueprint nodes and their `configured-by` edges — shows what is adjustable without a code change |

### What the Diagram JSON Contract Contains

Produced by `mix foundry.diagram.generate --json`. Schema is frozen — breaking changes
require an ADR.

```json
{
  "generated_at": "ISO8601",
  "domains": [
    {
      "id": "finance",
      "name": "Finance",
      "health": { "coverage": 0.78, "gaps": 2, "sensitive_gaps": 1 }
    }
  ],
  "nodes": [
    {
      "id": "MyApp.Finance.WithdrawalTransfer",
      "type": "transfer",
      "name": "WithdrawalTransfer",
      "domain": "finance",
      "sensitive": true,
      "health": {
        "compliance_posture": "gap",
        "test_coverage": 0.88,
        "has_runbook": true,
        "pending_migration": false
      },
      "triggers": ["POST /api/withdraw"],
      "reads": ["MyApp.Identity.Player", "MyApp.Finance.Wallet"],
      "writes": ["MyApp.Finance.Wallet", "MyApp.Finance.LedgerEntry"],
      "guards": ["MyApp.Compliance.KycCheck"],
      "terminals": ["committed", "kyc_error", "compensated"],
      "steps": [
        {
          "id": "validate_inputs",
          "kind": "step",
          "guards": ["MyApp.Compliance.KycCheck"],
          "reads": [], "writes": [],
          "error_paths": [{"type": "halt", "id": "kyc_error"}]
        }
      ]
    }
  ],
  "edges": [
    {
      "from": "POST /api/withdraw",
      "to": "MyApp.Finance.WithdrawalTransfer",
      "type": "triggers"
    }
  ]
}
```

Agent steps appear in `steps` with `"kind": "agent"` and the agent-specific fields defined
in ADR-017. They are not top-level nodes and do not appear in `nodes`.

The `kind` field is new in this schema version. All existing step objects that predate
this field are treated as `"kind": "step"` by the renderer — the field defaults to `"step"`
when absent, making the addition non-breaking for existing consumers. Valid `kind` values
are: `"step"` (generic step), `"update"` (Ash resource update), `"create"` (Ash resource
create), `"read"` (Ash resource read), and `"agent"` (Foundry agent step). Renderers that
do not recognise a `kind` value must fall back to `"step"` rendering rather than erroring.

### Implementation Stack

- **Canvas**: Cytoscape.js. Not D3, not a custom engine. Cytoscape handles layout,
  compound nodes, zoom, click/hover events.
- **Node styling**: Direct `switch` on `node.type` in the frontend module. Not a registry.
  Not a behaviour. A switch statement with 11 cases.
- **Detail drawer data**: `mix foundry.context <Module>` output rendered directly.
  No transformation layer between the Mix task output and the drawer template.
- **Live reload**: inotify watcher → Phoenix PubSub → LiveView push. The canvas re-renders
  on any source file change within 2 seconds (performance budget per ADR-012).
- **Diagram JSON generation**: `mix foundry.diagram.generate --json` is idempotent and
  fast (target: <500ms for a 50-module project). It must be runnable in CI for INV-008.

---

## Consequences

- ADR-008's "read-only system map" and "Activity Feed is the only change interface"
  decisions are inherited unchanged. ADR-016 adds visual specification; it does not
  change the interaction model.
- The 11 node types and 8 edge types are the complete visual vocabulary. Adding types
  requires an ADR with justification for why the existing taxonomy is insufficient.
- Mermaid output is a secondary artifact from the same JSON contract, used for GitHub
  README documentation and PR descriptions. `mix foundry.diagram.mermaid` produces it.
  The Cytoscape canvas is the primary governance instrument.
- Authorization matrix is Level 4 (drawer), not Level 3 (canvas), by explicit decision.
  The canvas edge approach is available in "Authorization" mode for on-demand use.
- The diagram JSON schema is frozen at the end of Phase 2. Adding fields requires an ADR.
  Agent step fields (ADR-017) are added as a non-breaking extension — new fields inside
  the existing `steps` array item, ignored by renderers that do not handle `"kind": "agent"`.

---

## What This Is Not

This ADR does not define the copilot interaction model (ADR-013), the proposal lifecycle
(ADR-014), or the Studio UX panels beyond the system map (ADR-012). It defines only the
visual representation of the target platform's domain model.
--- ./docs/adrs/ADR-017-agent-injection-governance.md ---
# ADR-017: Agent Injection Governance

**Status:** Accepted  
**Date:** 2026-03  
**Deciders:** Platform team  
**Supersedes:** ADR-001 §Out of Scope — "AshAI DSL introspection" item

---

## Context

ADR-001 deferred AshAI integration ("Foundry v1 will not fail on AshAI declarations —
it will ignore them and warn") on the grounds that the AshAI DSL was not stable enough
to freeze in the `mix foundry.context` schema.

The design questions are now resolved. The AshAI DSL is stable, the Reactor orchestration
model for agents is clear, the agent taxonomy is established, and the governance requirements
for regulated domains (human-in-the-loop gates, confidence thresholds as change-class
triggers, tool access governance) are understood. This ADR supersedes the deferral.

AshAI + Ash.Reactor is the correct and complete stack for agent injection in Foundry
target platforms. No Python framework, no LangGraph, no CrewAI. The infrastructure is:

```
AshAI          — prompt-backed Ash actions, tool declaration, vector search
Ash.Reactor    — orchestration, parallelism, compensation, dependency ordering
LangChain.ex   — LLM protocol (model selection, streaming, tool call protocol)
```

Foundry adds: governance, visualization, telemetry, and human-in-the-loop gate management.

---

## Decision

### Agent Steps Are First-Class Reactor Constructs

An agent step is an `Ash.Reactor` step whose implementation module is annotated with
Foundry governance metadata. It calls an AshAI prompt-backed action. It is not a separate
concept from a Reactor step — it is a step that happens to use an LLM to compute its
output. The Reactor handles parallelism, retry, compensation, and dependency ordering
exactly as for non-agent steps.

Governance metadata is declared on the **step implementation module**, not inline in the
Reactor DSL. This preserves the standard `Ash.Reactor` step syntax and avoids patching
the Reactor DSL — a coupling that would break on Ash upgrades. Foundry introspects the
module's Spark declarations to derive the governance fields for visualization, lint, and
`mix foundry.context`.

```elixir
# The step implementation module — carries Foundry governance metadata
defmodule MyApp.Risk.AgentSteps.ScoreRisk do
  use Foundry.AgentStep

  agent_type :scorer
  model :claude_sonnet
  confidence_threshold 0.7
  on_low_confidence :escalate_human
  human_gate queue: :compliance_review, sla_hours: 4
  tools [:read_player_history, :check_velocity, :read_spending_limit]
  telemetry_prefix [:my_app, :risk, :withdrawal, :risk_score]

  @impl true
  def run(args, _context) do
    MyApp.Risk.RiskAssessment
    |> Ash.ActionInput.for_action(:score_risk, args)
    |> Ash.run_action()
  end
end

# The Reactor — standard Ash.Reactor syntax, unchanged
defmodule MyApp.Risk.WithdrawalRiskReactor do
  use Reactor, extensions: [Ash.Reactor]

  step :risk_score, MyApp.Risk.AgentSteps.ScoreRisk do
    argument :transaction, input(:transaction)
    argument :player, input(:player)
  end
end
```

`use Foundry.AgentStep` is a Spark DSL extension that Foundry provides. It adds the
`agent_type`, `model`, `confidence_threshold`, `on_low_confidence`, `human_gate`, `tools`,
and `telemetry_prefix` DSL sections to the module. These are Foundry-specific — they are
not part of core AshAI or Ash.Reactor. The `run/2` callback is standard `Reactor.Step`
behaviour.

### Agent Taxonomy — 10 Types

Every agent step must declare one of these 10 `agent_type` values. The type determines
what telemetry fields are expected, what detail drawer template is rendered, and what
lint rules apply.

| Type | Purpose | Key output field | Compliance notes |
|---|---|---|---|
| `classifier` | Labels/categorises incoming data | `category: atom` | Low governance — fast, automated |
| `extractor` | Pulls structured data from unstructured input | `result: typed_struct` | Low — data pipeline |
| `scorer` | Produces a numeric assessment | `score: float, factors: [str], confidence: float` | Medium — drives decisions |
| `decision` | Makes a binary or multi-way choice | `action: atom, reason: str, confidence: float` | HIGH — may block flow; human gate required on compliance paths |
| `advisor` | Produces a recommendation | `response: str, citations: [str], escalate: bool` | Medium — human always reviews |
| `observer` | Monitors a stream and flags anomalies | `alert: struct | nil` | Low — passive until alert |
| `enricher` | Adds context to an existing entity | `enhanced_record: struct` | Low — additive |
| `router` | Determines which path a flow takes | `next_step_id: str` | Medium — structural |
| `summarizer` | Compresses history or events | `summary: str, key_facts: [str]` | Low — informational |
| `orchestrator` | Manages other agents, synthesises results | `completed_result: any` | HIGH — multi-agent; separate approval chain required |

### Change Classification for Agent Constructs

| Change | Class | Rationale |
|---|---|---|
| Adding an `agent` step to a Transfer or Reactor | `:behavioral` | New LLM call in a flow; requires domain lead approval |
| Changing `agent_type` | `:behavioral` | Different output schema and telemetry contract |
| Changing `model` | `:behavioral` | Different capability and cost profile |
| Changing `confidence_threshold` | `:behavioral` | Affects how often human gate triggers |
| Changing `on_low_confidence` handler | `:behavioral` | Changes fallback behaviour |
| Adding/removing tools from `tools` list on a compliance-gated resource | `:compliance` | Expands/contracts agent authority; ADR required |
| Removing a `human_gate` from a compliance-gated decision step | `:compliance` | Removes human oversight; ADR required |
| Changing `human_gate` SLA | `:behavioral` | Governance timeline change |
| Changing prompt content in a prompt-backed AshAI action | `:behavioral` | Affects output semantics |
| Adding an `agent` step to a `:sensitive` resource's Transfer | `:sensitive` | Dual approval required |

### Human Gate Specification

A `human_gate` declaration on an agent step creates a review task in the configured queue
when the agent's confidence falls below threshold, or always for `decision` steps on
compliance-gated paths regardless of confidence. The gate:

1. Halts the Reactor step and returns `:waiting_for_human`
2. Creates an `HumanGateTask` record (an Ash resource with `ash_oban` background processing)
3. Assigns the task to the configured queue with the declared SLA
4. When a human approves or overrides, the Reactor step resumes with the human's decision
5. The override is recorded in the audit log with `actor`, `timestamp`, `original_agent_decision`, and `human_decision`

**HumanGateTask resource ownership:** `HumanGateTask` is scaffolded into the *target
platform* — not into Foundry itself — because it holds domain-specific review records that
belong in the platform's audit trail. `Op.AddAgentStep` checks for the resource's existence
and scaffolds it into the target platform on first use if absent. Because `HumanGateTask`
is always `:sensitive`, this scaffold operation requires dual approval (ADR-005) before it
is applied. Implementers should expect this: the first agent step added to any project
triggers a two-step proposal — the `HumanGateTask` resource creation (`:sensitive`, dual
approval) followed by the agent step itself (`:behavioral`, domain lead approval). Both
proposals are shown together in the review panel with their distinct approval requirements.

The `HumanGateTask` resource is always `:sensitive` (INV-001). Override audit records are
permanent and require `ash_paper_trail` (INV-011) and soft delete only (INV-012).

The override rate (percentage of agent decisions changed by a human reviewer) is a key
quality signal surfaced in the Agent Health panel (Phase 8). A rising override rate
triggers a lint warning recommending prompt review. The threshold for this warning is
configurable per project via `manifest.exs` under `agent_governance.override_rate_warn_threshold`
(default: 0.20). A project-specific threshold must be documented in an ADR when it deviates
from the default.

### Lint Rules Added by ADR-017

The following lint rules are enforced by `Foundry.Lint.AgentStepChecker`:

- **agent_confidence_threshold_required**: `decision` and `scorer` steps must declare `confidence_threshold`
- **agent_human_gate_required**: `decision` steps on compliance-gated paths must declare `human_gate`
- **human_gate_only_on_gatable_types**: `human_gate` may only be declared on `decision` and `advisor` types; declaring it on `observer`, `summarizer`, `classifier`, `extractor`, `enricher`, or `router` types is a lint error — these types do not block flow and a halting gate contradicts their semantics
- **agent_tools_declared**: `tools` list must be non-empty; undeclared tool usage is a lint error
- **agent_telemetry_prefix_required**: `telemetry_prefix` must be declared on all agent steps
- **agent_type_declared**: `agent_type` must be one of the 10 canonical values
- **orchestrator_approval_chain**: `orchestrator` type steps require a separate `:behavioral` proposal; cannot be added in the same proposal as other agent steps

### Visualization — Agent Steps on the Canvas

Agent steps appear as inline step nodes inside the swimlane of their containing Transfer
or Reactor. They are NOT top-level canvas nodes.

The inline step node:
- Icon: `⊕`
- Label: step name + agent type label (e.g., "risk_score · scorer")
- Sub-label: model name + p95 latency + error rate (from telemetry)
- Confidence indicator: threshold value, current mean confidence

When confidence falls below threshold, the step node shows a `⬡ human_gate` branch in the
swimlane, with the queue name and SLA. This makes human oversight points visible in the
flow without navigating to the detail drawer.

The detail drawer for an agent step shows the type-specific template (see below by type).
All templates include: input/output schema, model, tool access list, confidence distribution
histogram, and — for `decision` type — the override rate.

**Per-type drawer content:**

`classifier` — distribution of output categories (last 24h), accuracy against labeled
samples if ground truth exists.

`scorer` — score distribution histogram (last 7d), top factors in high-score cases,
calibration metric (mean confidence vs actual accuracy).

`decision` — decision distribution, human escalation count, override rate. The override
rate is prominently displayed; it is the primary quality signal.

`observer` — current state (nominal/alerting), alert history (30d), alert routing
configuration.

`advisor` — resolution rate, average handle time, escalation rate, citation accuracy.
Human-in-the-loop is always-on for `advisor` type.

`enricher`, `extractor`, `summarizer` — throughput, error rate, latency.

`router` — routing distribution across paths (last 7d).

`orchestrator` — sub-agent coordination graph (shows which agents it orchestrates and
in what order), total cost/run, total latency.

### AshAI Version Requirement

AshAI 2.x or later is required for the Foundry DSL extension to function. The
`mix foundry.context` task reads the AshAI version from `mix.exs` as part of the version
manifest (INV-006). If AshAI is present but older than 2.x, the task warns and skips
agent step introspection — it does not fail.

Projects that do not use AshAI are unaffected. The `agent_steps` field in the context
schema is an empty list `[]` for all modules in such projects.

### Relationship to AshAI Domain DSL

The `tools` declaration in the Foundry agent step DSL maps to AshAI's domain-level tool
declaration:

```elixir
defmodule MyApp.Finance do
  use Ash.Domain, extensions: [AshAi]
  tools do
    tool :check_balance,    MyApp.Finance.Wallet,       :read
    tool :flag_transaction, MyApp.Finance.Transaction,  :flag
  end
end
```

Foundry's lint rule `agent_tools_declared` cross-references the `tools` list on each
agent step against the domain's AshAI tool declarations. A tool referenced in an agent
step but not declared in the domain is a lint error. A tool declared in the domain but
never referenced by any agent step generates a lint warning (dead tool declaration).

---

## Consequences

- ADR-001's deferral of AshAI is superseded. AshAI 2.x+ is now in the "conditionally
  present" category (project declares opt-in in manifest). Projects that opt in gain
  agent step governance; projects that do not are unaffected.
- The `mix foundry.context` schema gains an `agent_steps` field (documented in AGENTS.md
  and ADR-003 addendum). This is a non-breaking addition — the field is `[]` when absent.
- Phase 8 of BUILD_SEQUENCE (Agent Health panel) is the implementation milestone for
  the observability surface defined here.
- `orchestrator` agent type steps require a separate `:behavioral` proposal because they
  introduce coordination topology. This prevents an orchestrator from being added quietly
  inside a larger proposal.
- Human gate override records are permanent and `:sensitive`. They require audit logging
  via `ash_paper_trail` (INV-011) and soft delete only (INV-012). They are runtime records,
  not code change proposals — ADR-005 dual-approval applies to the scaffold of the
  `HumanGateTask` resource itself (see Human Gate Specification above), not to individual
  override records created at runtime.

---

## What This Is Not

This ADR does not govern which LLM models are available, API key management, or token
budget allocation. Those are ADR-010 concerns. It does not govern the copilot agent
behaviour (ADR-013). It governs the injection of AI agents into target platform domain
flows — the thing that target platforms build with Foundry, not Foundry's own copilot.
--- ./docs/adrs/ADR-019-package-extraction.md ---
# ADR-019: Package Extraction — Reusable Primitives vs Foundry-Internal Modules

**Status:** Deferred — write in full when first package is published to Hex
**Date:** 2026-03
**Deciders:** Platform team

---

## Context

Foundry is a meta-platform. Parts of it implement general-purpose primitives that any
Ash/Spark project could use: DSL introspection, lint rule running, human-in-the-loop
gates for Reactors. The question is which parts earn their own Hex package and which
parts are better kept internal.

The cost of extracting too early: premature abstraction, unstable API surfaces, maintenance
overhead before the design is proven. The cost of extracting too late: the logic becomes
entangled with Foundry internals and is harder to separate cleanly.

The decision criterion used: **extract if and only if there is a clear audience outside
Foundry who would use the package as-is, with no Foundry-specific configuration.**

---

## Decision

### Extracted as standalone packages

| Package | Rationale |
|---|---|
| `spark_meta` | Any Spark-based project wanting structured JSON/struct output of DSL state benefits from this. The generic walker requires no Foundry config. `SparkMeta.Extension` opt-in hook lets extension authors (e.g. AshPyro) provide richer output without modifying the core. |
| `spark_lint` | The rule runner protocol (behaviour + violation struct + mix task) is ~200 lines and completely domain-agnostic. Shipping it separately lets external teams publish their own rule packages. Foundry's actual rules ship in `Foundry.LintRules.*` (internal). |
| `reactor_human_gate` | Human-in-the-loop gates are useful to any AshAI team independently of Foundry. The `HumanGateTask` resource and `WaitForHumanStep` have no Foundry assumptions. Usable before Phase 8 of Foundry. |
| `reactor_agent_step` | The Spark DSL extension for Reactor agent step declarations (`agent_type`, `model`, `confidence_threshold`, `on_low_confidence`, `tools`, `telemetry_prefix`) is a natural companion to `reactor_human_gate`. Extraction confirmed alongside it. Depends on `reactor_human_gate`. |

### Rejected — stays internal

| Candidate | Why rejected |
|---|---|
| `ash_governed` (DSL annotation for sensitive resources) | Not needed for v1. `manifest.sensitive_resources` list is the declaration mechanism. A DSL annotation would improve developer ergonomics (co-location) but provides no new capability. Build if teams request it post-launch. |
| `spec_kit` (spec-kit document parser) | "Spec-kit" is Foundry vocabulary. No external audience for the document format yet. `Foundry.SpecKit` uses `MDEx` + `NimbleOptions` — ~150 lines of internal glue. Extract when a second tool wants to read the same ADR/runbook format. |
| `igniter_typed` / `igniter_ops` (typed Igniter protocol) | The describe/validate/run protocol lives in `Foundry.Operations.*`. Extract if a second tool needs the same protocol. Currently no such tool exists. |
| `ash_diff` (change classifier) | The ADR-005 classification rules are tightly coupled to the manifest sensitive-resources list and Foundry's four change classes. The underlying AST analysis uses `Sourceror` directly — the thin wrapper does not justify its own package. Lives in `Foundry.Diff`. |
| `Foundry.Proposals` (proposal state machine) | Coupled to git-backed storage (ADR-015) and blob-hash stale detection (ADR-009). Separating the state machine from the storage would require an abstraction whose API is unknown. Extract when a second use case appears. |

---

## Telemetry stance (recorded here for completeness)

Ash and Reactor already emit telemetry for all actions and steps. Foundry adds three
custom spans via `:telemetry.span/3`, no macros, no mandatory behaviour:

| Event name | Fields | Purpose |
|---|---|---|
| `[:foundry, :llm, :call]` | model, task_type, prompt_tokens, latency_ms, error | LLM API call observability |
| `[:foundry, :context, :subprocess]` | module, cached, latency_ms | `mix foundry.context` subprocess timing |
| `[:foundry, :proposal, :transition]` | proposal_id, from_state, to_state, change_class, approver_count | Proposal state machine audit |

Event name constants live in `Foundry.Telemetry`. This module contains only constants —
no macros, no `use` behaviour. Every instrumented call site is findable by grepping for
`Foundry.Telemetry`.

`reactor_agent_step` defines its own telemetry event names following the
`[app_name, domain_name, reactor_name, step_name]` convention (INV-017) — it does not
depend on `Foundry.Telemetry` (which would create a circular dependency).

---

## Consequences

- `spark_meta`, `spark_lint`, `reactor_human_gate`, `reactor_agent_step` appear in
  Foundry's `mix.exs` as regular Hex dependencies
- `Foundry.LintRules.*` contains INV-011..017 rule modules; they implement `SparkLint.Rule`
  and are registered in the Foundry application config
- External teams can ship their own `SparkLint.Rule` modules without depending on Foundry
- The `ash_governed` decision is explicitly deferred, not forgotten — if teams request
  co-located sensitive resource annotations, build it then
- This ADR must be written in full (replacing this stub) before the first package ships to Hex,
  so the Hex package README can reference it

---

## What to fill in when writing the full ADR

- Final Hex package names and initial version constraints
- `SparkMeta.Extension` behaviour specification
- `SparkLint.Rule` behaviour specification and violation struct fields
- `reactor_human_gate` install mechanics (`mix reactor_human_gate.install` scope)
- `reactor_agent_step` DSL surface (confirm matches INV-014..017 declarations)
- Link to published Hex packages

--- ./docs/lint-catalogue.md ---
# docs/lint-catalogue.md — Foundry Lint Rule Catalogue

> **Purpose:** Authoritative list of all lint rules implemented or planned for
> `mix foundry.lint.all`. Each rule maps to one or more invariants and has a
> defined severity, detection mechanism, and implementation module target.
>
> **Closes:** Gap #53 (decorator library governance — `:decorated_transfer_step` rule
> makes the silent governance hole explicit and surfaced).
>
> **Rule:** When a new lint rule is added to `Foundry.Lint.*`, it must be catalogued here
> first (status: `planned`) before implementation begins. This is how the linter's
> coverage is tracked without duplicating what the code says.

---

## Severity Levels

| Severity | Behaviour | When to use |
|---|---|---|
| `:error` | Build fails (`mix foundry.lint.all` exits non-zero) | Invariant violation — the system cannot be trusted with this gap |
| `:warning` | Lint report includes violation; build passes | Governance risk that should be addressed but does not break correctness |
| `:info` | Surfaced in Studio lint tab; never in CI output | Informational signal for developer awareness |

---

## Rules by Invariant

### INV-001 — Sensitive Resource Approval

| Rule ID | Severity | Description | Implementation module | Status |
|---|---|---|---|---|
| `:sensitive_resource_unapproved_change` | `:error` | A diff touching a sensitive resource was submitted without dual approval. Enforced at apply time, not lint time — the approval workflow is the primary gate. Lint checks that sensitive resources are declared in the manifest. | `Foundry.Lint.SensitiveResourceRule` | planned |

---

### INV-002 — No Direct Filesystem Writes

| Rule ID | Severity | Description | Implementation module | Status |
|---|---|---|---|---|
| `:direct_file_write` | `:error` | Detects `File.write!/2`, `File.stream!/2`, or `EEx.eval_string/2` on paths in `lib/` or `test/`. Igniter is the only permitted write mechanism. | `Foundry.Lint.FileWriteRule` | planned |

---

### INV-004 — Idempotency Declaration

| Rule ID | Severity | Description | Implementation module | Status |
|---|---|---|---|---|
| `:missing_idempotency` | `:error` | A Reactor module with external side-effect steps (money movement, provider API calls, state transitions with audit implications) does not declare an idempotency key. The rule infers side effects from step types. Purely internal read/compute Reactors are exempt. | `Foundry.Lint.IdempotencyRule` | planned |

---

### INV-005 — Runbook Links

| Rule ID | Severity | Description | Implementation module | Status |
|---|---|---|---|---|
| `:missing_runbook` | `:error` | A Reactor module with more than 3 steps does not declare `@runbook`. The lint rule validates that the declared path resolves to an existing file — a non-existent runbook is as bad as no runbook. | `Foundry.Lint.RunbookRule` | planned |

---

### INV-006 — Description Coverage

| Rule ID | Severity | Description | Implementation module | Status |
|---|---|---|---|---|
| `:missing_description` | `:error` | An Ash resource attribute does not have a `description:` value. All public modules must have `@moduledoc`. Test modules are exempt. This rule is the raw material for the system map detail panel — without descriptions, the panel degrades. | `Foundry.Lint.DescriptionRule` | planned |

---

### INV-008 — Diagram Currency

| Rule ID | Severity | Description | Implementation module | Status |
|---|---|---|---|---|
| `:uncommitted_diagram` | `:error` | `mix foundry.diagram.generate` produces output that differs from what is committed in `docs/diagrams/system_map.json`. Detected by CI running the task and checking for unstaged changes. Not a traditional lint rule — implemented as a CI step, not in `Foundry.Lint.*`. | CI step in `mix foundry.diagram.generate --check` | planned |

---

### INV-010 — Notification Channels

| Rule ID | Severity | Description | Implementation module | Status |
|---|---|---|---|---|
| `:missing_notification_config` | `:warning` | The project manifest does not declare one or more of the three required notification targets (`runbook_stale`, `adapter_verify_failed`, `compliance_test_failed`). A warning because operational staleness is not a build-time concern — but a project going to production without notification config is a governance risk flagged in the compliance dashboard. | `Foundry.Lint.ManifestValidator` | planned |

---

### INV-011 — Paper Trail on Sensitive Resources

| Rule ID | Severity | Description | Implementation module | Status |
|---|---|---|---|---|
| `:missing_paper_trail` | `:error` | A resource in `manifest.sensitive_resources` (or an `ash_authentication` User/Token resource) does not declare `use AshPaperTrail.Resource` in its extensions. | `Foundry.Lint.PaperTrailRule` | planned |

---

### INV-012 — Soft Delete on Sensitive Resources

| Rule ID | Severity | Description | Implementation module | Status |
|---|---|---|---|---|
| `:missing_archival` | `:error` | A sensitive resource does not use `AshArchival.Resource`. Also checks that no `:destroy` action on a sensitive resource uses `soft_delete?: false` without an exemption declared in the manifest. | `Foundry.Lint.ArchivalRule` | planned |

---

### INV-013 — Feature Flag ADR Links

| Rule ID | Severity | Description | Implementation module | Status |
|---|---|---|---|---|
| `:missing_flag_adr` | `:error` | A `fun_with_flags` feature flag declared with `governance: :compliance` or `governance: :sensitive` does not have an ADR link in its Foundry governance metadata. | `Foundry.Lint.FeatureFlagRule` | planned |

---

### Manifest Validation

| Rule ID | Severity | Description | Implementation module | Status |
|---|---|---|---|---|
| `:manifest_missing_required_approver` | `:error` | `approvers.sensitive_lead` or `approvers.compliance_officer` is absent from the manifest. | `Foundry.Lint.ManifestValidator` | planned |
| `:manifest_unknown_sensitive_resource` | `:error` | A module listed in `sensitive_resource_exemptions` is not in `sensitive_resources`. | `Foundry.Lint.ManifestValidator` | planned |
| `:manifest_invalid_coverage_weights` | `:error` | `coverage_weights` values do not sum to 1.0 ± 0.001. | `Foundry.Lint.ManifestValidator` | planned |
| `:manifest_exclusion_no_comment` | `:warning` | An entry in `context_exclusions` has no accompanying comment with an issue reference. | `Foundry.Lint.ManifestValidator` | planned |
| `:manifest_missing_cldr_backend` | `:error` | `conditional_libraries` includes `:ash_money` but no CLDR backend module is discoverable in the project. | `Foundry.Lint.ManifestValidator` | planned |

---

### Admin Route Security

| Rule ID | Severity | Description | Implementation module | Status |
|---|---|---|---|---|
| `:admin_route_unauthenticated` | `:error` | A route for `oban_web`, `phoenix_live_dashboard`, or `fun_with_flags_ui` is not behind an `ash_authentication` session check. The rule inspects the router module for pipeline assignments on these paths. | `Foundry.Lint.AdminRouteRule` | planned |

---

### Money Type

| Rule ID | Severity | Description | Implementation module | Status |
|---|---|---|---|---|
| `:raw_money_type` | `:error` | An Ash resource attribute declares type `Money.t()` directly instead of `Ash.Type.Money`. Raw `Money.t()` bypasses the CLDR backend validation and breaks `ash_money` introspection. | `Foundry.Lint.MoneyTypeRule` | planned |

---

### AshPyro Component Convention (conditional — only when `:ash_pyro` in `conditional_libraries`)

| Rule ID | Severity | Description | Implementation module | Status |
|---|---|---|---|---|
| `:missing_data_attributes` | `:warning` | A LiveView component rendered by a `LiveResource` declaration does not include `data-action`, `data-field`, or `data-*` attributes on interactive elements. AshPyro-generated components are exempt (the rule recognises AshPyro macro output). | `Foundry.Lint.DataAttributeRule` | planned |

---

### Decorator Governance (Gap #53 — closes Gap #32)

| Rule ID | Severity | Description | Implementation module | Status |
|---|---|---|---|---|
| `:decorated_transfer_step` | `:warning` | A function in a Transfer module (Reactor with Transfer DSL) is annotated with a `@decorate` attribute from the `decorator` library. Foundry cannot introspect decorated function signatures — the change class of modifications to these steps cannot be determined automatically. **Manual review is required for any change touching decorated Transfer steps.** This warning is surfaced in: (1) the lint tab of the review panel whenever a proposal touches a decorated Transfer step, (2) `mix foundry.lint.all` output. The warning does not block the proposal — it flags it for deliberate human attention. | `Foundry.Lint.DecoratorRule` | planned |

**Rationale:** The `decorator` library wraps function definitions in a macro. Foundry reads
DSL declarations and module structure via Spark introspection; decorated functions appear
as ordinary functions to the introspection layer but their runtime behaviour may differ.
For Transfer steps — which carry `:sensitive` or `:behavioral` classification — this
ambiguity is a governance risk. The lint warning ensures it is never silent.

**This rule closes Gap #32 (decorator library unaddressed) and Gap #53 (decorator lint signal required).**
Once this rule is implemented, the `decorator` library's governance stance is: permitted,
with mandatory lint warning on Transfer steps. No further ADR is needed unless the team
decides to support full decorator introspection (a future enhancement, not a v1 concern).

---

## Rule Implementation Notes

All rules in `Foundry.Lint.*` follow the same contract:

```elixir
@callback check(module :: module(), context :: Foundry.Lint.Context.t()) ::
  {:ok, [Foundry.Lint.Violation.t()]} | {:error, term()}
```

`Foundry.Lint.Context.t()` carries: the compiled module, its Spark DSL extension info,
the current manifest, and the full module list (for cross-module rules like the
sensitive resource check).

Rules are composed by `mix foundry.lint.all`, which runs all registered rules against
all modules and aggregates violations into the structured JSON output.

The lint runner short-circuits on `:error` severity violations for CI — it collects
all violations first (so the developer sees everything at once), then exits non-zero
if any `:error` violations exist.
--- ./docs/manifest-schema-draft.md ---
# docs/manifest-schema-draft.md — Foundry Project Manifest Schema

> **Status:** Pre-ADR draft — consolidated from implicit references across ADR-001 through ADR-015.
> This document exists to give `Foundry.Manifest` Ash resource design a complete target.
> It will be superseded by ADR-011 once the Ash resource is defined.
> Do not treat this as a frozen contract. Treat it as the authoritative candidate schema.
>
> **Rule:** If you find a manifest field referenced in any ADR or invariant that is not listed
> here, add it here and note which document references it. Do not let implicit manifest fields
> accumulate in ADRs without being reflected in this document.

---

## File Location

```
.foundry/manifest.exs   ← committed to the target project repository
```

Foundry's own manifest lives at the same path within Foundry's own repository.
The schema is identical regardless of whether the project is Foundry itself or a target platform.

---

## Full Schema (Elixir keyword list format)

```elixir
# .foundry/manifest.exs
[
  # ── Identity ──────────────────────────────────────────────────────────────

  # Human-readable project name. Used in Studio UI headers, notification subjects,
  # and audit log records.
  project_name: "MyApp",

  # The target domain type. Informational only — does not change enforcement behaviour.
  # Used in bootstrap mode to select template defaults.
  # Values: :igaming | :fintech | :healthcare | :legal | :insurance | :other
  domain_type: :igaming,

  # ── Sensitive Resources ────────────────────────────────────────────────────
  # Source: ADR-005, INV-001, INV-011, INV-012

  # Modules that require dual approval, AshPaperTrail, AshArchival, and
  # full audit logging. Authentication User and Token resources are always
  # added to this set automatically — do not list them here.
  sensitive_resources: [
    MyApp.Finance.LedgerEntry,
    MyApp.Finance.Wallet,
    # Healthcare example: MyApp.Records.PatientRecord
    # Legal example: MyApp.Documents.PrivilegedDocument
  ],

  # Per-sensitive-resource exemptions. Each entry requires a documented reason
  # and is a :compliance class change to add or remove.
  # Source: INV-011 (paper_trail exemption), INV-012 (archival exemption)
  sensitive_resource_exemptions: [
    # {MyApp.Finance.LedgerEntry, paper_trail: :exempt, reason: "..."},
    # {MyApp.Finance.ArchivedWallet, archival: :exempt, reason: "..."}
  ],

  # ── Approvers ─────────────────────────────────────────────────────────────
  # Source: ADR-005, ADR-014, approval_queue_blocked runbook

  approvers: [
    # Required for :sensitive dual approval slot 1.
    sensitive_lead: "finance-lead@company.com",

    # Optional fallback when sensitive_lead is unavailable.
    sensitive_lead_delegate: "cto@company.com",

    # Qualifies as :sensitive dual approval slot 2,
    # and as the sole approver for :behavioral changes.
    domain_lead: "platform-lead@company.com",

    # Qualifies as :sensitive dual approval slot 2.
    platform_lead: "platform-lead@company.com",

    # Required sole approver for :compliance changes. No override path.
    compliance_officer: "compliance@company.com",

    # Optional fallback for compliance_officer.
    compliance_officer_delegate: "legal@company.com"
  ],

  # ── Approval SLAs ─────────────────────────────────────────────────────────
  # Source: approval_queue_blocked runbook

  # nil means no SLA. The operations board shows proposals exceeding their SLA in amber/red.
  approval_sla: [
    structural:  nil,
    behavioral:  [hours: 24],
    sensitive:   [hours: 4],
    compliance:  [hours: 48]
  ],

  # ── Auto-Apply Configuration ───────────────────────────────────────────────
  # Source: ADR-005, ADR-014, BUILD_SEQUENCE Phase 5

  # When true, approved :structural proposals are applied immediately on approval.
  # The approval action IS the apply trigger for :structural auto-apply.
  # All other classes always require a separate deliberate Apply action.
  auto_apply_structural: false,

  # ── Change Generation Phase Gate ──────────────────────────────────────────
  # Source: ADR-010, ADR-013, BUILD_SEQUENCE Phase 3/4

  # Controls whether the copilot generates real diffs (Phase 4+) or only
  # describes what would be proposed (Phase 3).
  # This is also set in config/foundry_studio.exs but the manifest value
  # takes precedence for per-project overrides.
  # Note: config :foundry_studio, change_generation_enabled: true/false is the
  # primary mechanism; this manifest field enables per-project override.
  change_generation_enabled: true,

  # ── Copilot Agentic Loop ──────────────────────────────────────────────────
  # Source: ADR-010 §Agentic Loop Specification

  copilot: [
    # Maximum bash tool calls per copilot request before :context_budget_exceeded.
    # Circuit breaker — not a quality knob. Normal operations never hit this.
    # Increase if complex multi-module operations routinely hit the limit.
    # Decrease to 4–5 for faster average response at the cost of depth.
    max_tool_calls: 8
  ],

  # ── Notifications ─────────────────────────────────────────────────────────
  # Source: INV-010, ADR-001 (swoosh, Slack webhook)

  # All three keys are required. Omitting any triggers a :missing_notification_config
  # lint warning (not a build failure, but a governance risk flag).
  notifications: [
    runbook_stale:          [channel: :slack,  target: "#ops-alerts"],
    adapter_verify_failed:  [channel: :email,  target: "platform-lead@company.com"],
    compliance_test_failed: [channel: :slack,  target: "#compliance-alerts"]
  ],

  # ── Test Coverage ─────────────────────────────────────────────────────────
  # Source: ADR-007

  # When true, a domain coverage score below 0.6 fails CI.
  # Recommended: false for new projects, true before go-live.
  coverage_gate: false,

  # Override the default domain coverage formula weights.
  # All five weights must sum to 1.0.
  coverage_weights: [
    transfer_coverage:    0.25,
    rule_coverage:        0.20,
    blueprint_coverage:   0.20,
    compliance_coverage:  0.25,
    ui_coverage:          0.10
  ],

  # ── Data Retention ────────────────────────────────────────────────────────
  # Source: ADR-012 §Data Retention

  # Override the default retention periods (financial/regulated platform defaults).
  # All values are in days.
  data_retention: [
    proposals:           365,    # completed proposals in .foundry/proposals/
    audit_log:           2555,   # .foundry/audit.jsonl (7 years — financial default)
    activity_feed:       90      # in-Studio activity feed entries
  ],

  # ── Context Exclusions ────────────────────────────────────────────────────
  # Source: studio_ux_degradation runbook (workaround for cyclic DSL modules)

  # Modules excluded from mix foundry.context introspection.
  # Use only as a temporary workaround for cyclic dependency or DSL loop issues.
  # Each exclusion should have a filed issue reference.
  context_exclusions: [
    # MyApp.Finance.ProblemModule   # Issue #42 — cyclic dependency in DSL
  ],

  # ── Conditionally Present Libraries ───────────────────────────────────────
  # Source: ADR-001 §Conditionally Present

  # Declares which optional ecosystem libraries are present in this target platform.
  # Foundry uses this list to enable/disable lint rules and scaffold operations
  # that are only valid when the library is present.
  conditional_libraries: [
    :ash_money,          # enables Ash.Type.Money generation, validates CLDR backend
    :ash_state_machine,  # enables state transition generation and lint rules
    # :ash_pyro,         # enables AshPyro component lint rules
    # :fun_with_flags,   # enables feature flag generation and INV-013 lint rule
  ]
]
```

---

## Field Reference Table

| Field | Type | Required | Default | Source |
|---|---|---|---|---|
| `project_name` | string | yes | — | convention |
| `domain_type` | atom | no | `:other` | bootstrap templates |
| `sensitive_resources` | list of modules | no | `[]` | ADR-005, INV-001 |
| `sensitive_resource_exemptions` | keyword list | no | `[]` | INV-011, INV-012 |
| `approvers` | keyword list | yes | — | ADR-005, ADR-014 |
| `approvers.sensitive_lead` | email string | yes | — | ADR-005 |
| `approvers.sensitive_lead_delegate` | email string | no | none | approval runbook |
| `approvers.domain_lead` | email string | no | none | ADR-005 |
| `approvers.platform_lead` | email string | no | none | ADR-014 |
| `approvers.compliance_officer` | email string | yes | — | ADR-005 |
| `approvers.compliance_officer_delegate` | email string | no | none | approval runbook |
| `approval_sla` | keyword list | no | see defaults | approval runbook |
| `auto_apply_structural` | boolean | no | `false` | ADR-005, ADR-014 |
| `change_generation_enabled` | boolean | no | `true` | ADR-010, ADR-013 |
| `notifications` | keyword list | yes* | — | INV-010 |
| `notifications.runbook_stale` | channel config | yes* | — | INV-010 |
| `notifications.adapter_verify_failed` | channel config | yes* | — | INV-010 |
| `notifications.compliance_test_failed` | channel config | yes* | — | INV-010 |
| `coverage_gate` | boolean | no | `false` | ADR-007 |
| `coverage_weights` | keyword list | no | see ADR-007 defaults | ADR-007 |
| `data_retention` | keyword list | no | see ADR-012 defaults | ADR-012 |
| `context_exclusions` | list of modules | no | `[]` | degradation runbook |
| `conditional_libraries` | list of atoms | no | `[]` | ADR-001 |

*Required in the sense that omission triggers a lint warning (not a build failure). See INV-010.

---

## Validation Rules

The following are enforced by `mix foundry.lint.all` against the manifest:

1. `approvers.sensitive_lead` and `approvers.compliance_officer` must be present — lint error if absent.
2. `notifications` with all three keys must be present — lint warning if absent (INV-010).
3. `sensitive_resource_exemptions` entries must reference modules in `sensitive_resources` — lint error for unknown modules.
4. `coverage_weights` values must sum to 1.0 ± 0.001 — lint error.
5. `context_exclusions` entries should have a comment with an issue reference — lint warning if absent.
6. If `conditional_libraries` includes `:ash_money`, a CLDR backend module must be discoverable — lint error.

---

## What This Document Is Not

This is not a frozen API contract. It is a pre-ADR design target. When `Foundry.Manifest`
is implemented as an Ash resource, ADR-011 will be written from this document, and ADR-011
will become the contract. This document will then be archived.

Do not add fields to this document speculatively. Only add fields that are already
referenced (explicitly or implicitly) in an existing ADR, invariant, or runbook.
If a new field is needed, the originating decision must be documented in the relevant ADR first.
--- ./docs/mix_task_summary_schemas.md ---
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
--- ./docs/reference-project-fixture.md ---
# docs/reference-project-fixture.md — iGaming Reference Project

> **Purpose:** This document declares the structure of the iGaming reference project
> used to validate every phase's acceptance criteria in BUILD_SEQUENCE.md.
> It is the written contract that the actual code in `reference_projects/igaming/`
> must implement. Write the code from this document, not the other way around.
>
> **Status:** Canonical. Changes to this document require review — every phase's
> "done when" criteria depends on what is declared here.
>
> **Closes:** Gap #54 in REVIEW_AND_PLAN.md.

---

## Project Identity

```elixir
# .foundry/manifest.exs (reference project)
project_name: "IgamingRef",
domain_type: :igaming,
```

Root application module: `IgamingRef`
OTP application name: `:igaming_ref`

---

## Domains

The reference project has three domains. This is the minimum to make the system map
non-trivial (multiple clusters), the compliance matrix meaningful, and the coverage
formula exercise all five dimensions.

| Domain module | Purpose |
|---|---|
| `IgamingRef.Finance` | Ledger, wallets, transfers — the financial core |
| `IgamingRef.Players` | Player accounts, KYC, self-exclusion |
| `IgamingRef.Promotions` | Bonus campaigns, blueprints, wagering |

---

## Resources

### `IgamingRef.Finance` domain

#### `IgamingRef.Finance.Wallet`
- **Type:** Ash resource (`ash_postgres`)
- **Sensitive:** yes
- **Description:** Holds a player's current balance across currency denominations
- **Attributes:** `id`, `player_id` (belongs_to Players.Player), `currency` (string), `balance` (`Ash.Type.Money`), `status` (atom: `:active | :frozen | :closed`), `inserted_at`, `updated_at`
- **Actions:** `read`, `create`, `credit`, `debit`, `freeze`, `close`
- **State machine:** yes — states: `:active`, `:frozen`, `:closed`; transitions: `freeze` (active→frozen), `unfreeze` (frozen→active), `close` (active|frozen→closed)
- **Paper trail:** required (INV-011)
- **Archival:** required (INV-012) — soft delete only
- **Compliance links:** `RG-MGA-001` (wallet integrity), `RG-UK-003` (balance accuracy)
- **Rate limited:** yes (debit action)
- **Telemetry prefix:** `[:igaming_ref, :finance, :wallet]`

#### `IgamingRef.Finance.LedgerEntry`
- **Type:** Ash resource (`ash_postgres`)
- **Sensitive:** yes
- **Description:** Immutable record of every financial movement. Append-only by policy.
- **Attributes:** `id`, `wallet_id` (belongs_to Wallet), `amount` (`Ash.Type.Money`), `direction` (atom: `:credit | :debit`), `kind` (atom: `:deposit | :withdrawal | :bonus | :wager | :win | :reversal`), `idempotency_key` (string, unique), `reference_id` (string), `inserted_at`
- **Actions:** `read`, `create` — no update, no destroy (policy enforced)
- **State machine:** no
- **Paper trail:** required (INV-011)
- **Archival:** required (INV-012)
- **Compliance links:** `RG-MGA-001`, `RG-MGA-002` (ledger immutability), `RG-UK-003`
- **Telemetry prefix:** `[:igaming_ref, :finance, :ledger_entry]`

#### `IgamingRef.Finance.WithdrawalRequest`
- **Type:** Ash resource (`ash_postgres`)
- **Sensitive:** yes
- **Description:** A player's request to withdraw funds. Goes through approval and provider routing.
- **Attributes:** `id`, `player_id`, `wallet_id`, `amount` (`Ash.Type.Money`), `status` (atom: `:pending | :approved | :processing | :completed | :rejected | :cancelled`), `provider` (string), `provider_reference` (string, nullable), `inserted_at`, `updated_at`
- **Actions:** `read`, `create`, `approve`, `reject`, `cancel`, `mark_processing`, `mark_completed`
- **State machine:** yes — states mirror status attribute
- **Paper trail:** required (INV-011)
- **Archival:** required (INV-012)
- **Compliance links:** `RG-UK-014` (withdrawal processing), `RG-MGA-007` (withdrawal limits)
- **Telemetry prefix:** `[:igaming_ref, :finance, :withdrawal_request]`

---

### `IgamingRef.Players` domain

#### `IgamingRef.Players.Player`
- **Type:** Ash resource (`ash_postgres`)
- **Sensitive:** yes (PII-bearing)
- **Description:** A registered player account. The root of all player-scoped data.
- **Attributes:** `id`, `email` (string, unique), `username` (string, unique), `date_of_birth` (date), `country_code` (string), `kyc_status` (atom: `:unverified | :pending | :verified | :rejected`), `risk_level` (atom: `:low | :medium | :high`), `status` (atom: `:active | :suspended | :self_excluded | :closed`), `inserted_at`, `updated_at`
- **Actions:** `read`, `create`, `update_kyc_status`, `suspend`, `self_exclude`, `close`
- **State machine:** yes — status states; transitions: `suspend` (active→suspended), `reinstate` (suspended→active), `self_exclude` (active→self_excluded), `close` (active|suspended→closed)
- **Paper trail:** required (INV-011)
- **Archival:** required (INV-012)
- **Compliance links:** `RG-UK-002` (player verification), `RG-MGA-003` (KYC requirements), `RG-UK-008` (self-exclusion)
- **Rate limited:** no
- **Telemetry prefix:** `[:igaming_ref, :players, :player]`

#### `IgamingRef.Players.SelfExclusionRecord`
- **Type:** Ash resource (`ash_postgres`)
- **Sensitive:** yes
- **Description:** Immutable record of a self-exclusion event. Append-only.
- **Attributes:** `id`, `player_id`, `excluded_at`, `exclusion_type` (atom: `:temporary | :permanent`), `duration_days` (integer, nullable), `reinstated_at` (nullable), `inserted_at`
- **Actions:** `read`, `create`, `mark_reinstated` — no destroy
- **Paper trail:** required (INV-011)
- **Archival:** required (INV-012)
- **Compliance links:** `RG-UK-008`, `RG-MGA-009` (self-exclusion integrity)
- **Telemetry prefix:** `[:igaming_ref, :players, :self_exclusion_record]`

---

### `IgamingRef.Promotions` domain

#### `IgamingRef.Promotions.BonusCampaign`
- **Type:** Ash resource (`ash_postgres`)
- **Sensitive:** no
- **Description:** A configured bonus campaign. Declares eligibility rules, amounts, and wagering requirements.
- **Attributes:** `id`, `name` (string), `kind` (atom: `:deposit_match | :free_spins | :cashback`), `status` (atom: `:draft | :active | :paused | :expired`), `eligibility_rule` (string — module name reference), `bonus_amount` (`Ash.Type.Money`), `wagering_multiplier` (decimal), `max_redemptions` (integer, nullable), `starts_at` (datetime), `expires_at` (datetime), `inserted_at`, `updated_at`
- **Actions:** `read`, `create`, `update`, `activate`, `pause`, `expire`
- **State machine:** yes — status states
- **Paper trail:** no (not sensitive)
- **Archival:** no
- **Compliance links:** `RG-MGA-005` (bonus terms transparency), `RG-UK-011` (bonus wagering disclosure)
- **Telemetry prefix:** `[:igaming_ref, :promotions, :bonus_campaign]`

#### `IgamingRef.Promotions.BonusGrant`
- **Type:** Ash resource (`ash_postgres`)
- **Sensitive:** no
- **Description:** A specific bonus awarded to a player from a campaign.
- **Attributes:** `id`, `player_id`, `campaign_id`, `amount` (`Ash.Type.Money`), `wagering_remaining` (decimal), `status` (atom: `:active | :wagered | :forfeited | :expired`), `granted_at`, `expires_at`, `inserted_at`, `updated_at`
- **Actions:** `read`, `create`, `apply_wager`, `forfeit`, `expire`, `complete`
- **State machine:** yes — status states
- **Paper trail:** no
- **Archival:** no
- **Compliance links:** `RG-MGA-005`, `RG-UK-011`
- **Telemetry prefix:** `[:igaming_ref, :promotions, :bonus_grant]`

---

## Authentication Resources (always sensitive — added automatically)

#### `IgamingRef.Accounts.User`
- **Type:** Ash resource (`ash_authentication`)
- **Sensitive:** always (not in manifest list — added automatically by classifier)
- **Description:** Authentication subject. Linked to Player record post-registration.
- **Strategies:** password, magic_link
- **Paper trail:** required (INV-011)
- **Archival:** required (INV-012)

#### `IgamingRef.Accounts.Token`
- **Type:** Ash resource (`ash_authentication`)
- **Sensitive:** always
- **Description:** Authentication tokens (session, magic link, reset).
- **Paper trail:** required (INV-011)
- **Archival:** required (INV-012)

---

## Transfers (Reactors)

### `IgamingRef.Finance.WithdrawalTransfer`
- **Type:** Reactor + Transfer DSL
- **Description:** Processes an approved withdrawal request through to provider submission. Handles balance debit, ledger recording, and provider API call. Fully idempotent.
- **Idempotency key:** `withdrawal_request_id`
- **Steps:** `validate_sufficient_balance`, `debit_wallet`, `create_ledger_entry`, `submit_to_provider`, `update_withdrawal_status`
- **Rules:** `SufficientBalance`, `WithdrawalLimitNotExceeded`, `PlayerNotSelfExcluded`
- **Compliance links:** `RG-UK-014`, `RG-MGA-007`
- **Runbook:** `docs/runbooks/withdrawal_transfer.md` *(to be created)*
- **Telemetry prefix:** `[:igaming_ref, :finance, :withdrawal_transfer]`
- **Sensitive:** yes (touches LedgerEntry, Wallet, WithdrawalRequest — all sensitive)

### `IgamingRef.Promotions.BonusGrantTransfer`
- **Type:** Reactor + Transfer DSL
- **Description:** Awards a bonus to a player when campaign eligibility is confirmed. Credits wallet and creates grant record. Idempotent.
- **Idempotency key:** `{player_id, campaign_id}`
- **Steps:** `check_eligibility`, `check_campaign_active`, `credit_wallet`, `create_ledger_entry`, `create_bonus_grant`
- **Rules:** `PlayerEligibleForCampaign`, `CampaignNotExpired`, `PlayerNotSelfExcluded`
- **Compliance links:** `RG-MGA-005`
- **Runbook:** `docs/runbooks/bonus_grant_transfer.md` *(to be created)*
- **Telemetry prefix:** `[:igaming_ref, :promotions, :bonus_grant_transfer]`
- **Sensitive:** no (touches Wallet/LedgerEntry which are sensitive — but the Transfer itself is classified by its rule set, not its resources. Classifier will escalate to :sensitive because it touches sensitive resources.)

---

## Rules

| Module | Domain | Description | Compliance |
|---|---|---|---|
| `IgamingRef.Finance.Rules.SufficientBalance` | Finance | Wallet balance must cover the requested amount | RG-MGA-001 |
| `IgamingRef.Finance.Rules.WithdrawalLimitNotExceeded` | Finance | Withdrawal amount must not exceed the player's configured daily limit | RG-UK-014, RG-MGA-007 |
| `IgamingRef.Players.Rules.PlayerNotSelfExcluded` | Players | Player must not have an active self-exclusion record | RG-UK-008, RG-MGA-009 |
| `IgamingRef.Promotions.Rules.PlayerEligibleForCampaign` | Promotions | Player meets the campaign's eligibility criteria | RG-MGA-005 |
| `IgamingRef.Promotions.Rules.CampaignNotExpired` | Promotions | Campaign's expires_at has not passed | RG-MGA-005 |

---

## Compliance Requirements

These are the RG-* requirements declared in `docs/regulations/` for the reference project.
Minimum set to make `mix foundry.compliance.check` non-trivial and the compliance matrix
meaningful across three status states (passing, failing, unimplemented).

| ID | Summary | Implementing module(s) | Status |
|---|---|---|---|
| `RG-MGA-001` | Wallet balance integrity — balance never goes negative | `Finance.Wallet`, `Finance.LedgerEntry`, `Finance.Rules.SufficientBalance` | planned |
| `RG-MGA-002` | Ledger immutability — entries cannot be modified or deleted | `Finance.LedgerEntry` (policy: no update/destroy) | planned |
| `RG-MGA-003` | KYC verification required before first withdrawal | `Players.Player` (kyc_status check in WithdrawalTransfer) | planned |
| `RG-MGA-005` | Bonus terms must be transparent and enforced | `Promotions.BonusCampaign`, `Promotions.BonusGrant`, `Promotions.Rules.PlayerEligibleForCampaign` | planned |
| `RG-MGA-007` | Withdrawal processing within declared SLA | `Finance.WithdrawalRequest`, `Finance.WithdrawalTransfer` | planned |
| `RG-MGA-009` | Self-exclusion records must be immutable | `Players.SelfExclusionRecord` | planned |
| `RG-UK-002` | Player identity must be verified before account activation | `Players.Player` (kyc_status gate) | planned |
| `RG-UK-003` | Player-facing balance must match ledger sum at all times | `Finance.Wallet`, `Finance.LedgerEntry` | planned |
| `RG-UK-008` | Self-exclusion must block all financial transactions immediately | `Players.Rules.PlayerNotSelfExcluded` (in all Transfers) | planned |
| `RG-UK-011` | Bonus wagering requirements must be disclosed at grant time | `Promotions.BonusCampaign`, `Promotions.BonusGrant` | planned |
| `RG-UK-014` | Withdrawals must be processed to original payment method | `Finance.WithdrawalTransfer` | planned |

---

## Manifest Configuration (reference project)

```elixir
# reference_projects/igaming/.foundry/manifest.exs
[
  project_name: "IgamingRef",
  domain_type: :igaming,

  sensitive_resources: [
    IgamingRef.Finance.Wallet,
    IgamingRef.Finance.LedgerEntry,
    IgamingRef.Finance.WithdrawalRequest,
    IgamingRef.Players.Player,
    IgamingRef.Players.SelfExclusionRecord
    # IgamingRef.Accounts.User and Token are added automatically
  ],

  approvers: [
    sensitive_lead: "finance-lead@igamingref.test",
    sensitive_lead_delegate: "cto@igamingref.test",
    domain_lead: "platform-lead@igamingref.test",
    platform_lead: "platform-lead@igamingref.test",
    compliance_officer: "compliance@igamingref.test"
  ],

  approval_sla: [
    structural:  nil,
    behavioral:  [hours: 24],
    sensitive:   [hours: 4],
    compliance:  [hours: 48]
  ],

  auto_apply_structural: false,
  change_generation_enabled: true,

  notifications: [
    runbook_stale:          [channel: :slack,  target: "#ops-alerts"],
    adapter_verify_failed:  [channel: :email,  target: "platform-lead@igamingref.test"],
    compliance_test_failed: [channel: :slack,  target: "#compliance-alerts"]
  ],

  coverage_gate: false,
  coverage_weights: [
    transfer_coverage:    0.25,
    rule_coverage:        0.20,
    blueprint_coverage:   0.20,
    compliance_coverage:  0.25,
    ui_coverage:          0.10
  ],

  conditional_libraries: [
    :ash_money,
    :ash_state_machine,
    :fun_with_flags
  ]
]
```

---

## Expected `mix foundry.context.all` Output Shape

Running `mix foundry.context.all --json` against the reference project must return
modules grouped by domain. Summary counts (for Phase 1 acceptance validation):

| Domain | Resources | Transfers | Rules |
|---|---|---|---|
| `Finance` | 3 (Wallet, LedgerEntry, WithdrawalRequest) | 1 (WithdrawalTransfer) | 2 (SufficientBalance, WithdrawalLimitNotExceeded) |
| `Players` | 2 (Player, SelfExclusionRecord) | 0 | 1 (PlayerNotSelfExcluded) |
| `Promotions` | 2 (BonusCampaign, BonusGrant) | 1 (BonusGrantTransfer) | 2 (PlayerEligibleForCampaign, CampaignNotExpired) |
| `Accounts` | 2 (User, Token — auth) | 0 | 0 |

**Total:** 9 resources, 2 transfers, 5 rules, 11 compliance requirements.

---

## Expected Lint Results (Phase 1 validation)

Running `mix foundry.lint.all --json` against a freshly scaffolded reference project
(before tests are written) must produce:

- **Zero** `:missing_description` violations (all attributes and modules have descriptions)
- **Zero** `:missing_paper_trail` violations (all sensitive resources declare AshPaperTrail)
- **Zero** `:missing_archival` violations (all sensitive resources declare AshArchival)
- **Zero** `:missing_idempotency` violations (both Transfers declare idempotency keys)
- **Warnings** for `:missing_notification_config` — not an error (manifest has config, but
  the test channels are non-functional in the test environment by design)
- **At least one** compliance requirement with `status: :planned` (not yet implemented
  E2E test) — to make the compliance matrix show an incomplete state

---

## Runbooks Required

These runbooks are referenced by Transfer modules (INV-005) and must exist as files:

- `docs/runbooks/withdrawal_transfer.md` — for `WithdrawalTransfer`
- `docs/runbooks/bonus_grant_transfer.md` — for `BonusGrantTransfer`

Stub content is sufficient for the reference project. The runbook file just needs to
exist at the declared path — INV-005 lint rule checks file existence, not content quality.

---

## What This Document Is Not

This document does not describe the full iGaming business domain. It describes the
*minimum viable reference project* that makes every phase's acceptance criteria testable.
The reference project is a test fixture, not a production system. It is complete enough
to exercise all six Mix tasks, all lint rules, and the compliance check — nothing more.
--- ./docs/regulations/platform_invariants.md ---
# Platform Invariants

> These are the non-negotiable constraints of Foundry itself — not of any target platform.
> They are enforced by the compiler, the linter, and the approval workflow.
> Violations are build failures, not warnings.

---

## INV-001: No Autonomous Changes to Sensitive Domain Resources

**Requirement:** Any change affecting resources designated `:sensitive` in the project manifest requires dual human approval before application.

**Scope:** Determined per project via `manifest.sensitive_resources`. Examples: LedgerEntry, Wallet (iGaming/fintech); PatientRecord (healthcare); PrivilegedDocument (legal). Foundry does not hardcode what counts as sensitive — the project declares it.

**Enforcement:** Change classifier tags these as `:sensitive`. Approval workflow blocks application until two distinct approvers have confirmed. Audit log records both approvals with timestamps and approver identity.

**Rationale:** Certain domain resources carry legal, regulatory, or financial integrity requirements. No level of AI confidence justifies bypassing human review on these. The decision of which resources are sensitive belongs to the project, not to the platform.

---

## INV-002: No Direct Filesystem Writes from Agent

**Requirement:** All code changes are routed through Igniter operations executed by the Foundry backend via `Foundry.Operations.run/2`. Agents never write to the filesystem directly.

**Scope:** All source files in `lib/`, `test/`, `config/`. For `docs/` (ADRs, runbooks, regulations), agents may propose plain-text content which humans review and commit. The compiler validates code; humans validate prose.

**Enforcement:** `Foundry.Operations.run/2` is the only code-change entry point. `File.write!/2` on source files is a forbidden pattern detected by the linter. The mechanism (local Igniter call vs WebSocket to cloud backend) is an implementation detail — the invariant holds in both modes.

**Note on raw Igniter:** Agents may use raw Igniter API (not catalogue operations) for novel patterns. "Raw" means using Igniter's own functions directly rather than a pre-built `Op.*` module. It does not mean bypassing Igniter. String interpolation to produce Elixir source is always forbidden.

---

## INV-003: Infrastructure Is Proposal-Only

**Requirement:** Kubernetes configs, Postgres configs, CI pipeline modifications — agents produce proposals, humans apply.

**Scope:** All files outside the application codebase: `k8s/`, `deploy/`, `.github/workflows/`, database configuration files.

**Enforcement:** The `Op.InfrastructureProposal` operation renders a diff for human review and routes to the infrastructure approver. There is no `Op.ApplyInfrastructure` operation.

---

## INV-004: Every External Side-Effect Reactor Must Declare Idempotency

**Requirement:** All Reactor modules that perform external side effects (money movement, provider API calls, state transitions with audit implications) must include an idempotency declaration with a key field.

**Scope:** Reactors where replaying a step would cause harm — double charges, duplicate API calls, duplicate audit records. The target platform's core library defines the exact DSL syntax. Purely internal read/compute Reactors are exempt.

**Enforcement:** `mix foundry.lint.all` — `:missing_idempotency` lint rule. The lint rule reads the Reactor's step types to determine if external effects are present. Build fails when required and absent.

---

## INV-005: Every Reactor Must Have a Runbook Link

**Requirement:** All Reactor modules must declare `@runbook` pointing to an existing runbook file.

**Scope:** All modules using `Reactor` with more than 3 steps.

**Enforcement:** `mix foundry.lint.all` — `:missing_runbook` lint rule. Build fails if runbook file doesn't exist at the declared path.

---

## INV-006: Description Coverage Must Be Complete

**Requirement:** All Ash resource attributes must have a `description:` value. All public modules must have `@moduledoc`.

**Scope:** All Ash resources in `lib/`. Test modules are exempt.

**Enforcement:** `mix foundry.lint.all` — `:missing_description` lint rule. Build fails. This is the raw material for the system map detail panel and the copilot's domain knowledge — without it, both degrade.

---

## INV-007: Compliance Requirements Must Have Implementation Pointers

**Requirement:** Every RG-* requirement declared in a regulation file must have at least one `implementation:` pointer to a module or test.

**Scope:** All requirement entries in `docs/regulations/*.md`.

**Enforcement:** `mix foundry.compliance.check` — `:unimplemented_requirement` violation. This is a CI gate for projects that have declared compliance certifications in their manifest.

---

## INV-008: Generated Diagrams Must Be Committed

**Requirement:** The system diagram generated by `mix foundry.diagram.generate` must not have an uncommitted diff at CI time.

**Scope:** `docs/diagrams/system_map.json` and associated rendered outputs.

**Enforcement:** CI runs `mix foundry.diagram.generate` and checks for unstaged changes. An uncommitted diagram means the diagram doesn't reflect the current codebase — a violation of the "always current" guarantee.

---

## INV-009: The Spec-Kit Is the Only Manual Documentation

**Requirement:** The only documentation that requires manual authorship is: ADRs, regulation files, runbooks, and AGENTS.md. All other documentation is generated from code.

**Scope:** `docs/adrs/`, `docs/regulations/`, `docs/runbooks/`, `AGENTS.md`.

**Rationale:** Documentation that can be generated from code must be generated from code. Manually maintaining what the compiler already knows creates synchronization drift. The spec-kit contains only decisions, constraints, and procedures — things the compiler cannot know.

---

## INV-010: Staleness Conditions Must Have Notification Channels

**Requirement:** The project manifest must declare notification targets for operational staleness conditions. Staleness is never silently ignored.

**Scope:** Three required notification types:
- `runbook_stale` — a runbook has not been tested within the configured interval (default 90 days)
- `adapter_verify_failed` — a provider adapter's contract test failed its scheduled verification
- `compliance_test_failed` — a compliance-tagged E2E test failed in the latest CI run

**Manifest declaration:**
```elixir
notifications: [
  runbook_stale:          [channel: :slack, target: "#ops-alerts"],
  adapter_verify_failed:  [channel: :email, target: "platform-lead@company.com"],
  compliance_test_failed: [channel: :slack, target: "#compliance-alerts"]
]
```

**Enforcement:** `mix foundry.lint.all` — `:missing_notification_config` lint rule warns (not fails) if notification channels are not declared. The scheduled staleness jobs will log but not deliver notifications until channels are configured. A project going to production without notification config is a governance risk flagged in the compliance dashboard.

**Rationale:** The operations board is a pull medium — someone must be looking at it. Regulated platforms require that compliance failures and operational risks are actively surfaced to responsible parties, not passively visible to those who check.

---

## INV-011: Sensitive Resources Must Have Change History

**Requirement:** All resources designated `:sensitive` in the project manifest must use
`AshPaperTrail` to record a change history. A sensitive resource without paper trail
configuration is a lint error.

**Scope:** All modules in `manifest.sensitive_resources`, plus authentication User and Token
resources (which are always `:sensitive` regardless of manifest declaration).

**Enforcement:** `mix foundry.lint.all` — `:missing_paper_trail` lint rule. Reads each
sensitive resource's extensions list and fails if `AshPaperTrail.Resource` is absent.

**Rationale:** In regulated domains, knowing *that* a sensitive record changed is insufficient —
the audit chain requires knowing *what* changed, *when*, and under *which* approval. Paper trail
is the machine-readable audit log for individual record mutations. Without it, the audit log
(INV-001) records approvals but not the actual data changes.

**Override:** A sensitive resource may declare `paper_trail: :exempt` in the manifest with a
documented reason. This is a `:compliance` class change (ADR-005) and requires compliance
officer approval. Exemptions must be reviewed annually.

---

## INV-012: Sensitive Resources Must Use Soft Delete

**Requirement:** All resources designated `:sensitive` must use `AshArchival` for soft deletion.
Hard deletion of sensitive records (ledger entries, wallet records, PHI, audit records) is
prohibited unless explicitly exempted.

**Scope:** All modules in `manifest.sensitive_resources`, plus authentication User and Token resources.

**Enforcement:** `mix foundry.lint.all` — `:missing_archival` lint rule. Reads each sensitive
resource's extensions list and fails if `AshArchival.Resource` is absent. Also checks that
no `:destroy` action on a sensitive resource bypasses archival (i.e., uses `soft_delete?: false`).

**Rationale:** Hard deletion of regulated data is frequently illegal (financial records, health
records, audit trails). In iGaming, deleting a LedgerEntry is a regulatory violation. Soft
deletion preserves records while marking them inactive, satisfying both product requirements
(the record is "gone" from user perspective) and regulatory requirements (the data is retained).

**Override:** A sensitive resource may declare `archival: :exempt` in the manifest with a
documented reason and the specific regulation that permits hard deletion. This is a `:compliance`
class change and requires compliance officer approval.

---

## INV-013: Compliance-Gated Feature Flags Must Have ADR Links

**Requirement:** Any `fun_with_flags` feature flag that gates a compliance control, a sensitive
operation, or a regulatory feature must declare an ADR link in its Foundry governance metadata.
A compliance-gated flag without an ADR link is a lint error.

**Scope:** Feature flags declared with `governance: :compliance` or `governance: :sensitive`
in their Foundry governance metadata (declared when the flag is created).

**Enforcement:** `mix foundry.lint.all` — `:missing_flag_adr` lint rule. Reads flags from
the project's `fun_with_flags` configuration and checks for governance metadata.

**Rationale:** A feature flag that can silently disable a compliance control (e.g., "temporarily
disable self-exclusion enforcement during the migration") is a compliance risk at the configuration
layer, not the code layer. The approval and audit chain must extend to flag state changes, not
just code changes. The ADR link ensures the rationale for the flag's existence is documented
and its activation/deactivation is governed.

**Classification:** Adding a compliance-gated feature flag is a `:compliance` class change (ADR-005).
Activating or deactivating a compliance-gated flag in production is also a `:compliance` class
change and must go through the approval workflow.

---

## Implementation Tracker

| INV | Lint rule / check | Status |
|---|---|---|
| INV-001 | Change classifier `:sensitive` + dual approval workflow, reads `manifest.sensitive_resources`; auth resources always `:sensitive` | planned |
| INV-002 | Linter: forbidden `File.write!` on source files; `Foundry.Operations.run/2` as sole entry point | planned |
| INV-003 | No `Op.ApplyInfrastructure` in catalogue | by design |
| INV-004 | `:missing_idempotency` lint rule — infers from Reactor step types | planned |
| INV-005 | `:missing_runbook` lint rule — validates file exists at declared path | planned |
| INV-006 | `:missing_description` lint rule | planned |
| INV-007 | `foundry.compliance.check :unimplemented_requirement` | planned |
| INV-008 | CI diagram diff check | planned |
| INV-009 | Enforced by convention + team discipline | by design |
| INV-010 | `:missing_notification_config` lint warning | planned |
| INV-011 | `:missing_paper_trail` lint rule — sensitive resources must use AshPaperTrail | planned |
| INV-012 | `:missing_archival` lint rule — sensitive resources must use AshArchival | planned |
| INV-013 | `:missing_flag_adr` lint rule — compliance-gated flags must have ADR links | planned |
--- ./docs/runbooks/approval_queue_blocked.md ---
# Runbook: Blocked Approval Queue

**Applies to:** `:sensitive` and `:compliance` change proposals awaiting approval  
**Reactor/Component:** `Foundry.Approvals` workflow  
**Last tested:** —  
**Escalation:** See escalation chain below

---

## Symptoms

- A `:sensitive` or `:compliance` proposal has been waiting for approval beyond the SLA
- The designated approver is unavailable (out of office, incident response, offboarding)
- A hotfix needs to reach production but is blocked on a `:sensitive` approval
- A `:compliance` change is blocked because the compliance officer is unavailable

---

## SLA Definitions (configure in manifest)

```elixir
approval_sla: [
  structural:  nil,          # no SLA — auto-apply or casual review
  behavioral:  hours: 24,    # domain lead reviews within 24h
  sensitive:   hours: 4,     # sensitive lead + one other within 4h
  compliance:  hours: 48     # compliance officer within 48h
]
```

The operations board shows proposals that have exceeded their SLA in amber/red.

---

## Step 1: Confirm the Proposal Is Genuinely Blocked

```bash
mix foundry.approvals.status --pending

# Output shows:
# - proposal_id
# - change_class
# - created_at
# - waiting_for: ["finance-lead@company.com", "platform-lead@company.com"]
# - sla_deadline
# - sla_exceeded: true/false
```

If the approver simply hasn't seen the notification: resend it.
```bash
mix foundry.approvals.notify --proposal-id <id>
```

If the approver is genuinely unavailable, proceed to Step 2.

---

## Step 2: Identify the Delegation Path

Check the manifest for a configured delegate:

```elixir
# .foundry/manifest.exs
approvers: [
  sensitive_lead: "finance-lead@company.com",
  sensitive_lead_delegate: "cto@company.com",   # used when sensitive_lead unavailable
  compliance_officer: "compliance@company.com",
  compliance_officer_delegate: "legal@company.com"
]
```

If a delegate is configured: notify the delegate. Their approval carries the same weight
as the primary approver's. The audit log records which role approved and in what capacity.

If no delegate is configured: proceed to Step 3.

---

## Step 3: No Delegate Configured

**For `:sensitive` proposals (non-emergency):**
Wait for the approver to return. There is no override path for non-emergency sensitive
changes. If this is causing release delays frequently, add a delegate to the manifest
(this is a `:structural` change to the manifest itself).

**For `:sensitive` proposals (genuine emergency / production incident):**
Two conditions must both be true before an emergency override is considered:
1. There is a production incident actively causing customer harm or data loss
2. The fix has been verified by someone with equivalent domain knowledge

If both conditions are met:
1. The on-call engineer and the platform lead must both approve in writing (Slack/email)
2. The override is logged manually in the audit log with: proposal ID, approvers, reason, timestamp
3. The compliance officer (or delegate) must review the override within 24 hours
4. An ADR review is triggered to assess whether the approval policy needs updating

This is the emergency break-glass path. It requires two humans. It is always audited.
It is not a mechanism for bypassing approval because it's inconvenient.

**For `:compliance` proposals:**
There is no emergency override path. Compliance changes that bypass the compliance officer
create regulatory exposure that is worse than the delay. Wait for the compliance officer
or their designated delegate.

---

## Step 4: After Resolution

If the blockage was caused by a manifest misconfiguration (no delegate, wrong contact):
- Update the manifest (`sensitive_lead_delegate`, notification channels)
- This is a `:structural` change — no special approval needed

If the blockage revealed an organisational gap (no one with the right authority available):
- Document it as a finding
- The compliance officer and platform lead review the approval policy at the next
  governance review cycle

---

## Escalation Chain

```
Proposal blocked → notify designated approver
  → SLA exceeded → notify delegate (if configured)
    → delegate unavailable → platform lead + on-call engineer
      → genuine emergency → break-glass (two humans, always audited)
        → compliance officer review within 24h of break-glass use
```

For `:compliance` proposals: escalation stops at compliance officer.
No break-glass path exists for compliance changes.
--- ./docs/runbooks/compliance_test_failure.md ---
# Runbook: Compliance Test Failure

**Applies to:** Compliance-tagged E2E tests (`@tag :compliance`)  
**Reactor/Component:** CI compliance gate + `mix foundry.compliance.check`  
**Last tested:** —  
**Escalation:** Compliance officer → Platform lead

---

## Symptoms

- CI fails at the compliance gate with `:compliance_test_failed`
- Compliance dashboard shows a red requirement (e.g., `RG-UK-002: ❌ FAIL`)
- `mix foundry.compliance.check` reports failing tagged tests
- A release is blocked pending compliance resolution

---

## Step 1: Identify Which Requirement Failed

```bash
mix foundry.compliance.check --json | jq '.failures'

# Output includes:
# - requirement_id: "RG-UK-002"
# - test_module: "MyAppE2E.Compliance.SelfExclusionTest"
# - test_name: "self-excluded player cannot log in during exclusion period"
# - last_passed: "2026-02-15"
# - failure_reason: "element not found: [data-action='self-exclude']"
```

---

## Step 2: Classify the Failure

**Class A — Test infrastructure failure** (the test itself is broken, not the feature)

Signs: `failure_reason` mentions missing `data-*` selector, timeout, or seed data issue.
The feature likely still works; the test can't reach it.

```bash
# Run the test locally with headed browser to see what's happening
mix test test/e2e/compliance/self_exclusion_test.exs --seed 0

# Common causes:
# - UI component was refactored and data-* attribute was renamed/removed (INV in ADR-007)
# - Test seed data generator changed and the test's preconditions no longer hold
# - A LiveView route changed
```

Fix: update the test selector or generator. This is a `:structural` change — no compliance
officer approval needed, but the compliance officer must be notified that the test was
temporarily failing before being fixed.

**Class B — Feature regression** (the compliance requirement is actually not met)

Signs: the test reaches the UI correctly but the assertion fails (wrong error message,
wrong behaviour, wrong state in database).

This is a genuine compliance failure. **Do not bypass the CI gate.**

Proceed to Step 3.

---

## Step 3 (Class B): Assess Scope and Notify

1. Identify which code change introduced the regression:
   ```bash
   git log --oneline -20
   git bisect start HEAD <last-green-commit>
   ```

2. Notify the compliance officer immediately. Do not wait for the root cause analysis.
   The notification must include: requirement ID, description of observed behaviour,
   the commit range under investigation.

3. Assess whether the regression affects live production:
   - If the feature is not yet in production: block the release, fix in development
   - If the feature IS in production and is now broken: this is a live compliance incident —
     escalate to the compliance officer for regulatory notification obligations

---

## Step 4 (Class B): Fix and Re-Certify

The fix is a `:compliance` class change (ADR-005). It requires:
- Compliance officer approval
- An ADR or ADR update explaining what broke and how it was fixed
- The compliance test must pass in CI before the fix is considered complete
- The compliance dashboard must show the requirement green before release proceeds

```bash
# After fix is applied and CI passes:
mix foundry.compliance.check
# All requirements must show ✅ PASS before release gate is cleared
```

---

## Step 5: Post-Incident

After resolution, the compliance officer reviews:
- Was the regression introduced by a `:behavioral` change that should have triggered
  a compliance review but didn't? If so, the classifier rules in ADR-005 may need updating.
- Was the E2E test's coverage adequate? Did it catch the regression at the right layer?
- Update the compliance dashboard's `last_reviewed` date for the affected requirement.

---

## What Is Never Acceptable

- Disabling or skipping a compliance-tagged test to unblock a release
- Merging a change that makes a compliance test pass by weakening the assertion
- Releasing to production while a compliance requirement is red, even temporarily

If there is business pressure to release despite a compliance failure, the decision
must be made by the compliance officer with documented reasoning — not by a developer
commenting out a test.
--- ./docs/runbooks/igniter_operation_failure.md ---
# Runbook: Igniter Operation Failure

**Applies to:** All scaffold operations in `FoundryStudio.Operations.*`  
**Last tested:** —  
**Escalation:** Platform team

---

## Symptoms

- Copilot shows "Scaffold operation failed" in the review panel
- `mix foundry.studio.scaffold` exits with non-zero status
- Proposed diff is empty or malformed
- Applied change results in a compilation error

---

## Step 1: Read the Operation Error

```bash
# Get the structured error from the last operation
mix foundry.studio.scaffold.last-error

# The output will include:
# - operation: which Op.* module failed
# - step: which step in the pipeline failed
# - reason: the Igniter error or AST parse error
# - dry_run_output: the partial diff before failure
```

---

## Step 2: AST Parse Error

If `reason` contains "failed to parse module" or "zipper could not find target":

```bash
# The target module may have a syntax issue that prevents Igniter from reading it
mix compile --force 2>&1 | head -30

# If compilation fails: fix the syntax error first, then retry the scaffold operation
# The scaffold operation is not the cause — it cannot apply to a module that doesn't compile
```

---

## Step 3: Operation Template Outdated

If `reason` contains "unknown DSL option" or "deprecated key":

The scaffold operation's template uses a DSL option that has changed in the current library version.

```bash
# Check which library version changed
mix foundry.studio.versions.check

# Compare the failing operation's template against current ExDoc
mix foundry.studio.docs.fetch ash Resource.Dsl.Attribute

# The operation template needs updating — this requires a platform team fix
# Workaround: make the change manually using the CLI pattern the operation would generate
```

To report: open an issue with `mix foundry.studio.scaffold.last-error --full` output attached.

---

## Step 4: Dry-Run Passes, Apply Fails

If the dry-run diff looks correct but applying it fails:

```bash
# Check for file permission issues
ls -la lib/  

# Check for concurrent modification (another process writing the same file)
# This is rare but can happen if the file watcher triggers a recompile during apply
mix foundry.studio.scaffold.retry --last-operation
```

If retry also fails: apply the dry-run diff manually.

```bash
# Get the clean diff
mix foundry.studio.scaffold.last-error --dry-run-diff > /tmp/proposed.patch

# Review and apply manually
patch -p1 < /tmp/proposed.patch
mix compile
mix foundry.studio.lint.all
```

---

# Runbook: Project Server Unavailable

**Applies to:** `FoundryStudio.Project.Reader` and all dependent components  
**Last tested:** —  
**Escalation:** Platform team

---

## Symptoms

- Studio UI shows "Unable to connect to project" 
- System map fails to load
- Copilot cannot build context (returns `:context_build_failed`)
- `mix foundry.studio.context <Module>` times out

---

## Step 1: Check Studio Process

```bash
# For local mode
ps aux | grep foundry.studio
# If not running: mix foundry.studio (in the project directory)

# Check for port conflict
lsof -i :4001
# If another process owns 4001: configure a different port in config/foundry_studio.exs
```

---

## Step 2: Check Project Compilation

The Project Server reads from compiled modules. If the project doesn't compile, it has no data.

```bash
mix compile
# If compilation fails: fix compilation errors first
# The Studio cannot display a system map for a project that doesn't compile
```

---

## Step 3: Check File Watcher

```bash
# Verify inotify limits (Linux only)
cat /proc/sys/fs/inotify/max_user_watches
# If < 8192: increase it
sudo sysctl fs.inotify.max_user_watches=65536
```

---

## Step 4: Manual Context Retrieval

While the Project Server is unavailable, context is still available via CLI:

```bash
# Get context for a specific module
mix foundry.studio.context Foundry.Finance.BetTransfer

# Get compliance coverage
mix foundry.studio.compliance.check

# Get system diagram data
mix foundry.studio.diagram.generate --json
```

These run Mix tasks directly against the project. They are what the Studio calls internally.
The Studio being unavailable does not remove development capability — it removes the UI layer.
--- ./docs/runbooks/project_reader_unavailable.md ---
# Runbook: Project Server Unavailable

**Applies to:** `Foundry.Project.Reader` and all dependent components  
**Last tested:** —  
**Escalation:** Platform team

---

## Symptoms

- Studio UI shows "Unable to connect to project" 
- System map fails to load
- Copilot cannot build context (returns `:context_build_failed`)
- `mix foundry.context <Module>` times out

---

## Step 1: Check Studio Process

```bash
# For local mode
ps aux | grep foundry.studio
# If not running: mix foundry.studio (in the project directory)

# Check for port conflict
lsof -i :4001
# If another process owns 4001: configure a different port in config/foundry_studio.exs
```

---

## Step 2: Check Project Compilation

The Project Server reads from compiled modules. If the project doesn't compile, it has no data.

```bash
mix compile
# If compilation fails: fix compilation errors first
# The Studio cannot display a system map for a project that doesn't compile
```

---

## Step 3: Check File Watcher

```bash
# Verify inotify limits (Linux only)
cat /proc/sys/fs/inotify/max_user_watches
# If < 8192: increase it
sudo sysctl fs.inotify.max_user_watches=65536
```

---

## Step 4: Manual Context Retrieval

While the Project Server is unavailable, context is still available via CLI:

```bash
# Get context for a specific module
mix foundry.context Foundry.Finance.BetTransfer

# Get compliance coverage
mix foundry.compliance.check

# Get system diagram data
mix foundry.diagram.generate --json
```

These run Mix tasks directly against the project. They are what the Studio calls internally.
The Studio being unavailable does not remove development capability — it removes the UI layer.
--- ./docs/runbooks/studio_copilot_failure.md ---
# Runbook: Copilot Engine Failure

**Applies to:** Foundry Studio copilot engine  
**Reactor/Component:** `Foundry.Copilot.Engine`  
**Last tested:** —  
**Escalation:** Platform team

---

## Symptoms

- Copilot returns "I was unable to build context for this request"
- Copilot proposals are missing impact analysis or compliance information
- Copilot generates code that fails `mix foundry.lint.all`
- Copilot produces Ash 2.x syntax in an Ash 3.x project

---

## Step 1: Identify the Failure Class

```bash
# Check the Studio logs for the last copilot request
mix foundry.logs --tail=50 --filter=copilot

# Look for one of these error codes:
# :context_build_failed    → Project Reader is unavailable (see: runbooks/project_reader_unavailable.md)
# :igniter_operation_failed → Scaffold operation errored (see: runbooks/igniter_operation_failure.md)
# :llm_api_error           → Anthropic API error (proceed to Step 2)
# :version_mismatch        → Stack version detection failed (proceed to Step 3)
# :adr_contradiction       → Proposal contradicts an ADR (proceed to Step 4)
```

---

## Step 2: LLM API Error

```bash
# Verify API key is configured
mix foundry.config --check=llm_api_key

# Check Anthropic status page (agent cannot do this — human must check)
# https://status.anthropic.com

# If API is down: the copilot is unavailable. 
# Visualization panels remain functional.
# Developers can still use CLI tools directly:
mix foundry.context <Module>
mix foundry.lint.all
mix foundry.compliance.check
```

The copilot is a convenience layer over these tasks. It is not the only way to use the platform.

---

## Step 3: Stack Version Mismatch

The copilot failed to include correct stack versions in the LLM context.

```bash
# Regenerate version manifest
mix foundry.versions.refresh

# Verify output includes all critical libraries
mix foundry.versions.check
# Expected: ash, ash_double_entry, ash_state_machine, phoenix, oban
# If any are missing: add them to config/foundry_studio.exs under :version_tracking
```

---

## Step 4: ADR Contradiction Detected

The proposal was blocked because it contradicts an ADR. This is **correct behaviour**, not a failure.

1. Read the ADR cited in the block message
2. Determine if the ADR is outdated or if the user's intent needs to be revised
3. If ADR is outdated: update it (human authors the ADR update, copilot cannot)
4. If user intent conflicts with a correct ADR: explain the constraint to the user

ADR contradictions should **never** be overridden by disabling the ADR check.
If a constraint is wrong, update the ADR through the proper process.

---

## Step 5: Proposals Generating Invalid Code

If approved proposals consistently fail lint after application:

```bash
# Run the validation step manually on the last proposal
mix foundry.scaffold.validate --last-proposal

# This runs the same lint + semantic checks as the pre-approval flow
# If this passes but post-application fails, the apply step has a bug
# File an issue with the diff output attached
```

Common causes:
- The Igniter operation is outdated and generates deprecated DSL syntax (update the operation module)
- The project has a custom lint rule that isn't covered by the standard validation pipeline (add it to `config/foundry_studio.exs` under `:custom_lint_rules`)

---

## Escalation

If none of the above resolves the issue:
1. Export the failing request context: `mix foundry.copilot.export --last-request`
2. Post to the `#foundry-studio-platform` channel with the exported context attached
3. Do not share the full LLM prompt in public channels — it may contain project-sensitive domain information
--- ./docs/runbooks/studio_ux_degradation.md ---
# Runbook: Studio UX Degradation

**Applies to:** Foundry Studio UI — rendering, panel loading, WebSocket connectivity  
**Component:** Phoenix LiveView application (`mix foundry.studio`)  
**Last tested:** —  
**Escalation:** Platform team (`#foundry-studio-platform`)

---

## Symptoms

- System map takes >3 seconds to render (performance budget: ADR-012)
- Any panel shows loading state indefinitely (>10 seconds)
- "Unable to connect" or WebSocket disconnect banner visible in the Studio header
- Copilot shows spinner but emits no first token within 5 seconds
- Review panel diff area is blank on a proposal that has a diff
- Node detail drawer opens but shows no content
- Notification badge count is stale or not updating

---

## Step 1: Identify the Failure Layer

Three distinct layers can cause UX degradation. Identify which before taking action.

**Layer 1 — WebSocket / LiveView process**
Signs: Disconnect banner visible. Copilot messages do not send or receive. Panel updates
have frozen mid-session. The "reconnecting…" spinner appears.

**Layer 2 — Mix task subprocess (data retrieval)**
Signs: Studio loaded initially but specific panels time out when navigating to them.
Node detail panel spins on click. Copilot shows "Building context…" without progressing.

**Layer 3 — LLM API (copilot only)**
Signs: All five visualization panels load and update correctly. Only the copilot spinner
is stuck. The system map, compliance matrix, operations board, and test coverage map
are unaffected.

Proceed to the step matching your layer. If unclear, start with Step 2.

---

## Step 2: WebSocket / LiveView Disconnection

```bash
# Verify the Studio process is running
ps aux | grep "foundry.studio"

# If not running (local mode):
# Navigate to the project directory and restart
mix foundry.studio

# Check if the port is accessible
curl -I http://localhost:4001
# Expected: HTTP 200 with upgrade headers available
```

**Intermittent disconnects (<30 seconds, then reconnects automatically):** This is expected
behaviour during a deploy rolling restart in cloud mode, or when the machine suspends.
LiveView reconnects automatically. The disconnect banner clears on reconnect. No action required.

**Persistent disconnect (>2 minutes without reconnect):**

```bash
# Check Studio logs for the disconnect reason
mix foundry.logs --tail=100 --filter=websocket

# Common causes and fixes:

# 1. Idle timeout (LiveView process killed after inactivity)
#    Fix: increase timeout in config/foundry_studio.exs
#    config :phoenix, :live_view, timeout: 86_400_000  # 24h in ms

# 2. Network proxy stripping WebSocket upgrade headers
#    Signs: connects briefly, immediately disconnects
#    Fix: configure proxy to pass Upgrade and Connection headers

# 3. Node restart in cloud mode
#    Signs: disconnect happened at deployment time
#    Fix: libcluster should reform the mesh automatically (check below)
mix foundry.cluster.status
# If node count < expected: check libcluster configuration and cloud platform logs
```

If the process is running but the browser cannot connect: hard-refresh (`Cmd+Shift+R`).
LiveView session state can desync after a deploy. Hard-refresh forces a new session.

---

## Step 3: Slow or Hung Panels (Mix Task Layer)

All panels that show content (all panels except the Copilot) source their data from Mix
task subprocesses. Profile the slow task:

```bash
# Test the primary data source for each panel directly
time mix foundry.diagram.generate --json > /dev/null   # System Map
time mix foundry.compliance.check --json > /dev/null   # Compliance Matrix
time mix foundry.context.all --json > /dev/null        # Operations Board, Test Coverage Map
```

**If any task takes >5 seconds:**

```bash
# The most common cause: project is not compiled or has a large compile delta
mix compile
# After compile: re-run the slow task to check if it recovers

# Second most common cause: the project has raw Ecto modules
# Foundry falls back to a slower module scan for modules it can't introspect via Spark
# Check for direct Ecto.Schema usage:
grep -r "use Ecto.Schema" lib/ | wc -l
# If >0: these modules cause slower introspection — see ADR-001 on raw Ecto limitations
```

**If `mix foundry.context <Module>` specifically times out for one module:**
That module may have a cyclic dependency or a DSL declaration that causes Spark to loop.

```bash
mix foundry.context MyApp.Finance.ProblemModule --timeout=10s 2>&1
# If it exits with timeout: file an issue with the module path
# Workaround: exclude the module temporarily via manifest under `context_exclusions:`
```

**If diagram.generate is fast but the System Map still renders slowly:**
The bottleneck is the D3 rendering pipeline in the browser. Check the browser console
for JavaScript errors. Common causes:

- Browser tab was backgrounded (CPU throttled). Bring tab to foreground and wait for render to complete.
- >200 nodes being rendered — the D3 force simulation takes time. After initial render, interaction should be fast.
- Browser memory pressure — try closing other tabs and reloading.

---

## Step 4: Copilot Spinner Without Response (LLM Layer)

```bash
# Send a minimal diagnostic request to verify API connectivity
mix foundry.copilot.ping
# This sends a <100 token request with no project context
# Expected: response within 3 seconds
# On success: "API reachable. Model: claude-sonnet-[version]. Latency: Xms"
```

**If ping fails:**

```bash
# Check Studio logs for the error code
mix foundry.logs --tail=50 --filter=llm_api

# Error: :authentication_error
# The API key is invalid or expired
mix foundry.config --check=llm_api_key
# Rotate the key in config/foundry_studio.exs and restart Studio

# Error: :rate_limited
# The team is generating many proposals simultaneously
# The engine queues and retries with exponential backoff
# The copilot panel shows: "Waiting for API availability…"
# If persistent (>5 minutes): check Anthropic dashboard for quota usage

# Error: :timeout
# The Anthropic API is slow or unreachable
# Check: https://status.anthropic.com (must be checked by a human — Studio cannot self-diagnose)
# If API is confirmed down: copilot is offline until recovery
# All four visualization panels and all CLI Mix tasks remain functional
```

**If ping succeeds but normal requests hang:**
The context assembly subprocess (`mix foundry.context`) is the bottleneck — see Step 3.
The copilot waits for context before calling the API. A slow Mix task causes apparent
LLM lag even when the API is healthy.

```bash
# Confirm:
time mix foundry.context MyApp.Finance.Wallet
# If >2 seconds: Step 3 is the root cause, not the LLM
```

---

## Step 5: Review Panel Diff Not Rendering

```bash
# Check the proposal's current state
mix foundry.proposals.status --pending

# Expected output includes: proposal_id, state, diff_present: true/false
```

**If `diff_present: false`:** The Igniter dry-run produced no changes — this is a no-op
proposal. The review panel correctly shows "No changes would be made." This is not a bug.
If changes were expected, the operation parameters may be incorrect — dismiss and regenerate.

**If `diff_present: true` but the panel shows blank:**
The LiveView component lost its socket state. Hard-refresh (`Cmd+Shift+R`).
If hard-refresh doesn't restore the diff: dismiss and regenerate. The proposal diff is
stored in the database — regeneration is not data loss, it is re-computation.

**If the diff renders but is visually broken (overlapping lines, missing syntax highlighting):**
Browser compatibility issue. Supported browsers: latest Chrome, Firefox, Safari (desktop only).
Mobile browsers are not supported (ADR-012 §Responsive and Mobile).

---

## Step 6: Notification Badge Stale or Not Updating

Notification counts are pushed via Phoenix PubSub over the LiveView WebSocket. A stale count
indicates the WebSocket connection has gone stale without triggering the disconnect banner.

```bash
# Force reconnect: close and reopen the browser tab
# or:
# Hard-refresh: Cmd+Shift+R
```

If the badge remains stale after reconnect:

```bash
# Check PubSub is functioning in cloud mode
mix foundry.cluster.pubsub.check
# Verifies all nodes can publish and receive on the foundry:notifications topic

# In local mode: PubSub is in-process and should always work
# A stale badge in local mode after hard-refresh is a bug — file an issue
```

---

## What Is Never Acceptable

- Clearing the Nebulex cache manually without restarting Studio (cache state may be inconsistent mid-session)
- Modifying proposal records directly in the database to change state — use `mix foundry.proposals.*` commands only
- Disabling the blob hash check to force-apply a stale proposal
- Restarting the database to resolve a UX issue (this purges in-flight proposals — confirm no pending approvals before any database restart)

---

## Escalation

If none of the above resolves the issue:

```bash
# Export a full diagnostic bundle
mix foundry.diagnostics --full > /tmp/foundry-diag-$(date +%Y%m%d-%H%M%S).txt
```

The diagnostic bundle includes: Studio process state, recent log tail, Mix task timings,
cluster node status, cache hit/miss rates, and the last 5 error codes from the telemetry
pipeline. It does **not** include LLM prompt content or proposal diffs (to avoid
capturing sensitive domain information).

Post the bundle in `#foundry-studio-platform`. Do not share in public channels.

---

## Related Runbooks

| Symptom | Runbook |
|---|---|
| Copilot context build fails | `docs/runbooks/project_reader_unavailable.md` |
| Scaffold operation fails in review panel | `docs/runbooks/igniter_operation_failure.md` |
| Copilot returns `:llm_api_error` persistently | `docs/runbooks/studio_copilot_failure.md` |
| Approval queue blocked / SLA exceeded | `docs/runbooks/approval_queue_blocked.md` |
| Compliance test failing in CI | `docs/runbooks/compliance_test_failure.md` |
--- ./docs/spec_kit_index_schema.md ---
# docs/spec_kit_index_schema.md — Spec-Kit Index Schema

> **Status:** Active — governs `mix foundry.spec_kit.index` output format.
> `Foundry.Copilot.ContextBuilder` includes this file in the Tier 1 system prompt.
> The agent reads it directly from context — no tool call needed to locate documents.
> Do not change the schema without updating ContextBuilder and the index generation task.

---

## File Location

```
.foundry/spec_kit_index.json   ← generated, committed to the project repository
```

Generated by `mix foundry.spec_kit.index`. Run in CI. Output committed alongside source.
Stale index (index mtime older than any indexed source file) fails CI via
`mix foundry.spec_kit.index --check` — same enforcement pattern as INV-008.

---

## Top-Level Structure

```json
{
  "generated_at": "2026-03-16T10:00:00Z",
  "project": "MyApp",
  "document_count": 28,
  "documents": [ ...entries... ]
}
```

---

## Per-Document Entry Schema

```json
{
  "id": "ADR-010",
  "type": "adr",
  "title": "LLM Selection — Claude Sonnet, Agentic Context Model",
  "status": "Accepted",
  "file_path": "docs/adrs/ADR-010-llm-model-and-context.md",
  "summary": "Defines the three-tier context model and bash-only tool interface. The agent uses a shell for all file access, search, and Mix task execution. Two structured tools handle DSL pattern finding and operation schemas.",
  "tags": ["llm", "context", "copilot", "adapter", "shell", "tools"],
  "supersedes": null,
  "superseded_by": null,
  "last_modified": "2026-03-16"
}
```

### Field definitions

| Field | Type | Extraction source | Required |
|---|---|---|---|
| `id` | string | Filename prefix (`ADR-010`) or `AGENTS`, `runbook:<slug>`, `regulation:<slug>`, `usage_rules:<lib>` | Yes |
| `type` | enum | Derived from directory path | Yes |
| `title` | string | First H1 heading | Yes |
| `status` | string | `**Status:**` frontmatter field. `null` for non-ADR documents | ADRs only |
| `file_path` | string | Relative path from project root | Yes |
| `summary` | string | First substantive paragraph, max 2 sentences / 300 characters | Yes |
| `tags` | string[] | Extracted keywords — see Tag Extraction | Yes |
| `supersedes` | string\|null | `**Supersedes:**` frontmatter value | No |
| `superseded_by` | string\|null | `**Superseded by:**` frontmatter value | No |
| `last_modified` | string | File mtime, ISO 8601 date | Yes |

### Document types

| Directory / path | Type | ID format | Example |
|---|---|---|---|
| `docs/adrs/` | `adr` | `ADR-NNN` from filename | `ADR-010` |
| `docs/runbooks/` | `runbook` | `runbook:<slug>` | `runbook:studio_copilot_failure` |
| `docs/regulations/` | `regulation` | `regulation:<slug>` | `regulation:platform_invariants` |
| `AGENTS.md` | `agents` | `AGENTS` | `AGENTS` |
| `.foundry/usage_rules/` | `usage_rules` | `usage_rules:<lib>` | `usage_rules:ash` |

---

## Tag Extraction

Lowercase keywords from title + summary + H2 headings. Rules:

1. Split into words, lowercase, strip punctuation
2. Remove stop words (the, a, an, is, are, for, with, by, in, on, at, to, of, and, or,
   not, this, that, it, its, be, as, from, will, must, when, if, all, any, each, per, no)
3. Remove words shorter than 3 characters
4. Deduplicate, sort alphabetically
5. Maximum 12 tags per document

**Manual overrides:** A document may declare `**Tags:** llm, context, adapter` in
frontmatter. Merged with extracted tags, capped at 12. Use sparingly.

---

## Summary Extraction Rules

First substantive paragraph after the frontmatter block (lines matching `**Key:** Value`).
Skip: blockquotes, code fences, horizontal rules, headings, empty lines.
Truncate at 2 sentences or 300 characters, whichever comes first. Do not truncate mid-word.
If no substantive paragraph found in first 30 lines: `summary` is `null`, generation warns.

---

## Token Budget

Full index must stay within **400 tokens** when included in Tier 1 system prompt.
`mix foundry.spec_kit.index` warns at 380 tokens (10% headroom).
Growth rate: ~15 tokens per document. Budget accommodates ~26 documents.
When project reaches 25 documents, review against ADR-010 §Tier 1.

---

## Commands

```bash
# Generate and commit
mix foundry.spec_kit.index
git add .foundry/spec_kit_index.json
git commit -m "foundry: regenerate spec-kit index"

# CI staleness check
mix foundry.spec_kit.index --check
# exits 0 if current, 1 if any indexed file is newer than the index
```

---

## What Is NOT in the Index

- Full document content — agent reads with `bash("cat <path>")`
- Elixir source files — introspected via `mix foundry.context`, searched via `bash("grep ...")`
- Proposal files — scanned separately from `.foundry/proposals/`
- Audit log — append-only, never indexed
