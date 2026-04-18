---
name: "foundry-govern"
description: >
  Enforce Foundry governance before any code generation. Executes AGENTS.md
  §Agent reasoning sequence steps 1–10. Reads NodeEntry, traverses constraint
  graph (ADRs + regulations), classifies change, checks INV-001..018.
  BLOCKS if any invariant is violated. Returns confirmed plan or BLOCKED message.
user-invocable: false
disable-model-invocation: true
---

## Governance Sequence

You are enforcing AGENTS.md §Agent reasoning sequence steps 1–10.
**Do not generate code. Do not write files. Produce ONLY: a confirmed plan, or a BLOCKED message.**

### Step 1 — Read NodeEntry
```bash
mix foundry.project.context <affected_module> --json
```
If the module is unknown, identify it from the current tasks.md or plan.md.

### Step 2 — Traverse ADR constraint graph
For each ADR in `NodeEntry.adrs`: read the full document via bash.
Follow `Extends:` headers — read those ADRs too (one level deep only).

### Step 3 — Traverse regulation constraint graph
For each requirement ID in `NodeEntry.compliance`:
  - Read `docs/regulations/<file>.md`
  - Follow requirement → linked ADR references

### Step 4 — Read runbook if in scope
If a Reactor with >3 steps is involved: read `NodeEntry.runbook`.

### Step 5 — Run pre-generation checklist
Check each item from AGENTS.md §Pre-generation checklist against the proposed change.
Record any gaps.

### Step 6 — Check @description fields
Read `@description` and `description:` fields on all touched attributes.
Flag any proposed change that contradicts an existing description.

### Step 7 — Classify change
Assign one of: `:structural` | `:behavioral` | `:sensitive` | `:compliance`
Using the Change Classification table from AGENTS.md. When in doubt, classify upward.

### Step 8 — Contradiction check
Check every INV-001..018 against the proposed change.

**BLOCKING RULE:** If any invariant is violated, output ONLY:
```
BLOCKED: INV-XXX violated.
Rule: [exact invariant text]
Reason: [specific contradiction between proposed change and invariant]
Resolution: [what must change before proceeding]
```
Do not output a plan. Do not output code. Stop here.

### Step 9 — Classify spec-kit requirements
- `:behavioral` or `:compliance` → ADR draft REQUIRED as first file in proposal
- `:structural` with new concept → ADR draft offered, not required
- `:structural` modification → no spec-kit step

### Step 10 — Construct and output confirmed plan
Output the ordered session plan:
```
Change class: :<class>
Approver required: <role>
Auto-apply permitted: <yes/no>

Plan:
[spec]      <ADR/runbook stub if required>
[tests]     <test skeletons from DSL declarations + ADR boundary conditions>
[code]      <implementation constrained by test structure>
[migration] <mix ash.codegen — only if schema changes>
```

Wait for human confirmation before proceeding.
