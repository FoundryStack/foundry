# ADR-023 — Product Positioning and Target Domain Taxonomy

**Status:** Accepted
**Date:** 2026-03-23
**Supersedes:** —
**Tags:** positioning, domains, product, target-market

---

## Context

Foundry's technical architecture is well-defined across ADR-001 through ADR-017. What
was missing until now is an explicit record of *what Foundry is for* — the domain
categories it targets, the problems it solves, and the boundaries of where it applies
well versus where it does not. These decisions have consequences for the codebase:
which demo domains ship with the platform, what the onboarding flow assumes, how the
system map is presented to different audiences, and what the copilot is tuned to know.

Without a recorded positioning decision, these choices get made implicitly — in landing
copy, in demo selection, in sales conversations — and the codebase gradually reflects
assumptions that were never made explicit or reviewed.

---

## Decision

### What Foundry is

Foundry is a meta-platform for building complex domain systems — where declarative
specifications are the executable code, every layer is always visualizable, and an AI
agent understands the entire architecture before changing a single line.

The core claim is an isomorphic relationship between the business domain model and the
running system. This is not a documentation feature. It is a structural property: the
Ash DSL declaration, the running application, the system map visualization, and the
agent's working context are all derived from the same single source of truth.

This distinguishes Foundry from two adjacent categories:

- **AI coding tools** (Cursor, GitHub Copilot, Claude Code): These operate on
  imperative codebases file-by-file without structured domain context. They are
  additive tools. Foundry is a complete environment.

- **Configured enterprise software** (ServiceNow, Jira Service Management, SAP
  workflow modules): These impose a vendor domain model that organizations configure
  to approximate their actual domain. Foundry lets teams declare their domain
  correctly — and own it outright.

### The target problem class

Foundry applies well when all three of the following are true:

1. The domain is complex — multiple entities, non-trivial relationships, business rules
   that must be enforced, state machines with compliance or audit implications.

2. The system must be long-lived — it will be maintained, extended, and understood by
   different people over years, not sprints.

3. The team cannot afford opacity — either because the domain has regulatory
   requirements, or because the cost of "only one person understands this" is
   unacceptable, or because AI-assisted development is a stated goal and that requires
   a structured, introspectable codebase.

### Target domain taxonomy

Domains are grouped into three categories. Each category has a distinct primary
argument for Foundry — infrastructure cost, process correctness, or organizational
transparency.

**Category 1: IT Operations**
Primary argument: vendor model lock-in and licensing cost.

| Domain | Core entities | Primary Foundry advantage |
|---|---|---|
| ITSM | Incident, ChangeRequest, Problem, ServiceCatalogItem | Correct domain model, no vendor lock-in, copilot-evolvable workflows |
| ITAM | Asset, License, ProcurementRequest, LifecycleEvent | Full asset lifecycle as a domain, not a configuration screen |
| ESM | ServiceRequest (per department), OnboardingWorkflow | Per-department domain models sharing one platform and one copilot |
| ITOM / AIOps | AlertEvent, IncidentCorrelation, RemediationWorkflow | BEAM handles real-time event streams natively; Reactor for auto-remediation |

**Category 2: Software Delivery**
Primary argument: context fragmentation across disconnected tools degrades AI assistance.

| Domain | Core entities | Primary Foundry advantage |
|---|---|---|
| SDLC platform | Requirement, DesignDecision, Deployment, TestResult | One coherent model from requirement to running feature |
| DevOps orchestration | Pipeline, ApprovalGate, EnvironmentPromotion | Reactor workflows replace imperative CI scripts |
| Test governance | TestPlan, CoverageRequirement, ComplianceScenario | Test skeletons derived from domain model, not hand-written |
| Release management | Release, FeatureFlag, RollbackPolicy | ADR-linked feature flags, classifier-enforced change classification |

**Category 3: Business Operations**
Primary argument: either infrastructure cost (real-time) or organizational opacity (process).

