defmodule Foundry.TestScenario.LiveViewRegistry do
  @moduledoc """
  ETS-backed registry mapping LiveView channel PIDs to test process PIDs.

  Used by AshTracer to forward action events from LiveView handlers back to
  the test process where they can be collected by RuntimeCapture.

  Registry is lazy-initialized on first access and shared across all processes.
  """

  use GenServer

  @server_name __MODULE__.Server
  @table_name :foundry_liveview_registry

  def register(lv_pid, test_pid) when is_pid(lv_pid) and is_pid(test_pid) do
    ensure_started()
    GenServer.call(@server_name, {:register, lv_pid, test_pid})
  end

  def unregister(lv_pid) when is_pid(lv_pid) do
    ensure_started()
    GenServer.call(@server_name, {:unregister, lv_pid})
  end

  def unregister_by_test_pid(test_pid) when is_pid(test_pid) do
    ensure_started()
    GenServer.call(@server_name, {:unregister_by_test_pid, test_pid})
  end

  def lookup(lv_pid) when is_pid(lv_pid) do
    try do
      case :ets.lookup(@table_name, lv_pid) do
        [{^lv_pid, test_pid}] -> {:ok, test_pid}
        [] -> :not_found
      end
    rescue
      ArgumentError -> :not_found
    end
  end

  @impl true
  def init(:ok) do
    _ = :ets.new(@table_name, [:named_table, :public, :set])
    {:ok, %{monitors: %{}, test_refs: %{}}}
  end

  @impl true
  def handle_call({:register, lv_pid, test_pid}, _from, state) do
    {state, monitor_ref} = ensure_monitor(test_pid, state)
    :ets.insert(@table_name, {lv_pid, test_pid})
    {:reply, :ok, put_in(state.test_refs[test_pid], monitor_ref)}
  end

  def handle_call({:unregister, lv_pid}, _from, state) do
    state =
      case :ets.lookup(@table_name, lv_pid) do
        [{^lv_pid, test_pid}] ->
          :ets.delete(@table_name, lv_pid)
          maybe_demonitor(test_pid, state)

        [] ->
          state
      end

    {:reply, :ok, state}
  end

  def handle_call({:unregister_by_test_pid, test_pid}, _from, state) do
    :ets.select_delete(@table_name, [{{:_, test_pid}, [], [true]}])
    {:reply, :ok, maybe_demonitor(test_pid, state)}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, test_pid, _reason}, state) do
    :ets.select_delete(@table_name, [{{:_, test_pid}, [], [true]}])

    {:noreply,
     state
     |> update_in([:monitors], &Map.delete(&1, ref))
     |> update_in([:test_refs], &Map.delete(&1, test_pid))}
  end

  defp ensure_started do
    case Process.whereis(@server_name) do
      nil ->
        case GenServer.start_link(__MODULE__, :ok, name: @server_name) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
        end

      _pid ->
        :ok
    end
  end

  defp ensure_monitor(test_pid, %{test_refs: test_refs} = state) do
    case Map.get(test_refs, test_pid) do
      nil ->
        ref = Process.monitor(test_pid)
        {%{state | monitors: Map.put(state.monitors, ref, test_pid)}, ref}

      ref ->
        {state, ref}
    end
  end

  defp maybe_demonitor(test_pid, %{test_refs: test_refs} = state) do
    if :ets.select_count(@table_name, [{{:_, test_pid}, [], [true]}]) == 0 do
      case Map.pop(test_refs, test_pid) do
        {nil, _} ->
          state

        {ref, remaining_refs} ->
          Process.demonitor(ref, [:flush])
          %{state | test_refs: remaining_refs, monitors: Map.delete(state.monitors, ref)}
      end
    else
      state
    end
  end
end
