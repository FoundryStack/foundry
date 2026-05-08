defmodule Foundry.TestScenario.RuntimeCapture do
  @moduledoc false

  @trace_key :foundry_test_scenario_trace

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
      Foundry.TestScenario.LiveViewRegistry.unregister_by_test_pid(self())
    end
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

  defp drain_liveview_events do
    receive do
      {:foundry_ash_event, event_attrs} ->
        case Process.get(@trace_key) do
          %{events: events, sequence: seq} = trace ->
            event =
              event_attrs
              |> Map.put_new(:status, :passed)
              |> Map.put_new(:provenance, :executed)
              |> Map.put_new(:sequence, seq + 1)
              |> Map.put_new(:focus_node_id, Map.get(event_attrs, :node_id))

            Process.put(@trace_key, %{trace | events: [event | events], sequence: seq + 1})

          _ ->
            :ok
        end

        drain_liveview_events()
    after
      0 -> :ok
    end
  end
end
