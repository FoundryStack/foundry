--- ./docs/adrs/ADR-001-double-entry-ledger.md ---
# ADR-001: Double-Entry Ledger for Financial Transactions

**Status:** Accepted

**Date:** 2024-03-01

## Context

The iGaming domain requires immutable, auditable financial transaction records. Players make deposits, withdrawals, and earn bonuses. Wallets receive complex operations including debits, credits, chargebacks, and reversals.

## Decision

We use a double-entry ledger pattern via AshDoubleEntry, where every financial movement creates a pair of offsetting entries. This ensures:
- Balance integrity (sum of entries always equals wallet balance)
- Audit trail (every transaction is immutable and traceable)
- Regulatory compliance (financial transactions are fully documented)

## Consequences

- **Positive:** Perfect audit trail, guaranteed consistency, regulatory compliance
- **Negative:** Requires additional database writes (each transaction creates 2 entries instead of 1)
- **Mitigation:** Batch writes within Reactors to minimize I/O

## Related Decisions

- ADR-003: Multi-currency account structure
- ADR-008: AshDoubleEntry adoption in Ash framework

---

For details, see `docs/regulations/ukgc_mga.md` and `docs/regulations/` directory.

--- ./docs/mga_requirements.md ---
# IgamingRef Regulations — Malta Gaming Authority (MGA)
#
# These requirements are parsed by `mix foundry.compliance.check`.
# Format: ### RG-<JURISDICTION>-<NNN> heading, then Summary/Implementation/Test tag lines.

---

### RG-MGA-001
**Summary:** Wallet balance integrity — balance must never go negative
**Implementation:** `IgamingRef.Finance.Wallet`, `IgamingRef.Finance.LedgerEntry`, `IgamingRef.Finance.Rules.SufficientBalance`
**Test tag:** `:rg_mga_001`
**Status:** planned

### RG-MGA-002
**Summary:** Ledger immutability — entries cannot be modified or deleted after creation
**Implementation:** `IgamingRef.Finance.LedgerEntry`
**Test tag:** `:rg_mga_002`
**Status:** planned

### RG-MGA-003
**Summary:** KYC verification required before first withdrawal is permitted
**Implementation:** `IgamingRef.Players.Player`
**Test tag:** `:rg_mga_003`
**Status:** planned

### RG-MGA-005
**Summary:** Bonus terms must be transparent and enforced at grant time
**Implementation:** `IgamingRef.Promotions.BonusCampaign`, `IgamingRef.Promotions.BonusGrant`, `IgamingRef.Promotions.Rules.PlayerEligibleForCampaign`
**Test tag:** `:rg_mga_005`
**Status:** planned

### RG-MGA-007
**Summary:** Withdrawal requests must be processed within the declared SLA
**Implementation:** `IgamingRef.Finance.WithdrawalRequest`, `IgamingRef.Finance.WithdrawalTransfer`
**Test tag:** `:rg_mga_007`
**Status:** planned

### RG-MGA-009
**Summary:** Self-exclusion records must be immutable — they cannot be deleted
**Implementation:** `IgamingRef.Players.SelfExclusionRecord`
**Test tag:** `:rg_mga_009`
**Status:** planned
--- ./docs/regulations/ukgc_mga.md ---
# IgamingRef Regulations — UKGC & MGA

---

### RG-MGA-001
**Summary:** Wallet balance integrity - balance never goes negative
**Implementation:** `IgamingRef.Finance.Wallet`, `IgamingRef.Finance.LedgerEntry`, `IgamingRef.Finance.Rules.SufficientBalance`
**Test tag:** `:rg_mga_001`
**Status:** planned

### RG-MGA-002
**Summary:** Ledger immutability - entries cannot be modified or deleted
**Implementation:** `IgamingRef.Finance.LedgerEntry`
**Test tag:** `:rg_mga_002`
**Status:** planned

### RG-MGA-003
**Summary:** KYC verification required before first withdrawal
**Implementation:** `IgamingRef.Players.Player`
**Test tag:** `:rg_mga_003`
**Status:** planned

### RG-MGA-005
**Summary:** Bonus terms must be transparent and enforced
**Implementation:** `IgamingRef.Promotions.BonusCampaign`, `IgamingRef.Promotions.BonusGrant`, `IgamingRef.Promotions.Rules.PlayerEligibleForCampaign`
**Test tag:** `:rg_mga_005`
**Status:** planned

### RG-MGA-007
**Summary:** Withdrawal processing within declared SLA
**Implementation:** `IgamingRef.Finance.WithdrawalRequest`, `IgamingRef.Finance.WithdrawalTransfer`
**Test tag:** `:rg_mga_007`
**Status:** planned

### RG-MGA-009
**Summary:** Self-exclusion records must be immutable
**Implementation:** `IgamingRef.Players.SelfExclusionRecord`
**Test tag:** `:rg_mga_009`
**Status:** planned

### RG-UK-002
**Summary:** Player identity must be verified before account activation is permitted
**Implementation:** `IgamingRef.Players.Player`
**Test tag:** `:rg_uk_002`
**Status:** planned

### RG-UK-003
**Summary:** Player-facing balance must match the sum of all ledger entries at all times
**Implementation:** `IgamingRef.Finance.Wallet`, `IgamingRef.Finance.LedgerEntry`
**Test tag:** `:rg_uk_003`
**Status:** planned

### RG-UK-008
**Summary:** Self-exclusion must block all financial transactions immediately upon activation
**Implementation:** `IgamingRef.Players.Rules.PlayerNotSelfExcluded`
**Test tag:** `:rg_uk_008`
**Status:** planned

