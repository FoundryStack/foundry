# FND-20260510-102715-364194-bonus-flow-gaps-in-repla: Bonus flow gaps in replay safety and coverage
**Status:** Captured  
**Date:** 2026-05-10T10:27:15Z  
**Session:** 622542f5-c2e6-4eb5-8805-1dee1924d551  
**Mode:** ask  
**Related Nodes:** IgamingRef.Promotions.BonusEvaluationReactor, IgamingRef.Promotions.BonusGrant, IgamingRef.Finance.LedgerEntry  
**Related Docs:** docs/adrs/ADR-001-double-entry-ledger.md, docs/adrs/ADR-002-bonus-engine-design.md, docs/runbooks/bonus_evaluation_reactor.md, docs/runbooks/bonus_grant_transfer.md  
**Tags:** bonuses, replay-safety, idempotency, ledger, tests
## Summary

The bonus engine still has unclosed gaps in replay safety, nested condition semantics, ledger completeness, and success-path test coverage.

## Technical Findings

- [VERIFIED] BonusEvaluationReactor marks processed events only after execution, but does not short-circuit already processed BonusEvent rows.
- [VERIFIED] BonusConditionGroup documents nested trees via parent_group_id, yet the reactor evaluates groups independently and ignores nesting.
- [INFERRED] The bonus transfer path does not visibly implement ADR-001 double-entry semantics for bonus movements.
- [VERIFIED] Existing bonus tests are mostly scaffolding and do not cover successful grant issuance, processed_at transitions, or retry/idempotency behavior.

## Source Request

Review bonuses. Do you see any gaps if implementation or tests?
