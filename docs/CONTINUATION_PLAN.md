# Foundry — Continuation Plan

> **Context:** Spec-kit review complete. Suggestions applied. This document describes
> the recommended sequence for continuing from here toward Phase 1 implementation.
>
> Three open gaps remain before Phase 1 code can begin:
> Gap #53 (decorator lint signal), Gap #54 (reference project fixture), and
> Gap #1 (manifest schema — now partially closed, but ADR-011 still deferred).
> Two of these are small. One defines the acceptance criteria for everything.

---

## Immediate Next Steps (pre-implementation, spec-kit only)

These two items must be completed before writing any Elixir. Neither requires code.
Both are small. Do them in this order.

### Step 1: Write `docs/reference-project-fixture.md` (Gap #54) — ~2 hours

This is the highest-priority remaining gap. Every phase in BUILD_SEQUENCE.md says
"done when: runs against the iGaming reference project." Without this document,
those acceptance criteria cannot be evaluated.

The fixture document declares:

- Which Elixir modules exist in the reference project (`MyApp.Finance.Wallet`, `MyApp.Finance.LedgerEntry`, etc.)
- Which domains they belong to
- Which resources are in `sensitive_resources`
- Which RG-* compliance requirements exist and which modules implement them
- Which optional libraries are present (`:ash_money`, `:ash_state_machine`, `:fun_with_flags` at minimum)
- At least one Transfer module with compliance links and a state machine

This document becomes the target for Phase 1's JSON task outputs. It is also the
source for the actual reference project code that will live under `reference_projects/igaming/`
in the Foundry repository.

**Output:** `docs/reference-project-fixture.md`

---

### Step 2: Add `:decorated_transfer_step` lint rule stub to lint catalogue (Gap #53) — ~30 min

This is a spec decision, not an implementation task. Add a single entry to the lint
rule catalogue (wherever lint rules are being tracked) with status `planned`:

```
:decorated_transfer_step — warns when a Transfer step function is decorated via the
`decorator` library. The copilot cannot auto-classify the change class of decorated
Transfer steps. Manual review is required. Not a build failure; a warning surfaced
in the lint tab of the review panel.
```

Once this is documented, Gap #32 (decorator library) can be marked closed with the
resolution "governed by planned lint warning; no introspection in v1."

**Output:** Entry in the lint rule catalogue (wherever that lives — likely `Foundry.Lint.*` @moduledoc sketch or a lint catalogue section in ADR-002 or a new `docs/lint-catalogue.md`)

---

## Ash Domain Design

With the spec-kit complete and the two pre-implementation gaps closed, Ash domain
design can begin. This is the start of real implementation work.

### Design order (strict — each depends on the previous)

**1. `Foundry.Manifest` resource** — the load-bearing configuration resource

This is the first resource to design because everything else reads from it.
Use `docs/manifest-schema-draft.md` as the exact field target.

Key design decisions to make during Ash resource design (not spec-kit decisions — code decisions):
- How are `sensitive_resources` stored? List of module name strings, or a has-many relationship to a `SensitiveResource` embedded resource?
- How are `approvers` stored? Embedded resource with named role fields, or a polymorphic relationship?
- `conditional_libraries` — list of atoms or a has-many relationship?

Recommendation: favour embedded resources over nested keyword lists for anything that
has validation rules. `approvers` and `notifications` are good candidates for embedded resources.
`sensitive_resources` and `context_exclusions` can be simple lists of strings.

The manifest lives at `.foundry/manifest.exs` — it is read by `Foundry.Manifest.Reader`
(a plain module, not an Ash resource) and validated by the Ash resource's changesets.
The Ash resource is the schema + validation layer; the file is the storage layer.

**When the Ash resource is defined: write ADR-011.**

---

**2. `Foundry.Proposals.Proposal` resource** — the proposal state machine resource

The state machine is fully specified in ADR-014. The Ash resource maps directly:

- `ash_state_machine` for the DRAFT → PENDING_REVIEW → APPROVED → APPLIED → COMMITTED
  state machine (plus REJECTED, STALE, SUPERSEDED terminal states)
