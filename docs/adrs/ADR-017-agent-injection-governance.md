# ADR-017: Agent Injection Governance

**Status:** Accepted  
**Date:** 2026-03  
**Deciders:** Platform team  
**Supersedes:** ADR-001 §Out of Scope — "AshAI DSL introspection" item

---

## Context

ADR-001 deferred AshAI integration ("Foundry v1 will not fail on AshAI declarations —
it will ignore them and warn") on the grounds that the AshAI DSL was not stable enough
to freeze in the `mix foundry.context` schema.

The design questions are now resolved. The AshAI DSL is stable, the Reactor orchestration
model for agents is clear, the agent taxonomy is established, and the governance requirements
for regulated domains (human-in-the-loop gates, confidence thresholds as change-class
triggers, tool access governance) are understood. This ADR supersedes the deferral.

AshAI + Ash.Reactor is the correct and complete stack for agent injection in Foundry
target platforms. No Python framework, no LangGraph, no CrewAI. The infrastructure is:

```
AshAI          — prompt-backed Ash actions, tool declaration, vector search
Ash.Reactor    — orchestration, parallelism, compensation, dependency ordering
LangChain.ex   — LLM protocol (model selection, streaming, tool call protocol)
```

Foundry adds: governance, visualization, telemetry, and human-in-the-loop gate management.

---

## Decision

### Agent Steps Are First-Class Reactor Constructs

An agent step is an `Ash.Reactor` step whose implementation module is annotated with
Foundry governance metadata. It calls an AshAI prompt-backed action. It is not a separate
concept from a Reactor step — it is a step that happens to use an LLM to compute its
output. The Reactor handles parallelism, retry, compensation, and dependency ordering
exactly as for non-agent steps.

Governance metadata is declared on the **step implementation module**, not inline in the
Reactor DSL. This preserves the standard `Ash.Reactor` step syntax and avoids patching
the Reactor DSL — a coupling that would break on Ash upgrades. Foundry introspects the
module's Spark declarations to derive the governance fields for visualization, lint, and
`mix foundry.context`.

```elixir
# The step implementation module — carries Foundry governance metadata
defmodule MyApp.Risk.AgentSteps.ScoreRisk do
  use Foundry.AgentStep

  agent_type :scorer
  model :claude_sonnet
  confidence_threshold 0.7
  on_low_confidence :escalate_human
  human_gate queue: :compliance_review, sla_hours: 4
  tools [:read_player_history, :check_velocity, :read_spending_limit]
  telemetry_prefix [:my_app, :risk, :withdrawal, :risk_score]

  @impl true
  def run(args, _context) do
    MyApp.Risk.RiskAssessment
    |> Ash.ActionInput.for_action(:score_risk, args)
    |> Ash.run_action()
  end
end

# The Reactor — standard Ash.Reactor syntax, unchanged
defmodule MyApp.Risk.WithdrawalRiskReactor do
  use Reactor, extensions: [Ash.Reactor]

  step :risk_score, MyApp.Risk.AgentSteps.ScoreRisk do
    argument :transaction, input(:transaction)
    argument :player, input(:player)
  end
end
```

`use Foundry.AgentStep` is a Spark DSL extension that Foundry provides. It adds the
`agent_type`, `model`, `confidence_threshold`, `on_low_confidence`, `human_gate`, `tools`,
and `telemetry_prefix` DSL sections to the module. These are Foundry-specific — they are
not part of core AshAI or Ash.Reactor. The `run/2` callback is standard `Reactor.Step`
behaviour.

### Agent Taxonomy — 10 Types

Every agent step must declare one of these 10 `agent_type` values. The type determines
what telemetry fields are expected, what detail drawer template is rendered, and what
lint rules apply.

| Type | Purpose | Key output field | Compliance notes |
|---|---|---|---|
| `classifier` | Labels/categorises incoming data | `category: atom` | Low governance — fast, automated |
| `extractor` | Pulls structured data from unstructured input | `result: typed_struct` | Low — data pipeline |
| `scorer` | Produces a numeric assessment | `score: float, factors: [str], confidence: float` | Medium — drives decisions |
| `decision` | Makes a binary or multi-way choice | `action: atom, reason: str, confidence: float` | HIGH — may block flow; human gate required on compliance paths |
| `advisor` | Produces a recommendation | `response: str, citations: [str], escalate: bool` | Medium — human always reviews |
| `observer` | Monitors a stream and flags anomalies | `alert: struct | nil` | Low — passive until alert |
| `enricher` | Adds context to an existing entity | `enhanced_record: struct` | Low — additive |
| `router` | Determines which path a flow takes | `next_step_id: str` | Medium — structural |
| `summarizer` | Compresses history or events | `summary: str, key_facts: [str]` | Low — informational |
| `orchestrator` | Manages other agents, synthesises results | `completed_result: any` | HIGH — multi-agent; separate approval chain required |

### Change Classification for Agent Constructs

| Change | Class | Rationale |
|---|---|---|
| Adding an `agent` step to a Transfer or Reactor | `:behavioral` | New LLM call in a flow; requires domain lead approval |
| Changing `agent_type` | `:behavioral` | Different output schema and telemetry contract |
| Changing `model` | `:behavioral` | Different capability and cost profile |
| Changing `confidence_threshold` | `:behavioral` | Affects how often human gate triggers |
| Changing `on_low_confidence` handler | `:behavioral` | Changes fallback behaviour |
| Adding/removing tools from `tools` list on a compliance-gated resource | `:compliance` | Expands/contracts agent authority; ADR required |
| Removing a `human_gate` from a compliance-gated decision step | `:compliance` | Removes human oversight; ADR required |
| Changing `human_gate` SLA | `:behavioral` | Governance timeline change |
| Changing prompt content in a prompt-backed AshAI action | `:behavioral` | Affects output semantics |
| Adding an `agent` step to a `:sensitive` resource's Transfer | `:sensitive` | Dual approval required |

### Human Gate Specification

A `human_gate` declaration on an agent step creates a review task in the configured queue
when the agent's confidence falls below threshold, or always for `decision` steps on
compliance-gated paths regardless of confidence. The gate:

1. Halts the Reactor step and returns `:waiting_for_human`
2. Creates an `HumanGateTask` record (an Ash resource with `ash_oban` background processing)
3. Assigns the task to the configured queue with the declared SLA
4. When a human approves or overrides, the Reactor step resumes with the human's decision
5. The override is recorded in the audit log with `actor`, `timestamp`, `original_agent_decision`, and `human_decision`

**HumanGateTask resource ownership:** `HumanGateTask` is scaffolded into the *target
platform* — not into Foundry itself — because it holds domain-specific review records that
belong in the platform's audit trail. `Op.AddAgentStep` checks for the resource's existence
and scaffolds it into the target platform on first use if absent. Because `HumanGateTask`
is always `:sensitive`, this scaffold operation requires dual approval (ADR-005) before it
is applied. Implementers should expect this: the first agent step added to any project
triggers a two-step proposal — the `HumanGateTask` resource creation (`:sensitive`, dual
approval) followed by the agent step itself (`:behavioral`, domain lead approval). Both
proposals are shown together in the review panel with their distinct approval requirements.

The `HumanGateTask` resource is always `:sensitive` (INV-001). Override audit records are
permanent and require `ash_paper_trail` (INV-011) and soft delete only (INV-012).

The override rate (percentage of agent decisions changed by a human reviewer) is a key
quality signal surfaced in the Agent Health panel (Phase 8). A rising override rate
triggers a lint warning recommending prompt review. The threshold for this warning is
configurable per project via `manifest.exs` under `agent_governance.override_rate_warn_threshold`
(default: 0.20). A project-specific threshold must be documented in an ADR when it deviates
from the default.

### Lint Rules Added by ADR-017

The following lint rules are enforced by `Foundry.Lint.AgentStepChecker`:

- **agent_confidence_threshold_required**: `decision` and `scorer` steps must declare `confidence_threshold`
- **agent_human_gate_required**: `decision` steps on compliance-gated paths must declare `human_gate`
- **human_gate_only_on_gatable_types**: `human_gate` may only be declared on `decision` and `advisor` types; declaring it on `observer`, `summarizer`, `classifier`, `extractor`, `enricher`, or `router` types is a lint error — these types do not block flow and a halting gate contradicts their semantics
- **agent_tools_declared**: `tools` list must be non-empty; undeclared tool usage is a lint error
- **agent_telemetry_prefix_required**: `telemetry_prefix` must be declared on all agent steps
- **agent_type_declared**: `agent_type` must be one of the 10 canonical values
- **orchestrator_approval_chain**: `orchestrator` type steps require a separate `:behavioral` proposal; cannot be added in the same proposal as other agent steps

### Visualization — Agent Steps on the Canvas

Agent steps appear as inline step nodes inside the swimlane of their containing Transfer
or Reactor. They are NOT top-level canvas nodes.

The inline step node:
- Icon: `⊕`
- Label: step name + agent type label (e.g., "risk_score · scorer")
- Sub-label: model name + p95 latency + error rate (from telemetry)
- Confidence indicator: threshold value, current mean confidence

When confidence falls below threshold, the step node shows a `⬡ human_gate` branch in the
swimlane, with the queue name and SLA. This makes human oversight points visible in the
flow without navigating to the detail drawer.

The detail drawer for an agent step shows the type-specific template (see below by type).
All templates include: input/output schema, model, tool access list, confidence distribution
histogram, and — for `decision` type — the override rate.

**Per-type drawer content:**

`classifier` — distribution of output categories (last 24h), accuracy against labeled
samples if ground truth exists.

`scorer` — score distribution histogram (last 7d), top factors in high-score cases,
calibration metric (mean confidence vs actual accuracy).

`decision` — decision distribution, human escalation count, override rate. The override
rate is prominently displayed; it is the primary quality signal.

`observer` — current state (nominal/alerting), alert history (30d), alert routing
configuration.

`advisor` — resolution rate, average handle time, escalation rate, citation accuracy.
Human-in-the-loop is always-on for `advisor` type.

`enricher`, `extractor`, `summarizer` — throughput, error rate, latency.

`router` — routing distribution across paths (last 7d).

`orchestrator` — sub-agent coordination graph (shows which agents it orchestrates and
in what order), total cost/run, total latency.

### AshAI Version Requirement

AshAI 2.x or later is required for the Foundry DSL extension to function. The
`mix foundry.context` task reads the AshAI version from `mix.exs` as part of the version
manifest (INV-006). If AshAI is present but older than 2.x, the task warns and skips
agent step introspection — it does not fail.

Projects that do not use AshAI are unaffected. The `agent_steps` field in the context
schema is an empty list `[]` for all modules in such projects.

### Relationship to AshAI Domain DSL

The `tools` declaration in the Foundry agent step DSL maps to AshAI's domain-level tool
declaration:

```elixir
defmodule MyApp.Finance do
  use Ash.Domain, extensions: [AshAi]
  tools do
    tool :check_balance,    MyApp.Finance.Wallet,       :read
    tool :flag_transaction, MyApp.Finance.Transaction,  :flag
  end
end
```

Foundry's lint rule `agent_tools_declared` cross-references the `tools` list on each
agent step against the domain's AshAI tool declarations. A tool referenced in an agent
step but not declared in the domain is a lint error. A tool declared in the domain but
never referenced by any agent step generates a lint warning (dead tool declaration).

---

## Consequences

- ADR-001's deferral of AshAI is superseded. AshAI 2.x+ is now in the "conditionally
  present" category (project declares opt-in in manifest). Projects that opt in gain
  agent step governance; projects that do not are unaffected.
- The `mix foundry.context` schema gains an `agent_steps` field (documented in AGENTS.md
  and ADR-003 addendum). This is a non-breaking addition — the field is `[]` when absent.
- Phase 8 of BUILD_SEQUENCE (Agent Health panel) is the implementation milestone for
  the observability surface defined here.
- `orchestrator` agent type steps require a separate `:behavioral` proposal because they
  introduce coordination topology. This prevents an orchestrator from being added quietly
  inside a larger proposal.
- Human gate override records are permanent and `:sensitive`. They require audit logging
  via `ash_paper_trail` (INV-011) and soft delete only (INV-012). They are runtime records,
  not code change proposals — ADR-005 dual-approval applies to the scaffold of the
  `HumanGateTask` resource itself (see Human Gate Specification above), not to individual
  override records created at runtime.

---

## What This Is Not

This ADR does not govern which LLM models are available, API key management, or token
budget allocation. Those are ADR-010 concerns. It does not govern the copilot agent
behaviour (ADR-013). It governs the injection of AI agents into target platform domain
flows — the thing that target platforms build with Foundry, not Foundry's own copilot.