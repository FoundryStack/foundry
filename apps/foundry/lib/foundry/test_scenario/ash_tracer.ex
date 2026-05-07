defmodule Foundry.TestScenario.AshTracer do
  @moduledoc """
  Ash.Tracer implementation for Foundry scenario tracing.

  Captures action spans and routes them to the test process via message passing,
  enabling cross-process instrumentation of LiveView handlers without modifying
  application code.

  When tracing a LiveView test:
  1. The LiveViewHook on_mount callback registers the LV channel PID with the test PID
  2. When Ash actions fire in the LV handler, this tracer captures them
  3. The tracer looks up the test PID and sends events back to it
  4. RuntimeCapture.drain_liveview_events() collects these events after each LV interaction
  """

  @behaviour Ash.Tracer

  @impl Ash.Tracer
  def trace_type?(:action), do: true
  def trace_type?(_), do: false

  @impl Ash.Tracer
  def start_span(:action, _name) do
    :ok
  end

  def start_span(_, _), do: :ok

  @impl Ash.Tracer
  def stop_span do
    :ok
  end

  @impl Ash.Tracer
  def set_metadata(:action, metadata) do
    resource = Map.get(metadata, :resource)
    action = Map.get(metadata, :action)

    if resource && action do
      node_id = resource |> to_string() |> String.trim_leading("Elixir.")

      event = %{
        node_id: node_id,
        action_kind: action_kind(action)
      }

      # Try to send to test process if we're in a LiveView handler
      case Foundry.TestScenario.LiveViewRegistry.lookup(self()) do
        {:ok, test_pid} ->
          send(test_pid, {:foundry_ash_event, event})

        :not_found ->
          # We're in the test process directly, record locally
          trace_key = :foundry_test_scenario_trace

          case Process.get(trace_key) do
            %{events: events, sequence: sequence} = trace ->
              new_sequence = sequence + 1

              updated_event =
                event
                |> Map.put(:status, :passed)
                |> Map.put(:provenance, :executed)
                |> Map.put(:sequence, new_sequence)
                |> Map.put(:focus_node_id, node_id)

              Process.put(trace_key, %{trace | events: [updated_event | events], sequence: new_sequence})

            _ ->
              :ok
          end
      end
    end

    :ok
  end

  def set_metadata(_, _), do: :ok

  @impl Ash.Tracer
  def get_span_context do
    :no_span
  end

  @impl Ash.Tracer
  def set_span_context(_context) do
    :ok
  end

  @impl Ash.Tracer
  def set_error(_error) do
    :ok
  end

  @impl Ash.Tracer
  def set_error(_error, _opts) do
    :ok
end

  @impl Ash.Tracer
  def set_handled_error(_error, _opts) do
    :ok
  end

  defp action_kind(:create), do: :create
  defp action_kind(:read), do: :read
  defp action_kind(:update), do: :update
  defp action_kind(:destroy), do: :destroy
  defp action_kind(_), do: :read
end
