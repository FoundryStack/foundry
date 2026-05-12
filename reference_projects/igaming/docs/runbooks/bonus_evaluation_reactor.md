# BonusEvaluationReactor Runbook

## Purpose

`IgamingRef.Promotions.BonusEvaluationReactor` evaluates inbound `BonusEvent` rows
against configured `BonusTrigger`, `BonusConditionGroup`, `BonusCondition`, and
`BonusExecution` resources.

## Failure Modes

1. Event cannot be loaded.
2. Condition evaluation fails due malformed params.
3. Execution handler fails (for example `BonusGrantTransfer` rejection).

## Operational Steps

1. Locate the `BonusEvent` by `id` and inspect `payload` and `idempotency_key`.
2. Check campaign config rows (`BonusTrigger`, `BonusCondition*`, `BonusExecution`)
   for missing or disabled entries.
3. Re-run the reactor with the same `event_id` after correcting config.
4. If `processed_at` is already set, the reactor treats the event as completed and
   skips campaign evaluation and execution.
5. If the event is stuck, set `processed_at` manually only after confirming all
   intended executions have been applied.

## Idempotency

- Event ingestion is deduplicated by `BonusEvent.idempotency_key`.
- `BonusGrantTransfer` remains idempotent per `{player_id, campaign_id}`.
- Condition groups are evaluated as a tree rooted at groups with no `parent_group_id`.
