# BUILD_SEQUENCE.md — Foundry

> This document describes the implementation order for building Foundry itself.
> It is not a spec-kit artifact (it captures sequencing, not decisions or invariants).
> It lives alongside the spec-kit and should be updated as phases complete.
>
> Key principle: each phase must be independently useful before the next begins.
> No phase depends on work that hasn't shipped yet.

---

## Phase 1: Structured Data Layer (foundation for everything)

**Goal:** Every Mix task outputs stable, structured data. Nothing is built on top of this yet — this is the foundation.

**Why first:** All visualization, all copilot context, all CI gates read from these tasks.
If the JSON schema is unstable, everything built on top breaks. Stabilize it before building on it.

**Deliverables:**

Mix tasks (external surface — schemas frozen at phase end):
- `mix foundry.project.context` — full system map: all nodes, edges, spec-kit index
  metadata (ADR-020). Schema: `docs/project_context_schema.md`. Output lives in ETS
  (Nebulex L1), not a committed JSON file. The `spec_kit` field is the authoritative
  spec-kit index for both the studio and the copilot Tier 1 system prompt.
  Code→spec linkage is preserved bidirectionally in a single output.
- `mix foundry.project.context <Module>` — per-module detail: full NodeEntry for a
  single module. Same command, optional argument narrows scope. Same walker, same ETS
  cache — a lookup into the already-computed node map. Used by the copilot agentic loop
  (lazy, per-turn) and the studio node detail panel. Replaces the former
  `mix foundry.context <Module>` command.
- `mix foundry.project.context --check` — CI staleness check. Computes
  `sha256(lib/**/*.ex + test/**/*.ex)` and compares against `.foundry/context.lock`.
  Exits 1 if they differ or if the lock file is absent. The lock file is 50 bytes,
  committed to the repository. Same pattern as `mix.lock`.
- `mix foundry.project.status` — complete runtime health picture: open proposals, all
  lint violations, all compliance gaps, pending migrations, CI state, test coverage,
  stack versions, manifest summary (ADR-020; replaces `mix foundry.project.snapshot`).
  Schema: `docs/mix_task_summary_schemas.md`. No token cap at the data layer —
  `Foundry.Copilot.ContextBuilder` applies its own truncation view for Tier 2.
  Included in Phase 1 because all its source data is Phase 1 data — deferring it
  leaves the studio (Phase 2) without a structured health signal.
- `mix foundry.lint.all` — all lint violations with structured output. Exits non-zero
  on `:error` severity violations. Absorbs version constraint enforcement as lint rules
  (`Foundry.LintRules.VersionRule` — reads `mix.lock`, emits `:ash_version_outdated`
  etc.). Called internally by `project.status` for its lint field; called directly by
  CI for the gate. Rule engine: `spark_lint` (internal as `Foundry.SparkLint.*` in
  Phase 1; extracted to Hex post-Phase 1 per ADR-019). Rule modules:
  `Foundry.LintRules.*` (always internal).

Internal modules (no external surface, built in Phase 1):
- `Foundry.FileSystem` — validated read boundary for all file reads (ADR-020). All
  channels and controllers that read project files must call `Foundry.FileSystem.read/2`.
  Built in Phase 1 so Phase 2 channels inherit it with no rework. ~40 lines: resolve
  permitted roots from manifest, reject paths outside them using `Path.expand/1` before
  prefix comparison (naive string matching fails on traversal variants such as
  `lib/../../.env`), return `{:ok, content}` or `{:error, :outside_boundary | :not_found}`.
- `Foundry.SparkMeta.*` — Spark DSL walker powering all context tasks. Designed as the
  future `spark_meta` package from day one; extraction to Hex is post-Phase 1 work.
- `Foundry.SparkLint.*` — rule runner engine (behaviour + violation struct + runner).
  Designed as the future `spark_lint` package from day one; extraction to Hex is
  post-Phase 1 work.
