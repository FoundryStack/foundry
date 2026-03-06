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

  alias Foundry.Manifest.{ApproverConfig, ApprovalSla, NotificationConfig, CoverageWeights, DataRetention}

  # ---------------------------------------------------------------------------
  # Attributes
  # ---------------------------------------------------------------------------

  attributes do
    uuid_primary_key :id

    # ── Identity ──────────────────────────────────────────────────────────────

    attribute :project_name, :string do
      description "Human-readable project name. Used in Studio UI headers and audit log records."
      allow_nil? false
    end

    attribute :domain_type, :atom do
      description "Target domain category. Used for bootstrap template selection. One of: :igaming, :fintech, :healthcare, :legal, :insurance, :other."
      constraints one_of: [:igaming, :fintech, :healthcare, :legal, :insurance, :other]
      default :other
    end

    # ── Sensitive Resources ────────────────────────────────────────────────────

    attribute :sensitive_resources, {:array, :string} do
      description "Module names (as strings) of resources requiring dual approval, AshPaperTrail, and AshArchival. Authentication User and Token resources are always added automatically and must not be listed here."
      default []
    end

    attribute :sensitive_resource_exemptions, {:array, Foundry.Manifest.SensitiveExemption} do
      description "Per-sensitive-resource exemptions for paper_trail or archival requirements. Each entry requires a documented reason and is a :compliance class change."
      default []
    end

    # ── Approvers ─────────────────────────────────────────────────────────────

    attribute :approvers, Foundry.Manifest.ApproverConfig do
      description "Named approver email addresses for each approval role. sensitive_lead and compliance_officer are required."
      allow_nil? false
    end

    # ── Approval SLAs ─────────────────────────────────────────────────────────

    attribute :approval_sla, Foundry.Manifest.ApprovalSla do
      description "Time limits for each change class to reach approval. nil means no SLA. Operations board shows proposals exceeding their SLA."
      default %ApprovalSla{
        structural: nil,
        behavioral: 24,
        sensitive: 4,
        compliance: 48
      }
    end

    # ── Auto-Apply ────────────────────────────────────────────────────────────

    attribute :auto_apply_structural, :boolean do
      description "When true, approved :structural proposals are applied immediately on approval. The approval action IS the apply trigger. All other classes always require a separate Apply action."
      default false
    end

    # ── Phase Gate ────────────────────────────────────────────────────────────

    attribute :change_generation_enabled, :boolean do
      description "Controls whether the copilot generates real diffs (Phase 4+) or only describes what would be proposed (Phase 3). The config/foundry_studio.exs value is the primary mechanism; this field enables per-project override."
      default true
    end

    # ── Notifications ─────────────────────────────────────────────────────────

    attribute :notifications, Foundry.Manifest.NotificationConfig do
      description "Notification channel configuration for the three required staleness conditions. All three keys are required by INV-010. Absence triggers a lint warning."
      allow_nil? true
      default nil
    end

    # ── Coverage ──────────────────────────────────────────────────────────────

    attribute :coverage_gate, :boolean do
      description "When true, a domain coverage score below 0.6 fails CI. Recommended: false for new projects, true before go-live."
      default false
    end

    attribute :coverage_weights, Foundry.Manifest.CoverageWeights do
      description "Override the default domain coverage formula weights. All five values must sum to 1.0."
      default %CoverageWeights{
        transfer_coverage: 0.25,
        rule_coverage: 0.20,
        blueprint_coverage: 0.20,
        compliance_coverage: 0.25,
        ui_coverage: 0.10
      }
    end

    # ── Data Retention ────────────────────────────────────────────────────────

    attribute :data_retention, Foundry.Manifest.DataRetention do
      description "Retention period overrides in days. Defaults are financial/regulated platform values."
      default %DataRetention{
        proposals: 365,
        audit_log: 2555,
        activity_feed: 90
      }
    end

    # ── Context Exclusions ────────────────────────────────────────────────────

    attribute :context_exclusions, {:array, :string} do
      description "Module names excluded from mix foundry.context introspection. Use only as a temporary workaround for cyclic dependency or DSL loop issues. Each exclusion should have an issue reference in a comment in manifest.exs."
      default []
    end

    # ── Conditional Libraries ─────────────────────────────────────────────────

    attribute :conditional_libraries, {:array, :atom} do
      description "Optional ecosystem libraries present in this target platform. Foundry uses this list to enable/disable lint rules and scaffold operations. Valid values: :ash_money, :ash_state_machine, :ash_pyro, :fun_with_flags."
      constraints items: [one_of: [:ash_money, :ash_state_machine, :ash_pyro, :fun_with_flags]]
      default []
    end

    timestamps()
  end

  # ---------------------------------------------------------------------------
  # Actions
  # ---------------------------------------------------------------------------

  actions do
    defaults [:read]

    create :load do
      description "Load and validate a manifest from a parsed keyword list. Called by Foundry.Manifest.Reader."
      accept [
        :project_name, :domain_type, :sensitive_resources, :sensitive_resource_exemptions,
        :approvers, :approval_sla, :auto_apply_structural, :change_generation_enabled,
        :notifications, :coverage_gate, :coverage_weights, :data_retention,
        :context_exclusions, :conditional_libraries
      ]
    end
  end

  # ---------------------------------------------------------------------------
  # Validations
  # ---------------------------------------------------------------------------

  validations do
    validate Foundry.Manifest.Validations.RequiredApprovers do
      description "sensitive_lead and compliance_officer must be present in approvers."
      message "approvers.sensitive_lead and approvers.compliance_officer are required"
    end

    validate Foundry.Manifest.Validations.ValidSensitiveExemptions do
      description "All sensitive_resource_exemptions must reference modules in sensitive_resources."
      message "sensitive_resource_exemptions references a module not in sensitive_resources"
    end

    validate Foundry.Manifest.Validations.ValidCoverageWeights do
      description "coverage_weights values must sum to 1.0 ± 0.001."
      message "coverage_weights must sum to 1.0"
    end

    validate Foundry.Manifest.Validations.CldrBackendPresent do
      description "If :ash_money is in conditional_libraries, a CLDR backend module must be discoverable in the project. Checked by inspecting compiled modules for a module using Cldr. The conditional_libraries check is performed inside the validator module — not in a where clause — because fragment/1 is not valid for Ash.DataLayer.Simple."
      message "conditional_libraries includes :ash_money but no CLDR backend module found"
    end
  end

  # ---------------------------------------------------------------------------
  # Calculations
  # ---------------------------------------------------------------------------

  calculations do
    calculate :has_notification_config, :boolean, expr(not is_nil(notifications)) do
      description "Whether the manifest has any notification configuration declared. False triggers INV-010 lint warning."
    end

    # Module-based calculations for list membership — fragment/1 is Postgres-only
    # and is not valid with Ash.DataLayer.Simple, which evaluates in Elixir.
    calculate :ash_money_enabled, :boolean,
              Foundry.Manifest.Calculations.LibraryEnabled,
              arguments: [library: :ash_money] do
      description "Whether :ash_money is declared in conditional_libraries."
    end

    calculate :fun_with_flags_enabled, :boolean,
              Foundry.Manifest.Calculations.LibraryEnabled,
              arguments: [library: :fun_with_flags] do
      description "Whether :fun_with_flags is declared in conditional_libraries."
    end
  end
