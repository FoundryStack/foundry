# docs/lint-catalogue.md — Foundry Lint Rule Catalogue

> **Purpose:** Authoritative list of all lint rules implemented or planned for
> `mix foundry.lint.all`. Each rule maps to one or more invariants and has a
> defined severity, detection mechanism, and implementation module target.
>
> **Closes:** Gap #53 (decorator library governance — `:decorated_transfer_step` rule
> makes the silent governance hole explicit and surfaced).
>
> **Rule:** When a new lint rule is added to `Foundry.Lint.*`, it must be catalogued here
> first (status: `planned`) before implementation begins. This is how the linter's
> coverage is tracked without duplicating what the code says.

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
| `:sensitive_resource_unapproved_change` | `:error` | A diff touching a sensitive resource was submitted without dual approval. Enforced at apply time, not lint time — the approval workflow is the primary gate. Lint checks that sensitive resources are declared in the manifest. | `Foundry.Lint.SensitiveResourceRule` | planned |

---

### INV-002 — No Direct Filesystem Writes

| Rule ID | Severity | Description | Implementation module | Status |
|---|---|---|---|---|
| `:direct_file_write` | `:error` | Detects `File.write!/2`, `File.stream!/2`, or `EEx.eval_string/2` on paths in `lib/` or `test/`. Igniter is the only permitted write mechanism. | `Foundry.Lint.FileWriteRule` | planned |

---

### INV-004 — Idempotency Declaration

| Rule ID | Severity | Description | Implementation module | Status |
|---|---|---|---|---|
| `:missing_idempotency` | `:error` | A Reactor module with external side-effect steps (money movement, provider API calls, state transitions with audit implications) does not declare an idempotency key. The rule infers side effects from step types. Purely internal read/compute Reactors are exempt. | `Foundry.Lint.IdempotencyRule` | planned |

---

### INV-005 — Runbook Links

| Rule ID | Severity | Description | Implementation module | Status |
|---|---|---|---|---|
| `:missing_runbook` | `:error` | A Reactor module with more than 3 steps does not declare `@runbook`. The lint rule validates that the declared path resolves to an existing file — a non-existent runbook is as bad as no runbook. | `Foundry.Lint.RunbookRule` | planned |

---

### INV-006 — Description Coverage

| Rule ID | Severity | Description | Implementation module | Status |
|---|---|---|---|---|
| `:missing_description` | `:error` | An Ash resource attribute does not have a `description:` value. All public modules must have `@moduledoc`. Test modules are exempt. This rule is the raw material for the system map detail panel — without descriptions, the panel degrades. | `Foundry.Lint.DescriptionRule` | planned |

---

### INV-008 — Diagram Currency

| Rule ID | Severity | Description | Implementation module | Status |
|---|---|---|---|---|
| `:uncommitted_diagram` | `:error` | `mix foundry.diagram.generate` produces output that differs from what is committed in `docs/diagrams/system_map.json`. Detected by CI running the task and checking for unstaged changes. Not a traditional lint rule — implemented as a CI step, not in `Foundry.Lint.*`. | CI step in `mix foundry.diagram.generate --check` | planned |

---

### INV-010 — Notification Channels

| Rule ID | Severity | Description | Implementation module | Status |
|---|---|---|---|---|
| `:missing_notification_config` | `:warning` | The project manifest does not declare one or more of the three required notification targets (`runbook_stale`, `adapter_verify_failed`, `compliance_test_failed`). A warning because operational staleness is not a build-time concern — but a project going to production without notification config is a governance risk flagged in the compliance dashboard. | `Foundry.Lint.ManifestValidator` | planned |

---

### INV-011 — Paper Trail on Sensitive Resources

| Rule ID | Severity | Description | Implementation module | Status |
|---|---|---|---|---|
| `:missing_paper_trail` | `:error` | A resource in `manifest.sensitive_resources` (or an `ash_authentication` User/Token resource) does not declare `use AshPaperTrail.Resource` in its extensions. | `Foundry.Lint.PaperTrailRule` | planned |

---

### INV-012 — Soft Delete on Sensitive Resources

| Rule ID | Severity | Description | Implementation module | Status |
|---|---|---|---|---|
| `:missing_archival` | `:error` | A sensitive resource does not use `AshArchival.Resource`. Also checks that no `:destroy` action on a sensitive resource uses `soft_delete?: false` without an exemption declared in the manifest. | `Foundry.Lint.ArchivalRule` | planned |

---

### INV-013 — Feature Flag ADR Links

| Rule ID | Severity | Description | Implementation module | Status |
|---|---|---|---|---|
| `:missing_flag_adr` | `:error` | A `fun_with_flags` feature flag declared with `governance: :compliance` or `governance: :sensitive` does not have an ADR link in its Foundry governance metadata. | `Foundry.Lint.FeatureFlagRule` | planned |

