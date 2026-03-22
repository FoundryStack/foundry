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
