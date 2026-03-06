defmodule Foundry.Context.ModuleContext do
  @moduledoc """
  The typed output struct for `mix foundry.context <Module> --json`.

  This struct defines the JSON schema frozen at the end of Phase 1.
  Breaking changes require an ADR. The schema matches ADR-003 exactly.

  All fields must be present in every output — use nil for absent optional values,
  not missing keys. Consumers depend on key presence, not key existence checks.
  """

  @type state_machine :: %{
    present: boolean(),
    states: [String.t()],
    transitions: [%{from: String.t(), to: String.t(), action: String.t()}],
    state_attribute: String.t() | nil
  }

  @type money_attribute :: %{
    name: String.t(),
    type: String.t(),
    cldr_backend: String.t()
  }

  @type test_coverage :: %{
    property_tests: boolean(),
    scenario_tests: boolean(),
    e2e_tests: boolean()
  }

  @enforce_keys [:module, :type, :domain, :description]
  defstruct [
    # Identity
    :module,              # String — fully qualified module name
    :type,                # atom — :resource | :transfer | :rule | :blueprint | :adapter | :live_page | :oban_job
    :domain,              # String — parent domain name
    :description,         # String — @moduledoc first paragraph

    # Relationships
    steps:               [],   # [String] — Transfer step function names
    rules:               [],   # [String] — Rule module names applied to this Transfer
    compliance:          [],   # [String] — RG-* requirement IDs
    runbook:             nil,  # String | nil — path to runbook file
    invariants:          [],   # [String] — declared spec_invariants
    related_resources:   [],   # [String] — resource module names referenced
    adrs:                [],   # [String] — ADR IDs referenced in @moduledoc

    # Metadata
    last_modified:        nil,  # String — ISO 8601 date
    sensitive:            false, # boolean

    # Test coverage
    test_coverage: %{
      property_tests: false,
      scenario_tests: false,
      e2e_tests: false
    },

    # Data layer
    data_layer:          nil,   # String | nil — "ash_postgres" | "ash_ets" | nil
    pending_migrations:  false, # boolean — true if mix ash.codegen --check exits non-zero

    # Extensions
    paper_trail:         false, # boolean
    archival:            false, # boolean

    # State machine (always present; present: false when no state machine)
    state_machine: %{
      present: false,
      states: [],
      transitions: [],
      state_attribute: nil
    },

    # API routes
    api_routes: [],     # [%{path: String, method: String, auth_required: boolean}]

    # Observability
    telemetry_prefix: [], # [String] — telemetry event prefix segments

    # Money
    money_attributes: [], # [%{name, type, cldr_backend}]

    # Auth
    authentication_subject: false, # boolean — true if this resource is an ash_authentication subject

    # Background jobs
    oban_queues: [], # [String] — queue names if this is an Oban worker

    # Rate limiting
    rate_limited: false, # boolean — true if hammer_plug middleware declared

    # Feature flags
    feature_flags: [] # [String] — flag names referenced in this module
  ]
end

defmodule Foundry.Context.AllContext do
  @moduledoc """
  The typed output for `mix foundry.context.all --json`.
  A map of domain name strings to lists of ModuleContext structs.

  JSON shape:
  {
    "Finance": [ <ModuleContext>, ... ],
    "Players": [ <ModuleContext>, ... ],
    ...
  }
  """

  @type t :: %{String.t() => [Foundry.Context.ModuleContext.t()]}
end

defmodule Foundry.Diagram.SystemMap do
  @moduledoc """
  The typed output for `mix foundry.diagram.generate --json`.
  A graph of nodes (modules) and edges (relationships), clustered by domain.
  Consumed by the Phase 2 System Map D3 renderer.

  Frozen at end of Phase 1. Breaking changes require an ADR.
  """

  @enforce_keys [:nodes, :edges, :clusters, :generated_at]
  defstruct [:nodes, :edges, :clusters, :generated_at]

  defmodule Node do
    @moduledoc "A node in the system map graph. Corresponds to one Ash resource, Transfer, Rule, etc."

    @enforce_keys [:id, :module, :type, :domain, :label]
    defstruct [
      :id,          # String — same as module name, used as D3 node id
      :module,      # String — fully qualified module name
      :type,        # atom — :resource | :transfer | :rule | :blueprint | :adapter
      :domain,      # String — parent domain
      :label,       # String — short display name (last module segment)
      sensitive: false,        # boolean
      has_compliance: false,   # boolean — has at least one RG-* link
      # Derived from ModuleContext.test_coverage (three booleans → single atom):
      # :none    — property_tests: false, scenario_tests: false, e2e_tests: false
      # :partial — at least one true, not all three
      # :full    — property_tests: true, scenario_tests: true, e2e_tests: true
      test_coverage: :none,
      pending_migrations: false
    ]
  end

  defmodule Edge do
    @moduledoc "A directed edge between two nodes. Represents a relationship, rule application, or Transfer step dependency."

    @enforce_keys [:from, :to, :kind]
    defstruct [
      :from,   # String — source node id
      :to,     # String — target node id
      :kind    # atom — :belongs_to | :has_many | :has_one | :many_to_many | :applies_rule | :transfer_step
    ]
  end

  defmodule Cluster do
    @moduledoc "A named cluster of nodes — corresponds to one domain."

    @enforce_keys [:id, :label, :node_ids]
    defstruct [:id, :label, :node_ids]
  end
