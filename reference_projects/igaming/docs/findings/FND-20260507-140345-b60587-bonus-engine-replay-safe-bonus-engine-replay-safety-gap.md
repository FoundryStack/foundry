# FND-20260507-140345-b60587-bonus-engine-replay-safe: Bonus engine replay-safety gap
**Status:** Captured  
**Date:** 2026-05-07T14:03:45Z  
**Session:** 75ff60c7-7649-4984-b92e-47c90ba4dd11  
**Mode:** ask  
**Related Nodes:** IgamingRef.Promotions.BonusEvaluationReactor, IgamingRef.Promotions.BonusEvent, IgamingRef.Promotions.BonusGrant, IgamingRef.Promotions.BonusGrantTransfer, IgamingRef.Promotions.Rules.CampaignNotExpired, IgamingRef.Promotions.Rules.PlayerEligibleForCampaign  
**Related Docs:** /Users/maxsvargal/Documents/Projects/foundry/reference_projects/igaming/docs/adrs/ADR-001-double-entry-ledger.md, /Users/maxsvargal/Documents/Projects/foundry/reference_projects/igaming/docs/adrs/ADR-002-bonus-engine-design.md, /Users/maxsvargal/Documents/Projects/foundry/reference_projects/igaming/docs/runbooks/bonus_evaluation_reactor.md, /Users/maxsvargal/Documents/Projects/foundry/reference_projects/igaming/AGENTS.md  
**Tags:** bonus-engine, idempotency, replay-safety, igaming, auditability
## Summary

The bonus flow is architecturally sound, but replay safety and idempotency scope are under-specified, especially around event ownership, terminal state marking, and campaign-level repeat grants.

## Technical Findings

- [VERIFIED] `BonusEvaluationReactor` and `BonusGrantTransfer` are intentionally split so rule evaluation and value movement are handled separately.
- [VERIFIED] The runbook documents deduplication by `BonusEvent.idempotency_key` and states `BonusGrantTransfer` is idempotent per `{player_id, campaign_id}`.
- [VERIFIED] `CampaignNotExpired` is evaluated at transfer time, not read time.

## Important Discoveries

- [INFERRED] `processed_at` behaves like a terminal marker, but not a robust ownership lock for concurrent processing.
- [INFERRED] A campaign-level idempotency key may conflict with `max_redemptions` or other legitimate multi-grant campaign semantics.

## Issues

- [ASSUMPTION] Bonus event processing may double-execute or drift under concurrent workers or partial failure unless an atomic claim/lock exists.
- [ASSUMPTION] Current runtime validation for bonus condition/execution params may be too late in the flow for regulated operations.

## Conclusions

- Bonus redemption semantics and retry behavior should be treated as ADR-worthy before implementation changes.
- The safest enhancement is to add an explicit event lifecycle with intent-level idempotency and persisted skip/fail reasons.

## Source Request

Analyze bonus system. Do you see any gaps or issues, edge cases? How you can enhance it and why?
