defmodule AshSDUI.Registry do
  @moduledoc false

  @table :ash_sdui_registry_ets
  @key {__MODULE__, :components}

  def init_table do
    ensure_ets_table()
  end

  defp ensure_ets_table do
    unless :ets.whereis(@table) do
      try do
        :ets.new(@table, [:set, :public, :named_table])
      rescue
        _ -> :ok
      catch
        _, _ -> :ok
      end
    end

    # Try to migrate entries from persistent_term to ETS
    # (but don't fail if anything goes wrong)
    try do
      case :persistent_term.get(@key, nil) do
        nil ->
          :ok

        map ->
          Enum.each(map, fn {name, entry} ->
            try do
              :ets.insert(@table, {name, entry})
            rescue
              _ -> :ok
            catch
              _, _ -> :ok
            end
          end)
      end
    rescue
      _ -> :ok
    catch
      _, _ -> :ok
    end

    :ets.whereis(@table)
  end

  def register(name, module, meta) do
    entry = Map.merge(meta, %{module: module, name: name})

    # Register in persistent_term (always available, even at compile-time)
    :global.set_lock({@key, self()})

    try do
      current = all_map()
      updated = Map.put(current, name, entry)
      :persistent_term.put(@key, updated)
    after
      :global.del_lock({@key, self()})
    end

    # Try to also add to ETS if table exists
    _ = safe_ets_insert(@table, {name, entry})

    :ok
  end

  defp safe_ets_insert(table, entry) do
    try do
      :ets.insert(table, entry)
    rescue
      _ -> :error
    catch
      _, _ -> :error
    end
  end

  def lookup(name) do
    # Ensure ETS table exists and is populated
    ensure_ets_table()

    # Try ETS first
    case try_ets_lookup(name) do
      {:ok, entry} -> {:ok, entry}
      _ -> lookup_in_map(name)
    end
  end

  def all do
    # Ensure ETS table exists and is populated
    ensure_ets_table()

    case try_ets_all() do
      {:ok, entries} -> entries
      _ -> Map.values(all_map())
    end
  end

  defp try_ets_all do
    try do
      entries =
        @table
        |> :ets.match({:_, :"$1"})
        |> List.flatten()

      {:ok, entries}
    rescue
      _ -> :error
    catch
      _, _ -> :error
    end
  end

  defp try_ets_lookup(name) do
    try do
      case :ets.lookup(@table, name) do
        [{^name, entry}] -> {:ok, entry}
        [] -> :error
      end
    rescue
      _ -> :error
    catch
      _, _ -> :error
    end
  end

  defp lookup_in_map(name) do
    map = all_map()

    case Map.get(map, name) do
      nil -> {:error, :not_found}
      entry -> {:ok, entry}
    end
  end

  defp all_map do
    case :persistent_term.get(@key, nil) do
      nil -> %{}
      map -> map
    end
  end
end