- `Foundry.LintRules.VersionRule` — reads `mix.lock` resolved versions, emits
  `:ash_version_outdated` and `:elixir_version_unsupported` lint rules. Replaces the
  former standalone `mix foundry.versions.check` task.
- `Foundry.SpecKit.IndexBuilder` — spec-kit document walker that populates the
  `spec_kit` field of `mix foundry.project.context`. Parses each document once with
  MDEx to a `%MDEx.Document{}` AST, cached in ETS by `{:spec_kit, file_path, mtime}`.
  Two consumers share the same cached AST: the index builder (summary, tags, mtime —
  lightweight, pre-warmed at startup) and the document server (full `SpecKitDocument`
  struct with sections and refs — produced on demand). One parse, two views. No
  standalone task; no separate output file.
- `Foundry.Context.SessionState` — captures the system map state at the start of an
  editing session (first user interaction after Studio mount or after a proposal is
  committed). Stored in ETS keyed by session ID. `mix foundry.project.context` returns
  a `graph_delta` field when a session state exists, showing added/changed/removed
  nodes and edges relative to session start. Used by the studio to render the system
  map preview mode during active proposals (Phase 4).

Retained alias (backward compat only — not a primary deliverable):
- `mix foundry.context <Module>` may alias to `mix foundry.project.context <Module>`
  for existing scripts; not listed in canonical documentation.
- `mix foundry.diagram.generate` may alias to `mix foundry.project.context` for any
  existing scripts; not listed in canonical documentation.

**Eliminated tasks (not built):**
- `mix foundry.context.all` — absorbed into `mix foundry.project.context`. No caller
  needs the node corpus without edges and spec_kit. Node counts from the former
  `context.all` acceptance matrix are now asserted against `project.context nodes`.
- `mix foundry.versions.check` — split: version data moves to `project.status` stack
  field (from `mix.lock`); version enforcement moves to `Foundry.LintRules.VersionRule`.
- `mix foundry.compliance.check` — absorbed into `project.status` compliance field.
  The full compliance matrix (all RG-* requirements with coverage detail) is a field
  in status, not a separate task.

**Schema design review before freeze:** Before the Phase 1 schema is frozen, conduct a
review against the full ADR-001 ecosystem. The NodeEntry schema must include all fields
defined in ADR-003 (`data_layer`, `pending_migrations`, `paper_trail`, `archival`,
`state_machine`, `api_routes`, `telemetry_prefix`, `money_attributes`,
`authentication_subject`, `oban_queues`, `rate_limited`, `feature_flags`, `rules`).
Adding these fields after the freeze requires an ADR.

**Output ordering:** Nodes in `mix foundry.project.context` output are ordered
alphabetically by fully-qualified module name. Edges are ordered by `from` FQN, then
`to` FQN. Ordering is deterministic, diff-stable, and requires no graph traversal.

**JSON schemas are frozen** at the end of Phase 1. Breaking schema changes require an ADR.
The NodeEntry schema in `docs/project_context_schema.md` is the contract;
`docs/mix_task_summary_schemas.md` is the contract for `project.status`.

**Done when:** All tasks below pass against the iGaming reference project.
See `docs/reference-project-fixture.md` §Phase 1 Acceptance Matrix for the complete
per-task assertion set including expected counts, field presence, lint profile,
boundary rejection tests, and CI check exit codes.

---

## Phase 2: System Map Viewer (read-only, zero risk)

**Goal:** A live, accurate system diagram that any developer can open and navigate.

**Why second:** This is the highest-value, zero-risk deliverable. It requires only Phase 1.
Every team member immediately benefits. Builds trust in the platform before it can make changes.

**Deliverables:**
- Phoenix LiveView application (`mix foundry.studio`)
- System Map panel — D3 interactive graph from `mix foundry.project.context`
- Node detail panel — moduledoc, attributes, actions, linked ADRs, test status
  (ADR-012 §System Map Interaction Details). Data from `mix foundry.project.context <Module>`.
