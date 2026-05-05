defmodule Foundry.TestScenario.RuntimeCapture do
  @moduledoc false

  @trace_key :foundry_test_scenario_trace

  def capture(context, fun) when is_map(context) and is_function(fun, 0) do
    metadata = trace_metadata(context)
    previous_trace = Process.get(@trace_key)
    Process.put(@trace_key, %{metadata: metadata, events: [], sequence: 0})

    try do
      result = fun.()
      flush_trace(:ok)
      result
    catch
      kind, reason ->
        flush_trace({kind, reason})
        :erlang.raise(kind, reason, __STACKTRACE__)
    after
      restore_previous_trace(previous_trace)
    end
  end

  def trace_node(node_id), do: trace_node(node_id, %{})

  def trace_node(node_id, attrs) when is_binary(node_id) do
    case Process.get(@trace_key) do
      %{events: events, sequence: sequence} = trace ->
        normalized_attrs =
          attrs
          |> Enum.into(%{})
          |> normalize_trace_attrs()

        event =
          normalized_attrs
          |> Map.put(:node_id, node_id)
          |> Map.put_new(:focus_node_id, Map.get(normalized_attrs, :focus_node_id, node_id))
          |> Map.put_new(:status, :passed)
          |> Map.put_new(:provenance, :executed)
          |> Map.put_new(:sequence, sequence + 1)

        Process.put(@trace_key, %{trace | events: [event | events], sequence: sequence + 1})
        :ok

      _ ->
        :ok
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

  defp normalize_trace_attrs(attrs) do
    Enum.into(attrs, %{}, fn
      {key, value} when is_atom(key) -> {key, value}
      {key, value} when is_binary(key) -> {String.to_atom(key), value}
    end)
  end

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
end
