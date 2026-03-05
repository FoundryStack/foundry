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
- Node detail panel — moduledoc, attributes, actions, linked ADRs, test status
- Compliance Matrix panel — from `compliance.check --json`
- inotify file watcher → live reload on source change
- `mix foundry.diagram.generate` running in CI with diff check (INV-008)

**No copilot. No code generation. Read-only.**

**Done when:** The iGaming reference project's system map opens, shows all domains,
all resources clickable with correct detail panels, and updates within 2 seconds of a file save.

---

## Phase 3: Copilot — Questions Only (no code changes)

**Goal:** A domain-aware assistant that answers questions about the project accurately.

**Why third:** Builds trust in the copilot's knowledge before it can make changes.
The team learns what it knows, where it's uncertain, what its limits are.
Mis-answers to questions are recoverable. Mis-generated code changes are not.

**Deliverables:**
- Copilot panel in the Studio UI (conversation interface)
- `Foundry.Copilot.ContextBuilder` — assembles context from Phase 1 tasks + spec-kit full inclusion
- `Foundry.Context.SpecKitReader` — reads all spec-kit docs from disk, mtime-cached (ADR-003)
- Intent classifier (ADR-010) — routes questions vs change requests
- Change requests in this phase: "I can propose this change but code generation is not yet enabled. Here's what I would do: [description]."
- ADR contradiction check (ADR-010)
- LLM API key configuration

**No Igniter. No diffs. No apply.**

**Done when:** The copilot correctly answers 10 representative questions about the iGaming
reference project, citing specific modules and ADRs, with no Ash 2.x syntax in responses.

---

## Phase 4: Copilot — Proposals (diff shown, human applies)

**Goal:** The copilot generates real proposals. Humans still apply the diff manually.

**Why fourth:** Decouples "can it generate correctly" from "can it apply safely". If
generation quality is poor, the cost is a rejected diff, not a broken codebase.

**Deliverables:**
- `Foundry.Operations` catalogue — all 20 operations (ADR-002)
- `Foundry.Operations.run/2` with `dry_run: true` support
- Migration proposal generation — `Op.AddResource`, `Op.AddAttribute`, `Op.AddRelationship` include migration diffs
- Diff renderer in the review panel (code diff + migration diff side by side)
- Pre-approval validation: lint result + semantic checks + impact analysis
- Change classifier (ADR-005) — tags every proposal with its class, including migration classification
- Approval routing to correct approver per manifest (ADR-005)
- Proposal storage with blob hash (ADR-009 — stale detection), including migration file hashes
- Audit log for `:sensitive` and `:compliance` proposals

**The diff is shown. The human copies it and applies it manually (or pastes into their terminal).**
No auto-apply. This is intentional — it forces validation of diff quality before auto-apply is trusted.

**Done when:** The copilot generates correct, lint-passing diffs for all 20 operation types
against the iGaming reference project, including migrations for structural changes.
Approval routing works. Audit log records correctly.

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

## Phase Dependencies

```
Phase 1 (JSON tasks)
  └── Phase 2 (System Map) ─────────────────────────┐
        └── Phase 3 (Copilot: questions)             │
              └── Phase 4 (Copilot: proposals) ──────┤
                    └── Phase 5 (Auto-apply)          │
                          └── Phase 6 (Ops + Tests) ──┤
                                └── Phase 7 (Builder) ─┘
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
- **Agent-to-agent orchestration** — multiple Foundry agents coordinating on a large change. Requires the proposal / approval model to handle compound proposals. Future work.
- **Ash 2.x compatibility** — not supported. ADR-001.