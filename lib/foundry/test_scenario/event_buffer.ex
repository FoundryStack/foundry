defmodule Foundry.TestScenario.EventBuffer do
  @moduledoc false

  @table_name :foundry_test_scenario_event_buffer
  @owner_name :foundry_test_scenario_event_buffer_owner

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
        ensure_owner_process()

      _tid ->
        @table_name
    end
  end

  defp ensure_owner_process do
    case Process.whereis(@owner_name) do
      nil ->
        parent = self()

        pid =
          spawn(fn ->
            Process.register(self(), @owner_name)
            :ets.new(@table_name, [:named_table, :public, :duplicate_bag, read_concurrency: true])
            send(parent, {@owner_name, :ready})
            owner_loop()
          end)

        receive do
          {@owner_name, :ready} -> @table_name
        after
          100 ->
            if Process.alive?(pid) do
              @table_name
            else
              ensure_owner_process()
            end
        end

      _pid ->
        wait_for_table()
    end
  rescue
    ArgumentError ->
      wait_for_table()
  end

  defp wait_for_table(attempts_left \\ 20)

  defp wait_for_table(attempts_left) when attempts_left <= 0, do: @table_name

  defp wait_for_table(attempts_left) do
    case :ets.whereis(@table_name) do
      :undefined ->
        Process.sleep(5)
        wait_for_table(attempts_left - 1)

      _tid ->
        @table_name
    end
  end

  defp owner_loop do
    receive do
      :stop -> :ok
      _ -> owner_loop()
    end
  end
end
