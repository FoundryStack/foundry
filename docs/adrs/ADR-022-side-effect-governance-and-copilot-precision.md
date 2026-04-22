# ADR-022: Side-Effect Governance, Epistemic Markers, and Copilot Precision

**Status:** Accepted
**Date:** 2026-04
**Deciders:** Platform team
**Amends:** ADR-003 (NodeEntry schema), ADR-013 (copilot behaviour), ADR-016 (step
sub-graph detail), ADR-021 (StepEntry schema)

---

## Context

Four gaps surfaced through working sessions on the iGaming reference project:

1. **Side effects are ungoverned in the graph.** `NodeEntry` tracks `oban_queues` (which
   queue a Reactor *runs on*) but not the side effects it *emits* — Oban job enqueues,
   Ash notifiers, external HTTP calls. A `WithdrawalTransfer` that calls a regulatory API
   is invisible to change-impact analysis and compliance tracing. The lint system cannot
   enforce idempotency on what it cannot see.

2. **The copilot's blocked state is too coarse.** `BLOCKED` covers two fundamentally
   different situations: a request that can proceed once an artifact is created
   (`BLOCKER`), and a request that is architecturally wrong and must be redesigned
   (`REFUSE`). Conflating them forces the human to interpret which situation applies —
   that interpretation belongs in the tool.

3. **Proposal output carries no epistemic signal.** When the copilot proposes a change,
   the reviewer cannot tell which claims are sourced from live DSL introspection
   (`[VERIFIED]`), inferred from context (`[INFERRED]`), or assumed without confirmation
   (`[ASSUMPTION]`). This is the exact information a reviewer needs to know what to
   double-check before approving.

4. **The CodeGenerator retry loop does not distinguish failure modes.** Compile failures
   are retried (correct). Specification gaps — where the agent cannot proceed because
   the spec-kit is silent on the case — are also retried (incorrect). The two failure
   classes need different handlers: retry for implementation failures, escalate for
   specification failures.

ADR-021 extended `StepEntry` with `step_kind`, `target_resource`, and `target_action`.
This ADR adds `side_effects` to `StepEntry`, and `side_effects` to `NodeEntry` for
resource-action-level side effects. It also formalises the copilot precision requirements
above as behavioural rules enforceable in the test suite.

---

## Decision: Side-Effect Governance

### Principle

Side effects are a first-class governed construct in Foundry. They must be declared
before they can be called. An undeclared side effect on a `:sensitive` Reactor is a
lint error. An undeclared side effect on any Reactor is a lint warning. The linter
cannot enforce what it cannot see — declaration is what makes enforcement possible.

### Declaration surfaces (annotation-first strategy)

**Ash `notifier` and `change` DSL entries** — already introspectable via `spark_meta`.
These are automatically promoted to `SideEffectEntry` structs in the context output.
No new DSL required; use native Ash:

```elixir
defmodule MyApp.Finance.Wallet do
  use Ash.Resource
  
  actions do
    create :credit do
      change MyApp.Changes.RecordCredit
      notifier MyApp.Notifiers.BalanceChange
    end
  end
end
```

**Oban job enqueues and external HTTP calls** — declared via a comment annotation
above the `run/2` callback in the step module. The linter scans for this annotation.
If a step module imports `Oban` or HTTP clients but lacks the annotation, it's a
lint warning (or error on `:sensitive` Reactors). This keeps the step module as the
single source of truth without requiring a new DSL:

```elixir
defmodule MyApp.Steps.EnqueueFraudCheck do
  # @side_effect oban_emit: FraudCheck, queue: risk, idempotent: true, key_from: [:transfer_id]
  def run(%{transfer_id: tid} = args, _context, _state) do
    Oban.insert(MyApp.Workers.FraudCheck.new(%{transfer_id: tid}))
    {:ok, %{enqueued: true}}
  end
end
```

The annotation is not evaluated at compile time. It is purely for linter consumption
and as a breadcrumb for developers reading the code. The linter's `put_side_effects/1`
stage parses it via AST scan.

### Governance rule: one side effect per action

An Ash resource action may have at most one `notifier` and at most one `change` that
produces a side effect. If an operation requires multiple side effects, it must be
modelled as a Reactor — where each side effect is a named step, individually
observable in telemetry, and compensatable.

