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