end

# ---------------------------------------------------------------------------
# Embedded resources
# ---------------------------------------------------------------------------

defmodule Foundry.Manifest.ApproverConfig do
  @moduledoc """
  Named approver email addresses for each approval role.
  sensitive_lead and compliance_officer are required (validated on Foundry.Manifest).
  Delegate fields are optional fallbacks for when primary approvers are unavailable.
  See: docs/runbooks/approval_queue_blocked.md
  """

  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :sensitive_lead, :string do
      description "Primary approver for :sensitive dual approval slot 1. Required."
      allow_nil? false
    end

    attribute :sensitive_lead_delegate, :string do
      description "Fallback for sensitive_lead when unavailable. Optional."
      allow_nil? true
    end

    attribute :domain_lead, :string do
      description "Sole approver for :behavioral changes. Qualifies as :sensitive dual approval slot 2. Optional."
      allow_nil? true
    end

    attribute :platform_lead, :string do
      description "Qualifies as :sensitive dual approval slot 2. Optional."
      allow_nil? true
    end

    attribute :compliance_officer, :string do
      description "Sole approver for :compliance changes. No override path exists. Required."
      allow_nil? false
    end

    attribute :compliance_officer_delegate, :string do
      description "Fallback for compliance_officer when unavailable. Optional."
      allow_nil? true
    end
  end
end

defmodule Foundry.Manifest.ApprovalSla do
  @moduledoc """
  SLA definitions (in hours) for each change class.
  nil means no SLA for that class.
  The operations board shows proposals exceeding SLA in amber (approaching) or red (exceeded).
  See: docs/runbooks/approval_queue_blocked.md
  """

  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :structural, :integer do
      description "SLA in hours for :structural changes. nil means no SLA (auto-apply or casual review)."
      allow_nil? true
      default nil
    end

    attribute :behavioral, :integer do
      description "SLA in hours for :behavioral changes. Default: 24 hours."
      allow_nil? true
      default 24
    end

    attribute :sensitive, :integer do
      description "SLA in hours for :sensitive changes. Default: 4 hours."
      allow_nil? true
      default 4
    end

    attribute :compliance, :integer do
      description "SLA in hours for :compliance changes. Default: 48 hours."
      allow_nil? true
      default 48
    end
  end
