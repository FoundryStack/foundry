# ADR-025: Test Visualization in Studio

**Status:** Accepted  
**Date:** 2026-05-04  
**Amended:** 2026-05-09 by runtime-backed page trace normalization
**Context:** Tests are first-class in copilot-driven development (INV-023). Foundry Studio renders system architecture via graph, but tests remain invisible — Coverage sidebar tab is a placeholder, Flow drawer tab shows "No scenarios defined yet", and the Scenario lens button is inactive.

## Problem

Domain experts cannot review test coverage without reading source code. Scenarios exist (ExUnit tests with invariants, state machines, compliance mappings, property tests), but Studio has no way to visualize them:

- Which graph nodes participate in a scenario?
- What is the execution flow (start → end)?
- What are the Given/When/Then steps?
- How does this scenario satisfy a compliance requirement?

Tests remain invisible to reviewers and stakeholders.

## Solution

Extract scenarios from annotated ExUnit test files, link them to graph nodes via a `ScenarioEntry` struct, and render them in Studio:

1. **Annotation Convention**: Scenario metadata added via `@moduletag` in test files (category, nodes, graph_path, steps, compliance_links)
2. **ScenarioEntry**: New data model representing a single scenario with nodes, execution path, BDD steps, and compliance links
3. **ScenarioExtractor**: AST-based parser that discovers scenarios from test files
4. **Coverage Tab**: Domain-grouped scenario browser showing coverage score, category filters, and node participation
5. **Graph Overlay**: On scenario selection, highlight participating nodes and execution path with START/END markers
6. **Flow Drawer Tab**: Render Given/When/Then steps in plain language, show participating nodes and compliance links

### Amendment: Runtime-first Scenario Resolution and Page Trace Normalization

For scenarios backed by runtime evidence, Foundry keeps static and runtime traces as
separate evidence streams. Studio presents a resolved flow derived from runtime first,
then enriched by static metadata only where the match is unambiguous or the renderer
needs inferred bridge structure. Static evidence remains a fallback when runtime traces
are absent.

For page scenarios backed by runtime evidence, Foundry applies page-specific runtime
semantics during normalization without changing the existing `provenance` field or
persisting page-only role fields into generic `ExTracer` structs:

- `:framework_mount` — LiveView mount/entry events emitted by the runtime harness
- `:app_behavior` — resource actions executed by the page itself
- `:test_observation` — helper/assertion reads executed by the test process

Studio presents one canonical page flow per scenario. Canonical page flow:

- collapses duplicated disconnected/connected mount cycles
- excludes `:test_observation` steps from graph-path extension and overlay routing
- prefers exact action nodes when page metadata resolves a single matching action
- preserves raw runtime evidence separately from the resolved Studio flow
- preserves the raw per-test flows alongside the canonical flow for debugging and future drill-down UI

## Scope

This ADR specifies:

- Scenario annotation convention using `@moduletag` in ExUnit files
- `ScenarioEntry` data model: id, name, category, source_file, source_module, nodes[], graph_path[], compliance_links[], steps (given/when/then), tags
- Four scenario categories: `:invariant`, `:state_machine`, `:compliance`, `:property`
- Coverage tab UX: domain score bar, scenario list grouped by category, per-scenario node indicators
- Graph overlay mechanism: `graph:scenario_overlay` server event, node dimming/highlighting, path animation, START/END badges
- Drawer Flow tab: Given/When/Then rendering, participating nodes, compliance links
- Test generation rules: scenario stubs committed before implementation (per INV-023)

Out of scope (Phase C/D):

- Property test result visualization (StreamData property values)
- Mutation testing dashboard
- Test failure playback

## Design

### 1. Annotation Convention

Tests declare scenario metadata via module-level or describe-level `@moduletag`:

```elixir
@moduletag category: :invariant
@moduletag nodes: ["Finance.WithdrawalTransfer", "Finance.Rules.SufficientBalance"]
@moduletag graph_path: ["Finance.WithdrawalTransfer", "Finance.Rules.SufficientBalance", "Finance.Wallet"]
@moduletag compliance_links: ["RG-UK-014"]
@moduletag steps: %{
  given: ["A player with active status", "A wallet with £500 balance"],
  when: ["The player requests a withdrawal of £600"],
  then: ["The withdrawal is rejected", "The wallet balance remains £500"]
}
```

