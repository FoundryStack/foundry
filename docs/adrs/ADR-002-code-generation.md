# ADR-002: Code Generation — Igniter for All Code, No String Interpolation

**Status:** Accepted  
**Date:** 2026-03  
**Deciders:** Platform team

---

## Context

The copilot must generate and modify Elixir source code. There are three approaches:

1. **String interpolation**: build Elixir code as strings, write to disk
2. **Catalogue-only scaffold**: every generation must use a pre-built Igniter operation module
3. **Igniter operations (structured or raw)**: catalogue operations for common cases, raw Igniter API for novel cases

String interpolation is simpler to implement. It is wrong for this use case.
Catalogue-only is too rigid — it blocks legitimate work on genuinely novel module types.

## Decision

**All code generation uses Igniter. String interpolation for Elixir source is forbidden.
Catalogue operations are preferred; raw Igniter API is permitted when no catalogue operation fits.**

For common patterns: use the catalogue operation (e.g., `Op.AddRule`, `Op.AddTransfer`).  
For novel patterns: use `Igniter.create_new_file/3` or `Igniter.Project.Module.create_module/3` directly.  
For modifying existing files: `Igniter.Project.Module.find_and_update_module/3` with `Sourceror.Zipper`.  
For multi-file operations: composed Igniter pipelines (dry-run first, apply on approval).

The distinction between "catalogue" and "raw Igniter" is about convenience and consistency,
not about safety. Both produce AST-valid, formatter-compliant output. Both stream a diff
for human review before application. The catalogue operations simply encode the Foundry-specific
conventions (adding `@description`, wiring into domain, creating test stub) that raw Igniter
does not know about.

## Rationale

String-based generation has three failure modes that compound in regulated systems:

**Structural invalidity**: generated Elixir strings can be syntactically valid but semantically wrong (missing `do`/`end`, wrong module nesting, incorrect attribute types). The compiler catches this, but only after the file is written and reviewed, creating a confusing edit → reject → regenerate loop.

**Formatting instability**: string-generated code doesn't match the project's formatter configuration. This creates noisy diffs where formatting changes are mixed with actual logic changes, making review harder.

**Incremental unsafety**: when modifying an existing file, string interpolation can accidentally overwrite adjacent code. Igniter's zipper operations are scoped to specific AST nodes and cannot affect sibling nodes.

Igniter's AST manipulation is the published tool for exactly this use case. It handles formatting, idempotency (applying the same operation twice is safe), and provides dry-run output as a structured diff.

## Migration Generation

Scaffold operations that add or modify resources, attributes, or relationships must also
generate the corresponding `ash_postgres` migration. The mechanism:

```
Op.AddResource / Op.AddAttribute / Op.AddRelationship
  → Igniter pipeline for the code change (dry_run: true)
  → subprocess: mix ash.codegen <auto_name> --dry-run
  → migration file captured as part of the diff
  → both code diff + migration diff shown in review panel
  → on approval: code applied first, then mix ash.codegen (generates migration), then mix ash.migrate
```

The migration is shown alongside the code change in the review panel. Approvers see both.
The migration is part of the proposal's blob hash check (ADR-009).

For `:sensitive` resources: the migration is classified at the same level as the code change.
A migration touching a sensitive resource's table requires dual approval (ADR-005, INV-001).

## Authentication Scaffold

`Op.AddAuthenticationResource` wraps the `ash_authentication` Igniter generators. This
operation is not a raw Igniter call — it composes `ash_authentication`'s own published
Igniter operations, which means it stays current with `ash_authentication`'s own upgrade
path. The copilot does not generate authentication code from scratch.

## Consequences

- The 20 catalogue operations cover the common cases; raw Igniter covers the rest
- Agents must never use `File.write!/2` or `EEx.eval_string/2` on Elixir source files — this is the hard line
- When using raw Igniter for a novel pattern, the operation should be promoted to the catalogue if it will be needed again
- The diff produced by raw Igniter is indistinguishable from catalogue operation output in the review panel — both require the same human approval before apply
- Migration diffs are always included in proposals that touch resource structure

## The 20 Primary Operations

| Operation | Module | What it does |
|---|---|---|
| `add_resource` | `Op.AddResource` | New Ash resource with full declaration skeleton + migration |
| `add_transfer` | `Op.AddTransfer` | New Reactor + Transfer DSL, idempotency wired, telemetry spans included |
| `add_rule` | `Op.AddRule` | New Rule module with jurisdiction stubs + spec_invariants |
| `add_blueprint` | `Op.AddBlueprint` | New Blueprint with config_schema + forfeiture rules |
| `add_adapter` | `Op.AddAdapter` | New Provider Adapter with auth + contract test stubs |
| `add_action` | `Op.AddAction` | New action on existing resource |
| `add_attribute` | `Op.AddAttribute` | New attribute on existing resource with @description + migration |
| `add_relationship` | `Op.AddRelationship` | New relationship, bidirectional wiring + migration |
| `add_policy` | `Op.AddPolicy` | New Ash policy on existing resource |
| `add_compliance_link` | `Op.AddComplianceLink` | Link RG-* ID to implementing module |
| `update_rule_jurisdiction` | `Op.UpdateRuleJurisdiction` | Add jurisdiction clause to existing Rule |
| `add_livepage` | `Op.AddLivePage` | New LiveResource page for Back Office (with data-* attributes) |
| `add_oban_job` | `Op.AddObanJob` | New Oban worker with AshOban integration + telemetry spans |
| `add_notification` | `Op.AddNotification` | New notification event with channel routing |
| `add_test_module` | `Op.AddTestModule` | Test skeleton from DSL introspection (stream_data + bypass) |
| `add_state_transition` | `Op.AddStateTransition` | New AshStateMachine transition with guard + test stub |
| `add_authentication_resource` | `Op.AddAuthenticationResource` | User + Token resources via ash_authentication Igniter generators |
| `add_feature_flag` | `Op.AddFeatureFlag` | New fun_with_flags flag declaration with governance metadata |
| `add_money_attribute` | `Op.AddMoneyAttribute` | Monetary attribute using Ash.Type.Money; validates CLDR backend |
| `add_api_route` | `Op.AddApiRoute` | New ash_json_api route with auth + validation test stubs |