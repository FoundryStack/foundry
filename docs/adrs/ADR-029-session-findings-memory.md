# ADR-029: Canonical Session Findings Memory

**Status:** Accepted  
**Date:** 2026-05  
**Deciders:** Platform team

---

## Context

Foundry already preserves ephemeral chat memory in the Studio session digest, but that data
is scoped to one conversation and is not part of the canonical spec-kit. Important discoveries
made during implementation and support work are therefore easy to lose:

- Root causes found while debugging a provider integration
- Rejected implementation paths that explain "why not"
- Non-obvious invariants discovered from tests, traces, or production support
- Risks or unresolved issues that should shape future changes

These findings are exactly the kind of durable project knowledge future copilot sessions need,
but they do not fit cleanly into ADRs, runbooks, or regulation files.

## Decision

**Foundry treats durable session findings as a first-class spec-kit artifact family stored in
`docs/findings/`.**

The copilot may append a hidden `foundry-memory` JSON block to the end of a response when a
turn produced reusable technical knowledge. Foundry strips that block from the visible
assistant message, validates it, and persists a markdown artifact in `docs/findings/`.

Each artifact captures:

- A short title and one-paragraph summary
- Technical findings, discoveries, issues, and conclusions
- Related nodes and spec-kit documents
- Tags for retrieval
- Session metadata such as capture time and source request

## Why `docs/findings/`

- It is canonical project knowledge, not transient telemetry
- It belongs in the same retrieval surface as ADRs, runbooks, and regulations
- Markdown keeps the artifact reviewable in git and readable without Foundry
- The copilot can search and cite it later through the existing spec-kit index

## What Findings Are Not

Findings do not replace ADRs.

- Use an ADR when the project is making or changing an architectural decision
- Use a runbook when the knowledge is procedural and operational
- Use a regulation file when the knowledge is a tracked external requirement
- Use a finding when the knowledge is a durable technical discovery, hazard, rejected path,
  debugging conclusion, or implementation constraint that future sessions should remember

Findings are also not a turn-by-turn transcript. Transient progress notes, TODO lists, and
routine restatements of existing docs must not be persisted.

## Consequences

- The spec-kit index now includes `findings`
- Retrieval may surface prior findings alongside ADRs, runbooks, and regulations
- The Studio session panel can show recently saved findings
- Git history becomes the review and audit surface for preserved "why" discovered during work