- `AshPaperTrail` required (INV-011 — Proposal is a sensitive resource in Foundry's own manifest)
- `AshArchival` required (INV-012)
- The proposal JSON file schema (ADR-014 §Proposal Storage) maps directly to Ash attributes

Key embedded resources to design alongside:
- `ApprovalSlot` — approver, approved_at, role
- `LintResult` — structured lint output
- `ImpactAnalysis` — structured impact output
- `BlobHash` — map of file paths to git blob hashes (ADR-009)

---

**3. `Foundry.Audit.Event` resource** — the append-only audit log entry

Simple resource. Maps to one JSONL line in `.foundry/audit.jsonl`.
Key constraint: no update or destroy actions. Append-only enforced by Ash policy.

---

**4. Mix task stubs** — Phase 1 deliverables, data contracts before implementation

Before implementing the six Mix tasks, define their output contracts as structs or
typed schemas. These are the interfaces that all of Phase 2 and 3 depend on.
Write the struct definitions first, verify they match the ADR-003 schema, then implement.

Tasks to stub:
- `mix foundry.context <Module> --json` → `Foundry.Context.ModuleContext` struct
- `mix foundry.context.all --json` → `%{domain => [ModuleContext]}`
- `mix foundry.diagram.generate --json` → `Foundry.Diagram.SystemMap` struct
- `mix foundry.compliance.check --json` → `Foundry.Compliance.CheckResult` struct
- `mix foundry.lint.all --json` → `Foundry.Lint.LintReport` struct
- `mix foundry.versions.check --json` → `Foundry.Versions.VersionManifest` struct

**The JSON schema for these structs is frozen at the end of Phase 1.** Breaking changes
require an ADR. Define them carefully.

---

## Phase 1 Implementation Sequence

Once domain design is complete and structs are stubbed, implement in this order:

```
1. mix foundry.versions.check    — simplest: reads mix.exs, outputs JSON
                                   Done first to unblock INV-006 (versions in every prompt)

2. mix foundry.context <Module>  — the core introspection task
                                   Implement against the reference project fixture
                                   Schema must match ADR-003 exactly

3. mix foundry.context.all       — calls foundry.context for all modules, aggregates

4. mix foundry.lint.all          — implements INV-001 through INV-013 lint rules
                                   Start with INV-006 (description coverage) and
                                   INV-011/INV-012 (paper_trail, archival) — highest value

5. mix foundry.compliance.check  — reads regulation files, checks implementation pointers

6. mix foundry.diagram.generate  — builds graph from foundry.context.all output
```

The **schema design review** (BUILD_SEQUENCE.md Phase 1) happens after task 2 is
working but before tasks 3–6 are started. Verify the full ADR-003 field list is
present in the live output before freezing.

---

## What Not to Do

- **Do not start Phase 2 (Studio UI) before Phase 1's JSON tasks are stable.** The system map is built from `diagram.generate` output. Building the UI against an unstable schema wastes effort.
- **Do not design the copilot engine modules as Ash resources.** `Foundry.Copilot.ContextBuilder`, `IntentClassifier`, `ConfidenceClassifier` are plain functional modules or GenServers. They have no persistent state requiring Ash.
- **Do not write ADR-011 before `Foundry.Manifest` Ash resource exists.** The manifest schema draft is the pre-ADR target — it is not a substitute for the ADR.
- **Do not begin the reference project implementation (code) before the fixture document is written.** Code the reference project from the fixture, not the other way around.

---

## Parallel Track: Can Anything Run in Parallel?

Yes. Two workstreams can run in parallel once domain design (steps 1–3 above) is complete:

**Track A — Phase 1 Mix tasks** (described above)

**Track B — Reference project scaffold**
Once `docs/reference-project-fixture.md` is written, a developer can scaffold the
reference project's Ash resources in `reference_projects/igaming/` using standard
`mix ash.gen.resource` (or manually). This track produces the live codebase that
Track A's Mix tasks will run against. The two tracks converge at the Phase 1
acceptance criteria check: "all six tasks run against the iGaming reference project."

These two tracks have no code dependency on each other. They only need to agree on
the fixture document, which is why the fixture document must come first.

---

## Summary Checklist

```
Pre-implementation (spec-kit only):
  [ ] docs/reference-project-fixture.md — declare reference project structure (Gap #54)
  [ ] Lint catalogue entry: :decorated_transfer_step (Gap #53)

Domain design:
  [ ] Foundry.Manifest Ash resource (use manifest-schema-draft.md as field target)
  [ ] Write ADR-011 immediately after Manifest resource is defined
  [ ] Foundry.Proposals.Proposal + embedded resources (ApprovalSlot, BlobHash, etc.)
  [ ] Foundry.Audit.Event resource
  [ ] Mix task output struct definitions (6 structs, schema frozen after Phase 1)

Phase 1 implementation (two parallel tracks):
  Track A: [ ] mix foundry.versions.check
           [ ] mix foundry.context <Module>
           [ ] Schema design review (verify full ADR-003 field coverage)
           [ ] mix foundry.context.all
           [ ] mix foundry.lint.all (INV rules)
           [ ] mix foundry.compliance.check
           [ ] mix foundry.diagram.generate
  Track B: [ ] Reference project scaffold in reference_projects/igaming/

Phase 1 done gate:
  [ ] All six tasks run against reference project, output matches fixture
  [ ] mix foundry.lint.all integrated into CI, fails on INV violations
  [ ] Schema frozen — any future breaking change requires ADR
```