This is INV-019 (see §New Invariants).

### SideEffectEntry struct

A new `SideEffectEntry` struct added to `NodeEntry`:

```json
{
  "type": "oban_emit | ash_notifier | external_http",
  "name": "EnqueueFraudCheck",
  "declared_on": "step | resource_action",
  "step_name": "enqueue_report",
  "action": null,
  "job_module": "MyApp.Workers.FraudCheck",
  "module": null,
  "queue": "risk",
  "trigger": null,
  "idempotent": true,
  "idempotency_key_from": ["transfer_id"],
  "declared": true,
  "epistemic": "VERIFIED"
}
```

Fields:
- `declared_on` — `"step"` or `"resource_action"`. Determines whether compensation is
  possible (step-level side effects can be compensated via `compensate/4`; resource-action
  level side effects cannot, which is a signal the action should become a Reactor).
- `declared` — `true` if an annotation or DSL entry exists. `false` if inferred by the
  linter from import/alias analysis. A `false` entry is a lint violation.
- `epistemic` — `"VERIFIED"` if extracted from annotation or live DSL. `"INFERRED"` if detected
  heuristically. The linter always flags `INFERRED` entries for follow-up.

### NodeEntry schema amendment

`NodeEntry` gains a top-level `side_effects: [SideEffectEntry]` field (empty list
default — non-breaking). For Reactors and Transfers, step-level side effects are
also nested under `steps[].side_effects` (see §StepEntry amendment below).

### StepEntry amendment (extends ADR-021)

`StepEntry` gains:

```json
"side_effects": [
  {
    "type": "oban_emit",
    "name": "EnqueueFraudCheck",
    "declared_on": "step",
    "idempotent": true,
    "declared": true,
    "epistemic": "VERIFIED"
  }
]
```

This is the field the detail drawer renders in the step expansion view.

### Extraction pipeline

- `ash_notifier` and `change` entries: extracted by `spark_meta` from existing Ash
  DSL introspection. Already available — this ADR promotes them into `SideEffectEntry`
  structs rather than leaving them as raw text.
- `oban_emit` and `external_http` with `declared: true`: extracted by the linter's
  `put_side_effects/1` stage via comment annotation AST scan. The annotation format
  is `# @side_effect <type>: <name>, <field>: <value>, ...` on the line immediately
  before the `def run/3` callback.
- Undeclared heuristics: the linter checks step modules for imports/aliases of
  `Oban` and HTTP clients (`Req`, `Finch`, `HTTPoison`, `Tesla`). Any step module with
  such an import that lacks a corresponding annotation comment emits a lint violation
  with `declared: false` and `epistemic: "INFERRED"`.

---

## Decision: Epistemic Markers on Proposal Output

When the copilot proposes a change, each substantive claim in the proposal annotation
(not the generated code itself) carries one of three markers:

| Marker | Meaning |
|---|---|
| `[VERIFIED]` | Sourced from live DSL introspection (`mix foundry.project.context`) or explicit spec-kit text |
| `[INFERRED]` | Reasoned from context — closest existing pattern, naming conventions, domain structure |
| `[ASSUMPTION]` | Not confirmed by any source. The reviewer must verify before approval |

**Where markers appear:** In the review panel's "Impact" tab annotation, not in the
generated diff itself. The diff is code; the annotation is the copilot's reasoning.

**Format:**

```
Impact annotation for debit_wallet step:
  Field type `Ash.Type.Money` [VERIFIED — mix foundry.exdoc Ash.Type.Money]
  Idempotency key `transfer_id` [VERIFIED — existing pattern: CreditTransfer]
  Naming convention `debit_and_record` [INFERRED — matches existing Wallet action names]
  Compliance link RG-UK-014 [ASSUMPTION — not yet confirmed against regulation text]
```

**`[ASSUMPTION]` triggers a pre-approval warning** in the review panel: the proposal
is approvable but the warning is shown alongside the diff. The reviewer must explicitly
dismiss `[ASSUMPTION]` warnings before the Approve button is enabled. This is a UI
gate, not a hard block.

---

## Decision: `BLOCKER` vs `REFUSE` Distinction

The current `BLOCKED` state is split into two response types with different meanings
and different UX:

### `BLOCKER` — blocked, but unblockable by creating an artifact

The request is valid but cannot proceed until a prerequisite exists. The path forward
is concrete and actionable.

```
This proposal cannot proceed yet.
Reason: [one sentence on what is missing].
To unblock: [one sentence on what artifact/change resolves it — with a direct action].

[Create ADR for this case ↗]   [Continue without ADR (structural only)]
```

Applies when:
- A `:compliance` change has no ADR link (unblocked by: create ADR → link it)
- A new external integration has no runbook (unblocked by: create runbook)
- A spec-kit gap prevents safe generation (unblocked by: `speckit.clarify` resolves gap)

### `REFUSE` — the request itself must be redesigned

The architecture of the request conflicts with an invariant or ADR. No artifact creation
fixes it. The request must change.

```
This proposal cannot proceed.
Reason: [one sentence on the specific conflict].
Conflicts with: [ADR/INV reference, quoted rule].
To redesign: [one sentence on the correct architectural direction].
```

Applies when:
- The request would produce multiple side effects in a single resource action (INV-019)
- The request contradicts a `BLOCKED` ADR decision
- The request would remove a `human_gate` from a compliance-gated Reactor (INV-015)

**Both formats remain terse.** No apology. No hedging. The distinction between them
is informational, not a softening.

---

## Decision: Pre-Mortem Block in Review Output

When a proposal contains a Reactor or Transfer with external side effects, the review
panel's Impact tab includes a lightweight pre-mortem summary before the diff:

```
Pre-mortem (WithdrawalTransfer)
  RaceConditionCheck:       WARN — step enqueue_report has undeclared external_http
  IdempotencyCheck:         PASS — transfer_id declared on debit_wallet
  PolicyContradictionCheck: PASS
  CompensationCheck:        WARN — enqueue_report has no compensation path
```

**Check definitions:**

| Check | PASS condition | WARN condition |
|---|---|---|
| `RaceConditionCheck` | All steps with external side effects have idempotency keys | Any step with `side_effects[].idempotent: false` on a `:sensitive` Reactor |
| `IdempotencyCheck` | All steps with `type: external_http` or `type: oban_emit` declare `idempotency_key_from` | Missing declaration |
| `PolicyContradictionCheck` | No conflicting policy conditions detected across steps in the same Reactor | Conflicting conditions |
| `CompensationCheck` | All write steps and side-effect steps have a `compensate/4` callback | Write/side-effect step without compensation on a `:sensitive` Reactor |

A `WARN` does not block approval — it surfaces in the Impact tab with a dismiss option.
A `WARN` on a `:sensitive` Reactor upgrades to an `ERROR` and blocks approval until
dismissed by the Sensitive lead. This aligns with the dual-approval requirement for
`:sensitive` changes in ADR-005.

---

## Decision: Spec-Gap Escalation in CodeGenerator

The `CodeGenerator` sub-agent currently has one failure path: compile failure → retry
(max 3) → `APPLY_FAILED`. This ADR adds a second typed failure:

```elixir
{:error, :compile_failure, details}   # retry-eligible — max 3
{:error, :spec_gap, description}      # escalate immediately — no retry
```

A `spec_gap` failure fires when the agent, during the generation pass, encounters a
design decision that the spec-kit does not cover and cannot safely be inferred. Examples:
- The step requires an idempotency strategy, but the project has no pattern for this
  type of external call
- A compliance link is needed but the regulation file does not exist yet
- A new resource relationship implies a policy decision that no ADR covers

**On `{:error, :spec_gap, description}` the orchestrator:**

1. Aborts the branch (`git branch -D foundry/prop_<id>`) — no partial state
2. Does **not** retry — spec gaps do not resolve by regenerating
3. Surfaces a structured `BLOCKER` response (per §Decision: `BLOCKER` vs `REFUSE`):
   "I couldn't complete this change. The spec needs to cover: [description]. My
   interpretation is [X]. Should I draft an ADR for this case, or clarify the existing one?"
4. Routes to `speckit.clarify` — the one permitted clarifying question (INV-005 still
   applies; the escalation produces one structured question, not a multi-turn loop)

**This does not change the max-3 retry behaviour for compile failures.** The split is
purely about routing: implementation failures retry, specification failures escalate.

---

## New Invariants