### RG-UK-011
**Summary:** Bonus wagering requirements must be disclosed to the player at grant time
**Implementation:** `IgamingRef.Promotions.BonusCampaign`, `IgamingRef.Promotions.BonusGrant`
**Test tag:** `:rg_uk_011`
**Status:** planned

### RG-UK-014
**Summary:** Withdrawals must be processed to the player's original payment method
**Implementation:** `IgamingRef.Finance.WithdrawalTransfer`
**Test tag:** `:rg_uk_014`
**Status:** planned

--- ./docs/runbooks/bonus_grant_transfer.md ---
# Bonus Grant Transfer Runbook

## Overview

Awards a bonus to a player when campaign eligibility is confirmed. Credits the wallet and creates a tracking record for wagering.

## Steps

1. **Load Context** — Fetches player, campaign, wallet, and existing grants for rule evaluation
2. **Evaluate Rules** — Runs three compliance checks:
   - PlayerNotSelfExcluded — ensures player is not in self-exclusion period
   - CampaignNotExpired — validates campaign is still active
   - PlayerEligibleForCampaign — checks eligibility rules (tier, geography, etc.)
3. **Credit Wallet** — Credits the player's wallet with the bonus amount. On failure, no funds credited. On later failure, debits via compensation
4. **Create Ledger Entry** — Records the credit as an immutable audit trail
5. **Create Bonus Grant** — Creates BonusGrant record tracking wagering requirements and expiry

## Idempotency

The transfer is idempotent via the `{player_id, campaign_id}` composite key. Retrying a completed grant is safe — the credit operation will idempotently update the wallet, and the BonusGrant creation will update the existing record.

## Compliance

- **RG-MGA-005** — Bonus Terms — ensures bonus terms are enforced according to MGA regulations

--- ./docs/runbooks/provider_sync.md ---
# Provider Sync Runbook

## Overview

Synchronizes the game catalog from a provider's API and creates or updates local records. Fully idempotent.

## Steps

1. **Load Provider** — Fetches and validates the provider configuration, ensures status is :active
2. **Fetch Games** — Calls the provider's API to retrieve the current list of games with metadata
3. **Sync Games** — Creates or updates Game records for each fetched game
4. **Update Catalog** — Updates GameCatalog entries to mark games as visible/available

## Idempotency

The sync is idempotent via the `provider_id` key. Running the sync multiple times is safe — duplicate game creates are handled by idempotent merge semantics, and GameCatalog updates are atomic.

## Compliance

- **RG-MGA-006** — Provider Agreements — ensures only approved providers are synced
- **RG-UK-007** — Game Certification — ensures only certified games are added to the catalog

--- ./docs/runbooks/withdrawal_transfer.md ---
# Withdrawal Transfer Runbook

## Overview

Handles the complete flow of processing an approved withdrawal request through to provider submission.

## Steps

1. **Load Request** — Fetches the withdrawal request from the database and validates it's in the :approved state
2. **Load Player & Wallet** — Retrieves the player and wallet records needed for rule evaluation
3. **Evaluate Rules** — Runs three compliance rules:
   - PlayerNotSelfExcluded — ensures player is not in self-exclusion period
   - SufficientBalance — validates wallet has sufficient balance
   - WithdrawalLimitNotExceeded — checks against daily/weekly/monthly limits
4. **Debit Wallet** — Atomically deducts funds. On failure, no funds move. On later failure, re-credits via compensation
5. **Create Ledger Entry** — Records the debit as an immutable audit trail
6. **Submit to Provider** — Sends withdrawal request to payment provider (Stripe/PayPal). Failures trigger compensation (re-credit)
7. **Update Status** — Marks the WithdrawalRequest as :processing with provider reference

## Idempotency

The transfer is idempotent via the `withdrawal_request_id` key. Retrying a completed transfer is safe — the debit operation will idempotently update the wallet balance, and the provider will reject duplicate submission attempts.

## Compliance

- **RG-UK-014** — Withdrawal Processing — ensures withdrawals follow FCA-mandated procedures
- **RG-MGA-007** — Withdrawal Limits — enforces daily/monthly limits for MGA-licensed operators

--- ./docs/ukgc_requirements.md ---
# IgamingRef Regulations — UK Gambling Commission (UKGC)

---

### RG-UK-002
**Summary:** Player identity must be verified before account activation is permitted
**Implementation:** `IgamingRef.Players.Player`
**Test tag:** `:rg_uk_002`
**Status:** planned

### RG-UK-003
**Summary:** Player-facing balance must match the sum of all ledger entries at all times
**Implementation:** `IgamingRef.Finance.Wallet`, `IgamingRef.Finance.LedgerEntry`
**Test tag:** `:rg_uk_003`
**Status:** planned

### RG-UK-008
**Summary:** Self-exclusion must block all financial transactions immediately upon activation
**Implementation:** `IgamingRef.Players.Rules.PlayerNotSelfExcluded`
**Test tag:** `:rg_uk_008`
**Status:** planned

### RG-UK-011
**Summary:** Bonus wagering requirements must be disclosed to the player at grant time
**Implementation:** `IgamingRef.Promotions.BonusCampaign`, `IgamingRef.Promotions.BonusGrant`
**Test tag:** `:rg_uk_011`
**Status:** planned

### RG-UK-014
**Summary:** Withdrawals must be processed to the player's original payment method
**Implementation:** `IgamingRef.Finance.WithdrawalTransfer`
**Test tag:** `:rg_uk_014`
**Status:** planned