end

defmodule Foundry.Compliance.CheckResult do
  @moduledoc """
  The typed output for `mix foundry.compliance.check --json`.
  Reports the implementation and test coverage status for each declared RG-* requirement.

  Frozen at end of Phase 1. Breaking changes require an ADR.
  """

  @enforce_keys [:requirements, :summary, :generated_at]
  defstruct [:requirements, :summary, :generated_at]

  defmodule Requirement do
    @moduledoc "The status of a single RG-* compliance requirement."

    @enforce_keys [:id, :summary, :status]
    defstruct [
      :id,                 # String — e.g. "RG-UK-014"
      :summary,            # String — one-line description
      :status,             # atom — :implemented | :partial | :unimplemented | :planned
      implementing_modules: [],  # [String] — modules that declare this requirement
      test_tags: [],             # [String] — ExUnit tags linking tests to this requirement
      last_test_run: nil,        # String | nil — ISO 8601 datetime of last CI run result
      last_test_passed: nil      # boolean | nil — whether the last CI run passed
    ]
  end

  defmodule Summary do
    @moduledoc "Aggregate counts across all requirements."

    defstruct [
      total: 0,
      implemented: 0,
      partial: 0,
      unimplemented: 0,
      planned: 0,
      passing_tests: 0,
      failing_tests: 0
    ]
  end
end

defmodule Foundry.Lint.LintReport do
  @moduledoc """
  The typed output for `mix foundry.lint.all --json`.
  Aggregates all violations from all lint rules across all modules.

  Frozen at end of Phase 1. Breaking changes require an ADR.
  """

  @enforce_keys [:passed, :violations, :generated_at]
  defstruct [:passed, :violations, :generated_at,
    error_count: 0,
    warning_count: 0,
    info_count: 0
  ]

  defmodule Violation do
    @moduledoc "A single lint violation from any lint rule."

    @enforce_keys [:rule_id, :severity, :message]
    defstruct [
      :rule_id,     # atom — e.g. :missing_description
      :severity,    # atom — :error | :warning | :info
      :message,     # String — human-readable description
      module: nil,  # String | nil
      file_path: nil, # String | nil
      line: nil       # integer | nil
    ]
  end
end

defmodule Foundry.Versions.VersionManifest do
  @moduledoc """
  The typed output for `mix foundry.versions.check --json`.
  Current dependency versions read from mix.exs.

  This is included in every LLM prompt as the first item (INV-006).
  The schema is intentionally flexible — it includes all known ecosystem
  libraries but does not fail if a library is absent (not all projects
  use all libraries).

  Frozen at end of Phase 1. Breaking changes require an ADR.
  """

  defstruct [
    # Core (always present in target platforms)
    ash: nil,
    ash_postgres: nil,
    spark: nil,
    phoenix: nil,
    phoenix_live_view: nil,
    igniter: nil,
    ecto_sql: nil,
    postgrex: nil,

    # Ash extensions
    ash_state_machine: nil,
    ash_oban: nil,
    ash_double_entry: nil,
    ash_json_api: nil,
    ash_paper_trail: nil,
    ash_archival: nil,
    ash_authentication: nil,
    ash_authentication_phoenix: nil,
    ash_money: nil,

    # Money stack
    ex_money: nil,
    ex_money_sql: nil,

    # Background jobs
    oban: nil,

    # Feature flags
    fun_with_flags: nil,

    # Rate limiting
    hammer: nil,
    hammer_plug: nil,

    # HTTP
    req: nil,
    finch: nil,
    bandit: nil,

    # Email
    swoosh: nil,

    # Caching
    nebulex: nil,

    # Clustering
    libcluster: nil,

    # Observability
    opentelemetry: nil,
    opentelemetry_exporter: nil,

    # Testing
    stream_data: nil,
    bypass: nil,
    mox: nil,
    wallaby: nil,
    ex_machina: nil,

    # UI
    ash_pyro: nil,

    # Metadata
    elixir_version: nil,
    otp_version: nil,
    generated_at: nil
  ]
end
