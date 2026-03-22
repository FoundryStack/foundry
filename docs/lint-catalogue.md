# docs/lint-catalogue.md — Foundry Lint Rule Catalogue

> **Purpose:** Authoritative list of all lint rules implemented or planned for
> `mix foundry.lint.all`. Each rule maps to one or more invariants and has a
> defined severity, detection mechanism, and implementation module target.
>
> **Rule:** When a new lint rule is added to `Foundry.LintRules.*`, it must be
> catalogued here first (status: `planned`) before implementation begins.
> This is how the linter's coverage is tracked without duplicating what the code says.

---

## Severity Levels

| Severity | Behaviour | When to use |
|---|---|---|
| `:error` | Build fails (`mix foundry.lint.all` exits non-zero) | Invariant violation — the system cannot be trusted with this gap |
| `:warning` | Lint report includes violation; build passes | Governance risk that should be addressed but does not break correctness |
| `:info` | Surfaced in Studio lint tab; never in CI output | Informational signal for developer awareness |

---

## Rules by Invariant

### INV-001 — Sensitive Resource Approval

| Rule ID | Severity | Description | Implementation module | Status |
|---|---|---|---|---|
| `:sensitive_resource_unapproved_change` | `:error` | A diff touching a sensitive resource was submitted without dual approval. Enforced at apply time, not lint time — the approval workflow is the primary gate. Lint checks that sensitive resources are declared in the manifest. | `Foundry.LintRules.SensitiveResourceRule` | planned |

---

### INV-002 — No Direct Filesystem Writes

| Rule ID | Severity | Description | Implementation module | Status |
|---|---|---|---|---|
| `:direct_file_write` | `:error` | Detects `File.write!/2`, `File.stream!/2`, or `EEx.eval_string/2` on paths in `lib/` or `test/`. Igniter is the only permitted write mechanism. | `Foundry.LintRules.FileWriteRule` | planned |

---

### INV-004 — Idempotency Declaration

| Rule ID | Severity | Description | Implementation module | Status |
|---|---|---|---|---|
| `:missing_idempotency` | `:error` | A Reactor module with external side-effect steps (money movement, provider API calls, state transitions with audit implications) does not declare an idempotency key. The rule infers side effects from step types. Purely internal read/compute Reactors are exempt. | `Foundry.LintRules.IdempotencyRule` | planned |

---

### INV-005 — Runbook Links

| Rule ID | Severity | Description | Implementation module | Status |
|---|---|---|---|---|
| `:missing_runbook` | `:error` | A Reactor module with more than 3 steps does not declare `@runbook`. The lint rule validates that the declared path resolves to an existing file — a non-existent runbook is as bad as no runbook. | `Foundry.LintRules.RunbookRule` | planned |

---

### INV-006 — Description Coverage

| Rule ID | Severity | Description | Implementation module | Status |
|---|---|---|---|---|
| `:missing_description` | `:error` | An Ash resource attribute does not have a `description:` value. All public modules must have `@moduledoc`. Test modules are exempt. This rule is the raw material for the system map detail panel — without descriptions, the panel degrades. | `Foundry.LintRules.DescriptionRule` | planned |

---

### INV-008 — Context Lock Currency

| Rule ID | Severity | Description | Implementation module | Status |
|---|---|---|---|---|
| `:context_lock_stale` | `:error` | `.foundry/context.lock` does not match `sha256(lib/**/*.ex + test/**/*.ex)`. Detected by CI running `mix foundry.project.context --check`. Not a traditional lint rule — implemented as the `--check` flag on the context command, not in `Foundry.LintRules.*`. | `mix foundry.project.context --check` | planned |

---

### INV-010 — Notification Channels

| Rule ID | Severity | Description | Implementation module | Status |
|---|---|---|---|---|
| `:missing_notification_config` | `:warning` | The project manifest does not declare one or more of the three required notification targets (`runbook_stale`, `adapter_verify_failed`, `compliance_test_failed`). A warning because operational staleness is not a build-time concern — but a project going to production without notification config is a governance risk flagged in the compliance dashboard. | `Foundry.LintRules.ManifestValidator` | planned |

---

### INV-011 — Paper Trail on Sensitive Resources

| Rule ID | Severity | Description | Implementation module | Status |
|---|---|---|---|---|
| `:missing_paper_trail` | `:error` | A resource in `manifest.sensitive_resources` (or an `ash_authentication` User/Token resource) does not declare `use AshPaperTrail.Resource` in its extensions. | `Foundry.LintRules.PaperTrailRule` | planned |

---

### INV-012 — Soft Delete on Sensitive Resources

| Rule ID | Severity | Description | Implementation module | Status |
|---|---|---|---|---|
| `:missing_archival` | `:error` | A sensitive resource does not use `AshArchival.Resource`. Also checks that no `:destroy` action on a sensitive resource uses `soft_delete?: false` without an exemption declared in the manifest. | `Foundry.LintRules.ArchivalRule` | planned |

---

### INV-013 — Feature Flag ADR Links

| Rule ID | Severity | Description | Implementation module | Status |
|---|---|---|---|---|
| `:missing_flag_adr` | `:error` | A `fun_with_flags` feature flag declared with `governance: :compliance` or `governance: :sensitive` does not have an ADR link in its Foundry governance metadata. | `Foundry.LintRules.FeatureFlagRule` | planned |

---

### Version Constraints

