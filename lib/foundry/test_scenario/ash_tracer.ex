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
  @context_key :foundry_test_scenario_trace_context
  @span_stack_key :foundry_test_scenario_span_stack

  @impl Ash.Tracer
  def trace_type?(:action), do: true
  def trace_type?(_), do: false

  @impl Ash.Tracer
  def start_span(:action, _name) do
    push_span_frame(:action)
    :ok
  end

  def start_span(_, _), do: :ok

  @impl Ash.Tracer
  def stop_span do
    pop_span_frame()
    :ok
  end

  @impl Ash.Tracer
  def set_metadata(:action, metadata) do
    merge_span_metadata(metadata)
    :ok
  end

  def set_metadata(_, _), do: :ok

  defp push_span_frame(span_type) do
    if trace_context = current_trace_context() do
      frame = %{type: span_type, metadata: %{}, trace_context: trace_context}
      Process.put(@span_stack_key, [frame | Process.get(@span_stack_key, [])])
    end
  end

  defp merge_span_metadata(metadata) do
    case Process.get(@span_stack_key, []) do
      [frame | rest] ->
        Process.put(@span_stack_key, [
          %{frame | metadata: Map.merge(frame.metadata, metadata)} | rest
        ])

      [] ->
        :ok
    end
  end

  @impl Ash.Tracer
  def get_span_context do
    current_trace_context() || :no_span
  end

  @impl Ash.Tracer
  def set_span_context(:no_span) do
    Process.delete(@context_key)
    :ok
  end

  def set_span_context(%{trace_id: trace_id} = context) when is_binary(trace_id) do
    Process.put(@context_key, context)
    :ok
  end

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

  defp pop_span_frame do
    case Process.get(@span_stack_key, []) do
      [frame | rest] ->
        Process.put(@span_stack_key, rest)
        emit_frame_event(frame)

      [] ->
        :ok
    end
  end

  defp emit_frame_event(%{
         type: :action,
         metadata: metadata,
         trace_context: %{trace_id: trace_id}
       })
       when is_binary(trace_id) do
    case action_event(metadata) do
      nil -> :ok
      event -> Foundry.TestScenario.EventBuffer.push(trace_id, event)
    end
  end

  defp emit_frame_event(_frame), do: :ok

  defp action_event(metadata) do
    resource = Map.get(metadata, :resource)
    action = Map.get(metadata, :action)

    if resource && action do
      node_id = resource |> to_string() |> String.trim_leading("Elixir.")

      %{
        node_id: node_id,
        action_kind: action_kind(action)
      }
    end
  end

  defp current_trace_context do
    case Process.get(@context_key) do
      %{trace_id: trace_id} = context when is_binary(trace_id) -> context
      _ -> nil
    end
  end

  defp action_kind(:create), do: :create
  defp action_kind(:read), do: :read
  defp action_kind(:update), do: :update
  defp action_kind(:destroy), do: :destroy
  defp action_kind(_), do: :read
end
