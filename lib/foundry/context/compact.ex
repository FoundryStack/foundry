defmodule Foundry.Context.Compact do
  @moduledoc """
  Generic recursive compact serialization that filters empty values from maps and structs.

  Recursively strips nil, false, [], and "" from any map at any nesting depth.
  This ensures that stub fields (Phase B/D feature gates) are omitted today,
  and will appear automatically when populated in future phases — no code changes needed.
  """

  def compact(struct) when is_struct(struct) do
    struct |> Map.from_struct() |> compact()
  end

  def compact(map) when is_map(map) do
    map
    |> Enum.reduce(%{}, fn {k, v}, acc ->
      compacted = compact(v)
      if empty?(compacted), do: acc, else: Map.put(acc, k, compacted)
    end)
  end

  def compact(list) when is_list(list), do: Enum.map(list, &compact/1)

  def compact(v), do: v

  defp empty?(nil), do: true
  defp empty?(false), do: true
  defp empty?([]), do: true
  defp empty?(""), do: true
  defp empty?(map) when is_map(map) and map_size(map) == 0, do: true
  defp empty?(_), do: false
end
