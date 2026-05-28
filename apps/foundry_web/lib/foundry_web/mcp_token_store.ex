defmodule FoundryWeb.McpTokenStore do
  use GenServer

  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def store_token(token, expire_at) do
    GenServer.cast(__MODULE__, {:store, token, expire_at})
  end

  def valid_token?(token) do
    GenServer.call(__MODULE__, {:valid, token})
  end

  @impl true
  def init(_opts) do
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:store, token, expire_at}, state) do
    new_state = Map.put(state, token, expire_at)
    {:noreply, new_state}
  end

  @impl true
  def handle_call({:valid, token}, _from, state) do
    current_time = System.system_time(:second)

    case Map.get(state, token) do
      nil ->
        {:reply, false, state}

      expire_at ->
        if current_time < expire_at do
          {:reply, true, state}
        else
          # Token expired, remove it
          new_state = Map.delete(state, token)
          {:reply, false, new_state}
        end
    end
  end
end