| Domain | Core entities | Primary Foundry advantage |
|---|---|---|
| Fintech / payments | Ledger, Transaction, Wallet, ComplianceReport | Compiler-enforced invariants on sensitive resources, full audit trail |
| iGaming | PlayerWallet, GameRound, OddsEvent, RegulatoryReport | BEAM concurrency; per-jurisdiction compliance as domain invariants |
| Healthcare | Patient, CareEvent, ClinicalDecision, Schedule | Human-in-the-loop gates on clinical workflows; complete audit trail |
| Logistics | Order, Fulfillment, InventoryEvent, ExceptionWorkflow | Complex state machines as Reactor workflows, not background job spaghetti |
| Legal / Insurance | Case, PolicyAdministration, DocumentWorkflow | Long-running processes with approval chains, modeled correctly |
| HR operations | Employee, OnboardingWorkflow, PerformanceCycle | Cross-department coordination as a single declared process |
| Enterprise internal | (domain-specific) | Most underserved category; Foundry is the first viable alternative to hand-rolled tools |

### What Foundry is not for

- **Simple CRUD applications** with no meaningful domain complexity. The DSL overhead
  is not justified. A Phoenix app with Ecto is the right answer.

- **Greenfield exploration** where the domain is unknown and must be discovered
  through rapid iteration. Foundry rewards teams who can declare their domain because
  they understand it. Bootstrap mode (AGENTS.md §The bootstrap case) helps, but
  Foundry accelerates clarity — it does not substitute for it.

- **Teams that want autonomous AI.** The agent proposes; humans approve. If the goal
  is zero human oversight of code changes, Foundry is the wrong tool by design.

- **Organizations that need a configured off-the-shelf product.** Foundry requires a
  development team or a Foundry-certified partner to model the domain. The payoff is
  complete ownership and exact fit. The investment is real.

---

## Consequences

### For the demo domain library (Phase 5+)

The platform ships with reference implementations for the following domains, in
priority order based on breadth of illustration:

1. **Fintech payment ledger** — illustrates invariant enforcement, sensitive resources,
   audit trail, dual approval. Small domain, extreme constraints.

2. **ITSM platform** — illustrates state machines, service catalog, SLA management.
   Shows ESM extensibility across departments.

3. **iGaming back office** — illustrates BEAM concurrency, real-time updates,
   per-jurisdiction compliance as domain invariants.

4. **Healthcare patient flow** — illustrates human-in-the-loop Reactor gates,
   clinical decision tracking, compliance-driven E2E tests.

5. **Enterprise onboarding orchestration** — illustrates cross-domain Reactor
   workflows, multi-department coordination, ESM applied to HR.

6. **SDLC platform** — illustrates Foundry building Foundry (dogfooding case),
   requirement-to-deployment traceability.

Each reference implementation is a valid Foundry target platform — complete with
AGENTS.md, ADRs, regulations, and a spec-kit index. They are also the source material
for sponsored domain builds (ADR-019).

### For the system map (ADR-016)

The domain taxonomy above informs the node type vocabulary in ADR-016. Domain
categories should be visually distinct in the system map — not just by label, but
by structural signature. An ITSM domain looks different from a fintech domain at
the graph level (state-machine-heavy vs invariant-heavy vs workflow-heavy).

### For the copilot (ADR-013)

The copilot's system prompt includes a domain category tag derived from the
project manifest. This tag adjusts the copilot's reasoning posture — an iGaming
domain activates jurisdiction-awareness; a healthcare domain activates clinical
decision gate checking; a fintech domain activates sensitive-resource dual-approval
reminders. Domain category is declared in `manifest.exs` as `domain_category:
:itsm | :fintech | :igaming | :healthcare | :logistics | :sdlc | :enterprise_internal
| :other`.

### For the codebase boundary

This ADR does not change any existing technical decision. It records the product
context that existing technical decisions serve. When a technical decision appears
to conflict with a target domain's requirements, this ADR is the reference for
evaluating whether the conflict is real or whether the domain modeling is wrong.

---

## Alternatives considered

**Positioning Foundry as a SaaS-specific platform.** Rejected. SaaS is a deployment
and pricing model, not a domain complexity class. The target problem is orthogonal
to whether the customer charges per seat.

**Positioning Foundry against AI coding tools directly.** Rejected as primary
framing. Foundry is a complete environment, not a better autocomplete. Competitive
comparison with Cursor or Copilot is a secondary argument, relevant only after the
primary value proposition is established.

**Not recording this as an ADR.** Rejected. Positioning decisions made informally
get encoded in the codebase anyway — in what demo domains ship, in what the onboarding
flow assumes, in what the copilot is tuned to know. Recording them explicitly makes
them reviewable, changeable, and linkable from the technical decisions they influence.