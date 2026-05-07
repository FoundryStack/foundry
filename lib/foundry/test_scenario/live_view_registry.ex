defmodule Foundry.TestScenario.LiveViewRegistry do
  @moduledoc """
  ETS-backed registry mapping LiveView channel PIDs to test process PIDs.

  Used by AshTracer to forward action events from LiveView handlers back to
  the test process where they can be collected by RuntimeCapture.

  Registry is lazy-initialized on first access and shared across all processes.
  """

  @table_name :foundry_liveview_registry

  def register(lv_pid, test_pid) when is_pid(lv_pid) and is_pid(test_pid) do
    init_table()
    :ets.insert(@table_name, {lv_pid, test_pid})
    :ok
  end

  def unregister(lv_pid) when is_pid(lv_pid) do
    init_table()
    :ets.delete(@table_name, lv_pid)
    :ok
  end

  def lookup(lv_pid) when is_pid(lv_pid) do
    init_table()
    case :ets.lookup(@table_name, lv_pid) do
      [{^lv_pid, test_pid}] -> {:ok, test_pid}
      [] -> :not_found
    end
  end

  defp init_table do
    # Use ets:info to check if table exists
    # If not, create it as a named_table (public, read-only for readers)
    case :ets.info(@table_name) do
      :undefined ->
        :ets.new(@table_name, [:named_table, :public, :set])
      _ ->
        :ok
    end
  end
end
