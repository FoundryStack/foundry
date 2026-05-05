defmodule Foundry.Context.Scenarios.RuntimeTraceStore do
  @moduledoc false

  alias Foundry.Context.Scenarios.RuntimeTrace

  def load(project_root) do
    trace_dir = Path.join(project_root, ".foundry/scenario_traces")

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

  def lookup(runtime_lookup, scenario_id, test_name) do
    normalized_test_name = normalize_runtime_test_name(test_name)

    runtime_lookup
    |> Map.get(scenario_id, [])
    |> Enum.find(fn payload ->
      trace_test_name = normalize_runtime_test_name(payload.test_name || "")

      trace_test_name == normalized_test_name or
        String.ends_with?(trace_test_name, normalized_test_name)
    end)
  end

  def normalize_runtime_test_name(name) do
    name
    |> to_string()
    |> String.replace_prefix("test ", "")
    |> String.replace_prefix("property ", "")
  end
end