- Spec-kit document overlay — full `SpecKitDocument` served via `FoundryChannel fetch_document`;
  renders sections, compliance refs, module cross-links. Raw file content for Elixir
  source served via `FoundryChannel fetch_file`.
- System map table view alternative — required for WCAG 2.1 AA compliance (ADR-012 §Accessibility)
- Empty and loading states for all panels (ADR-012 §Empty and Loading States)
- Compliance Matrix panel — from `project.status` compliance field
- Bootstrap / onboarding overlay for projects with no spec-kit (ADR-012 §Onboarding)
- Command palette (`Cmd+K`) — navigation and operation preview, with phase-gate (ADR-012 §Command Palette)
- Notification inbox UI (ADR-012 §Notification Inbox)
- inotify file watcher → invalidates ETS cache → live reload on source change
- `mix foundry.project.context --check` running in CI (INV-008 enforcement via
  `.foundry/context.lock` comparison)
- **UI surface nodes** (ADR-027): LiveView (▣) nodes derived from Phoenix router walk,
  SDUI subtype detection, Sourceror action-call scanning, `calls_action` and
  `feature_flagged_by` edges, `external:feature_flag:*` synthetic nodes
- **igaming web layer** (ADR-027): `reference_projects/igaming/lib/web/` — Home, Game,
  Login, Deposit, Withdrawal pages using AshSDUI; Phoenix.LiveViewTest scenario tests
  in `test/pages/`; `Foundry.PreviewServer` on-demand dev server for sidebar preview

**UX specification:** ADR-012. All interaction details, performance budgets, and
accessibility requirements in that document govern Phase 2 implementation.

**No copilot. No code generation. Read-only.**

**Done when:** The iGaming reference project's system map opens, shows all domains, all
resources clickable with correct detail panels, updates within 2 seconds of a file save,
passes WCAG 2.1 AA audit (ADR-012 §Accessibility), meets all ADR-012 §Performance Budgets,
AND LiveView page nodes appear with correct route labels, `calls_action` edges to Ash
resources, feature flag external nodes, and a functioning sidebar Preview button.

---

## Phase 3: Copilot — Questions Only (no code changes)

**Goal:** A domain-aware assistant that answers questions about the project accurately.

**Why third:** Builds trust in the copilot's knowledge before it can make changes.
The team learns what it knows, where it's uncertain, what its limits are.
Mis-answers to questions are recoverable. Mis-generated code changes are not.

**Deliverables:**

**Usage rules:**
- `mix foundry.usage_rules.fetch` — copies `USAGE.md` / `AGENTS.md` from each
  dependency into `.foundry/usage_rules/<lib>.md` at `mix deps.get` time.
  Foundry maintains usage rules for core stack: Ash 3.x, Reactor, Phoenix LiveView,
  Ecto, Oban. Generates `.foundry/usage_rules/foundry_conventions.md` — Foundry-specific
  conventions every generated module must follow (see ADR-002 §Foundry Conventions File).

**Context assembly:**
- `mix foundry.project.status` — single JSON object (60s TTL) built from the underlying
  Phase 1 tasks. No token cap at the data layer. Renamed from `mix foundry.project.snapshot`
  per ADR-020. Schema: `docs/mix_task_summary_schemas.md`.
  Built in Phase 1; wired into `ContextBuilder` here.
- `Foundry.Copilot.ContextBuilder` — assembles three-tier context:
  - Tier 1 (system prompt, per session): AGENTS.md + stack versions + spec-kit index.
    Stack versions read from `project.status` stack field (sourced from `mix.lock`).
    Spec-kit index read from the `spec_kit` field of the ETS-cached project context.
    Nebulex key: `{:project_context, project_root, max_mtime}`. Pre-warmed at startup.
    ContextBuilder applies its own ~400-token view over the full status for Tier 2.
  - Tier 2 (per request): truncated view of `mix foundry.project.status`, 60s TTL
  - Tier 3 (shell): assembled dynamically by the agent during the loop

