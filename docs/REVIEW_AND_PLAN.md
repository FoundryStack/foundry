# Foundry — Design Review & Spec-Kit Status

## What's Solid (do not revisit)

- Structured retrieval over RAG for code — ADR-003
- Igniter for all generation, no string interpolation — ADR-002
- Four-class change approval, :sensitive configured per project — ADR-005
- No drag-and-drop, Activity Feed is the only change interface — ADR-008
- Spec-kit is decisions + constraints only, not code duplication — this document
- Git + ETS storage, no Postgres dependency for Foundry itself — ADR-015

---

## Gap Status

| # | Description | Status | Resolution |
|---|---|---|---|
| 1 | Project Manifest underspecified | Closed | `docs/manifest-schema-draft.md` consolidates all manifest fields. `lib/foundry/manifest.ex` Ash resource designed. ADR-011 to be written once resource is stable in production. |
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
| 32 | decorator library unaddressed | Closed | `docs/lint-catalogue.md` `:decorated_transfer_step` lint rule — warning on decorated Transfer steps, no introspection in v1. See Gap #53. |
| 33 | Beacon CMS stance | Closed | ADR-001 Out of Scope for v1 |
| 34 | jason implicit dependency | Closed | ADR-001 Core Stack table |
| 35 | bandit vs cowboy unspecified | Closed | ADR-001 Core Stack table (Bandit) |
| 36 | Asset pipeline (esbuild/tailwind) absent | Closed | ADR-001 Studio UI Asset Pipeline section |
| 37 | bypass test mechanism unspecified | Closed | ADR-004 Test Tool Specs; ADR-007 tool assignments |
| 38 | ADR-010 file contained ADR-001 content (duplicate) | Closed | ADR-010 rewritten with correct LLM/context content |
| 39 | No copilot agent behaviour spec (confidence, errors, clarifying question UX) | Closed | ADR-013 |
| 40 | No proposal lifecycle state machine | Closed | ADR-014 |
| 41 | No Studio UX specification (panels, palette, interactions) | Closed | ADR-012 |
| 42 | "Impact analysis" term used but never defined | Closed | ADR-012 §Impact Tab |
| 43 | Dual approval mechanics unspecified (revocation, timeouts, audit record) | Closed | ADR-014 §Dual Approval Mechanics |
| 44 | ADR linking UX for :compliance proposals unspecified | Closed | ADR-014 §ADR Linking for Compliance Changes |
| 45 | Phase-gate flag mechanics unspecified | Closed | ADR-010 §Phase-Gated Behaviour; ADR-013 §Phase-Gated Copilot Behaviour; ADR-014 §Phase-Gated Features |
| 46 | Performance budgets absent | Closed | ADR-012 §Performance Budgets |
| 47 | Data retention policy absent | Closed | ADR-012 §Data Retention |
| 48 | No Studio UX degradation runbook | Closed | docs/runbooks/studio_ux_degradation.md |
| 49 | Cmd+P shortcut incorrect (should be Cmd+K) | Closed | ADR-012 §Command Palette; AGENTS.md updated |
| 50 | Foundry incorrectly implied Postgres dependency for its own state | Closed | ADR-015: git-backed files + ETS; ADR-001 core stack table split; ADR-012 retention table updated; ADR-014 storage section updated |
| 51 | ADR-001 core stack table conflated Foundry and target platform dependencies | Closed | ADR-001 split into Foundry dependencies and target platform dependencies |
| 52 | INV-008 and INV-010 missing from AGENTS.md Hard Invariants summary | Closed | AGENTS.md updated: INV-008, INV-009, INV-010 added to invariants summary with cross-references |
| 53 | decorator library creates silent governance hole on Transfer steps | Closed | `docs/lint-catalogue.md` — `:decorated_transfer_step` lint rule defined (status: planned). Warning surfaced in review panel and CLI. Gap #32 also closed. |
| 54 | iGaming reference project undeclared — Phase acceptance criteria have no verifiable target | Closed | `docs/reference-project-fixture.md` — 3 domains, 9 resources, 2 transfers, 5 rules, 11 RG-* requirements, manifest config, expected lint/context output counts. |

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
| Proposal state machine | `Foundry.Proposals.StateMachine` |
| Impact analysis computation | `Foundry.Copilot.ImpactAnalyzer` |
| Confidence classification | `Foundry.Copilot.ConfidenceClassifier` |
| Intent classification | `Foundry.Copilot.IntentClassifier` |
| Prompt construction | `Foundry.Copilot.PromptBuilder` |

---

## Deferred ADRs (write when the corresponding code exists)

- **ADR-011**: Project Manifest contract — `Foundry.Manifest` Ash resource is now designed (`lib/foundry/manifest.ex`). Write ADR-011 after the resource is stable in production (Phase 1 complete). Pre-ADR schema: `docs/manifest-schema-draft.md`.
- **ADR-016**: Bootstrap spec-kit generation — when `mix foundry.spec_kit.init` is built (previously ADR-012, then ADR-015 — renumbered now that ADR-015 is the storage model)

Do not write these speculatively. A spec-kit document without corresponding code is
pre-emptive documentation — the very thing the discipline exists to prevent.

---

## Open Items Requiring Future ADRs

None outstanding. All gaps closed. See gap tracker above.

---

## Current Spec-Kit File List

```
AGENTS.md                              ← primary agent context (updated: INV-008–010 added)
docs/
  BUILD_SEQUENCE.md                    ← implementation phases
  REVIEW_AND_PLAN.md                   ← this file (updated: all gaps closed)
  manifest-schema-draft.md             ← pre-ADR-011 manifest field schema
  reference-project-fixture.md         ← iGaming reference project declaration (Gap #54)
  lint-catalogue.md                    ← all planned lint rules (Gap #53, closes Gap #32)
  adrs/
    ADR-001-stack-selection.md         ← updated: full ecosystem
    ADR-002-code-generation.md         ← updated: migration generation, 20 operations
    ADR-003-agent-context-strategy.md  ← updated: full context schema
    ADR-004-dependency-governance.md   ← updated: ecto clarification, test tools
    ADR-005-change-approval-model.md   ← updated: migration classification, auth, feature flags
    ADR-006-infrastructure-governance.md
    ADR-007-test-generation-strategy.md ← updated: tool assignments, AshPyro note
    ADR-008-visualization-paradigm.md
    ADR-009-concurrent-proposals.md
    ADR-010-llm-model-and-context.md   ← rewritten: correct LLM/context content
    ADR-012-studio-ux-specification.md ← new
    ADR-013-copilot-agent-behavior.md  ← new
    ADR-014-proposal-lifecycle.md      ← new
    ADR-015-storage-model.md           ← new: git + ETS, no Postgres for Foundry
  regulations/
    platform_invariants.md             ← INV-001 through INV-013
  runbooks/
    studio_copilot_failure.md
    igniter_operation_failure.md
    project_reader_unavailable.md
    compliance_test_failure.md
    approval_queue_blocked.md
    studio_ux_degradation.md           ← new
lib/foundry/
  manifest.ex                          ← Foundry.Manifest Ash resource + embedded resources
  proposals/
    proposal.ex                        ← Foundry.Proposals.Proposal + embedded resources
  audit/
    event.ex                           ← Foundry.Audit.Event (append-only)
  context/
    structs.ex                         ← Mix task output struct definitions (Phase 1 JSON contract)
```