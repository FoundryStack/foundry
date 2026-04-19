defmodule Foundry.Context.Compact do
  @moduledoc """
  Generic recursive compact serialization that filters empty values from maps and structs.

  Recursively strips nil, false, [], and "" from any map at any nesting depth.
  Also sanitizes strings by replacing non-standard characters with ASCII equivalents.
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
  
  def compact(string) when is_binary(string) do
    # Replace common non-standard characters with safe ASCII equivalents
    # using explicit unicode codepoints to avoid encoding mismatches.
    string
    |> String.replace("\u2014", "-")   # em-dash
    |> String.replace("\u2013", "-")   # en-dash
    |> String.replace("\u00D7", "*")   # multiplication sign
    |> String.replace("\u201C", "\"")  # left double quote
    |> String.replace("\u201D", "\"")  # right double quote
    |> String.replace("\u2018", "'")   # left single quote
    |> String.replace("\u2019", "'")   # right single quote
    |> String.replace("\u2026", "...") # ellipsis
  end

  def compact(v), do: v

  defp empty?(nil), do: true
  defp empty?(false), do: true
  defp empty?([]), do: true
  defp empty?(""), do: true
  defp empty?(map) when is_map(map) and map_size(map) == 0, do: true
  defp empty?(_), do: false
end
