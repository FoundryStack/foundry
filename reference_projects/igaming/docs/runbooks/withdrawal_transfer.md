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
