defmodule ExTracer.Utils do
  @moduledoc false

  def first_present(map, keys) when is_map(map) and is_list(keys) do
    Enum.find_value(keys, fn key ->
      case Map.fetch(map, key) do
        {:ok, value} -> value
        :error -> nil
      end
    end)
  end

  def literal_value({:%{}, _meta, pairs}) do
    pairs
    |> Enum.map(fn {key, value} -> {literal_value(key), literal_value(value)} end)
    |> Map.new()
  end

  def literal_value({:__aliases__, _meta, parts}), do: Enum.join(parts, ".")

  def literal_value({:{}, _meta, values}) do
    values
    |> Enum.map(&literal_value/1)
    |> List.to_tuple()
  end

  def literal_value(list) when is_list(list) do
    if Keyword.keyword?(list) do
      Enum.map(list, fn {key, value} -> {key, literal_value(value)} end)
    else
      Enum.map(list, &literal_value/1)
    end
  end

  def literal_value(value), do: value

  def block_statements({:__block__, _, statements}), do: statements
  def block_statements(nil), do: []
  def block_statements(statement), do: [statement]

  def last_expression({:__block__, _, statements}), do: List.last(statements)
  def last_expression(expression), do: expression

  def ast_to_text(nil), do: nil

  def ast_to_text(ast) do
    ast
    |> Macro.to_string()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  def short_call_snippet(module_name, fun_name, args) do
    rendered_args =
      args
      |> List.wrap()
      |> Enum.take(2)
      |> Enum.map(&ast_to_text/1)
      |> Enum.join(", ")

    "#{module_name}.#{fun_name}(#{rendered_args})"
  end

  def normalize_string_list(value) when is_list(value) do
    value
    |> Enum.map(&normalize_optional_string/1)
    |> Enum.reject(&is_nil/1)
  end

  def normalize_string_list(value) when is_nil(value), do: []

  def normalize_string_list(value) do
    value
    |> normalize_optional_string()
    |> List.wrap()
    |> Enum.reject(&is_nil/1)
  end

  def normalize_optional_string(nil), do: nil
  def normalize_optional_string(value) when is_binary(value), do: String.trim(value)
  def normalize_optional_string(value) when is_atom(value), do: Atom.to_string(value)
  def normalize_optional_string(value), do: to_string(value)

  def stringify(value) when is_binary(value), do: value
  def stringify(value) when is_atom(value), do: Atom.to_string(value)
  def stringify(value), do: to_string(value)

  def normalize_name(nil), do: nil
  def normalize_name(value), do: value |> stringify() |> String.trim_leading(":")

  def base_node_id(nil), do: nil

  def base_node_id(graph_id) do
    graph_id
    |> stringify()
    |> String.split(":step:", parts: 2)
    |> List.first()
    |> String.split(":action:", parts: 2)
    |> List.first()
  end

  def maybe_put(map, _key, nil), do: map
  def maybe_put(map, _key, []), do: map
  def maybe_put(map, key, value), do: Map.put(map, key, value)

  def non_empty_list([]), do: nil
  def non_empty_list(nil), do: nil
  def non_empty_list(list), do: list

  def distinct_consecutive(list) do
    list
    |> Enum.reduce([], fn item, acc ->
      case acc do
        [^item | _] -> acc
        _ -> [item | acc]
      end
    end)
    |> Enum.reverse()
  end
end
