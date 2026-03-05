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
| 11 | ash_postgres + migration lifecycle absent | Closed | ADR-001, ADR-002, ADR-005 migration classification |
| 12 | Money stack underspecified | Closed | ADR-001 Money/Currency Stack section |
| 13 | ash_authentication / ash_authentication_phoenix absent | Closed | ADR-001 Authentication Scaffold; ADR-005 auth always :sensitive |
| 14 | ash_paper_trail governance absent | Closed | INV-011; ADR-005 classifier |
| 15 | ash_archival governance absent | Closed | INV-012; ADR-005 classifier |
| 16 | AshAI stance undocumented | Closed | ADR-001 Out of Scope — v1 ignores and warns |
| 17 | AshPyro + DaisyUI unaddressed | Closed | ADR-001 Conditionally Present; ADR-007 data-* note |
| 18 | Observability stack absent | Closed | ADR-001 Observability Stack section |
| 19 | fun_with_flags governance absent | Closed | ADR-001 Feature Flags; INV-013; ADR-005 classifier |
| 20 | nebulex cache implementation unspecified | Closed | ADR-003 (Nebulex L1 for spec-kit + ExDoc caches); ADR-010 |
| 21 | hammer / hammer_plug absent | Closed | ADR-001 Rate Limiting; ADR-005 classifier |
| 22 | swoosh unspecified | Closed | ADR-001 Email/Notifications section |
| 23 | libcluster absent for cloud mode | Closed | ADR-001 Clustering section |
| 24 | mix foundry.context schema incomplete | Closed | ADR-003 full schema; AGENTS.md updated |
| 25 | ADR-004 forbidden ecto rule ambiguous | Closed | ADR-004 clarification: direct-only, transitive permitted |
| 26 | Req/Finch pool governance unspecified | Closed | ADR-004 Req/Finch clarification |
| 27 | Test tool assignments missing from ADR-007 | Closed | ADR-007 Test Tool Assignments section |
| 28 | Admin UI security (oban_web, live_dashboard) unaddressed | Closed | ADR-001 Admin UI Libraries section; ADR-005 classifier |
| 29 | ash_state_machine underspecified | Closed | ADR-001 listed; ADR-002 Op.AddStateTransition; ADR-003 schema; ADR-005 classifier |
| 30 | ash_json_api governance gaps | Closed | ADR-001 listed; ADR-002 Op.AddApiRoute; ADR-003 schema; ADR-005 classifier |
| 31 | Migration governance absent | Closed | ADR-001 Migration Lifecycle; ADR-002 migration generation; ADR-005 migration classification |
| 32 | decorator library unaddressed | **Open** | Low priority — no governance model yet; agents treat decorated functions as opaque |
| 33 | Beacon CMS stance | Closed | ADR-001 Out of Scope for v1 |
| 34 | jason implicit dependency | Closed | ADR-001 Core Stack table |
| 35 | bandit vs cowboy unspecified | Closed | ADR-001 Core Stack table (Bandit) |
| 36 | Asset pipeline (esbuild/tailwind) absent | Closed | ADR-001 Studio UI Asset Pipeline section |
| 37 | bypass test mechanism unspecified | Closed | ADR-004 Test Tool Specs; ADR-007 tool assignments |

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
| Migration proposal generation | `Foundry.Operations.MigrationProposer` |
| Authentication scaffold composition | `Foundry.Operations.Op.AddAuthenticationResource` |
| Feature flag governance metadata | `Foundry.FeatureFlags.GovernanceRegistry` |

---

## Deferred ADRs (write when the corresponding code exists)

- **ADR-011**: Project Manifest contract — when `Foundry.Manifest` Ash resource is defined
- **ADR-012**: Bootstrap spec-kit generation — when `mix foundry.spec_kit.init` is built

Do not write these speculatively. A spec-kit document without corresponding code is
pre-emptive documentation — the very thing the discipline exists to prevent.

---

## Open Items Requiring Future ADRs

- **`decorator` library governance** — agents currently treat decorated functions as opaque (no introspection). If `decorator` is used on Transfer steps or compliance-critical paths, a governance model is needed. Track as Gap #32 above.

---

## Current Spec-Kit File List

```
spec-kit/
  AGENTS.md                              ← primary agent context
  BUILD_SEQUENCE.md                      ← implementation phases
  REVIEW_AND_PLAN.md                     ← this file
  adrs/
    ADR-001-stack-selection.md           ← updated: full ecosystem
    ADR-002-code-generation.md           ← updated: migration generation, 20 operations
    ADR-003-agent-context-strategy.md    ← updated: full context schema
    ADR-004-dependency-governance.md     ← updated: ecto clarification, test tools
    ADR-005-change-approval-model.md     ← updated: migration classification, auth, feature flags
    ADR-006-infrastructure-governance.md
    ADR-007-test-generation-strategy.md  ← updated: tool assignments, AshPyro note
    ADR-008-visualization-paradigm.md
    ADR-009-concurrent-proposals.md
    ADR-010-llm-model-and-context.md     ← updated: full version manifest, Nebulex
  regulations/
    platform_invariants.md               ← updated: INV-011, INV-012, INV-013
  runbooks/
    studio_copilot_failure.md
    igniter_operation_failure.md
    project_reader_unavailable.md
    compliance_test_failure.md
    approval_queue_blocked.md
```