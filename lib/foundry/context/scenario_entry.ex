defmodule Foundry.Context.ScenarioEntry do
  @moduledoc """
  Represents a single Studio scenario extracted from test source.

  The canonical runtime story is the ordered `flow`. Aggregate fields like
  `nodes` and `graph_path` are derived summaries that help with coverage
  grouping and graph navigation.
  """

  @type category :: :invariant | :state_machine | :compliance | :property

  @type flow_step :: %{
          id: String.t(),
          type: atom() | String.t(),
          label: String.t(),
          node_id: String.t() | nil,
          focus_node_id: String.t() | nil,
          focus_targets: [String.t()],
          emits: [String.t()],
          reacts_to: String.t() | nil,
          action: String.t() | nil,
          actor: String.t() | nil,
          details: String.t() | nil
        }

  @derive Jason.Encoder

  @enforce_keys [:id, :name, :category, :source_file, :source_module]
  defstruct [
    :id,
    :name,
    :category,
    :source_file,
    :source_module,
    nodes: [],
    graph_path: [],
    compliance_links: [],
    flow: [],
    tags: []
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          category: category(),
          source_file: String.t(),
          source_module: String.t(),
          nodes: [String.t()],
          graph_path: [String.t()],
          compliance_links: [String.t()],
          flow: [flow_step()],
          tags: [atom() | {atom(), any()}]
        }
end