**Fallback** (when `nodes:` is not declared): ScenarioExtractor scans `alias` statements in the file and maps short names to graph node IDs via `ProjectContext.nodes/0`.

### 2. ScenarioEntry Data Model

```elixir
defstruct [
  :id,            # "Finance.SufficientBalance.rejects_exceeds"
  :name,          # "SufficientBalance — rejects when amount exceeds balance"
  :category,      # :invariant | :state_machine | :compliance | :property
  :source_file,   # "test/finance/withdrawal_transfer_test.exs"
  :source_module, # "IgamingRef.Finance.WithdrawalTransferTest"
  nodes: [],           # ["Finance.WithdrawalTransfer", "Finance.Rules.SufficientBalance"]
  graph_path: [],      # ordered execution path
  compliance_links: [], # ["RG-UK-014"]
  steps: %{given: [], when: [], then: []},
  tags: []        # raw @moduletag list for extensibility
]
```

### 3. Scenario Categories

| Category | Purpose | Coverage Metric | Generated by |
|---|---|---|---|
| `:invariant` | Invariant property that must always hold (e.g., balance never negative) | `scenario_tests` in test_coverage | Copilot analyzing domain invariants |
| `:state_machine` | State transition validation (e.g., WithdrawalRequest: pending → approved → paid) | `scenario_tests` in test_coverage | Copilot analyzing state_machine metadata |
| `:compliance` | Regulatory requirement satisfaction (e.g., RG-UK-014 withdrawal limits) | `e2e_tests` in test_coverage | Copilot mapping RG-* requirements to scenarios |
| `:property` | Property-based invariant (e.g., wallet balance never negative via StreamData) | `property_tests` in test_coverage | Copilot generating StreamData generators |

### 4. Coverage Tab UX

**Design**: Sidebar tab showing domain-grouped scenario browser.

Top: **Coverage Score Bar**
```
Transfer ████░░░░ 80%   Rule ████░░░░░░ 60%   Compliance ██░░░░░░░░ 50%
Property ██████████ 100%   UI ████░░░░ 75%
Overall Score: 74% ⚠ Below 80% target
```

Formula (per ADR-007): `weighted_mean([transfer: 0.25, rule: 0.20, blueprint: 0.20, compliance: 0.25, ui: 0.10])`

Per-domain score: `mean(scenario_count_for_domain)` — 4+ scenarios = 100%, 0 = 0%, linear interpolation.

Middle: **Scenario List by Category**
```
▾ INVARIANT (4 scenarios)
  [INV] Sufficient Balance — rejects exceeds    ● Finance.WithdrawalTransfer, SufficientBalance
  [INV] Player Not Self-Excluded — enforces    ● Players.Player, Finance.WithdrawalTransfer

▾ COMPLIANCE (2)
  [RG-UK-014] Withdrawal limit enforced        ● Finance.WithdrawalTransfer
  [RG-MGA-007] KYC required before withdrawal  ● Players.Player, Finance.WithdrawalTransfer

▾ STATE_MACHINE (3)
  [SM] WithdrawalRequest pending → approved    ● Finance.WithdrawalRequest

▾ PROPERTY (5)
  [PROP] Wallet balance never negative         ● Finance.Wallet
```

Each row: `phx-click="select_scenario" phx-value-id={scenario.id}`  
Selected scenario: highlighted border + background color from category

### 5. Graph Overlay Mechanism

**Server → Client** event:
```elixir
push_event(socket, "graph:scenario_overlay", %{
  nodes: ["Finance.WithdrawalTransfer", "Finance.Rules.SufficientBalance", "Finance.Wallet"],
  path: ["Finance.WithdrawalTransfer", "Finance.Rules.SufficientBalance", "Finance.Wallet"],
  start: "Finance.WithdrawalTransfer",
  end: "Finance.Wallet"
})
```

