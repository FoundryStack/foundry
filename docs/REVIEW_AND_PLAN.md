# Foundry — Design Review & Spec-Kit Status

## What's Solid (do not revisit)

- Structured retrieval over RAG for code — ADR-003
- Igniter for all generation, no string interpolation — ADR-002
- Four-class change approval, :sensitive configured per project — ADR-005
- No drag-and-drop, copilot is the only change interface — ADR-008
- Spec-kit is decisions + constraints only, not code duplication — this document

---

## Gap Status

| # | Description | Status | Resolution |
|---|---|---|---|
| 1 | Project Manifest underspecified | **Open** | Needs ADR-011 when Ash resource exists |
| 2 | Copilot disambiguation failure modes | Closed | AGENTS.md INV-005 |
| 3 | ExDoc cache per-library key | Closed | ADR-003 consequences |
| 4 | Domain coverage formula missing | Closed | ADR-007 Domain Coverage Formula section |
| 5 | Bootstrap mode for new projects | Closed | AGENTS.md bootstrap case + BUILD_SEQUENCE Phase 6 |
| 6 | Concurrent proposals unspecified | Closed | ADR-009 |
| 7 | Staleness notification channels | Closed | INV-010 in platform_invariants.md |
| 8 | LLM model choice undocumented | Closed | ADR-010 |
| 9 | Build sequence absent from spec-kit | Closed | BUILD_SEQUENCE.md |
| 10 | Dogfooding (Foundry on Foundry) | Closed | AGENTS.md "Foundry vs Target Platforms" |

---

## What Belongs in Code, Not Spec-Kit

The following are intentionally absent from spec-kit. They live as `@moduledoc` and
`@description` on the Ash resources and modules that implement them.

| Topic | Module |
|---|---|
| Change classification logic | `Foundry.Copilot.Classifier` |
| Scaffold operation contracts | `Foundry.Operations.*` |
| Lint rule implementations | `Foundry.Lint.*` |
| Manifest schema and validation | `Foundry.Manifest` Ash resource |
| Context assembly pipeline | `Foundry.Copilot.ContextBuilder` |
| Test generation rules | `Foundry.Testing.Generator` |
| ExDoc cache implementation | `Foundry.Context.DocCache` |
| Domain coverage calculation | `Foundry.Testing.CoverageCalculator` |
| Stale proposal detection | `Foundry.Operations.ProposalStore` |
| Notification dispatch | `Foundry.Notifications.Dispatcher` |

---

## Deferred ADRs (write when the corresponding code exists)

- **ADR-011**: Project Manifest contract — when `Foundry.Manifest` Ash resource is defined
- **ADR-012**: Bootstrap spec-kit generation — when `mix foundry.spec_kit.init` is built

Do not write these speculatively. A spec-kit document without corresponding code is
pre-emptive documentation — the very thing the discipline exists to prevent.

---

## Current Spec-Kit File List

```
spec-kit/
  AGENTS.md                              ← primary agent context
  BUILD_SEQUENCE.md                      ← implementation phases
  REVIEW_AND_PLAN.md                     ← this file
  adrs/
    ADR-001-stack-selection.md
    ADR-002-code-generation.md
    ADR-003-agent-context-strategy.md
    ADR-004-dependency-governance.md
    ADR-005-change-approval-model.md
    ADR-006-infrastructure-governance.md
    ADR-007-test-generation-strategy.md
    ADR-008-visualization-paradigm.md
    ADR-009-concurrent-proposals.md
    ADR-010-llm-model-and-context.md
  regulations/
    platform_invariants.md               ← INV-001 through INV-010
  runbooks/
    studio_copilot_failure.md
    igniter_operation_failure.md
    project_reader_unavailable.md
```