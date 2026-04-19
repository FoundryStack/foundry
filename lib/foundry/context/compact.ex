defmodule Foundry.Context.Compact do
  @moduledoc """
  Generic recursive compact serialization that filters empty values from maps and structs.

  Recursively strips nil, false, [], and "" from any map at any nesting depth.
  This ensures that stub fields (Phase B/D feature gates) are omitted today,
  and will appear automatically when populated in future phases — no code changes needed.
  """

  defmacro __using__(_opts) do
    quote do
      defimpl Jason.Encoder do
        def encode(entry, opts) do
          entry
          |> Map.from_struct()
          |> Foundry.Context.Compact.compact()
          |> Jason.Encode.map(opts)
        end
      end
    end
  end

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

  def sanitize_json(json_str) do
    # Replace all Elixir escape sequences (\x{...}) with safe equivalents
    Regex.replace(~r/\\x\{([0-9a-f]+)\}/, json_str, fn _match, code ->
      code
      |> String.to_integer(16)
      |> case do
        0x2014 -> "-"
        0x2013 -> "-"
        0x00D7 -> "*"
        0x201C -> "\\\""
        0x201D -> "\\\""
        0x2018 -> "'"
        0x2019 -> "'"
        0x2026 -> "..."
        unicode -> "#{<<unicode::utf8>>}"
      end
    end)
  end

  defp empty?(nil), do: true
  defp empty?(false), do: true
  defp empty?([]), do: true
  defp empty?(""), do: true
  defp empty?(map) when is_map(map) and map_size(map) == 0, do: true
  defp empty?(_), do: false
end
