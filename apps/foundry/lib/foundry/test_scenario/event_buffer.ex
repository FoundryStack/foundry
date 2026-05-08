defmodule Foundry.TestScenario.EventBuffer do
  @moduledoc false

  @table_name :foundry_test_scenario_event_buffer

  def push(trace_id, event) when is_binary(trace_id) and is_map(event) do
    ensure_table()
    :ets.insert(@table_name, {trace_id, System.unique_integer([:positive, :monotonic]), event})
    :ok
  end

  def take(trace_id) when is_binary(trace_id) do
    try do
      events =
        @table_name
        |> :ets.lookup(trace_id)
        |> Enum.sort_by(fn {_trace_id, sequence, _event} -> sequence end)
        |> Enum.map(fn {_pid, _sequence, event} -> event end)

      if events != [] do
        :ets.delete(@table_name, trace_id)
      end

      events
    rescue
      ArgumentError -> []
    end
  end

  defp ensure_table do
    case :ets.whereis(@table_name) do
      :undefined ->
        try do
          :ets.new(@table_name, [:named_table, :public, :duplicate_bag])
        rescue
          ArgumentError -> @table_name
        end

      _tid ->
        @table_name
    end
  end
end