**Client implementation** (JavaScript hook):
1. Dim all nodes not in `nodes` set: `opacity: 0.15, filter: grayscale(100%)`
2. Highlight nodes in `nodes` set: `opacity: 1, filter: none`
3. Add `START` badge on `start` node (green, top-left position)
4. Add `END` badge on `end` node (red, top-left position)
5. Highlight edges connecting nodes in `path`: 2px width, primary color, directional pulse animation
6. Auto-fit viewport to highlighted subgraph (Cytoscape `cy.fit(cy.$(nodes))`)

Uses Cytoscape `cy.style()` overrides — same mechanism as existing `applyProposalOverlay`.

### 6. Drawer Flow Tab

When scenario is selected, Flow tab renders:

```
GIVEN
  • A player with active status
  • A wallet with balance >= withdrawal amount
  • The player is not self-excluded

WHEN
  • The player requests a withdrawal within their limit

THEN
  • The withdrawal request is created in :pending state
  • The player balance is not yet debited
  • A compliance audit event is logged

Participating Nodes
  Players.Player → Finance.WithdrawalTransfer → Finance.Rules.SufficientBalance → Finance.Wallet

Compliance
  RG-UK-014: Withdrawal limits enforced
```

When Flow tab renders a **node** (not scenario), list scenarios involving that node as clickable chips:
```
Scenarios Involving This Node
  [INV] Sufficient Balance — rejects exceeds [click to select]
  [SM] WithdrawalRequest pending → approved [click to select]
```

Clicking a chip triggers `phx-click="select_scenario"` → overlay applies → Flow tab re-renders for that scenario.

### 7. Copilot Generation Rules

Per INV-023, test skeletons (including scenario annotations) are committed **before** implementation:

1. Copilot generates test file with `describe` blocks
2. Each `describe` gets `@moduletag category:`, `@moduletag nodes:`, `@moduletag graph_path:`, `@moduletag steps:`
3. Test body is stubbed (`:ok`)
4. Proposal is committed (Phase 1)
5. Developer implements test assertions (Phase 2)
6. Copilot generates implementation code (Phase 3)

This ensures tests define the contract before code exists.

## Example: Compliance Scenario Annotation

```elixir
defmodule IgamingRef.Finance.WithdrawalScenarioTest do
  use ExUnit.Case, async: true
  
  describe "RG-UK-014 — Withdrawal within limit proceeds to review" do
    @moduletag category: :compliance
    @moduletag compliance_links: ["RG-UK-014"]
    @moduletag nodes: ["Finance.WithdrawalTransfer", "Finance.Rules.WithdrawalLimitNotExceeded",
                       "Players.Player", "Finance.Wallet"]
    @moduletag graph_path: ["Players.Player", "Finance.WithdrawalTransfer",
                            "Finance.Rules.WithdrawalLimitNotExceeded", "Finance.Wallet"]
    @moduletag steps: %{
      given: [
        "A player with KYC-verified status",
        "A wallet with balance >= withdrawal amount",
        "The player is not self-excluded"
      ],
      when: ["The player requests a withdrawal within their limit"],
      then: [
        "The withdrawal request is created in :pending state",
        "The player balance is not yet debited",
        "A compliance audit event is logged"
      ]
    }
    
    test "creates withdrawal request in pending state" do
      # Stub before implementation
      :ok
    end
  end
end
```

## Consequences

**Positive:**
- Tests become first-class review artifacts — no code reading required
- Coverage score is visible at a glance (domain score bar)
- Scenarios are linked to graph nodes — flow visualization is immediate
- Compliance requirements (RG-*) are traceable to scenarios
- Non-technical reviewers can understand test intent via Given/When/Then
- Scenario stubs commit before implementation (INV-023 compliance)

**Negative:**
- Test files require disciplined annotation — copilot-enforced via generation templates
- Coverage score calculation requires scenarios; early projects may have partial coverage until scenarios are extracted
- Graph overlay requires JavaScript hook changes (but reuses existing patterns)

**Risk Mitigation:**
- ScenarioExtractor gracefully handles files with no `@moduletag` annotations
- Fallback to alias analysis for `nodes` field when not explicitly declared
- Coverage score formula includes domain count (scenarios present = higher score, encouraging annotation)
