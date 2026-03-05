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
  {"task": "question"|"change"|"ambiguous", "operation": <operation_name>|null, "confidence": 0-1}

Context: [stack versions, 3 most relevant DSL summaries — max 2000 tokens total]
User: [user's message]
```

If `confidence < 0.7`: the operation is ambiguous. Ask one clarifying question.
If `task == "ambiguous"`: ask one clarifying question before proceeding.

This call is cheap (small context, structured output) and runs before the expensive generation call.

### Task 2: Proposal Generation

Full context prompt. Structured output for the operation parameters.

```
System: [AGENTS.md invariants section — always included, ~500 tokens]
        [Stack versions — always included, ~200 tokens]
        [Relevant ADR summaries — retrieved by topic, max 3 ADRs, ~600 tokens]
        [ExDoc for the specific DSL elements involved — on-demand, ~400 tokens]
        [Closest existing pattern from codebase — on-demand, ~400 tokens]
        [Module context from mix foundry.context — for affected modules, ~600 tokens]

User: [original intent + any clarification]

Max total context: ~3000 tokens system + user message
```

The operation parameters are extracted from the response as structured JSON.
The Igniter operation module receives parameters, not generated code.
The LLM generates *what to do*, not *the Elixir source*.

### Task 3: Question Answering

Context assembled from structured retrieval + RAG over docs.

```
System: [Stack versions]
        [Relevant module context from mix foundry.context]
        [Relevant ADR/runbook text from RAG index — max 3 chunks]

User: [question]

Max total context: ~2000 tokens
```

Response is prose. No structured output required.

## Why Claude Sonnet Specifically

- Tool use / structured output is reliable and well-tested
- Context window is sufficient for the bounded prompts above — we never approach the limit
- The ADR contradiction check (querying the RAG index against the proposal) is a tool use pattern that works well
- Cost is acceptable for the usage pattern: classification calls are cheap, generation calls are bounded

**No GPT-4, no local models for the initial version.** The copilot's value depends on
consistent quality. Switching models is a breaking change to the agent's behaviour and
must be treated as such — it requires re-validating all scaffold operations.

## The ADR Contradiction Check

Before finalising a generation response, the copilot performs one additional structured step.
All ADRs are already in context (full inclusion per ADR-003). The classifier prompt asks:

```
Given the full spec-kit context already provided, does the proposed action contradict
any ADR or platform invariant? Respond with JSON:
{"contradiction": true|false, "adr_id": "<id>"|null, "summary": "<why>"|null}
```

If `contradiction: true`:
  Block the proposal. Return: "This proposal conflicts with [ADR-XXX]: [summary].
  Review the ADR before proceeding."

This is not a separate retrieval call — the spec-kit is already in context.
It is a structured classification step on content the model has already read.

## Context Window Budget Allocation

Total budget per generation call: ~4000 tokens (well within any current model's limits,
ensuring headroom for future growth without architectural changes).

| Component | Budget | Source |
|---|---|---|
| AGENTS.md invariants | ~500 | Static, always included |
| Stack versions | ~200 | From mix.exs, always included |
| Full spec-kit (ADRs + runbooks + regulations) | ~1500 | Read from disk, mtime-cached |
| ExDoc fragments | ~400 | On-demand fetch, per-library cache |
| Codebase pattern example | ~400 | PatternFinder, on-demand |
| Module context | ~600 | mix foundry.context |
| User message + history | ~300 | Runtime |
| **Total** | **~3900** | Within 4000 token budget |

Note: AGENTS.md invariants are a subset of the full spec-kit. When the full spec-kit
is included, AGENTS.md does not need to be included separately — it is already present.

## Consequences

- The model name is not hardcoded in application logic — it comes from `config/foundry.exs` under `:llm_model`
- Changing the model requires an ADR update and re-validation of the scaffold operation test suite
- If Claude API is unavailable, the copilot is offline; all four visualization panels continue to function (they do not use the LLM)
- Cost is predictable: classification calls ~$0.001, generation calls ~$0.01-0.02 per proposal
- The context assembly pipeline (`Foundry.Copilot.ContextBuilder`) is the highest-value component to test — its output quality directly determines proposal quality
- There is no embedding model, no vector database, no RAG pipeline. The system has no ML infrastructure dependency beyond the LLM API itself.
- **Critical rule: never include raw source files in context.** Always use `mix foundry.context` structured output. A full 200-line Ash resource in context costs ~1000 tokens and is mostly noise for the specific task. Structured introspection gives attribute-level precision at a fraction of the token cost.