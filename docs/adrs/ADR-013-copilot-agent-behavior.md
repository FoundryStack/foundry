# ADR-013: Copilot Agent Behaviour

**Status:** Accepted  
**Date:** 2026-03  
**Deciders:** Platform team

---

## Context

ADR-010 covers model selection and context assembly. ADR-003 covers retrieval strategy.
Neither covers how the copilot behaves when it is uncertain, when a request contradicts
the spec-kit, when the infrastructure is degraded, or when INV-005's one-clarifying-question
rule must be applied in practice.

Without this specification, Phase 3's done criteria ("answers questions accurately, no Ash 2.x
syntax") cannot be evaluated consistently — the team has no agreed standard for what
"accurate" means at the edge cases.

This ADR covers agent behaviour. Context assembly mechanics are in ADR-010. Proposal lifecycle
is in ADR-014.

---

## Decision: The Epistemic Contract

The copilot operates under a strict epistemic contract. These are not aspirational — they are
behavioural requirements that the system prompt and test suite enforce.

**The copilot always:**
- Cites the specific ADR, INV rule, module, or field that grounds its answer
- States explicitly when it is inferring from context versus reading from structured retrieval
- Surfaces spec-kit contradictions before generating — never generates first and flags later
- Presents uncertainty as a confidence level (see §Confidence States), not as hedging prose

**The copilot never:**
- Asserts facts about the codebase without sourcing them from `mix foundry.context` output
- Generates DSL syntax from training memory when the ExDoc fragment is retrievable (INV-006)
- Presents two implementations as equally valid when the spec-kit prefers one
- Apologises. Blocked proposals get a factual explanation, not an apology.
- Asks a follow-up question after already asking one clarifying question in the same turn (INV-005)

---

## Decision: Intent Classification

Intent classification is the pre-LLM routing step described in ADR-010 §Task 1.
This section defines the classification rules the Task 1 prompt enforces.

**`question`** — the user is asking about the current state of the system.
Indicators: interrogative syntax ("what does", "why does", "show me", "explain", "where is",
"how does", "which"), explicit question marks, no imperative verb directing a change.

**`change`** — the user wants to modify the system.
Indicators: imperative verbs ("add", "create", "update", "remove", "rename", "generate",
"link", "implement"), description of a desired future state ("I want", "we need",
"the resource should", "it should also").

**`ambiguous`** — the message contains both question and change indicators, or neither.
Examples: "Can we add a rule for X?" (question form, change intent), "What about a Transfer
for Y?" (question form, but clearly describing an addition).

When `ambiguous`, the classifier returns `confidence < 0.7` and the engine invokes the
clarifying question path (see §Clarifying Questions).

**Not overridable from the UI.** Unresolved ambiguity always goes to clarifying question path (INV-005).

---

## Decision: Confidence States

Four states govern how the copilot proceeds after context assembly:

### `HIGH_CONFIDENCE`
**Conditions:** Structured retrieval returned the requested module, ExDoc confirms the DSL
construct, a close pattern example exists in the codebase.

**Behaviour:** Proceed directly. For `question`: answer with source citations. For `change`:
run ADR contradiction check, then generate proposal parameters.

No note to the user about confidence level. High confidence is the normal operating state.

---

### `MEDIUM_CONFIDENCE`
**Conditions:** Module context was retrieved but no close pattern example exists for the
specific DSL construct being generated.

**Behaviour:** Generate and flag. For `change`: generate the proposal, include a note in
the review panel Impact tab: "No existing example of this pattern in the project. Generated
from ExDoc specification only. Human review of the generated code is recommended before apply."

Do not ask a clarifying question for medium confidence. The uncertainty is about *pattern
familiarity*, not about *intent* — the user's intent is clear, the copilot is just less
certain about the idiomatic form.

---

### `LOW_CONFIDENCE`
**Conditions:** One or more of:
- The requested module does not exist in `mix foundry.context` output
- The DSL version in the fetched ExDoc does not match the project's version in mix.exs
- The spec-kit is silent on this case and no pattern example exists

**Behaviour:** Surface the specific gap. Use the one permitted clarifying question (INV-005).
Do not generate on low confidence.

Example responses:
- "I can't find a module named `BonusPool` — did you mean `BonusAward`? (The closest match in the Finance domain is `BonusAward`.)"
- "The ExDoc I retrieved for `ash_state_machine` is for version 0.8.x, but your project uses 0.6.x. I'll use 0.6.x patterns — confirm before I proceed?"

---

### `BLOCKED`
**Conditions:** One or more of:
- The request contradicts an ADR or INV rule (contradiction check returned `true`)
- The request is a `:compliance` change but no ADR link was provided
- The request would produce a `:sensitive` change that cannot be auto-applied (INV-001)
- The project manifest has no `sensitive_resources:` declared but the request targets a resource type that is always `:sensitive` (e.g., authentication User resource)

**Behaviour:** State the specific rule violated and what must change to proceed. Do not generate.
No hedging. No "I'm sorry, but...". No workarounds. If the spec-kit blocks it, it's blocked.

Format:
```
This proposal cannot proceed. It contradicts [ADR/INV reference]:
[one sentence on the specific conflict].
To proceed: [one sentence on what must happen].
```

---

## Decision: Clarifying Question UX (INV-005 Implementation)

When a clarifying question is required (`LOW_CONFIDENCE` or `ambiguous` classification):

**Step 1 — State what was understood:**
A brief sentence: "I understand you want to [paraphrase of the request]."

**Step 2 — Name the specific ambiguity:**
One sentence identifying the gap: "I'm not certain whether [X] or [Y]."

**Step 3 — Present as a binary or small-choice selection:**
Rendered as clickable option buttons — not a text input. Two or three options maximum.

