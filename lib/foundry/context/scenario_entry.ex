defmodule Foundry.Context.ScenarioEntry do
  @moduledoc """
  Represents a single Studio scenario extracted from test source.

  The canonical runtime story is the ordered `flow`. Aggregate fields like
  `nodes` and `graph_path` are derived summaries that help with coverage
  grouping and graph navigation.
  """

  @type category :: :invariant | :state_machine | :compliance | :property
  @type level :: :rule | :action | :transfer | :reactor | :webhook | :job
  @type evidence_mode :: :runtime | :static
  @type trace_status :: :captured | :missing | :stale

  @type flow_step :: %{
          id: String.t(),
          type: atom() | String.t(),
          kind: atom() | String.t() | nil,
          label: String.t(),
          node_id: String.t() | nil,
          focus_node_id: String.t() | nil,
          focus_targets: [String.t()],
          emits: [String.t()],
          reacts_to: String.t() | nil,
          action: String.t() | nil,
          actor: String.t() | nil,
          provenance: :executed | :expanded | :branch | String.t() | nil,
          status: :matched | :passed | :failed | :short_circuit | :potential | String.t() | nil,
          module_function: String.t() | nil,
          source_snippet: String.t() | nil,
          result: String.t() | nil,
          details: String.t() | nil,
          line: pos_integer() | nil,
          test_name: String.t() | nil,
          test_kind: :test | :property | String.t() | nil
        }

  @type test_case :: %{
          name: String.t(),
          kind: :test | :property | String.t(),
          file: String.t(),
          line: pos_integer() | nil
        }

  @derive Jason.Encoder

  @enforce_keys [:id, :name, :category, :source_file, :source_module]
  defstruct [
    :id,
    :name,
    :category,
    :level,
    :source_file,
    :source_module,
    :evidence_mode,
    :trace_status,
    :expansion_mode,
    nodes: [],
    graph_path: [],
    compliance_links: [],
    flow: [],
    evidence_summary: %{},
    entry_points: [],
    tests: [],
    tags: []
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          category: category(),
          level: level() | String.t() | nil,
          source_file: String.t(),
          source_module: String.t(),
          evidence_mode: evidence_mode() | String.t() | nil,
          trace_status: trace_status() | String.t() | nil,
          expansion_mode: atom() | String.t() | nil,
          nodes: [String.t()],
          graph_path: [String.t()],
          compliance_links: [String.t()],
          flow: [flow_step()],
          evidence_summary: map(),
          entry_points: [map()],
          tests: [test_case()],
          tags: [atom() | {atom(), any()}]
        }
end
