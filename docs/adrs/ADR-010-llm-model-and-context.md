# ADR-010: LLM Selection — Claude Sonnet, Structured Context, Bounded Prompts

**Status:** Accepted  
**Date:** 2026-03  
**Deciders:** Platform team

---

## Context

The copilot engine requires an LLM for three distinct tasks:
1. **Intent classification** — is this a question, a change request, or ambiguous? Which operation?
2. **Proposal generation** — generate the structured content for an Igniter operation
3. **Question answering** — answer domain questions from context

These tasks have different cost, latency, and capability requirements.
The choice of model and context assembly strategy has direct consequences on cost,
hallucination rate, and the quality of proposals.

## Decision

**Primary model: Claude Sonnet (latest stable) for all three task types.**  
**Classification uses a structured output prompt with constrained response format.**  
**Context is assembled from structured retrieval — never by dumping full files.**  
**Prompt size is bounded per task type.**

### Task 1: Intent Classification

Small, fast prompt. Structured output only.

```
System: You are a classifier. Respond only with valid JSON matching this schema:
  {
    "task": "question" | "change" | "ambiguous",
    "operation": <operation_name> | null,
    "confidence": 0.0–1.0
  }

Context: [stack versions — always, ~200 tokens]
         [3 most relevant module DSL summaries — ~600 tokens]

User: [user's message]

Max total context: ~1000 tokens
```

**Confidence threshold:** If `confidence < 0.7`, treat as `"ambiguous"` regardless of the
`task` field value. Ask one clarifying question (INV-005).

**`task == "ambiguous"`**: Ask one clarifying question before proceeding to Tasks 2 or 3.

**Phase gate:** After classification, check the `foundry_change_generation_enabled` config
flag (see §Phase-Gated Behaviour below). If false and `task == "change"`, route to the
`CHANGE_PREVIEW` path instead of Task 2 — describe what would be proposed without executing.

This call is cheap (small context, structured output) and runs before any generation call.

---

### Task 2: Proposal Generation

Full context prompt. Structured output for the operation parameters.

```
System: [AGENTS.md invariants section — always included, ~500 tokens]
        [Stack versions — always included, ~200 tokens]
        [Full spec-kit: all ADRs + runbooks + regulations — always included, ~1500 tokens]
        [ExDoc for the specific DSL elements involved — on-demand, ~400 tokens]
        [Closest existing pattern from codebase — on-demand, ~400 tokens]
        [Module context from mix foundry.context — for affected modules, ~600 tokens]

User: [original intent + any clarification from Task 1]

Max total context: ~3900 tokens system + user message
```

**Note on AGENTS.md:** AGENTS.md is part of the full spec-kit included above. It does not
need to be included separately. The "AGENTS.md invariants" slot is satisfied by the full
spec-kit inclusion.

The operation parameters are extracted from the response as structured JSON.
The Igniter operation module receives parameters, not generated code.
**The LLM generates *what to do*, not the Elixir source.**

After parameter extraction, the ADR contradiction check runs (see §ADR Contradiction Check).

---

### Task 3: Question Answering

Context assembled identically to Task 2 — full spec-kit inclusion, no RAG.

```
System: [Stack versions — always]
        [Full spec-kit: all ADRs + runbooks + regulations — always, ~1500 tokens]
        [Relevant module context from mix foundry.context — for named modules]

User: [question]

Max total context: ~3000 tokens
```

**No RAG for question answering.** The entire spec-kit fits comfortably in context (ADR-003).
RAG would add infrastructure and retrieval failures to a problem that full inclusion solves
trivially. The model sees all constraints on every question — not a similarity-ranked subset
that might miss the relevant ADR. See ADR-003 for full rationale.

Response is prose. No structured output required.

---

## Why Claude Sonnet Specifically

- Structured output / tool use is reliable for the classification and parameter-extraction patterns above
- Context window is sufficient for the bounded prompts above — we never approach the limit
- Cost is acceptable: classification calls are cheap; generation calls are bounded at ~$0.01–0.02
- The ADR contradiction check is a structured classification step, not a separate retrieval pipeline

**No GPT-4, no local models for the initial version.** The copilot's value depends on
consistent quality. Switching models requires re-validating all 20 scaffold operations
against the iGaming reference project — it is a breaking change and requires an ADR update.

---

## The ADR Contradiction Check

Before finalising a Task 2 response, the engine runs one additional structured classification
step. The full spec-kit is already in context. The system prompt asks the model:

```
Given the full spec-kit context already provided, does the proposed action contradict
any ADR or platform invariant? Respond only with valid JSON:
{
  "contradiction": true | false,
  "adr_id": "<id>" | null,
  "summary": "<one sentence explaining the conflict>" | null
}
```

**If `contradiction: true`:**
Block the proposal. Return to the user:
`"This proposal conflicts with [ADR-XXX §Section]: [summary]. Review the ADR before
proceeding. If the ADR is outdated, a human must update it — the constraint cannot be
bypassed from the copilot."`

**If `contradiction: false`:** proceed to Igniter parameter extraction.

This is not a separate API call — it reuses the context already assembled for Task 2.
It is a structured output step that adds negligible latency (~1s) and no token cost beyond
the generation call itself.

---

## Context Window Budget Allocation

Total budget per generation call: **~4000 tokens**.
This is well within any current model's context limit and provides headroom for spec-kit
growth without architectural changes. When the full spec-kit approaches 2000 tokens,
this ADR should be revisited.

