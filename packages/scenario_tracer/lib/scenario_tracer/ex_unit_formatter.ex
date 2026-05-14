defmodule ScenarioTracer.ExUnitFormatter do
  use GenServer

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def init(opts) do
    {:ok, collector} = ScenarioTracer.TraceCollector.JsonFile.start(Map.new(opts))
    {:ok, %{collector: collector, started_at: %{}}}
  end

  def handle_cast({:suite_started, _opts}, state), do: {:noreply, state}

  def handle_cast({:test_started, %ExUnit.Test{name: name}}, state) do
    {:noreply, put_in(state.started_at[name], System.monotonic_time(:millisecond))}
  end

  def handle_cast({:test_finished, %ExUnit.Test{} = test}, state) do
    started_at = Map.get(state.started_at, test.name)
    duration_ms = if started_at, do: System.monotonic_time(:millisecond) - started_at, else: nil

    event = %{
      scenario_id: scenario_id(test),
      source_module: inspect(test.module),
      describe_name: describe_name(test),
      test_name: to_string(test.name),
      file: to_string(test.tags[:file] || ""),
      line: test.tags[:line],
      captured_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      outcome: outcome(test),
      duration_ms: duration_ms,
      failure_message: failure_message(test),
      failure_line: failure_line(test),
      events: []
    }

    :ok = ScenarioTracer.TraceCollector.JsonFile.record(state.collector, event)
    :ok = ScenarioTracer.TraceCollector.JsonFile.flush(state.collector)
    {:noreply, %{state | started_at: Map.delete(state.started_at, test.name)}}
  end

  defp scenario_id(test), do: "#{inspect(test.module)}.#{describe_name(test) |> String.downcase() |> String.replace(~r/[^a-z0-9]+/u, "_") |> String.trim("_")}"
  defp describe_name(test), do: to_string(test.tags[:describe] || test.name)
  defp outcome(%{state: nil}), do: "passed"
  defp outcome(%{state: {:failed, _}}), do: "failed"
  defp outcome(_), do: "passed"
  defp failure_message(%{state: {:failed, failures}}), do: inspect(failures)
  defp failure_message(_), do: nil
  defp failure_line(%{tags: tags}), do: tags[:line]
end
