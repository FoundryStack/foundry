defmodule Foundry.Context.ScenarioEntry do
  @moduledoc """
  Represents a single test scenario extracted from an ExUnit test file.

  A scenario is a BDD-style test case annotated with @moduletag metadata
  declaring its category, participating graph nodes, execution path, and steps.

  Scenarios are extracted via `ScenarioExtractor` from test files and linked to
  graph nodes in Studio. Used by ADR-025 test visualization.

  ## Example

      %ScenarioEntry{
        id: "Finance.SufficientBalance.rejects_exceeds",
        name: "SufficientBalance — rejects when amount exceeds balance",
        category: :invariant,
        source_file: "test/finance/withdrawal_transfer_test.exs",
        source_module: "IgamingRef.Finance.WithdrawalTransferTest",
        nodes: ["Finance.WithdrawalTransfer", "Finance.Rules.SufficientBalance"],
        graph_path: ["Finance.WithdrawalTransfer", "Finance.Rules.SufficientBalance", "Finance.Wallet"],
        compliance_links: ["RG-UK-014"],
        steps: %{
          given: ["A player with active status", "A wallet with £500 balance"],
          when: ["The player requests a withdrawal of £600"],
          then: ["The withdrawal is rejected", "The wallet balance remains £500"]
        },
        tags: [:invariant, :compliance]
      }
  """

  @type category :: :invariant | :state_machine | :compliance | :property

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
    steps: %{given: [], when: [], then: []},
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
          steps: %{
            given: [String.t()],
            when: [String.t()],
            then: [String.t()]
          },
          tags: [atom() | {atom(), any()}]
        }
end