---

### Manifest Validation

| Rule ID | Severity | Description | Implementation module | Status |
|---|---|---|---|---|
| `:manifest_missing_required_approver` | `:error` | `approvers.sensitive_lead` or `approvers.compliance_officer` is absent from the manifest. | `Foundry.Lint.ManifestValidator` | planned |
| `:manifest_unknown_sensitive_resource` | `:error` | A module listed in `sensitive_resource_exemptions` is not in `sensitive_resources`. | `Foundry.Lint.ManifestValidator` | planned |
| `:manifest_invalid_coverage_weights` | `:error` | `coverage_weights` values do not sum to 1.0 ± 0.001. | `Foundry.Lint.ManifestValidator` | planned |
| `:manifest_exclusion_no_comment` | `:warning` | An entry in `context_exclusions` has no accompanying comment with an issue reference. | `Foundry.Lint.ManifestValidator` | planned |
| `:manifest_missing_cldr_backend` | `:error` | `conditional_libraries` includes `:ash_money` but no CLDR backend module is discoverable in the project. | `Foundry.Lint.ManifestValidator` | planned |

---

### Admin Route Security

| Rule ID | Severity | Description | Implementation module | Status |
|---|---|---|---|---|
| `:admin_route_unauthenticated` | `:error` | A route for `oban_web`, `phoenix_live_dashboard`, or `fun_with_flags_ui` is not behind an `ash_authentication` session check. The rule inspects the router module for pipeline assignments on these paths. | `Foundry.Lint.AdminRouteRule` | planned |

---

### Money Type

| Rule ID | Severity | Description | Implementation module | Status |
|---|---|---|---|---|
| `:raw_money_type` | `:error` | An Ash resource attribute declares type `Money.t()` directly instead of `Ash.Type.Money`. Raw `Money.t()` bypasses the CLDR backend validation and breaks `ash_money` introspection. | `Foundry.Lint.MoneyTypeRule` | planned |

---

### AshPyro Component Convention (conditional — only when `:ash_pyro` in `conditional_libraries`)

| Rule ID | Severity | Description | Implementation module | Status |
|---|---|---|---|---|
| `:missing_data_attributes` | `:warning` | A LiveView component rendered by a `LiveResource` declaration does not include `data-action`, `data-field`, or `data-*` attributes on interactive elements. AshPyro-generated components are exempt (the rule recognises AshPyro macro output). | `Foundry.Lint.DataAttributeRule` | planned |

---

### Decorator Governance (Gap #53 — closes Gap #32)

| Rule ID | Severity | Description | Implementation module | Status |
|---|---|---|---|---|
| `:decorated_transfer_step` | `:warning` | A function in a Transfer module (Reactor with Transfer DSL) is annotated with a `@decorate` attribute from the `decorator` library. Foundry cannot introspect decorated function signatures — the change class of modifications to these steps cannot be determined automatically. **Manual review is required for any change touching decorated Transfer steps.** This warning is surfaced in: (1) the lint tab of the review panel whenever a proposal touches a decorated Transfer step, (2) `mix foundry.lint.all` output. The warning does not block the proposal — it flags it for deliberate human attention. | `Foundry.Lint.DecoratorRule` | planned |

**Rationale:** The `decorator` library wraps function definitions in a macro. Foundry reads
DSL declarations and module structure via Spark introspection; decorated functions appear
as ordinary functions to the introspection layer but their runtime behaviour may differ.
For Transfer steps — which carry `:sensitive` or `:behavioral` classification — this
ambiguity is a governance risk. The lint warning ensures it is never silent.

**This rule closes Gap #32 (decorator library unaddressed) and Gap #53 (decorator lint signal required).**
Once this rule is implemented, the `decorator` library's governance stance is: permitted,
with mandatory lint warning on Transfer steps. No further ADR is needed unless the team
decides to support full decorator introspection (a future enhancement, not a v1 concern).

---

## Rule Implementation Notes

All rules in `Foundry.Lint.*` follow the same contract:

```elixir
@callback check(module :: module(), context :: Foundry.Lint.Context.t()) ::
  {:ok, [Foundry.Lint.Violation.t()]} | {:error, term()}
```

`Foundry.Lint.Context.t()` carries: the compiled module, its Spark DSL extension info,
the current manifest, and the full module list (for cross-module rules like the
sensitive resource check).

Rules are composed by `mix foundry.lint.all`, which runs all registered rules against
all modules and aggregates violations into the structured JSON output.

The lint runner short-circuits on `:error` severity violations for CI — it collects
all violations first (so the developer sees everything at once), then exits non-zero
if any `:error` violations exist.