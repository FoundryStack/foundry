defmodule Foundry.TestScenario.AshTracer do
  @moduledoc """
  Ash.Tracer implementation that bridges LiveView handler Ash calls to test process.

  Fires in the same BEAM process as the Ash action (the LiveView channel).
  On action span start, looks up the test PID from LiveViewRegistry and sends
  the action metadata back to the test process via message passing.
  """

  @behaviour Ash.Tracer

  @impl Ash.Tracer
  def get_span_context do
    :no_span
  end

  @impl Ash.Tracer
  def set_metadata(metadata) do
    # Extract span type and check if it's an action
    case Map.get(metadata, :span_type) do
      :action -> record_action(metadata)
      _ -> :ok
    end
  end

  @impl Ash.Tracer
  def stop_span do
    :ok
  end

  defp record_action(metadata) do
    # Extract LiveView channel PID from metadata
    # Ash includes pid in metadata automatically
    lv_pid = self()

    # Lookup test PID from registry
    case Foundry.TestScenario.LiveViewRegistry.lookup(lv_pid) do
      {:ok, test_pid} ->
        # Extract action metadata
        resource = Map.get(metadata, :resource)
        action = Map.get(metadata, :action)
        domain = Map.get(metadata, :domain)

        event_attrs = %{
          resource: resource,
          action: action,
          domain: domain,
          node_id: node_id(resource),
          action_kind: action_kind(action)
        }

        # Send to test process
        send(test_pid, {:foundry_ash_event, event_attrs})

      :not_found ->
        :ok
    end
  end

  defp node_id(nil), do: nil
  defp node_id(resource) when is_atom(resource) do
    resource
    |> Module.split()
    |> Enum.drop(1)
    |> Enum.join(".")
  end

  defp action_kind(action) when is_atom(action) do
    case action do
      :create -> :create
      :read -> :read
      :update -> :update
      :destroy -> :destroy
      _ -> :custom
    end
  end
  defp action_kind(_), do: nil
end