| Component | Budget | Slot | Droppable? |
|---|---|---|---|
| Stack versions (mix foundry.versions.check) | ~200 | 1 | Never — INV-006 |
| Full spec-kit (AGENTS.md + ADRs + runbooks + regulations) | ~1500 | 2 | Never |
| Module context (mix foundry.context, up to 5 modules) | ~600 | 3 | Reduce to 2 modules if over budget |
| ExDoc fragments (on-demand, Task 2 only) | ~400 | 4 | First to drop if over budget |
| Codebase pattern example (on-demand, Task 2 only) | ~400 | 5 | Second to drop if over budget |
| User message + turn history (last 3 turns) | ~300 | 6 | Reduce history if needed |
| **Total** | **~3900** | | |

**Drop order when budget is exceeded:**
1. Drop ExDoc fragment (Slot 4)
2. Drop pattern example (Slot 5)
3. Reduce module context from 5 modules to 2 (Slot 3)
4. Reduce turn history from 3 turns to 1 (Slot 6)
5. If still over budget after all drops: return `:context_budget_exceeded` error to the
   user — "This request requires more context than fits in one operation. Try narrowing
   the scope to a single module or domain."

Slots 1 and 2 are never dropped. A request that cannot fit within budget after drops
is rejected, not silently truncated.

---

## Nebulex Cache Strategy

Cache keys, TTLs, and eviction rules are fully specified in ADR-003 §Three-tier library documentation.
Summary: spec-kit documents cached by `{:spec_kit, file_path, mtime}`, ExDoc by `{:exdoc, library, version}` (24h TTL), version manifest by `{:versions, mix_exs_mtime}`.
On budget overflow: spec-kit evicted first, then ExDoc, then version manifest — all via Nebulex L1 (ETS).

## Phase-Gated Behaviour

The `foundry_change_generation_enabled` flag governs the Phase 3 → Phase 4 transition.
This is a **static config value**, not a `fun_with_flags` flag:

```elixir
# config/foundry_studio.exs
# Phase 3 deployment:
config :foundry_studio, change_generation_enabled: false

# Phase 4 deployment:
config :foundry_studio, change_generation_enabled: true
```

`fun_with_flags` is for runtime-togglable feature flags in target platforms. The phase gate
is a deployment-time decision that the platform team sets deliberately — it is not a
per-user or per-environment runtime toggle.

**When `change_generation_enabled: false`:**
- Task 1 (classification) still runs fully
- `task == "change"` routes to `CHANGE_PREVIEW` handler
- The handler runs context assembly and contradiction check, then emits a natural-language
  description of what the operation would do: "I would propose [operation], which would
  create [module] classified as [:behavioral]. The diff would touch [files]. Code generation
  is not yet enabled in this deployment."
- This allows the team to validate classification quality before trusting code output

---

## Error Codes

The copilot engine emits structured errors. These are the canonical codes used in
`studio_copilot_failure.md` and `Foundry.Copilot.Engine`:

| Code | Trigger | User-facing action |
|---|---|---|
| `:context_build_failed` | `mix foundry.context` returned non-zero | "Project may have compilation errors. Run `mix compile`." |
| `:igniter_operation_failed` | Igniter dry-run returned error | "Scaffold operation failed. See runbook: igniter_operation_failure.md." |
| `:llm_api_error` | Anthropic API unreachable or rate-limited | "LLM service unavailable. CLI tools remain functional." |
| `:version_mismatch` | Stack version detection failed | "Run `mix foundry.versions.refresh`." |
| `:adr_contradiction` | Contradiction check returned `true` | Cite the specific ADR/INV. Do not offer to bypass. |
| `:context_budget_exceeded` | Budget exceeded after all drops | "Narrow the request scope to a single module or domain." |
| `:clarification_required` | confidence < 0.7 or task == "ambiguous" | Present the binary-choice clarifying question (INV-005). |

These codes are logged with the full assembled context (minus the user message, which
may contain sensitive domain information) to the Studio's telemetry pipeline.

---

## What the Copilot Never Does

- **Never includes raw source files in context.** Always use `mix foundry.context` structured
  output. A full 200-line Ash resource costs ~1000 tokens and is mostly noise for any
  specific task. Structured introspection provides attribute-level precision at a fraction
  of the token cost.
- **Never generates Elixir source as a string.** The LLM produces operation parameters.
  Igniter produces code. This is INV-002 and INV-003 of ADR-002.
- **Never bypasses the ADR contradiction check.** Even if the model is highly confident,
  the check runs. If the ADR is wrong, the ADR is updated by a human.
- **Never silently truncates context.** Budget overflow is a hard error, not a soft trim.

---

## Consequences

- The model name comes from `config/foundry.exs` under `:llm_model` — not hardcoded
- Changing the model requires an ADR update and re-validation of the full scaffold operation suite
- If the Claude API is unavailable, all four visualization panels continue to function — they do not use the LLM
- The context assembly pipeline (`Foundry.Copilot.ContextBuilder`) is the highest-value component to test — its output quality directly determines proposal quality
- There is no embedding model, no vector database. The system has no ML infrastructure dependency beyond the LLM API
- INV-006 (stack versions always in every prompt) is enforced at the `ContextBuilder` layer — it is structurally impossible to call the LLM without Slot 1 being populated
- The phase gate (`change_generation_enabled`) is what makes Phase 3 ("questions only") and Phase 4 ("proposals") distinct deployments of the same codebase