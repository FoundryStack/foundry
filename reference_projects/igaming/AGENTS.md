# AGENTS.md - iGaming Reference Project

This file is the primary project-specific entry point for agents working inside
`reference_projects/igaming`. It is loaded together with Foundry's core copilot
prompt: Foundry supplies the universal governance model, while this file supplies
the target platform constitution.

Keep this document compact. Durable domain knowledge belongs in the spec-kit:
ADRs for decisions, regulations for compliance requirements, and runbooks for
operational procedures. Live code facts belong in `mix foundry.project.context`
and `mix foundry.project.status`, not in prose.

---

## What This Project Is

`IgamingRef` is a regulated iGaming reference platform used to exercise Foundry's
governed project-context, compliance, proposal, and Studio workflows.

The platform models:

- Player identity, KYC, account lifecycle, and self-exclusion
- Wallets, ledger entries, withdrawals, and financial transfers
- Bonus campaigns, bonus event evaluation, and bonus grants
- Gaming provider configuration, game catalog sync, and RTP certification
- PII vaulting, audit evidence, and operator/compliance policy checks

This is a reference target platform, not the Foundry meta-platform. Work from this
project root.

---

## Domain Risk Model

Treat these areas as governed and high-risk:

- Finance: `Wallet`, `LedgerEntry`, `Transfer`, `WithdrawalRequest`, and
  `WithdrawalTransfer`
- Players: `Player`, `SelfExclusionRecord`, KYC resources, and PII-bearing data
- Promotions: `BonusEvent`, bonus evaluation, bonus grants, wagering requirements,
  and wallet-crediting bonus flows
- Gaming: provider adapters, provider configuration, RTP certification, and catalog
  sync
- Ops: PII vault and audit evidence

The manifest declares sensitive resources and approvers. Do not infer sensitivity
from domain names alone; verify it through project status or project context.

---

## Project Constitution

- Financial movement, withdrawal orchestration, and bonus wallet-crediting flows
  must be treated as operationally sensitive even in the reference project.
- Player eligibility decisions include KYC, self-exclusion, jurisdiction checks,
  and any other gating that determines whether a player may act or receive value.
- Provider-facing integrations are governed by certification, replay safety,
  idempotency, and auditability requirements before convenience or throughput.
- PII vaulting and audit evidence are first-class compliance concerns. Changes in
  these areas must preserve traceability and operator reviewability.
- If a requested change materially alters bonus semantics, KYC lifecycle meaning,
  provider certification posture, or withdrawal orchestration strategy, surface the
  need for a new ADR before implementation.

---

## Known Spec-Kit Gaps

The reference project intentionally keeps the spec-kit small. Current coverage is
enough for Foundry acceptance testing, but not every domain decision has its own ADR.

Likely gaps to surface when relevant:

- Provider certification and adapter versioning decisions are mostly represented by
  regulations and runbooks, not ADRs.
- Bonus engine design is represented by code and runbooks; a dedicated ADR should be
  drafted before changing the campaign evaluation model.
- Player KYC and self-exclusion policy is represented by regulations and resource
  descriptions; a dedicated ADR should be drafted before changing lifecycle semantics.
- Withdrawal idempotency and provider submission behavior are documented in the
  runbook; a dedicated ADR should be drafted before changing orchestration strategy.
