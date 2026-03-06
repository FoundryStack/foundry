# Runbook: WithdrawalTransfer

> **Transfer module:** `IgamingRef.Finance.WithdrawalTransfer`
> **Last tested:** *(not yet tested — set this date after first drill)*
> **Owner:** finance-lead@igamingref.test
> **Escalation:** platform-lead@igamingref.test

---

## When this runbook applies

This runbook covers operational failure scenarios for the `WithdrawalTransfer` Reactor:

- Reactor step fails mid-flight (wallet debited but ledger entry not created)
- Provider submission fails after ledger entry written
- Duplicate withdrawal requests from retry storms
- Withdrawal stuck in `:processing` state

---

## Step 1 — Identify the stuck withdrawal

```bash
# Find withdrawal requests in :processing for more than 2 hours
mix foundry.context IgamingRef.Finance.WithdrawalRequest

# In iex
IgamingRef.Finance.WithdrawalRequest
|> Ash.Query.filter(status: :processing)
|> Ash.Query.filter(updated_at: [less_than: DateTime.add(DateTime.utc_now(), -7200, :second)])
|> Ash.read!(actor: :system)
```

---

## Step 2 — Check ledger entry

Verify whether a ledger entry was created for this withdrawal:

```elixir
IgamingRef.Finance.LedgerEntry
|> Ash.Query.filter(reference_id: withdrawal_request_id)
|> Ash.read!(actor: :system)
```

If **no ledger entry exists**: the wallet debit also did not complete. The Reactor compensated
correctly. Confirm wallet balance is intact, then re-trigger the Transfer.

If **ledger entry exists but no provider reference**: the provider call failed after the
ledger entry was written. Check provider logs. If the provider has no record of the
transaction, void the ledger entry manually (requires compliance officer approval —
`:compliance` class change) and re-trigger.

---

## Step 3 — Check provider status

Use the provider's admin console or API to look up the transaction by
`withdrawal_request.provider_reference`.

---

## Step 4 — Resolution paths

| Scenario | Action |
|---|---|
| Provider confirms payment sent | Call `mark_completed` action on the WithdrawalRequest |
| Provider has no record | Re-trigger the Transfer with the same `withdrawal_request_id` (idempotent) |
| Provider rejected (insufficient funds at provider) | Reject the WithdrawalRequest with reason; re-credit wallet |
| Reactor stuck, compensation failed | Page platform-lead; escalate to emergency override path |

---

## Compliance note

All manual interventions on sensitive resources require a Foundry proposal with
`:compliance` classification. Do not modify `WithdrawalRequest` or `LedgerEntry`
records directly — route all changes through Foundry.