Version constraint rules replace the former `mix foundry.versions.check` standalone task.
All version data is sourced from `mix.lock` resolved values — exact locked versions,
not constraints. These rules fire in `mix foundry.lint.all` and appear in the `lint`
field of `mix foundry.project.status`.

| Rule ID | Severity | Description | Implementation module | Status |
|---|---|---|---|---|
| `:ash_version_outdated` | `:error` | The resolved `ash` version in `mix.lock` is below the minimum supported version (3.x). Ash 2.x is not supported — mixing 2.x and 3.x patterns produces incorrect code generation. | `Foundry.LintRules.VersionRule` | planned |
| `:elixir_version_unsupported` | `:error` | The Elixir version in `.tool-versions` or `mix.exs` `elixir:` constraint is below the minimum required for Ash 3.x compatibility. | `Foundry.LintRules.VersionRule` | planned |
| `:ashai_version_outdated` | `:warning` | Agent steps are declared but the resolved `ash_ai` version is below 2.x. Fires only when `agent_steps` are present in the project. | `Foundry.LintRules.VersionRule` | planned |

`Foundry.LintRules.VersionRule` reads `mix.lock` directly. Git-sourced dependencies
are identified by their commit SHA; version rules are skipped for them (warning logged).

---

### Manifest Validation

| Rule ID | Severity | Description | Implementation module | Status |
|---|---|---|---|---|
| `:manifest_missing_required_approver` | `:error` | `approvers.sensitive_lead` or `approvers.compliance_officer` is absent from the manifest. | `Foundry.LintRules.ManifestValidator` | planned |
| `:manifest_unknown_sensitive_resource` | `:error` | A module listed in `sensitive_resource_exemptions` is not in `sensitive_resources`. | `Foundry.LintRules.ManifestValidator` | planned |
| `:manifest_invalid_coverage_weights` | `:error` | `coverage_weights` values do not sum to 1.0 ± 0.001. | `Foundry.LintRules.ManifestValidator` | planned |
| `:manifest_exclusion_no_comment` | `:warning` | An entry in `context_exclusions` has no accompanying comment with an issue reference. | `Foundry.LintRules.ManifestValidator` | planned |
| `:manifest_missing_cldr_backend` | `:error` | `conditional_libraries` includes `:ash_money` but no CLDR backend module is discoverable in the project. | `Foundry.LintRules.ManifestValidator` | planned |

---

### Admin Route Security

| Rule ID | Severity | Description | Implementation module | Status |
|---|---|---|---|---|
| `:admin_route_unauthenticated` | `:error` | A route for `oban_web`, `phoenix_live_dashboard`, or `fun_with_flags_ui` is not behind an `ash_authentication` session check. The rule inspects the router module for pipeline assignments on these paths. | `Foundry.LintRules.AdminRouteRule` | planned |

---

### Money Type

| Rule ID | Severity | Description | Implementation module | Status |
|---|---|---|---|---|
| `:raw_money_type` | `:error` | An Ash resource attribute declares type `Money.t()` directly instead of `Ash.Type.Money`. Raw `Money.t()` bypasses the CLDR backend validation and breaks `ash_money` introspection. | `Foundry.LintRules.MoneyTypeRule` | planned |

---

### AshPyro Component Convention (conditional — only when `:ash_pyro` in `conditional_libraries`)

| Rule ID | Severity | Description | Implementation module | Status |
|---|---|---|---|---|
| `:missing_data_attributes` | `:warning` | A LiveView component rendered by a `LiveResource` declaration does not include `data-action`, `data-field`, or `data-*` attributes on interactive elements. AshPyro-generated components are exempt (the rule recognises AshPyro macro output). | `Foundry.LintRules.DataAttributeRule` | planned |

---

### Decorator Governance

| Rule ID | Severity | Description | Implementation module | Status |
|---|---|---|---|---|
| `:decorated_transfer_step` | `:warning` | A function in a Transfer module is annotated with a `@decorate` attribute from the `decorator` library. Foundry cannot introspect decorated function signatures — the change class of modifications to these steps cannot be determined automatically. Manual review is required for any change touching decorated Transfer steps. Surfaced in the lint tab of the review panel and in `mix foundry.lint.all` output. Does not block the proposal. | `Foundry.LintRules.DecoratorRule` | planned |

---

### Provider Adapter Version

| Rule ID | Severity | Description | Implementation module | Status |
|---|---|---|---|---|
| `:adapter_version_not_active` | `:warning` | A provider adapter module is registered in `conditional_libraries` but is not set as the active version on any `ProviderConfig` record in the project. Indicates unused or deprecated adapter configuration. | `Foundry.LintRules.AdapterVersionRule` | planned |

---

## Rule Implementation Notes

All rules in `Foundry.LintRules.*` follow the same contract:

```elixir
@callback check(module :: module(), context :: Foundry.Lint.Context.t()) ::
  {:ok, [Foundry.Lint.Violation.t()]} | {:error, term()}
```

`Foundry.Lint.Context.t()` carries: the compiled module, its Spark DSL extension info,
the current manifest, and the full module list (for cross-module rules like the
sensitive resource check).

Rules are composed by `mix foundry.lint.all`, which runs all registered rules against
all modules and aggregates violations into the structured output. Violations are
ordered: `:error` severity first, then `:warning`, then `:info`. Within each severity,
violations are ordered alphabetically by module name.

The lint runner collects all violations first (so the developer sees everything at
once), then exits non-zero if any `:error` violations exist.