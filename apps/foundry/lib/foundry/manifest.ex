defmodule Foundry.Manifest do
  @moduledoc """
  The project manifest resource. Validates and provides typed access to the
  `.foundry/manifest.exs` configuration file for a target project.

  ## Storage

  The manifest lives as a plain Elixir keyword list at `.foundry/manifest.exs`
  in the target project's repository (ADR-015). This Ash resource is the
  schema + validation layer — it does not persist to a database.

  `Ash.DataLayer.Simple` is used here solely to leverage Ash's changeset
  validation, attribute type coercion, and embedded resource support. The
  manifest is **always a single instance** — it is loaded once at Studio
  startup and held in-process. It is never queried by ID, never paginated,
  and never written to a database. `Ash.DataLayer.Simple` is the lightest
  data layer that gives us Ash validations without any storage infrastructure.

  Do not add `:read` actions that imply collection semantics (list, filter,
  sort). The only meaningful action is `:load` — construct from a keyword list.

  ## Loading

  Use `Foundry.Manifest.Reader.load!/1` to read and validate the manifest file.
  That function parses the `.exs` file, constructs a `Foundry.Manifest` record
  via `Ash.Changeset.for_create/3` with the `:load` action, and raises if
  validation fails. The returned record is cached in ETS for the session
  (ADR-015 Tier 2 — keyed on `{:manifest, mix_exs_mtime}`).

  ## Validation

  All fields declared in `docs/manifest-schema-draft.md` are validated here.
  Invalid manifests raise at Studio startup — Foundry will not run against a
  project with a broken manifest.

  ## Calculations

  Calculations on this resource use Elixir-native `expr/1` forms only.
  SQL `fragment/1` expressions are not valid with `Ash.DataLayer.Simple` —
  it evaluates expressions in Elixir, not Postgres. Any calculation that
  appears to need a fragment should be implemented as a module-based
  calculation instead.

  ## ADR

  ADR-011 (deferred — write after this resource is stable in production).
  Pre-ADR schema: `docs/manifest-schema-draft.md`.
  """

  use Ash.Resource,
    domain: Foundry.Config,
    data_layer: Ash.DataLayer.Simple

  # ---------------------------------------------------------------------------
  # Attributes
  # ---------------------------------------------------------------------------

  attributes do
    uuid_primary_key(:id)

    # ── Identity ──────────────────────────────────────────────────────────────

    attribute :project_name, :string do
      description("Human-readable project name. Used in Studio UI headers and audit log records.")
      allow_nil?(false)
    end

    attribute :domain_type, :atom do
      description(
        "Target domain category. Used for bootstrap template selection. One of: :igaming, :fintech, :healthcare, :legal, :insurance, :other."
      )

      constraints(one_of: [:igaming, :fintech, :healthcare, :legal, :insurance, :other])
      default(:other)
    end

    # ── Sensitive Resources ────────────────────────────────────────────────────

    attribute :sensitive_resources, {:array, :string} do
      description(
        "Module names (as strings) of resources requiring dual approval, AshPaperTrail, and AshArchival. Authentication User and Token resources are always added automatically and must not be listed here."
      )

      default([])
    end

    attribute :sensitive_resource_exemptions, {:array, Foundry.Manifest.SensitiveExemption} do
      description(
        "Per-sensitive-resource exemptions for paper_trail or archival requirements. Each entry requires a documented reason and is a :compliance class change."
      )

      default([])
    end

    # ── Approvers ─────────────────────────────────────────────────────────────

    attribute :approvers, Foundry.Manifest.ApproverConfig do
      description(
        "Named approver email addresses for each approval role. sensitive_lead and compliance_officer are required."
      )

      allow_nil?(false)
    end

    # ── Approval SLAs ─────────────────────────────────────────────────────────

    attribute :approval_sla, Foundry.Manifest.ApprovalSla do
      description(
        "Time limits for each change class to reach approval. nil means no SLA. Operations board shows proposals exceeding their SLA."
      )

      default(nil)
    end

    # ── Auto-Apply ────────────────────────────────────────────────────────────

    attribute :auto_apply_structural, :boolean do
      description(
        "When true, approved :structural proposals are applied immediately on approval. The approval action IS the apply trigger. All other classes always require a separate Apply action."
      )

      default(false)
    end

    # ── Phase Gate ────────────────────────────────────────────────────────────

    attribute :change_generation_enabled, :boolean do
      description(
        "Controls whether the copilot generates real diffs (Phase 4+) or only describes what would be proposed (Phase 3). The config/foundry_studio.exs value is the primary mechanism; this field enables per-project override."
      )

      default(true)
    end

    # ── Notifications ─────────────────────────────────────────────────────────

    attribute :notifications, Foundry.Manifest.NotificationConfig do
      description(
        "Notification channel configuration for the three required staleness conditions. All three keys are required by INV-010. Absence triggers a lint warning."
      )

      allow_nil?(true)
      default(nil)
    end

    # ── Coverage ──────────────────────────────────────────────────────────────

    attribute :coverage_gate, :boolean do
      description(
        "When true, a domain coverage score below 0.6 fails CI. Recommended: false for new projects, true before go-live."
      )

      default(false)
    end

    attribute :coverage_weights, Foundry.Manifest.CoverageWeights do
      description(
        "Override the default domain coverage formula weights. All five values must sum to 1.0."
      )

      default(nil)
    end

    # ── Data Retention ────────────────────────────────────────────────────────

    attribute :data_retention, Foundry.Manifest.DataRetention do
      description(
        "Retention period overrides in days. Defaults are financial/regulated platform values."
      )

      default(nil)
    end

    # ── Context Exclusions ────────────────────────────────────────────────────

    attribute :context_exclusions, {:array, :string} do
      description(
        "Module names excluded from mix foundry.context introspection. Use only as a temporary workaround for cyclic dependency or DSL loop issues. Each exclusion should have an issue reference in a comment in manifest.exs."
      )

      default([])
    end

    # ── Conditional Libraries ─────────────────────────────────────────────────

    attribute :conditional_libraries, {:array, :atom} do
      description(
        "Optional ecosystem libraries present in this target platform. Foundry uses this list to enable/disable lint rules and scaffold operations. Valid values: :ash_money, :ash_state_machine, :ash_pyro, :fun_with_flags."
      )

      constraints(items: [one_of: [:ash_money, :ash_state_machine, :ash_pyro, :fun_with_flags]])
      default([])
    end

    timestamps()
  end

  # ---------------------------------------------------------------------------
  # Actions
  # ---------------------------------------------------------------------------

  actions do
    defaults([:read])

    create :load do
      description(
        "Load and validate a manifest from a parsed keyword list. Called by Foundry.Manifest.Reader."
      )

      accept([
        :project_name,
        :domain_type,
        :sensitive_resources,
        :sensitive_resource_exemptions,
        :approvers,
        :approval_sla,
        :auto_apply_structural,
        :change_generation_enabled,
        :notifications,
        :coverage_gate,
        :coverage_weights,
        :data_retention,
        :context_exclusions,
        :conditional_libraries
      ])
    end
  end

  # ---------------------------------------------------------------------------
  # Validations
  # ---------------------------------------------------------------------------

  validations do
    validate Foundry.Manifest.Validations.RequiredApprovers do
      description("sensitive_lead and compliance_officer must be present in approvers.")
      message("approvers.sensitive_lead and approvers.compliance_officer are required")
    end

    validate Foundry.Manifest.Validations.ValidSensitiveExemptions do
      description(
        "All sensitive_resource_exemptions must reference modules in sensitive_resources."
      )

      message("sensitive_resource_exemptions references a module not in sensitive_resources")
    end

    validate Foundry.Manifest.Validations.ValidCoverageWeights do
      description("coverage_weights values must sum to 1.0 ± 0.001.")
      message("coverage_weights must sum to 1.0")
    end

    validate Foundry.Manifest.Validations.CldrBackendPresent do
      description(
        "If :ash_money is in conditional_libraries, a CLDR backend module must be discoverable in the project. Checked by inspecting compiled modules for a module using Cldr. The conditional_libraries check is performed inside the validator module — not in a where clause — because fragment/1 is not valid for Ash.DataLayer.Simple."
      )

      message("conditional_libraries includes :ash_money but no CLDR backend module found")
    end
  end

  # ---------------------------------------------------------------------------
  # Calculations
  # ---------------------------------------------------------------------------

  calculations do
    calculate :has_notification_config, :boolean, expr(not is_nil(notifications)) do
      description(
        "Whether the manifest has any notification configuration declared. False triggers INV-010 lint warning."
      )
    end

    # Module-based calculations for list membership — fragment/1 is Postgres-only
    # and is not valid with Ash.DataLayer.Simple, which evaluates in Elixir.
    calculate :ash_money_enabled,
              :boolean,
              {Foundry.Manifest.Calculations.LibraryEnabled, library: :ash_money} do
      description("Whether :ash_money is declared in conditional_libraries.")
    end

    calculate :fun_with_flags_enabled,
              :boolean,
              {Foundry.Manifest.Calculations.LibraryEnabled, library: :fun_with_flags} do
      description("Whether :fun_with_flags is declared in conditional_libraries.")
    end
  end
end

defmodule Foundry.Manifest.Calculations.LibraryEnabled do
  @moduledoc """
  Module-based calculation for `Foundry.Manifest`.
  Returns true if the given library atom is present in `conditional_libraries`.

  Used in place of SQL `fragment/1` expressions, which are not valid with
  `Ash.DataLayer.Simple` (evaluated in Elixir, not Postgres).

  ## Usage

      calculate :ash_money_enabled, :boolean,
                Foundry.Manifest.Calculations.LibraryEnabled,
                arguments: [library: :ash_money]
  """

  use Ash.Resource.Calculation

  @impl true
  def calculate(records, opts, _context) do
    library = Keyword.fetch!(opts, :library)

    Enum.map(records, fn record ->
      library in (record.conditional_libraries || [])
    end)
  end
end