**INV-019: Resource actions may have at most one side effect**
An Ash resource action may have at most one `notifier` and at most one `change` that
produces a side effect. If an operation requires multiple side effects, it must be
modelled as a Reactor. Lint error on `:sensitive` resources; lint warning elsewhere.
Rationale: multiple side effects in one action means partial failure is
uncompensatable. A Reactor gives each side effect a named step, a telemetry span,
and a `compensate/4` path.

**INV-020: External HTTP calls on sensitive Reactors must declare idempotency**
Any `side_effect` with `type: external_http` on a Reactor or Transfer whose containing
resource is `:sensitive` must declare `idempotency_key_from`. Lint error. Rationale:
idempotency is a correctness requirement on sensitive financial flows, not a best
practice.

---

## Amendments to Existing ADRs

### ADR-003 §`mix foundry.project.context` Schema

Add to NodeEntry schema:

```json
"side_effects": [
  {
    "type": "oban_emit | ash_notifier | external_http",
    "name": "string",
    "declared_on": "step | resource_action",
    "step_name": "string | null",
    "action": "string | null",
    "job_module": "string | null",
    "module": "string | null",
    "queue": "string | null",
    "trigger": "string | null",
    "idempotent": "bool",
    "idempotency_key_from": ["string"],
    "declared": "bool",
    "epistemic": "VERIFIED | INFERRED"
  }
]
```

Add to `StepEntry` (within `steps[]`):

```json
"side_effects": [SideEffectEntry]
```

Both fields default to `[]`. Non-breaking.

### ADR-013 §Epistemic Contract

Append to "The copilot always:" list:

- Tags every substantive claim in proposal annotation with `[VERIFIED]`, `[INFERRED]`,
  or `[ASSUMPTION]` (see ADR-022 §Epistemic Markers)
- Emits a pre-mortem summary in the review panel Impact tab for any proposal touching
  a Reactor or Transfer with external side effects (see ADR-022 §Pre-Mortem Block)

Replace the single `BLOCKED` response format with two formats per ADR-022
§`BLOCKER` vs `REFUSE`.

### ADR-013 §Error Recovery Responses

Add new error code:

```
:spec_gap_escalation
```

```
I couldn't complete this change. The spec needs to cover: [description].

My interpretation: [X — with source citation].

[Draft ADR for this case ↗]   [Clarify existing ADR ↗]
```

### ADR-016 §Compound Node Expand/Collapse

Append to "Reactor/Transfer step sub-graphs" paragraph:

> Each expanded step node renders its `side_effects[]` as subordinate pill nodes
> attached below the step. Pills use the coral ramp for undeclared side effects and
> the teal ramp for declared. Clicking a pill opens the `SideEffectEntry` detail in
> the right drawer. A `declared: false` pill also renders the INV violation badge (⚠)
> inline. This makes the governance gap visible at the graph topology level, not only
> in a terminal lint output.

### ADR-021 §StepEntry Extended Fields

Append new field row to the StepEntry table:

| Field | Source | Notes |
|---|---|---|
| `side_effects` | Annotations and `spark_meta` Ash notifier/change walk | List of `SideEffectEntry`; empty list if none |

Append to §Consequences → Positive:

- **Side effects visible in graph**: `declared: false` side effects render as ⚠ pill
  nodes in the step sub-graph; change-impact analysis can now answer "what external
  systems does this Reactor touch?"

---

## Consequences

- `INV-019` and `INV-020` are new lint rules; they are warnings on first merge of this
  ADR and become errors after a 2-sprint grace period to allow existing code to be
  annotated
- The annotation-first strategy for `oban_emit` and `external_http` side effects
  requires no new DSL — all declaration uses existing Ash DSL or simple comment annotations
- The `BLOCKER` / `REFUSE` split requires updating the copilot test suite — all existing
  `BLOCKED` test cases must be reclassified into one of the two new types
- `[ASSUMPTION]` warnings in the review panel require a dismiss interaction; the approval
  flow for proposals with `[ASSUMPTION]` annotations is slightly longer — this is
  intentional friction, not a bug
- The spec-gap escalation path means some requests that previously reached `APPLY_FAILED`
  after 3 retries will now surface as `BLOCKER` after 0 retries — faster feedback, less
  wasted compute