end

defmodule Foundry.Manifest.NotificationConfig do
  @moduledoc """
  Notification channel configuration for the three staleness conditions required by INV-010.
  All three keys must be present — absence triggers the :missing_notification_config lint warning.
  Channels: :slack (requires target Slack channel string), :email (requires email address string).
  """

  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :runbook_stale, Foundry.Manifest.NotificationTarget do
      description "Notification target for runbooks that have not been tested within the configured interval (default 90 days). Required by INV-010."
      allow_nil? false
    end

    attribute :adapter_verify_failed, Foundry.Manifest.NotificationTarget do
      description "Notification target when a provider adapter contract test fails its scheduled verification. Required by INV-010."
      allow_nil? false
    end

    attribute :compliance_test_failed, Foundry.Manifest.NotificationTarget do
      description "Notification target when a compliance-tagged E2E test fails in the latest CI run. Required by INV-010."
      allow_nil? false
    end
  end
end

defmodule Foundry.Manifest.NotificationTarget do
  @moduledoc """
  A single notification delivery target — a channel type and a destination string.
  """

  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :channel, :atom do
      description "Delivery channel. :slack sends to a Slack channel via webhook. :email sends via Swoosh."
      constraints one_of: [:slack, :email]
      allow_nil? false
    end

    attribute :target, :string do
      description "Destination string. For :slack: a channel name like '#ops-alerts'. For :email: an email address."
      allow_nil? false
    end
  end
end

defmodule Foundry.Manifest.CoverageWeights do
  @moduledoc """
  Coverage formula weights for the domain coverage score (ADR-007).
  All five values must sum to 1.0 ± 0.001. Validated on Foundry.Manifest.
  """

  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :transfer_coverage, :decimal do
      description "Weight for transfer-level property test coverage. Default: 0.25."
      default Decimal.new("0.25")
      constraints min: 0, max: 1
    end

    attribute :rule_coverage, :decimal do
      description "Weight for rule-level invariant test coverage. Default: 0.20."
      default Decimal.new("0.20")
      constraints min: 0, max: 1
    end

    attribute :blueprint_coverage, :decimal do
      description "Weight for blueprint-level scenario test coverage. Default: 0.20."
      default Decimal.new("0.20")
      constraints min: 0, max: 1
    end

    attribute :compliance_coverage, :decimal do
      description "Weight for RG-* requirement E2E test coverage. Default: 0.25."
      default Decimal.new("0.25")
      constraints min: 0, max: 1
    end

    attribute :ui_coverage, :decimal do
      description "Weight for LiveResource integration test coverage. Default: 0.10."
      default Decimal.new("0.10")
      constraints min: 0, max: 1
    end
  end
end

defmodule Foundry.Manifest.DataRetention do
  @moduledoc """
  Data retention period overrides in days.
  Defaults are financial/regulated platform values (ADR-012 §Data Retention).
  Projects in other domains may override these to match their regulatory requirements.
  """

  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :proposals, :integer do
      description "Retention in days for completed proposals in .foundry/proposals/. Default: 365 days."
      default 365
      constraints min: 1
    end

    attribute :audit_log, :integer do
      description "Retention in days for .foundry/audit.jsonl. Default: 2555 days (7 years — financial regulatory minimum)."
      default 2555
      constraints min: 365
    end

    attribute :activity_feed, :integer do
      description "Retention in days for in-Studio Activity Feed entries. Default: 90 days."
      default 90
      constraints min: 1
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

defmodule Foundry.Manifest.SensitiveExemption do
  @moduledoc """
  A per-sensitive-resource exemption for paper_trail or archival requirements.
  Adding or removing an exemption is a :compliance class change (INV-011, INV-012).
  Exemptions must be reviewed annually.
  """

  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :resource_module, :string do
      description "The module name of the sensitive resource being exempted. Must be present in the parent manifest's sensitive_resources list."
      allow_nil? false
    end

    attribute :exemption_type, :atom do
      description "Which requirement is being exempted. :paper_trail exempts from INV-011. :archival exempts from INV-012."
      constraints one_of: [:paper_trail, :archival]
      allow_nil? false
    end

    attribute :reason, :string do
      description "Human-readable justification for the exemption. Required. Must reference the regulation that permits this exemption."
      allow_nil? false
    end

    attribute :adr_link, :string do
      description "Link to the ADR that approved this exemption. Required for :archival exemptions. Strongly recommended for :paper_trail exemptions."
      allow_nil? true
    end

    attribute :review_due, :date do
      description "Date by which this exemption must be reviewed. Exemptions must be reviewed annually. The compliance dashboard surfaces overdue reviews."
      allow_nil? true
    end
  end
end
