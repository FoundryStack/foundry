# ADR-010: LLM Selection — Claude Sonnet, Agentic Context Model

**Status:** Accepted
**Date:** 2026-03
**Deciders:** Platform team
**Supersedes:** ADR-010 v1 (fixed-slot budget model)

---

## Context

The copilot engine requires an LLM for three distinct tasks:
1. **Intent classification** — question, change, or ambiguous?
2. **Proposal generation** — structured parameters for an Igniter operation (Phase 4+)
3. **Question answering** — answer domain questions from context

The original ADR-010 specified a fixed 6-slot context assembly model. This has been
superseded by an agentic loop model: the agent has a shell, uses Mix tasks directly,
and fetches what it needs rather than receiving a pre-assembled fixed window.

---

## Decision

**Primary model: Claude Sonnet (latest stable) for all task types.**
**The agent operates in a single agentic loop with a bash tool.**
**Context is assembled in three tiers: system prompt, session snapshot, retrieved via shell.**

---

## Intent Classification

Classification is the **first reasoning step of the main agent loop** — not a separate
pre-LLM API call. The agent classifies the user's message as its opening reasoning step
before any tool calls.

**Four intent types:**

- `question` — user asks about current system state. Indicators: interrogative syntax,
  question marks, no imperative change verb.
- `change` — user wants to modify the system. Indicators: imperative verbs (add, create,
  update, remove, generate, link), description of desired future state.
- `speckit` — user asks to draft or update an ADR, runbook, or regulation. Indicators:
  "write an ADR", "update the runbook", "add a regulation entry". Produces a plain-text
  proposal; no Igniter call.
- `ambiguous` — message contains both question and change indicators, or neither.
  Routes to the one-clarifying-question path (INV-005).

**Confidence threshold:** When the agent's confidence in its classification is below 0.7,
it treats the intent as `ambiguous` regardless of which type it leans toward.

**Phase gate:** After classification, the agent checks `change_generation_enabled`.
If `false` and intent is `change`: produce a `CHANGE_PREVIEW` response describing the
operation without generating a diff (Phase 3 only — see §Phase-Gated Behaviour).

Classification and confidence are emitted in the reasoning trace:
```json
"intent_classification": {
  "task": "change",
  "confidence": 0.91
}
```

No separate API call. No `IntentClassifier` module.

---

## Context Model — Three Tiers

The copilot operates with a three-tier context model. Each tier has different
assembly timing, caching behaviour, and token characteristics.

---

### Tier 1 — System Prompt (assembled once per Studio session)

Loaded by `Foundry.Copilot.ContextBuilder` at Studio startup. Reloaded only on
Studio restart or stack version change detection.

| Component | Token bound | Source | Cache key |
|---|---|---|---|
| AGENTS.md | ~800 | File read | `{:spec_kit, path, mtime}` |
| Stack versions | ~200 | `mix foundry.versions.check` | `{:versions, mix_exs_mtime}` |
| Spec-kit index | ~400 | `.foundry/spec_kit_index.json` | `{:spec_kit_index, index_mtime}` |
| **Tier 1 total** | **~1400** | | |

AGENTS.md is the agent's constitution — invariants, orientation, spec-kit task postures,
shell constraints, key Mix task reference. It is never dropped or summarised.

The spec-kit index gives the agent a map of all spec-kit documents (ADRs, runbooks,
regulations, usage rules) with summaries and tags. The agent reads this directly from
context to decide which documents to read via bash. No search tool needed.

INV-006 is enforced at ContextBuilder initialisation — structurally impossible to start
the agent loop without stack versions in the system prompt.

---

### Tier 2 — Session Snapshot (refreshed per copilot request)

A single compact JSON object assembled by `Foundry.Copilot.ContextBuilder` at the
start of each request. 60-second TTL. Reflects current project state.

**Source:** `mix foundry.project.snapshot`
**Token bound:** ≤ 400 tokens
**Schema:** `docs/mix_task_summary_schemas.md`

Contains: domain list, sensitive module names, project structure shape (workers,
integrations, web layer), health signals (lint errors, open proposals, compliance gaps,
pending migrations), key file digest (core deps from mix.exs, approver from manifest).

**Why a snapshot replaces eight separate components:** Earlier drafts assembled domain
map, compliance summary, lint status, open proposals, pending migrations, project
structure, mix.exs, and manifest.exs separately (≤ 900 tokens total). The snapshot
gives the same orientation signal in ≤ 400 tokens with one assembly call and one
cache entry. When the agent needs depth on any component, it uses bash.

---

