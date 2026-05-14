defmodule Foundry.TestScenario.RuntimeCapture do
  @moduledoc false

  @trace_key :foundry_test_scenario_trace
  @context_key :foundry_test_scenario_trace_context

  def capture(context, fun) when is_map(context) and is_function(fun, 0) do
    metadata = trace_metadata(context)
    previous_trace = Process.get(@trace_key)
    Process.put(@trace_key, %{metadata: metadata, events: [], sequence: 0})

    try do
      result = fun.()
      drain_liveview_events()
      flush_trace(:ok)
      result
    catch
      kind, reason ->
        drain_liveview_events()
        flush_trace({kind, reason})
        :erlang.raise(kind, reason, __STACKTRACE__)
    after
      restore_previous_trace(previous_trace)
    end
  end

  def current_trace_id do
    case Process.get(@trace_key) do
      %{metadata: metadata} -> trace_id(metadata)
      _ -> nil
    end
  end

  def with_current_trace_context(fun) when is_function(fun, 0) do
    previous_context = Process.get(@context_key)

    try do
      case current_trace_id() do
        trace_id when is_binary(trace_id) ->
          Process.put(@context_key, %{trace_id: trace_id})

        _ ->
          :ok
      end

      fun.()
    after
      restore_previous_context(previous_context)
    end
  end

  def trace_call(attrs, fun) when is_map(attrs) and is_function(fun, 0) do
    with_current_trace_context(fn ->
      if persist_trace_call?(attrs) do
        trace_node(Map.get(attrs, :node_id), attrs)
      end

      fun.()
    end)
  end

  def trace_node(node_id, event_attrs \\ %{}) when is_binary(node_id) and is_map(event_attrs) do
    case Process.get(@trace_key) do
      %{events: events, sequence: seq} = trace ->
        event =
          event_attrs
          |> Map.put_new(:node_id, node_id)
          |> Map.put_new(:status, :passed)
          |> Map.put_new(:provenance, :executed)
          |> Map.put_new(:sequence, seq + 1)
          |> Map.put_new(:focus_node_id, Map.get(event_attrs, :node_id, node_id))

        Process.put(@trace_key, %{trace | events: [event | events], sequence: seq + 1})
        :ok

      _ ->
        :ok
    end
  end

  defp persist_trace_call?(%{module_function: module_function}) when is_binary(module_function) do
    not duplicate_ash_runtime_call?(module_function)
  end

  defp persist_trace_call?(%{"module_function" => module_function})
       when is_binary(module_function) do
    not duplicate_ash_runtime_call?(module_function)
  end

  defp persist_trace_call?(%{node_id: node_id}) when is_binary(node_id), do: true
  defp persist_trace_call?(%{"node_id" => node_id}) when is_binary(node_id), do: true
  defp persist_trace_call?(_attrs), do: false

  defp duplicate_ash_runtime_call?(module_function) do
    module_function in [
      "Ash.create",
      "Ash.read",
      "Ash.read_one",
      "Ash.get",
      "Ash.update",
      "Ash.destroy"
    ]
  end

  defp flush_trace(outcome) do
    case Process.get(@trace_key) do
      %{metadata: metadata, events: events} when events != [] ->
        trace_dir = Path.join(File.cwd!(), ".foundry/scenario_traces")
        File.mkdir_p!(trace_dir)

        payload =
          metadata
          |> Map.put(:outcome, normalize_outcome(outcome))
          |> Map.put(:captured_at, DateTime.utc_now() |> DateTime.to_iso8601())
          |> Map.put(:events, Enum.reverse(events))

        file_name = trace_file_name(metadata)

        File.write!(Path.join(trace_dir, file_name), Jason.encode!(payload, pretty: true))

      _ ->
        :ok
    end
  end

  defp trace_metadata(context) do
    source_module = context.module |> Atom.to_string() |> String.trim_leading("Elixir.")
    describe_name = context[:describe] || "Scenario"
    test_name = normalize_test_name(context[:test])

    %{
      scenario_id: scenario_id(source_module, describe_name),
      source_module: source_module,
      describe_name: describe_name,
      test_name: test_name,
      file: context[:file],
      line: context[:line]
    }
  end

  defp trace_id(metadata) do
    metadata
    |> Map.take([:scenario_id, :test_name, :line])
    |> :erlang.term_to_binary()
    |> Base.url_encode64(padding: false)
  end

  defp normalize_test_name(nil), do: "scenario"

  defp normalize_test_name(test_name) do
    test_name
    |> to_string()
    |> String.replace_prefix("test ", "")
    |> String.replace_prefix("property ", "")
  end

  defp scenario_id(source_module, describe_name) do
    suffix =
      describe_name
      |> to_string()
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/u, "_")
      |> String.trim("_")

    "#{source_module}.#{suffix}"
  end

  defp normalize_outcome(:ok), do: "ok"
  defp normalize_outcome({kind, reason}), do: "#{kind}:#{Exception.format_banner(kind, reason)}"

  defp safe_segment(value) do
    value
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "_")
    |> String.trim("_")
  end

  defp trace_file_name(metadata) do
    "#{safe_segment(metadata.scenario_id)}--#{trace_hash(metadata)}.json"
  end

  defp trace_hash(metadata) do
    metadata
    |> Map.take([:scenario_id, :test_name, :line])
    |> :erlang.term_to_binary()
    |> :erlang.phash2()
    |> Integer.to_string(36)
  end

  defp restore_previous_trace(nil), do: Process.delete(@trace_key)
  defp restore_previous_trace(previous_trace), do: Process.put(@trace_key, previous_trace)
  defp restore_previous_context(nil), do: Process.delete(@context_key)
  defp restore_previous_context(previous_context), do: Process.put(@context_key, previous_context)

  defp drain_liveview_events do
    case Process.get(@trace_key) do
      %{metadata: metadata} ->
        metadata
        |> trace_id()
        |> drain_pending_events()

        :ok

      _ ->
        :ok
    end

    drain_mailbox_events()
  end

  defp persist_event(event_attrs, trace, seq) do
    event =
      event_attrs
      |> Map.put_new(:status, :passed)
      |> Map.put_new(:provenance, :executed)
      |> Map.put_new(:sequence, seq + 1)
      |> Map.put_new(:focus_node_id, Map.get(event_attrs, :node_id))

    updated_trace = %{trace | events: [event | trace.events], sequence: seq + 1}
    Process.put(@trace_key, updated_trace)
    updated_trace
  end

  defp drain_mailbox_events do
    receive do
      {:foundry_ash_event, event_attrs} ->
        case Process.get(@trace_key) do
          %{sequence: seq} = trace ->
            event_attrs
            |> Map.put_new(:node_id, Map.get(event_attrs, :node_id))
            |> persist_event(trace, seq)

          _ ->
            :ok
        end

        drain_mailbox_events()
    after
      0 -> :ok
    end
  end

  defp drain_pending_events(trace_id, attempts_left \\ 6)

  defp drain_pending_events(_trace_id, attempts_left) when attempts_left <= 0 do
    drain_available_events(nil)
    :ok
  end

  defp drain_pending_events(trace_id, attempts_left) do
    drained_count = drain_available_events(trace_id)

    if drained_count == 0 do
      Process.sleep(5)
    end

    drain_pending_events(trace_id, attempts_left - 1)
  end

  defp drain_available_events(trace_id) do
    buffered_count = drain_buffered_events(trace_id)
    mailbox_count = drain_mailbox_events_count()
    buffered_count + mailbox_count
  end

  defp drain_buffered_events(nil), do: 0

  defp drain_buffered_events(trace_id) do
    trace_id
    |> Foundry.TestScenario.EventBuffer.take()
    |> Enum.reduce(0, fn event_attrs, count ->
      case Process.get(@trace_key) do
        %{sequence: seq} = trace ->
          event_attrs
          |> Map.put_new(:node_id, Map.get(event_attrs, :node_id))
          |> persist_event(trace, seq)

          count + 1

        _ ->
          count
      end
    end)
  end

  defp drain_mailbox_events_count do
    receive do
      {:foundry_ash_event, event_attrs} ->
        count =
          case Process.get(@trace_key) do
            %{sequence: seq} = trace ->
              event_attrs
              |> Map.put_new(:node_id, Map.get(event_attrs, :node_id))
              |> persist_event(trace, seq)

              1

            _ ->
              0
          end

        count + drain_mailbox_events_count()
    after
      0 -> 0
    end
  end
end
