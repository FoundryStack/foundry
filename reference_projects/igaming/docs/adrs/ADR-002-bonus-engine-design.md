# ADR-002: Event-Driven Bonus Evaluation and Grant Execution

**Status:** Proposed

**Date:** 2026-05-04

## Context

The promotions domain needs to evaluate inbound `BonusEvent` rows against configured
campaign rules and then award bonuses only when eligibility is confirmed.

The current bonus flow already splits responsibility across two parts:

- `IgamingRef.Promotions.BonusEvaluationReactor` evaluates inbound events against
  `BonusTrigger`, `BonusConditionGroup`, `BonusCondition`, and `BonusExecution`
  resources.
- `IgamingRef.Promotions.BonusGrantTransfer` performs the wallet credit, ledger entry,
  and `BonusGrant` creation.

This separation is necessary because bonus processing has two different concerns:

1. Rule evaluation must be repeatable and safe to retry.
2. Value movement must remain auditable and idempotent.

The project also already requires:

- immutable ledgering for financial movement via ADR-001
- bonus transparency and wagering disclosure via `RG-MGA-005` and `RG-UK-011`
- immediate self-exclusion enforcement via `RG-UK-008` and `RG-MGA-009`

## Decision

We keep the bonus engine as an event-driven, two-stage workflow:

1. `BonusEvaluationReactor` evaluates an inbound `BonusEvent`, determines matching
   campaigns, executes configured bonus steps, and marks the event processed only after
   successful execution. If a `BonusEvent` already has `processed_at` set, the reactor
   short-circuits and returns the loaded event without re-running campaign handlers.
2. `BonusGrantTransfer` applies the wallet credit, records the immutable ledger entry,
   and creates or updates the `BonusGrant` record for wagering tracking.

We rely on explicit idempotency boundaries:

- `BonusEvent.idempotency_key` deduplicates repeated ingestion attempts.
- `BonusGrantTransfer` is idempotent per `{player_id, campaign_id}`.

We also keep cross-domain eligibility checks inside the grant path so that the system
rejects bonus awards when the player is self-excluded or otherwise ineligible at the
time of award.

## Consequences

### Positive

- Bonus evaluation can be retried without duplicating wallet credits.
- Wallet movement stays aligned with the double-entry ledger pattern from ADR-001.
- The operational model is easy to reason about: evaluate first, grant second, mark the
  inbound event processed last.
- Compliance checks stay explicit at the point where value is awarded.

### Negative

- The workflow requires coordination between the evaluation reactor and the grant
  transfer.
- Failures between evaluation and grant completion can leave an event unprocessed and
  require operator re-run.
- The design depends on correct idempotency handling in both event ingestion and grant
  execution.

### Mitigation

- Preserve the current idempotency keys and composite uniqueness behavior.
- Keep the runbooks aligned with failure recovery and retry expectations.
- Maintain the existing bonus runbooks as the operational source of truth for recovery
  steps:
  - `docs/runbooks/bonus_evaluation_reactor.md`
  - `docs/runbooks/bonus_grant_transfer.md`
- Treat `BonusConditionGroup.parent_group_id` as a tree edge. Campaign condition
  evaluation starts at root groups and recurses through nested child groups using each
  group's combinator.

## Alternatives Considered

### 1. Single monolithic bonus job

Rejected because it would mix rule evaluation, wallet mutation, and ledger recording in
one step. That makes retries harder to reason about and increases the chance of duplicate
value movement after partial failures.

### 2. Direct wallet credit from the evaluation reactor

Rejected because the evaluation step should remain focused on campaign matching and
eligibility. Grant execution needs its own idempotent boundary and audit trail.

### 3. Precompute and persist all bonus outcomes before crediting

Rejected because bonus eligibility can depend on the player state at award time. The
system must still re-check self-exclusion and other blocking conditions when the grant
is actually applied.

## Related Decisions

- ADR-001: Double-Entry Ledger for Financial Transactions

## Operational Notes

- The bonus engine is expected to remain retry-safe.
- Operator recovery should use the existing runbooks rather than ad hoc database
  manipulation.
- Any change that alters the campaign evaluation model, grant idempotency boundary, or
  payout sequencing should update this ADR first.

For implementation details, see:

- `docs/runbooks/bonus_evaluation_reactor.md`
- `docs/runbooks/bonus_grant_transfer.md`