### Tier 3 — Shell and Tools (fetched on demand during the agent loop)

The agent has access to two interfaces for retrieving context during the loop:

**bash(command)** — a shell with a permitted command list (see §Shell Constraints).
This is the primary retrieval interface. The agent uses standard Unix tools and Mix
tasks to read files, search source, run the compiler, check lint, and fetch API docs.

```bash
# Read any file
cat docs/adrs/ADR-005-change-approval-model.md
cat lib/my_app/workers/payment_processor.ex
cat .foundry/usage_rules/ash.md

# Search across source
grep -rn "def handle_payment" lib/ --include="*.ex"
grep -B3 -A50 "defmodule.*Wallet" lib/my_app/finance/wallet.ex

# Navigate structure
ls lib/my_app/integrations/
find lib/ -name "*.ex" -path "*/workers/*"

# Semantic module introspection
mix foundry.context MyApp.Finance.Wallet --json

# API reference at pinned version
mix foundry.exdoc Ash.Resource.Attribute --function allow_nil?

# Pattern finding
mix foundry.pattern.find rule --domain Finance

# Verify writes
mix compile 2>&1
mix foundry.lint.all --json
mix test test/my_app/finance/wallet_test.exs 2>&1
```

**Two structured tools** for operations the shell cannot replicate with equivalent quality:

| Tool | Returns | Token bound | Rationale |
|---|---|---|---|
| `mix foundry.pattern.find <type> [--domain D]` (via bash) | Top-ranked existing DSL example — see §Pattern Selection | 400 | Ranking algorithm encodes domain logic: same type, same domain, most attributes, has tests, not sensitive. Deterministic and unit-testable. |
| `mix foundry.operation.schema <Op>` (via bash) | Parameter contract for a catalogue operation | 300 | Operations are documented in `.foundry/usage_rules/foundry_operations.md` but the Mix task provides structured JSON for programmatic use. |

Both are Mix tasks called via bash — not separate tool schemas. The agent calls them
like any other Mix task. The distinction from arbitrary bash is that their output
format is specced and stable.

**Circuit breaker:** `max_tool_calls` per request (default 8, manifest key
`copilot.max_tool_calls`). If reached without resolution: `:context_budget_exceeded`.
Safety valve against runaway loops — normal operations never approach this limit.

---

### Total context characteristics

| Tier | Bound |
|---|---|
| Tier 1 (system prompt) | ~1400 tokens |
| Tier 2 (session snapshot) | ≤ 400 tokens |
| Tier 3 (shell / tools, accumulated) | Grows during loop; circuit breaker at 8 calls |
| User message + 3-turn history | ~300 tokens |
| **Static total (Tier 1 + 2)** | **~1800 tokens** |

Well within any current model's context window. When static total approaches 3000
tokens, revisit this ADR.

---

## Shell Constraints

The bash tool operates with a permitted command list. This is enforced at the adapter
layer — blocked commands are rejected before execution with a structured error.

**Permitted:**

```
Read:      cat, ls, find, grep, head, tail, sed, wc, awk (read-only patterns)
Mix tasks: mix compile, mix foundry.*, mix test <specific-file>
Git read:  git log, git diff, git status, git show, git blame
```

**Blocked:**

```
Direct writes:   File.write!, cp/mv targeting lib/ or config/ — use Igniter
Git writes:      git commit, git push, git merge — Foundry manages commits
Deps:            mix deps.get, mix deps.compile — :compliance class, proposal-only
DB ops:          mix ecto.migrate, mix ash.migrate — proposal-only, never from agent
Network:         curl, wget, npm, pip, mix hex.* — no network from agent shell
Process:         kill, pkill, systemctl — no process management
```

The blocked list maps directly to INV-001 (no autonomous sensitive changes), INV-002
(no direct filesystem writes), INV-004 (infrastructure proposal-only), and the
principle that dependency and schema changes are governed changes, not agent actions.

---

## Change Intent Reasoning Posture

For `change` intents, the agent follows this posture before producing any output.
Enforced via system prompt instruction, not a separate API call.

1. Read the spec-kit index (already in Tier 1) — identify relevant ADRs and INVs by tag
2. Read those documents via `bash("cat <path>")` — follow cross-references with further reads
3. Read module context: `bash("mix foundry.context <Module> --json")`
4. Read a pattern example if creating a new construct: `bash("mix foundry.pattern.find <type>")`
5. Read the operation schema if using a catalogue operation: `bash("mix foundry.operation.schema <Op>")`
6. Reason about change classification and contradictions
7. Emit structured contradiction check block in reasoning trace (see §Reasoning Trace)
8. If contradiction: BLOCKED — cite ADR/INV, do not proceed
9. If no contradiction: CHANGE_PREVIEW (Phase 3) or proposal parameters (Phase 4+)

