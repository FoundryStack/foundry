# Runbook: BonusGrantTransfer

> **Transfer module:** `IgamingRef.Promotions.BonusGrantTransfer`
> **Last tested:** *(not yet tested — set this date after first drill)*
> **Owner:** platform-lead@igamingref.test
> **Escalation:** compliance@igamingref.test

---

## When this runbook applies

- Reactor fails mid-flight (wallet credited but BonusGrant record not created)
- Player reports receiving bonus credit but no wagering progress tracked
- Campaign expired between eligibility check and grant creation (race condition)
- Duplicate grant issued due to retry storm despite idempotency key

---

## Step 1 — Confirm the duplicate or missing grant

```elixir
# Check for existing grants for this player/campaign pair
IgamingRef.Promotions.BonusGrant
|> Ash.Query.filter(player_id: player_id, campaign_id: campaign_id)
|> Ash.read!(actor: :system)

# Check for the corresponding ledger entry
IgamingRef.Finance.LedgerEntry
|> Ash.Query.filter(reference_id: campaign_id, kind: :bonus)
|> Ash.read!(actor: :system)
```

---

## Step 2 — Idempotency key verification

The `BonusGrantTransfer` uses `{player_id, campaign_id}` as its idempotency key.
A duplicate ledger entry with key `"bonus_grant:<player_id>:<campaign_id>"` indicates
a retry-created duplicate. Check the `unique_idempotency_key` constraint was not
violated — if it was, the second `Ash.create` should have returned an error.

---

## Step 3 — Resolution paths

| Scenario | Action |
|---|---|
| Wallet credited but no BonusGrant | Create BonusGrant manually via Foundry proposal (:behavioral class) |
| BonusGrant exists but wallet not credited | Credit wallet via Foundry proposal; link to existing grant |
| Duplicate grant issued | Forfeit the duplicate grant; no wallet reversal needed |
| Campaign race condition | Mark the grant as :planned status in fixture; re-run compliance check |