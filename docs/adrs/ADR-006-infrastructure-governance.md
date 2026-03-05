# ADR-006: Infrastructure Governance — Proposal-Only from Agents

**Status:** Accepted  
**Date:** 2026-03  
**Deciders:** Platform team

---

## Context

Agents that understand code changes may also need to propose infrastructure changes
(Kubernetes resources, Postgres config, CI pipeline additions). The question is how much
autonomy agents have over infrastructure.

## Decision

**Agents propose infrastructure changes as structured diffs. Humans with infrastructure context apply them. No exceptions.**

The CI base pipeline is owned by the platform team. Projects extend it via overrides only:

```yaml
# .github/workflows/ci.yml — generated and owned by the platform
extends: foundry-studio/ci-base@v2
overrides:
  test_timeout: 10m
  additional_checks:
    - mix foundry.studio.compliance.check --strict
```

Agents may propose changes to the `overrides:` section.
Changes to the base pipeline require a platform-level PR, not a project-level approval.

When an agent determines infrastructure change is needed (e.g., new Oban queue requires
a Kubernetes ConfigMap change and a PgBouncer pool entry), it:
1. Generates the application code change as normal (Igniter, routes for approval)
2. Generates the infrastructure change as a PROPOSAL — a rendered diff in the review panel
3. Tags the proposal with `:infrastructure` so the manifest routes it to the infrastructure approver
4. The infrastructure approver reviews and applies manually

## Rationale

Infrastructure correctness cannot be verified by `mix foundry.studio.lint.all`. A wrong resource
limit affects all running pods. A wrong Postgres config affects all connections. The blast radius
extends far beyond what an agent can verify from the application codebase alone.

This is non-negotiable regardless of agent confidence level.

## Consequences

- The Studio review panel can render infrastructure diffs alongside code diffs in a single proposal
- Infrastructure proposals are never auto-applied even when all other parts of the change are `:structural`
- The audit log records infrastructure proposals with the same fidelity as code changes