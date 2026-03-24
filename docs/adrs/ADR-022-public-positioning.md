# ADR-022 — Public Positioning: Landing Page as Product Specification

**Status:** Accepted
**Date:** 2026-03-23
**Supersedes:** —
**Tags:** positioning, landing, marketing, product, claims

---

## Context

The Foundry landing page is not a marketing artifact maintained separately from
the product. It is a set of public claims that the product must make true. Claims
that the product cannot yet support are either deferred (marked clearly as roadmap)
or removed. Claims that the product does support must be demonstrable on demand.

This ADR records the public claims made on the Foundry landing page, their current
truthfulness status, and the technical decisions they imply. It is a living document:
when the product changes, this ADR is updated. When a claim becomes true, it moves
from deferred to active. When a claim is found to be false, it is removed from the
landing immediately.

This is not standard practice. It is the right practice for a product whose central
argument is transparency and auditability. Foundry cannot credibly claim that the
model and the running system are always honest with each other if its own public
claims are disconnected from its actual capabilities.

---

## Decision

### Active claims — true today, demonstrable on demand

**"Your domain model and your running system. Finally the same thing."**
True. The Ash DSL declaration is the running code. The system map is generated from
live introspection, not from a separate diagram tool. `mix foundry.diagram.generate`
produces the graph from code; CI enforces via diff-check (INV-008).

**"The system map is a live, interactive graph generated from running code — always
current, always accurate."**
True. Phase 2 complete. The system map updates within 2 seconds of a file save
(ADR-012 §Performance Budgets). It is not a static diagram. It cannot be manually
edited to show something the code does not contain.

**"An AI agent that reads your domain model, your architectural decisions, and your
live project snapshot before proposing any change."**
True for Q&A (Phase 3). The three-tier context model (ADR-010) is implemented.
The agent reads AGENTS.md, stack versions, and spec-kit index in Tier 1; the project
snapshot in Tier 2; domain introspection via bash in Tier 3. It does not propose
code changes yet — that is Phase 4.

**"Every change is classified. Sensitive changes require dual approval. Nothing is
autonomously applied."**
True for the proposal lifecycle (ADR-014). The change classification model
(ADR-005) is implemented. Auto-apply is only permitted for :structural changes when
explicitly configured. This is enforced, not advisory.

**"It is a standard Elixir application. Eject anytime."**
Partially true. The generated application code is standard Elixir. The `mix
foundry.eject` task (ADR-019) does not yet exist. This claim must be qualified as
a roadmap commitment on the landing until the task is implemented and tested.
Qualification: "Eject support ships before the cloud tier launches."

### Deferred claims — roadmap, labeled as such on the landing

**"From domain model to production UI — one coherent system."**
Phase 5. LiveView scaffolding, form and UI generation from domain model. Not yet
implemented. Labeled on landing as "in development."

**"Multi-agent business processes — deterministic Reactor workflows, composable,
auditable."**
Phase 8 (ADR-017). Agent injection governance is specified but not yet implemented
in the scaffolding layer. The Reactor workflow primitives exist. The full agent
injection and governance tooling does not. Labeled on landing as "in development."

**"Cloud hosted — Foundry hosts the environment, you own the code."**
ADR-019 Mode 3. Not yet launched. Labeled on landing as "coming soon — join
the waitlist."

**"Template library — six reference domain implementations."**
Phase 5+. Reference domains are in development as part of sponsored builds
(ADR-019 Mode 2). Not yet public. Labeled on landing as "in development."

### Claims that will never be made

**Any claim of autonomous deployment or autonomous production changes.**
INV-004 and INV-001 are hard invariants. The landing will never describe Foundry
as autonomous, self-operating, or capable of applying production changes without
human approval. These invariants exist in the codebase; they exist in the public
positioning.

**Specific uptime or SLA guarantees for the cloud tier.**
Until the cloud tier is operational and has measured uptime data, no SLA numbers
are stated publicly.

**Customer names or case studies without written consent.**
Design partners are not named on the landing without explicit written consent.
"Pre-launch — no published case studies yet" is the honest statement until the
first partner consents to being named.

**Benchmark numbers that are not independently verifiable.**
The infrastructure cost claims on the landing (Pinterest 200→4 servers, Bleacher
Report 150→5, $16k→$150/month Elixir rewrite) are all documented, named, and
verifiable from public sources. Any future benchmark added to the landing must meet
the same standard: named team, documented result, public source or customer consent.

---

## The demonstrable claim standard

Every active claim on the landing must pass this test:

> If a skeptical senior engineer books a demo specifically to verify this claim,
> can we demonstrate it live, on a real domain, in under 10 minutes?

If the answer is no, the claim is either deferred or removed. This standard is
evaluated quarterly, or whenever the landing is significantly updated.

Current claims and their demo paths:

| Claim | Demo path |
|---|---|
| System map generated from live code | Open any reference domain in `mix foundry.studio`, edit a resource, watch the map update |
| Agent reads domain model before answering | Ask the copilot a question about a resource that only exists in the DSL, not in any doc |
| Change classification with dual approval | Submit a change to a `:sensitive` resource, show that it enters the dual-approval queue |
| Declarative DSL is immediately readable | Show a new engineer the `Ledger` or `Incident` resource — ask them to describe what it does |

---

## Consequences

### Landing page update process

The landing page is version-controlled alongside the codebase. Changes to public
claims require:

1. An update to this ADR's active/deferred claim tables
2. Review by at least one technical team member and one person who has seen the
   demo recently
3. Verification that the claim passes the demonstrable claim standard above

Marketing copy changes that do not alter technical claims (tone, ordering,
visual design) do not require ADR review.

### Quarterly claim audit

Every quarter, the active claims table in this ADR is reviewed against the current
product state. Claims that have become demonstrable are moved from deferred to active
and the landing is updated. Claims that have slipped are moved back to deferred and
the landing is updated.

The audit is recorded as a git commit to this ADR with a dated note.

---

## Alternatives considered

**Maintaining the landing page separately from the spec-kit.** Rejected. Foundry's
central claim is that specifications and running systems stay in sync. Maintaining
a landing page that makes claims disconnected from the product spec-kit would
contradict the product's own argument. The irony would be noticed by exactly the
audience Foundry is trying to reach.

**Not recording public claims as an ADR.** Rejected for the same reason. Implicit
decisions about what the product claims to do get encoded in the landing, in sales
conversations, in demo scripts — and gradually diverge from what the product actually
does. This ADR makes that divergence visible and correctable.