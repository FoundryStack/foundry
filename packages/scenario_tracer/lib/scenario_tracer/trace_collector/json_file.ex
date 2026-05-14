defmodule ScenarioTracer.TraceCollector.JsonFile do
  @behaviour ExTracer.TraceCollector

  def start(opts) do
    trace_dir = Map.fetch!(opts, :trace_dir)
    File.mkdir_p!(trace_dir)
    {:ok, %{trace_dir: trace_dir, events: []}}
  end

  def record(state, event) do
    Process.put({__MODULE__, :state}, %{state | events: state.events ++ [event]})
    :ok
  end

  def flush(state) do
    state = Process.get({__MODULE__, :state}, state)

    case state.events do
      [] ->
        :ok

      [first | _] ->
        payload = Map.put(first, :events, Enum.map(state.events, &Map.drop(&1, [:events])))
        file_name = "#{Map.get(first, :scenario_id, "scenario")}-#{System.unique_integer([:positive])}.json"
        path = Path.join(state.trace_dir, file_name)
        File.write!(path, Jason.encode!(payload))
        Process.delete({__MODULE__, :state})
        :ok
    end
  end
end