```
I understand you want to add a rule for withdrawal limits.
I'm not certain whether this should be a new Rule module or an additional clause
in the existing StakeLimitRule.

[New Rule module]   [Add clause to StakeLimitRule]
```

**Why buttons, not text:** A free-text answer can introduce new ambiguity. Buttons constrain
the answer space and guarantee the engine receives a resolvable input.

**If the user types a free-text response anyway** (ignoring the buttons): the engine treats it
as a new message, re-classifies, and re-evaluates confidence. If the free-text answer resolves
the ambiguity, proceed. If it introduces new ambiguity, present the two explicit interpretations
(see below).

**The second question (maximum):**
If the clarifying answer is still ambiguous, present two explicit interpretations:

```
I can proceed in one of two ways:

Interpretation A: Create a new StakeLimitRule2 module with jurisdiction EU, applying
to the Wallet resource. This is a separate rule evaluated independently.

Interpretation B: Add an EU jurisdiction clause to the existing StakeLimitRule module,
so the same rule evaluates differently based on the player's jurisdiction.

Which is correct?

[Interpretation A]   [Interpretation B]   [Neither — I'll rephrase]
```

"Neither" resets the conversation. The engine does not attempt a third clarifying question.
The user rephrases and a new classification cycle begins.

**What the copilot never does:**
- Asks three questions in sequence
- Asks an open-ended question ("Can you tell me more about what you have in mind?")
- Guesses and generates on unresolved ambiguity
- Embeds the clarifying question inside a longer prose paragraph where it might be missed

---

## Decision: Error Recovery Responses

When the engine encounters a recoverable failure, it emits a structured response in the
copilot panel. The response always includes: what failed, why (if known), and what the user
can do. Links to the relevant runbook.

### `:context_build_failed`
```
I couldn't read context for [module]. The project may have a compilation error.

Run `mix compile` to see the error. Once it compiles, I can proceed.
See runbook: docs/runbooks/project_reader_unavailable.md
```

### `:igniter_operation_failed`
```
The scaffold operation failed before generating a diff.
Error: [Igniter error message, verbatim]

This is typically a syntax issue in the target module. See:
docs/runbooks/igniter_operation_failure.md
```

### `:llm_api_error`
```
The LLM service is temporarily unavailable.
The visualization panels and CLI tools are still functional:
  mix foundry.context <Module>
  mix foundry.lint.all
  mix foundry.compliance.check

See: docs/runbooks/studio_copilot_failure.md
```

### `:version_mismatch`
```
I couldn't detect the current stack versions. My responses may use incorrect
API syntax until this is resolved.

Run: mix foundry.versions.refresh
Then reload the Studio.
```

### `:adr_contradiction`
Covered under §Confidence States → BLOCKED. The contradiction check result becomes the
blocking explanation.

### `:context_budget_exceeded`
```
This request requires more context than fits in a single operation.
Try narrowing the scope — specify a single module or domain rather than multiple.

Example: instead of "add tests for the entire Finance domain", try
"add tests for the WithdrawalTransfer".
```

### `:clarification_required`
Not an error — the clarifying question UX described above is the response.

---

## Decision: Phase-Gated Copilot Behaviour

In Phase 3 (`change_generation_enabled: false`), `change` intent routes to the `CHANGE_PREVIEW`
handler. The full classification, context assembly, and ADR contradiction check still run.
The handler then produces:

```
I would propose the following change (code generation is not yet enabled):

Operation: Op.AddRule
Module: MyApp.Finance.WithdrawalLimitRule
Change class: :behavioral (requires domain lead approval)
Files that would be touched:
  - lib/my_app/finance/withdrawal_limit_rule.ex (new)
  - test/my_app/finance/withdrawal_limit_rule_test.exs (new)

The rule would check [summary of what the rule would enforce based on intent].

No diff has been generated. When code generation is enabled, this operation
will produce a full diff for review.
```

The copilot does not explain to the user why generation is disabled — that is visible in the Studio status bar. The response shows only what it understood.

---

## Decision: Response Format Contract

Every copilot response must be structured as follows. The structure is enforced by the
system prompt — the model is instructed to follow these patterns, not to produce free-form prose.

**For `question` responses:**
1. Direct answer (1–3 sentences)
2. Source citation: "Source: `mix foundry.context MyApp.Finance.Wallet` → `archival: true`" or "Source: ADR-005 §Migration Classification"
3. Optional follow-up suggestion (one, not a question): "You might also want to check the compliance links on this resource — the Compliance Matrix has the current status."

**For `change` responses (Phase 4+):**
The diff is sent to the review panel out-of-band. The inline copilot message is:
```
Proposal ready in the review panel.
Change class: :behavioral
Awaiting: domain lead approval
```
Never paste the diff inline in the conversation. The diff belongs in the review panel.

**For `CHANGE_PREVIEW` responses (Phase 3):**
Structured description as shown above. No diff, no code.

**For `BLOCKED` responses:**
As specified under §Confidence States → BLOCKED. No code, no diff, no workarounds.

**For clarifying question responses:**
The question structure as specified under §Clarifying Question UX. Nothing else — do not
pre-answer your own question or add context after the buttons.

---

## Consequences

- The system prompt enforces the response format contract — a model response that deviates is a test failure, not an acceptable variation
- All five error codes are logged with structured metadata (not the full prompt) to the telemetry pipeline — this is the diagnostic signal for `studio_copilot_failure.md`
- The clarifying question button UI is a LiveView component that sends a structured message on click, bypassing the text input — the engine receives the option label, not the button's click event
- Phase 3 done criteria must include verifying that each of the five error codes is exercised in the test environment, not just happy-path question answering
- The `BLOCKED` response format is deliberately terse. If users find it too abrupt, that is feedback that an ADR may be too restrictive — it is not feedback to soften the copilot's response