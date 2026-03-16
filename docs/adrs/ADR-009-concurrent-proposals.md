# ADR-009: Concurrent Proposals — Git Branch Isolation and Base-Commit Stale Detection

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

**Git branch isolation with base-commit stale detection.**

Every proposal writes to an isolated `foundry/prop_<id>` branch, never to the working
tree directly. The proposal stores the `base_commit` SHA at the time of generation.

**At apply time**, before merging:
```bash
# Check if affected files changed on main since the branch was cut
git diff <base_commit>..HEAD -- <affected_files>
```
- Empty output → fast-forward merge is safe → proceed
- Non-empty output → files changed on main since generation → **STALE**

Stale proposals are surfaced to the requester with the specific files that changed.
One-click regenerate re-cuts the branch from current HEAD and re-runs generation.

## Rationale

**Why git branches, not file hash maps:** The branch approach uses git's own ancestry
and diff machinery instead of reimplementing it. It provides complete isolation during
generation (the working tree is never touched), makes the diff artifact (`git diff
main..foundry/prop_<id>`) the natural review surface, and gives the compilation step
a valid full-project context. A hash map of individual files is a manual reimplementation
of what `git diff` already does correctly.

**Why not pessimistic locking:** Serialised bottlenecks for teams working on different
domains. Proposals that spend hours in approval queues would block all other generation
in the interim.

**Why not CRDT/OT:** AST merge is complex and produces changes that are hard to audit.
In a regulated system, every change needs a clear human decision chain.

**Branch cleanup:** Branches are deleted on proposal COMMITTED, REJECTED, or SUPERSEDED.
`mix foundry.proposals.gc` removes orphaned branches from crashed or abandoned proposals.

## The Stale Proposal UX

Stale banner rendering and regenerate interaction: ADR-012 §Stale Proposal Banner.

On detecting STALE: re-cut the branch from HEAD, re-run Igniter and `mix ash.codegen`,
re-compile. If the resulting diff is identical to the stale one, the conflict was in an
unrelated part of the codebase — the banner clears and the proposal proceeds. If the
diff differs, the new diff is shown for review.

## Proposal ID Generation

`"prop_" <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)` — e.g. `prop_3a7f1b2c`.
8 hex chars provide 4 billion combinations, sufficient for git-backed local storage.
The git branch is `foundry/prop_3a7f1b2c`.

## Consequences

- Proposals store `base_commit: "sha256..."` (one field) instead of a map of file hashes
- The apply step checks `git diff <base_commit>..HEAD -- <affected_files>` before merging
- Stale proposals are never silently applied — always surfaced to the requester
- The approval record stores the `base_commit` at the time of approval — providing a
  complete audit trail of what codebase state the approver reviewed
- No distributed locking infrastructure needed — git branches are the isolation mechanism
- The working tree is never modified during proposal generation; `mix foundry.studio`
  operates cleanly alongside active development