defmodule Foundry.Context.EdgeEntry do
  @moduledoc """
  Represents a directed edge between two nodes in the project context graph.

  Relations:
  - `references`: structural dependency (belongs_to relationship)
  - `referenced_by`: inverse structural dependency (has_one/has_many relationship)
  - `writes`: behavioral write dependency (Reactor create/update step)
  - `reads`: behavioral read dependency (Reactor read step)
  - `async`: event-driven dependency (Oban job → Reactor)
  - `guards`: rule guards a step or resource policy
  - `sequence`: step-to-step ordering within Reactor/Transfer
  - `compensation`: compensation path in saga
  - `configures`: declarative config module/resource configures a Reactor
  - `authenticates`: AshAuthentication User → Token
  - `persists_to`: resource persists to external system
  - `queues_via`: job/reactor queues via external queue
  - `calls_provider`: transfer step calls provider
  - `triggers`: boundary trigger starts a downstream flow
  - `enqueues`: boundary trigger/job enqueues a job
  """

  @derive Jason.Encoder

  @type relation ::
          :references
          | :referenced_by
          | :writes
          | :reads
          | :async
          | :guards
          | :sequence
          | :compensation
          | :configures
          | :authenticates
          | :persists_to
          | :queues_via
          | :calls_provider
          | :triggers
          | :enqueues

  @type t :: %__MODULE__{
          from: String.t(),
          to: String.t(),
          relation: relation(),
          cross_app: boolean(),
          cross_project: boolean(),
          step_name: String.t() | nil,
          step_index: integer() | nil,
          action_name: String.t() | nil,
          compliance_ids: [String.t()]
        }

  @enforce_keys [:from, :to, :relation]
  defstruct [
    :from,
    :to,
    :relation,
    cross_app: false,
    cross_project: false,
    step_name: nil,
    step_index: nil,
    action_name: nil,
    compliance_ids: []
  ]

  @spec new(from :: String.t(), to :: String.t(), relation :: relation()) :: t()
  def new(from, to, relation) when is_binary(from) and is_binary(to) and is_atom(relation) do
    %__MODULE__{from: from, to: to, relation: relation}
  end
end
