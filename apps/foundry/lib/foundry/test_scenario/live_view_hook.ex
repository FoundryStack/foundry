defmodule Foundry.TestScenario.LiveViewHook do
  @moduledoc """
  Phoenix LiveView on_mount hook that registers the LiveView channel PID
  with its associated test process PID during test execution.

  Reads the test PID from the Phoenix session if present (set by test helpers).
  The PID is then used by AshTracer to forward action events back to the test.
  Also records the page mount as an entry event in the scenario trace.

  Add to router via:
    live_session :default, on_mount: [Foundry.TestScenario.LiveViewHook]
  """

  def on_mount(_name, _params, session, socket) do
    case decode_trace_context(session) do
      {:ok, trace_context} ->
        Process.put(:foundry_test_scenario_trace_context, trace_context)

        # Record page entry in scenario trace
        page_module = socket.view |> Atom.to_string() |> String.trim_leading("Elixir.")

        Foundry.TestScenario.EventBuffer.push(trace_context.trace_id, %{
          node_id: page_module,
          action_kind: :entry,
          capture_origin: :live_view_mount
        })

        {:cont, socket}

      :not_found ->
        {:cont, socket}
    end
  end

  defp decode_trace_context(session) when is_map(session) do
    case session do
      %{"foundry_trace_id" => trace_id} when is_binary(trace_id) and trace_id != "" ->
        {:ok, %{trace_id: trace_id}}

      %{foundry_trace_id: trace_id} when is_binary(trace_id) and trace_id != "" ->
        {:ok, %{trace_id: trace_id}}

      _ ->
        :not_found
    end
  end

  defp decode_trace_context(_), do: :not_found
end
