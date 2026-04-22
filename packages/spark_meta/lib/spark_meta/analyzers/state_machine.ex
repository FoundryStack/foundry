defmodule SparkMeta.Analyzers.StateMachine do
  @moduledoc false

  @behaviour SparkMeta.Analyzer

  alias SparkMeta.Analysis

  @impl SparkMeta.Analyzer
  def analyze(context, %Analysis{} = analysis) do
    state_machine =
      if has_state_machine?(analysis) do
        states =
          context.module
          |> SparkMeta.Walker.entities([:state_machine, :states])
          |> Enum.map(&to_string(&1.name))

        transitions =
          context.module
          |> SparkMeta.Walker.entities([:state_machine, :transitions])
          |> Enum.map(fn transition ->
            %{
              from: to_string(transition.from),
              to: to_string(transition.to),
              action: to_string(transition.action)
            }
          end)

        state_attribute =
          context.module
          |> SparkMeta.Walker.get_opt([:state_machine], :state_attribute, nil)
          |> stringify()

        initial_states =
          context.module
          |> SparkMeta.Walker.get_opt([:state_machine], :initial_states, [])
          |> Enum.map(&to_string/1)

        default_initial_state =
          context.module
          |> SparkMeta.Walker.get_opt([:state_machine], :default_initial_state, nil)
          |> stringify()

        %{
          present: true,
          states: states,
          transitions: transitions,
          state_attribute: state_attribute,
          initial_states: initial_states,
          default_initial_state: default_initial_state,
          terminal_states: compute_terminal_states(states, transitions)
        }
      else
        default_state_machine()
      end

    {:ok, Analysis.put_fact(analysis, :state_machine, state_machine)}
  end

  defp has_state_machine?(analysis) do
    Map.get(analysis.facts, :extensions, [])
    |> Enum.any?(&(to_string(&1) == "Elixir.AshStateMachine.Resource"))
  end

  defp compute_terminal_states(states, transitions) do
    from_states = transitions |> Enum.map(& &1.from) |> MapSet.new()
    Enum.filter(states, &(&1 not in from_states))
  end

  defp stringify(nil), do: nil
  defp stringify(value), do: to_string(value)

  defp default_state_machine do
    %{
      present: false,
      states: [],
      transitions: [],
      state_attribute: nil,
      initial_states: [],
      default_initial_state: nil,
      terminal_states: []
    }
  end
end
