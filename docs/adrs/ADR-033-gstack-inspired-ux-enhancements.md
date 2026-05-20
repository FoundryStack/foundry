# ADR-033: gstack-Inspired UX Enhancements

**Status:** Accepted  
**Date:** 2026-05  
**Deciders:** Platform team

---

## Context

ADR-013 (Copilot Agent Behaviour) specifies that clarifying questions exist but leaves the
format and interview strategy open. The Foundry copilot handles governance + change classification well,
but lacks:

1. **Structured question format** — Prose clarifications are ambiguous and hard to parse
2. **Domain-specific forcing questions** — Interviews don't surface foundational assumptions (who acts?
   what pre-conditions? what guarantees?)
3. **Scope selection before generation** — Users request vague features like "add bonus system"
   without knowing if they want minimal, production-ready, or full regulatory implementation
4. **Pre-generation review pipeline** — Multiple independent concerns (business fit, governance
   constraints, architecture shape) are evaluated in a single pass, losing opportunity to
   auto-resolve obvious decisions
5. **State coverage for LiveView** — Components are generated without empty/error/loading states,
   requiring post-generation fixes

Research into gstack (Garry Tan's AI software factory) identified concrete patterns that apply:
- **D<N> question format** — Mandatory structure: title, context, stakes, recommendation, pros/cons
- **Forcing questions** — Six core questions (actor, pre-condition, post-condition, failure) +
  domain-specific additions (iGaming, fintech, healthcare)
- **Scope tiers** — MINIMAL / STANDARD / FULL before generation, not after
- **Auto-resolve pipeline** — Multiple reviewers (business, governance, architecture) in sequence,
  auto-deciding 80% of decisions, surfacing only genuine ambiguities

---

## Decision

### 1. Structured Clarifying Question Format (INV-005 amendment)

All clarifying questions (INV-005) and requirements interviews (INV-022) use the D<N> format:

```
D<N> — <one-line title>
Context: <one sentence grounding>
At stake: <consequence of wrong choice>
Recommendation: <letter> — <reason>

A) <Option> — Pro: <benefit> Con: <tradeoff>
B) <Option> — Pro: <benefit> Con: <tradeoff>

[Or describe what you have in mind:]
```

**No prose-based clarifications.** D-numbering starts at D1 per session. Maximum 2 questions
per turn across all paths. This closes ADR-013's open format, replacing it with the mandatory
D<N> structure.

**Behavioral rule:** Activity Feed renders options as clickable buttons. Free-text input always
available. Clicking a button sends structured option label, bypassing re-classification.

### 2. Domain-Specific Forcing Questions (INV-022 amendment)

Every `:behavioral` or `:compliance` change request opens with mandatory first-round forcing
questions:

- **Actor & trigger** — Who initiates this? (Player/Operator/System/External/Admin)
- **Pre-condition state** — What must be true before? (Which resource? What status gates it?)
- **Post-condition guarantee** — What must be true after? (Ledger? Audit? State change?)
- **Failure path** — What if it fails? (Compensate? Retry? Alert? Block?)

Domain-specific additions inject based on manifest.domain_type:
- **iGaming:** Player balance/wagering? RG limits? Reversibility?
- **Fintech:** Ledger/transfer? AML screening? Regulatory report?
- **Healthcare:** PHI access? Consent? HIPAA controls?
- **Legal/Insurance:** Policy/claim affected? Jurisdiction rules? Admissible audit?

These force explicit answers before domain-specific questions. Unresolved branches become
`[ASSUMPTION]` markers with risk notes.

### 3. Scope Selection Before Generation (New)

For `:behavioral` and `:compliance` changes, present scope tiers before plan construction:

```
MINIMAL — Smallest working version. What must exist, nothing extra.
STANDARD (recommended) — Production-ready for domain. Governance hooks + standard coverage.
FULL — Domain-compliant. All invariants, all edge cases, all regulatory paths.
```

User picks scope. Plan is constructed from confirmed scope tier. This prevents wasted generation
passes on wrongly-scoped implementations.

**Implementation:** UI component `scope_selector_card` in chat workspace. Renders when
`active_proposal` has `scope_pending: true`. Options are clickable; selection updates
`session_digest` and triggers plan construction with confirmed scope.

### 4. Multi-Review Autoplan Pipeline (New)

Three phases run sequentially before plan presentation for `:behavioral`/`:compliance`:

**Phase A — Business Fit**
- Is there already an existing resource/action that covers this? (check `mix foundry.pattern.find`)
- What is the narrowest version that proves it works?
- Auto-resolve if: pattern exists AND spec-kit covers it
- Surface as D<N> if: no pattern found OR spec-kit is silent

**Phase B — Governance**
- Change class confirmed?
- Approval chain identified?
- ADR required? (behavioral/compliance → yes; structural+new → offer)
- All INV constraints enumerated?
- Auto-resolve if: class is `:structural` AND no sensitive resources touched
- Surface as D<N> if: class ambiguous OR sensitive boundary unclear

**Phase C — Architecture**
- Resources touched (from system map)?
- New edges in graph (for visualization)?
- Migration needed?
- Reactor or action? (>1 side effect → must be Reactor per INV-019)
- Interface assessment (PlanArchitect public surface + hidden complexity)?
- Auto-resolve if: single resource, no migration, single side effect
- Surface as D<N> if: reactor boundary unclear OR migration timing ambiguous

Output: ordered plan with per-phase rationale + all D<N> questions batched at end. Majority of
decisions auto-resolved; only genuine ambiguities reach the user.

### 5. LiveView State Coverage Check (New lint rule)

New lint rule `missing_liveview_state_coverage`:
- Severity: `:warning`
- Checks: LiveView render/1 covers `@loading`, `@error`, empty collection cases
- Violation: component missing branches for empty/error/loading states

Also add to pre-generation checklist: "LiveView components cover all 5 states: empty, loading,
error, partial, full."

---

## Consequences

- **INV-005 and INV-022 now fully specified** — D<N> format is mandatory, no interpretation needed
- **Test suite must be updated** — Copilot output testing now validates D<N> format, not prose
- **Activity Feed needs new button UI** — Clickable option buttons for D<N> answers
- **New lint rule** — `missing_liveview_state_coverage` runs in `mix foundry.lint.all`
- **Chat components extended** — `scope_selector_card`, `autoplan_review_summary` rendered inline
- **Proposal generation defers scope questions** — No code written until scope is confirmed
- **Three new modules** (Cycle 2):
  - `Foundry.Chat.Retrieval.autoplan_context/2` — Phase A signals
  - `FoundryWeb.ChatSessionDomainLogic.build_autoplan_review/3` — Phase A/B/C orchestration
  - `Foundry.LintRules.LiveViewStateCoverage` — lint rule
- **Cycle 3 (later cycles)** — Project learnings JSONL store, governance retrospective view,
  parallel proposals feed panel (as specified in implementation plan)

---

## Related Decisions

- **ADR-013:** Copilot Agent Behaviour — format amendment
- **ADR-005:** Change Approval Model — classification rules still apply
- **ADR-022:** Side-Effect Governance — pre-mortem checks still apply
- **ADR-002:** Code Generation — scope tiers inform Igniter operation parameters
