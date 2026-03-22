defmodule Foundry.Context.EdgeEntry do
  @moduledoc """
  Represents a directed edge between two nodes in the project context graph.

  Relations:
  - `references`: structural dependency (belongs_to relationship)
  - `referenced_by`: inverse structural dependency (has_one/has_many relationship)
  - `writes`: behavioral write dependency (Reactor create/update step)
  - `reads`: behavioral read dependency (Reactor read step)
  - `async`: event-driven dependency (Oban job → Reactor)
  """

  @type relation :: :references | :referenced_by | :writes | :reads | :async

  @type t :: %__MODULE__{
    from: String.t(),
    to: String.t(),
    relation: relation(),
    cross_app: boolean(),
    cross_project: boolean()
  }

  @derive Jason.Encoder
  @enforce_keys [:from, :to, :relation]
  defstruct [
    :from,
    :to,
    :relation,
    cross_app: false,
    cross_project: false
  ]

  @spec new(from :: String.t(), to :: String.t(), relation :: relation()) :: t()
  def new(from, to, relation) when is_binary(from) and is_binary(to) and is_atom(relation) do
    %__MODULE__{from: from, to: to, relation: relation}
  end
end
