# ADR-009: Concurrent Proposals — Optimistic Locking on File Hash

**Status:** Accepted  
**Date:** 2026-03  
**Deciders:** Platform team

---

## Context

Multiple developers may use Foundry simultaneously and generate proposals that touch the
same source files. Without coordination, two approved proposals could produce conflicting
AST operations on the same file, resulting in a corrupted or inconsistent codebase.

Three approaches were considered:
1. **Pessimistic locking** — lock files when a proposal is generated, block others
2. **CRDT / operational transform** — merge concurrent edits automatically
3. **Optimistic locking** — detect conflicts at apply time, not generation time

## Decision

**Optimistic locking at the file level using git blob hashes.**

When a proposal is generated, Foundry records the current git blob hash for each file
the proposal would modify. At apply time, before executing the Igniter operation,
Foundry re-reads the current blob hash for each file.

- If hashes match: proceed with apply
- If any hash has changed: invalidate the proposal, notify the user with a clear message:
  "This proposal is stale — `lib/my_app/finance/bet_transfer.ex` was modified since the
   proposal was generated. Please review the current file and regenerate."

## Rationale

**Why not pessimistic locking:** It creates serialized bottlenecks for a team working on
different parts of the same module. A developer generating a proposal for a resource blocks
all others from generating proposals for that same resource for the duration of their review.
For proposals that take hours to route through approval queues, this is unacceptable.

**Why not CRDT/OT:** The merge problem for Elixir AST is complex and has failure modes
that are hard to explain to users. "Your change was automatically merged with another developer's
change" is difficult to audit. In a regulated system, every change needs a clear human
decision chain.

**Why optimistic locking works here:** Foundry proposals are typically reviewed and applied
within minutes to hours, not days. Conflicts are rare in practice because different developers
work on different domains. When they do occur, the correct resolution is clear: regenerate
against the current state. The cost of a regeneration is low; the cost of a silently wrong
merge is high.

## The Stale Proposal UX

A stale proposal in the review panel shows a clear visual indicator:
- The diff is still visible (so the developer can see what they intended)
- A banner: "Stale — file changed since generation. Regenerate to continue."
- One-click regenerate button that re-runs the same operation against the current codebase
- If the regenerated diff is identical: applies immediately (the conflict was in an unrelated part of the file)
- If different: shows a new diff for review

## Consequences

- Proposals store the blob hash of every file they would touch at generation time
- The apply step is a two-phase operation: check hashes, then execute Igniter
- Stale proposals are never silently applied — always surfaced to the user
- The approval record stores the blob hash state at the time of approval, providing a complete audit trail of what state the approver saw
- This does not require any distributed locking infrastructure — git hashes are the coordination mechanism