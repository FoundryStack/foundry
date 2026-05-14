defmodule ScenarioTracer.TraceStore.JsonFile do
  @moduledoc false
  @behaviour ExTracer.TraceStore

  alias ExTracer.RuntimeTrace

  def load(opts) do
    trace_dir = Map.fetch!(opts, :trace_dir)

    if File.dir?(trace_dir) do
      trace_dir
      |> Path.join("*.json")
      |> Path.wildcard()
      |> Enum.reduce(%{}, fn path, acc ->
        with {:ok, content} <- File.read(path),
             {:ok, payload} <- Jason.decode(content),
             scenario_id when is_binary(scenario_id) <- payload["scenario_id"] do
          trace = RuntimeTrace.from_map(payload)
          Map.update(acc, scenario_id, [trace], &[trace | &1])
        else
          _ -> acc
        end
      end)
      |> Map.new(fn {scenario_id, payloads} ->
        sorted = Enum.sort_by(payloads, & &1.captured_at, :desc)
        {scenario_id, sorted}
      end)
    else
      %{}
    end
  end

  def match(trace, test_name) do
    normalized_test_name = normalize_runtime_test_name(test_name)
    trace_test_name = normalize_runtime_test_name(trace.test_name || "")
    trace_test_name == normalized_test_name or String.ends_with?(trace_test_name, normalized_test_name)
  end

  def normalize_runtime_test_name(name) do
    name
    |> to_string()
    |> String.replace_prefix("test ", "")
    |> String.replace_prefix("property ", "")
  end
end