**The agent follows references, it does not preload.** The index in Tier 1 ensures all
ADR summaries are visible. References encountered during reading (e.g. "see ADR-005
§Migration Classification") trigger additional `cat` calls. Fetch on reference, not
on anticipation.

---

## Pattern Selection Criteria

`mix foundry.pattern.find <type> [--domain D]` returns the module whose Spark DSL
declarations most closely match what the agent is trying to generate.

**`type`** — required. One of: `rule`, `transfer`, `reactor`, `blueprint`, `resource`,
`oban_worker`.

**`domain`** — optional Ash domain module name. Scopes search; falls back to
cross-domain if no match found within the domain.

**Ranking (applied in order):**
1. Same construct type (required filter, not a tie-breaker)
2. Same domain as target (preferred)
3. Highest DSL attribute declaration count (richer example is more useful)
4. Has associated property tests (agent uses as model for test generation)
5. Not `:sensitive` in manifest (avoids leaking sensitive field names as scaffolding suggestions)

Output: full `mix foundry.context` struct for the top-ranked module, truncated at
400 tokens if necessary (truncation preserves module header and first 5–8 attributes).

Backed by `Foundry.Context.PatternFinder`. Deterministic and unit-testable — no fuzzy
matching.

---

## Usage Rules

`.foundry/usage_rules/` contains one Markdown file per dependency with agent-oriented
guidance: patterns, anti-patterns, idiomatic usage, version-specific gotchas. More
useful than ExDoc for agent consumption — written at the pattern level, not type level.

**Sources:**
- Packages that ship `USAGE.md` or `AGENTS.md` at package root — copied at `mix deps.get`
- Foundry-maintained rules for the core stack: Ash 3.x, Reactor, Phoenix LiveView, Ecto
- `foundry_conventions.md` — Foundry-specific generation conventions (module structure,
  required annotations, domain wiring, test co-location). See ADR-002 §Foundry Conventions File.

Generated by `mix foundry.usage_rules.fetch`. Output committed to `.foundry/usage_rules/`.
Indexed in the spec-kit index with type `usage_rules`. Agent reads via bash.

```bash
cat .foundry/usage_rules/ash.md
cat .foundry/usage_rules/foundry_operations.md
grep -A20 "Op.AddAttribute" .foundry/usage_rules/foundry_operations.md
```

`mix foundry.exdoc <Module> [--function name]` provides structured ExDoc output for
a specific module or function at the exact pinned version from `mix.exs`. Use when
usage rules are insufficient and precise API detail is needed. Cached by
`{:exdoc, library, version}` with 24h TTL.

---

## LLM Adapter

`Foundry.Copilot.Engine` is adapter-agnostic. Adapters implement the
`Foundry.Copilot.LLMAdapter` behaviour:

```elixir
defmodule Foundry.Copilot.LLMAdapter do
  @callback run(messages :: [map()], tools :: [map()], opts :: keyword()) ::
    {:ok, stream :: Enumerable.t()} | {:error, term()}
end
```

| Adapter | Use | Config |
|---|---|---|
| `Foundry.Copilot.AnthropicAdapter` | Production | `config/runtime.exs` |
| `Foundry.Copilot.LMStudioAdapter` | Local dev, CI, demos | `config/test.exs` |

```elixir
# config/runtime.exs
config :foundry_studio,
  llm_adapter: Foundry.Copilot.AnthropicAdapter,
  llm_model: "claude-sonnet-4-6"  # never hardcoded in source

# config/test.exs
config :foundry_studio,
  llm_adapter: Foundry.Copilot.LMStudioAdapter,
  llm_base_url: "http://localhost:1234/v1",
  llm_model: "local-model"
```

LM Studio uses the OpenAI-compatible tool calling API. `LMStudioAdapter` validates
tool calling support at startup with a minimal probe request:
- Tool calls present in response → confirmed, proceed normally
- Tool calls absent → log warning, Studio starts in degraded mode (visualization panels
  functional, copilot shows banner), do not crash

**Streaming is mandatory.** Both adapters stream token-by-token. Activity Feed LiveView
receives tokens via Phoenix PubSub. Performance budget: first streamed token ≤ 5 seconds
from message send (ADR-012 §Performance Budgets).

Model name from config (`:llm_model`), never hardcoded. Changing models requires
re-validating all catalogue operations against the iGaming reference project and an
ADR update.

---

## Reasoning Trace

Every CHANGE_PREVIEW and proposal response must include a structured reasoning trace.
This is the structured output of the agent's decision steps — not LLM prompt content
(privacy, per ADR-012 §Data Retention).

```json
"reasoning_trace": {
  "intent_classification": {
    "task": "change",
    "operation": "Op.AddRule",
    "confidence": 0.91
  },
  "shell_calls": [
    "cat docs/adrs/ADR-005-change-approval-model.md",
    "mix foundry.context MyApp.Finance.Wallet --json",
    "mix foundry.pattern.find rule --domain Finance"
  ],
  "contradiction_check": {
    "contradiction": false,
    "checked_adrs": ["ADR-005", "ADR-002"],
    "checked_invs": ["INV-001", "INV-011"],
    "summary": null
  },
  "change_class": ":behavioral",
  "confidence_state": "HIGH_CONFIDENCE",
  "session_snapshot": {
    "pending_migrations": 0,
    "open_proposals": 1,
    "lint_errors": 0
  }
}
```

`contradiction_check.checked_adrs` and `checked_invs` must be non-empty arrays.
An empty list means the check was skipped — test failure, not acceptable response.

For question responses (no proposal file): equivalent fields emitted as attributes
on the `[:foundry, :llm, :call]` telemetry span. Not persisted to disk.

**Dev-mode trace log:** `config :foundry_studio, copilot_trace_log: true` writes all
traces to `.foundry/logs/copilot_trace.jsonl` (gitignored). Local debugging only.
Set in `config/dev.exs` during Phase 3 development.

---

## Nebulex Cache Strategy

All caching via Nebulex L1 (ETS):

| Cache key | TTL | Invalidation trigger |
|---|---|---|
| `{:spec_kit, file_path, mtime}` | Mtime-based | inotify file watcher |
| `{:spec_kit_index, index_mtime}` | Mtime-based | `mix foundry.spec_kit.index` re-run |
| `{:project_snapshot, hash}` | 60 seconds | TTL expiry |
| `{:exdoc, library, version}` | 24 hours | TTL expiry |
| `{:versions, mix_exs_mtime}` | Mtime-based | mix.exs change |

**Pre-warming on startup:** `Foundry.Context.SpecKitReader` pre-warms the spec-kit index
and all indexed documents during application start (20–40 files typically — acceptable
for a local dev tool). First user request sees no cold-start delay.

**Cloud mode:** Pre-warming runs after git clone/pull, before WebSocket accepts connections.

**Session snapshot (Tier 2) uses TTL caching**, not mtime. The 60-second window means
the agent sees state that is at most 60 seconds old — acceptable for a human-in-the-loop
tool. A shorter TTL increases subprocess call frequency; a longer TTL risks stale health
signals during active development. 60 seconds is the right balance.

---

## Phase-Gated Behaviour

The `change_generation_enabled` flag governs the Phase 3 → Phase 4 transition.
Static config, not a `fun_with_flags` flag:

```elixir
# Phase 3:
config :foundry_studio, change_generation_enabled: false

# Phase 4:
config :foundry_studio, change_generation_enabled: true
```

When `false`: `change` intent routes to `CHANGE_PREVIEW` handler. Full classification,
context assembly, and contradiction check still run. The handler describes what the
operation would do without generating a diff. Validates classification quality before
trusting code output.

---

## Consequences

- The bash tool and agent loop in `Foundry.Copilot.Engine` are the highest-value
  components to test. Test shell constraint enforcement in isolation. Test the full
  loop against the iGaming reference project fixture.
- `Foundry.Copilot.ContextBuilder` Tier 2 assembly is the second-highest priority.
  A bug here produces subtle reasoning errors, not hard failures. Test that the
  snapshot is present and correctly formatted before any LLM call is made.
- There is no embedding model, no vector database, no similarity search. All retrieval
  is via shell (bash + Mix tasks) or direct file reads. No ML infrastructure dependency
  beyond the LLM API.
- INV-006 (stack versions always in system prompt) is enforced at ContextBuilder
  initialisation — structurally impossible to start the agent loop without stack
  versions in Tier 1.
- The two-write-path distinction (DSL operations via catalogue vs. plain Elixir via
  raw Igniter) is dissolved. One write path: agent generates content, Igniter applies,
  compiler and linter verify. The operations catalogue is a quality accelerator, not
  a capability boundary.
- If the LLM API is unavailable, all four visualization panels continue to function.
  They do not use the LLM.
- The phase gate makes Phase 3 ("questions only") and Phase 4 ("proposals") distinct
  deployments of the same codebase — only the config flag differs.