**Agent loop and tool interface:**
- `Foundry.Copilot.Engine` — agentic loop: assembles Tier 1 + 2 context, runs
  tool loop, dispatches bash calls, accumulates context, produces streaming response.
  Circuit breaker: `max_tool_calls` (default 20, manifest: `copilot.max_tool_calls`).
  See ADR-010 §Shell Constraints for the permitted command list.
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
  with non-empty `checked_adrs` and `checked_invs`, `session_status`,
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
- `docs/phase3-acceptance-questions.md` (Gap #70) passes: all answers cite specific
  modules and ADRs with no Ash 2.x syntax
- All five ADR-013 §Error Recovery error codes exercised with correct structured responses
- Clarifying question UX conforms to ADR-013 §Clarifying Question UX (buttons primary,
  input always visible, free-text re-classification works)
- `CHANGE_PREVIEW` conforms to ADR-013 §Phase-Gated Copilot Behaviour
- Reasoning trace conforms to ADR-015 §Proposal File Format (`checked_adrs` and
  `checked_invs` non-empty, `shell_calls` reflects actual reads)
- `mix foundry.project.context --check` passes in CI
- Shell constraint enforcement matches ADR-010 §Shell Constraints blocked-command list
- `LMStudioAdapter` startup validation behaves per ADR-010 §LLM Adapter degraded-mode spec
- `mix foundry.usage_rules.fetch` populates `.foundry/usage_rules/` including `foundry_conventions.md`

**Gap #70 (new):** `docs/phase3-acceptance-questions.md` — 10+ representative
questions about the iGaming reference project with expected citation format and
minimum acceptable response criteria. Author alongside `docs/reference-project-fixture.md`
(Gap #54). Both are prerequisites for Phase 3 done criteria.

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
- System map preview mode — `graph_delta` from `SessionState` used to highlight affected
  nodes, show phantom new nodes, dim removed nodes while proposal is in
  DRAFT/PENDING_REVIEW state. `SessionState` is captured on first interaction; the delta
  is recomputed against it on every proposal update. See `Foundry.Context.SessionState`.
- Impact analysis via bash traversal of the system map graph — agent runs targeted
  `mix foundry.project.context <Module>` queries; no separate ImpactAnalyzer module
- Pre-approval validation: lint result + impact summary
- Change classifier (ADR-005) — tags every proposal with its class, including migration
  classification
- Approval routing to correct approver per manifest (ADR-005)
- Proposal state machine — DRAFT → PENDING_REVIEW → APPROVED → APPLIED → COMMITTED,
  plus REJECTED / STALE / SUPERSEDED / APPLY_FAILED (ADR-014 §Proposal State Machine)
- `APPLY_FAILED` state: on compile failure after branch write, branch is discarded
  cleanly; agent retries up to 3 times, each iteration requires re-approval of new diff
- Dual approval mechanics — two-slot tracking, revocation, audit records
  (ADR-014 §Dual Approval Mechanics)
- ADR link field for `:compliance` proposals — validation and warning states
  (ADR-014 §ADR Linking)
- Base-commit stale detection (ADR-009) — `git diff <base_commit>..HEAD -- <files>`
  at apply time
- Stale proposal banner in review panel (ADR-012 §Stale Proposal Banner)
- Proposal visibility — PENDING_REVIEW and later visible to all project users; DRAFT
  private to requester (ADR-014 §Proposal Visibility)
- Approval tracking UI and notification inbox (ADR-012 §Approval Tracking UI, §Notification Inbox)
- Audit log for `:sensitive` and `:compliance` proposals
- `change_generation_enabled: true` set in Phase 4 deployment config
- `auto_apply_classes` manifest key (default: `[]`) — when a proposal's change class is
  in this list and all approval slots are filled, the `APPROVED → APPLIED` transition fires
  automatically without a manual "Apply" button press. `:behavioral`, `:sensitive`, and
  `:compliance` are hard-blocked from this list regardless of config.

**Proposal lifecycle specification:** ADR-014. State machine, apply step, and failure
paths in that document govern Phase 4 implementation.

**The diff is shown. The human presses "Apply" in the review panel** (unless the change
class is in `auto_apply_classes`, in which case approval IS the apply trigger).

**Done when:** The copilot generates correct, lint-passing diffs for representative
operation types against the iGaming reference project (at minimum: new resource with
migration, new Reactor rule, new compliance link, new attribute on sensitive resource),
using raw Igniter guided by project examples. Proposal state machine transitions are
correct including `APPLY_FAILED` → retry path. Dual approval blocks application until
both slots are filled. ADR link field blocks `:compliance` submission when empty. Audit
log records all `:sensitive` and `:compliance` approvals with timestamp, approver, and
base commit SHA. Stale detection correctly identifies proposals whose base commit has
been superseded by changes to affected files. 20 consecutive `:structural` auto-applies
(with `auto_apply_classes: [:structural]` in manifest) produce lint-passing, CI-green
results with no regressions.

---

## Phase 5: Operations Board + Test Coverage Map

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

## Phase 6: Domain Builder (Layer 3)

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

## Phase 7: Agent Injection Support

**Goal:** First-class governance and observability for AshAI agent steps in target platform
Reactors. Makes the human-in-the-loop gate a managed system feature, not ad-hoc code.

**Why here:** Agent steps are `:behavioral` changes — they require Phases 4 and 5 (copilot
proposals and auto-apply) to already work. The Agent Health panel requires the Operations
Board (Phase 5) as its home. Phase 7 is not a prerequisite; Phase 6 can begin in parallel
with Phase 7 if resource permits.

**Opt-in only:** Phase 7 features activate only for target projects that declare
`extensions: [AshAi]` in a domain module. Projects without AshAI are unaffected and receive
no lint errors related to agent governance.

**Deliverables:**
- Foundry Spark DSL extension for `Ash.Reactor` step — adds `agent_type`, `model`,
  `confidence_threshold`, `on_low_confidence`, `human_gate`, `tools`, `telemetry_prefix`
  declarations to step syntax
- `Foundry.Lint.AgentStepChecker` — enforces INV-014 through INV-017
- `agent_steps` field in `mix foundry.project.context <Module>` output — non-breaking
  addition; `[]` for non-AshAI projects
- `HumanGateTask` Ash resource — scaffolded into the target platform on first use by
  `Op.AddAgentStep`; always `:sensitive`; requires paper trail and soft delete
- `Foundry.Operations.HumanGateReactor` — manages gate lifecycle
- Agent step rendering in System Map — inline `⊕` step nodes in Transfer/Reactor
  swimlanes; type-specific detail drawer templates (ADR-016, ADR-017)
- Agent Health panel in Operations Board — per-agent-step: p95 latency, error rate,
  cost/call, confidence distribution, override rate
- Override rate lint warning — fires when override rate exceeds the project-configured
  threshold (manifest key: `agent_governance.override_rate_warn_threshold`, default 0.20)
- `Op.AddAgentStep` catalogue operation — adds an agent step to an existing Reactor;
  classified `:behavioral`
- AshAI version check in `Foundry.LintRules.VersionRule` — warns if AshAI < 2.x when
  agent steps are present

**Governance specification:** ADR-017 governs all Phase 7 implementation decisions.

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
              └── Phase 4 (Copilot: proposals + auto-apply config)
                    └── Phase 5 (Ops + Tests) ──┐
                          └── Phase 6 (Builder)  │
                          Phase 7 (Agents) ───────┘
                            (parallel with 6, requires 5)
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
- **Multi-Foundry-copilot coordination** — multiple Foundry copilot agents coordinating on a large change proposal. Requires compound proposal model. Deferred.
- **Agent step auto-tuning** — automatic adjustment of confidence thresholds or model selection based on observed override rates. Phase 7 surfaces the signal; acting on it automatically is a future capability.
- **Ash 2.x compatibility** — not supported. ADR-001.