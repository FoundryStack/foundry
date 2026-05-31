# FND-20260531-091943-23bd0d-bonus-engine-replay-safe: Bonus engine replay-safety gap
**Status:** Captured  
**Date:** 2026-05-31T09:19:43Z  
**Session:** 61ddef27-55e7-4837-8fe4-26ddda25581d  
**Related Nodes:** IgamingRef.Promotions.BonusEvaluationReactor, IgamingRef.Promotions.BonusGrantTransfer, IgamingRef.Promotions.BonusEvent, IgamingRef.Promotions.BonusGrant  
**Related Docs:** /Users/maxsvargal/Documents/Projects/foundry/reference_projects/igaming/docs/adrs/ADR-002-bonus-engine-design.md, /Users/maxsvargal/Documents/Projects/foundry/reference_projects/igaming/docs/runbooks/bonus_evaluation_reactor.md, /Users/maxsvargal/Documents/Projects/foundry/reference_projects/igaming/docs/runbooks/bonus_grant_transfer.md  
**Tags:** bonuses, idempotency, replay-safety, ledger, wallet-crediting
## Summary

The bonus flow is event-driven, but replay safety and idempotency around terminal state marking and repeat grants are still under-specified.

## Technical Findings

- [VERIFIED] `BonusEvaluationReactor` loads `BonusEvent`, player, active campaigns, matching campaigns, executes campaigns, and marks the event processed.
- [VERIFIED] `BonusGrantTransfer` credits the wallet, records a ledger entry, and creates a `BonusGrant` when eligibility is confirmed.

## Important Discoveries

- [INFERRED] The promotions flow is designed as an auditable wallet-crediting path, not just a campaign status update.

## Issues

- [ASSUMPTION] Replay-safety and idempotency still need careful review before changing bonus orchestration semantics.

## Conclusions

- Bonus semantics should be treated as governed finance-adjacent behavior, not as a simple marketing feature.
