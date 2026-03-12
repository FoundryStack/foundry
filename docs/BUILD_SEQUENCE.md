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
- `mix foundry.lint.all --json` — lint results with structured violations (includes INV-011, INV-012, INV-013 rules)
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
- Copilot panel in the Studio UI (conversation interface)
- `Foundry.Copilot.ContextBuilder` — assembles context per ADR-010 §Context Window Budget Allocation
- `Foundry.Context.SpecKitReader` — reads all spec-kit docs from disk, mtime-cached (ADR-003, ADR-010 §Nebulex Cache Strategy)
- `Foundry.Copilot.IntentClassifier` — Task 1 structured classification prompt (ADR-010 §Task 1, ADR-013 §Intent Classification)
- `Foundry.Copilot.ConfidenceClassifier` — four confidence states: HIGH, MEDIUM, LOW, BLOCKED (ADR-013 §Confidence States)
- Clarifying question UX — binary-choice button presentation, not free-text (ADR-013 §Clarifying Question UX)
- `CHANGE_PREVIEW` handler — describes what would be proposed without generating a diff (ADR-010 §Phase-Gated Behaviour, ADR-013 §Phase-Gated Copilot Behaviour); controlled by `change_generation_enabled: false` in config
- ADR contradiction check (ADR-010 §ADR Contradiction Check)
- All five error recovery responses — `:context_build_failed`, `:llm_api_error`, `:version_mismatch`, `:adr_contradiction`, `:context_budget_exceeded` (ADR-013 §Error Recovery Responses)
- LLM API key configuration

**Agent behaviour specification:** ADR-013. Response format contract, confidence handling,
and error recovery in that document govern Phase 3 copilot implementation.

**No Igniter. No diffs. No apply.**

**Done when:** The copilot correctly answers 10 representative questions about the iGaming
reference project, citing specific modules and ADRs, with no Ash 2.x syntax in responses;
AND all five error codes are exercised in the test environment with correct responses;
AND clarifying question UX renders as binary-choice buttons (not free-text prompts);
AND `CHANGE_PREVIEW` responses correctly describe operation scope without generating code.

---

## Phase 4: Copilot — Proposals (diff shown, human applies)

**Goal:** The copilot generates real proposals. Humans still apply the diff manually.

**Why fourth:** Decouples "can it generate correctly" from "can it apply safely". If
generation quality is poor, the cost is a rejected diff, not a broken codebase.

**Deliverables:**
- `Foundry.Operations` catalogue — all 20 operations (ADR-002)
- `Foundry.Operations.run/2` with `dry_run: true` support
- Migration proposal generation — `Op.AddResource`, `Op.AddAttribute`, `Op.AddRelationship` include migration diffs
- Diff renderer in the review panel — code diff + migration diff + lint tab + impact tab (ADR-012 §Review Panel Rendering)
- `Foundry.Copilot.ImpactAnalyzer` — deterministic impact analysis (ADR-012 §Impact Tab)
- Pre-approval validation: lint result + semantic checks + impact analysis
- Change classifier (ADR-005) — tags every proposal with its class, including migration classification
- Approval routing to correct approver per manifest (ADR-005)
- Proposal state machine — DRAFT → PENDING_REVIEW → APPROVED → APPLIED → COMMITTED, plus REJECTED / STALE / SUPERSEDED (ADR-014 §Proposal State Machine)
- Dual approval mechanics — two-slot tracking, revocation, audit records (ADR-014 §Dual Approval Mechanics)
- ADR link field for `:compliance` proposals — validation and warning states (ADR-014 §ADR Linking)
- Proposal storage with blob hash (ADR-009 — stale detection), including migration file hashes
- Stale proposal banner in review panel (ADR-012 §Stale Proposal Banner)
- Proposal visibility — PENDING_REVIEW and later visible to all project users; DRAFT private to requester (ADR-014 §Proposal Visibility)
- Approval tracking UI and notification inbox (ADR-012 §Approval Tracking UI, §Notification Inbox)
- Audit log for `:sensitive` and `:compliance` proposals
- `change_generation_enabled: true` set in Phase 4 deployment config

**Proposal lifecycle specification:** ADR-014. State machine, apply step, and failure paths
in that document govern Phase 4 implementation.

**The diff is shown. The human presses "Apply" in the review panel.**
No auto-apply in Phase 4. This is intentional — it validates diff quality before auto-apply is trusted.

**Done when:** The copilot generates correct, lint-passing diffs for all 20 operation types
against the iGaming reference project, including migrations for structural changes. Proposal
state machine transitions are correct. Dual approval blocks application until both slots are
filled. ADR link field blocks `:compliance` submission when empty. Audit log records all
`:sensitive` and `:compliance` approvals with timestamp, approver, and diff hash.

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