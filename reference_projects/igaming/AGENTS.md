# AGENTS.md - iGaming Reference Project

This file is the primary project-specific entry point for agents working inside
`reference_projects/igaming`. It is loaded together with Foundry's core copilot
prompt: Foundry supplies the universal governance model, while this file supplies
the target platform context.

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

## Context Loading Model

Foundry and project context are both required:

- Foundry core context defines the universal agent rules, proposal lifecycle,
  change classes, and invariants.
- This `AGENTS.md` defines the igaming project orientation and retrieval posture.
- The spec-kit index points to ADRs, regulations, and runbooks that must be read
  before answering or changing governed areas.
- `mix foundry.project.status` gives current health, stack, lint, compliance, and
  sensitive-resource summary.
- `mix foundry.project.context [Module]` gives live code-derived facts for modules,
  resources, Reactors, Transfers, policies, relationships, and compliance links.

Do not duplicate the full system map here. Use the generated project context for
topology and source-derived details.

---

## Source Of Truth Order

When sources overlap, use this order:

1. Live structured context from compiled code for attributes, actions, policies,
   relationships, state machines, side effects, telemetry, and runbook links.
2. Regulations for compliance requirements and test tags.
3. ADRs for accepted architectural and domain decisions.
4. Runbooks for operational recovery, idempotency, and failure handling.
5. This file for project orientation and where to look next.

If a change needs a decision that is not covered by an ADR or regulation, surface a
spec-kit gap before proposing implementation.

---

## High-Scrutiny Areas

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

## Spec-Kit Navigation

Start with the most specific artifact for the work:

- Ledger and wallet integrity: `docs/adrs/ADR-001-double-entry-ledger.md` and
  `docs/regulations/ukgc_mga.md`
- Withdrawal flow operations: `docs/runbooks/withdrawal_transfer.md`
- Bonus grant operations: `docs/runbooks/bonus_grant_transfer.md`
- Bonus event evaluation: `docs/runbooks/bonus_evaluation_reactor.md`
- Provider catalog sync: `docs/runbooks/provider_sync.md`
- Compliance requirements: `docs/regulations/ukgc_mga.md`

`docs.md` is not a spec-kit artifact and is not part of Foundry's governed context
roots. Do not treat it as authoritative.

---

## Project-Specific Working Rules

- For questions, answer from the spec-kit and live project context, citing the file,
  requirement, ADR, runbook, module, or field that grounds the answer.
- For changes touching financial movement, player eligibility, KYC, self-exclusion,
  provider certification, bonus awards, PII, or audit evidence, read the relevant
  regulation and runbook before planning.
- For structural code facts, prefer `mix foundry.project.context <Module>` over
  source-file prose.
- For DSL syntax, use current project usage rules, ExDoc, and existing local patterns.
- For external side effects in Reactors or Transfers, verify idempotency and
  compensation expectations before proposing changes.
- For compliance changes, require an ADR link or surface the missing ADR as a blocker.

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
