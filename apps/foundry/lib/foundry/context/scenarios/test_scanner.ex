defmodule Foundry.Context.Scenarios.TestScanner do
  @moduledoc false

  alias Foundry.Context.Scenarios.TestBlock
  alias Foundry.Context.Scenarios.Utils

  def extract_from_ast(ast, source_module, file_path, alias_map, callback) do
    Macro.prewalk(ast, [], fn
      {:describe, _meta, [describe_name, [do: body]]} = node, acc ->
        {node, acc ++ [callback.(describe_name, body, source_module, file_path, alias_map)]}

      {:describe, _meta, [describe_name, body]} = node, acc ->
        {node, acc ++ [callback.(describe_name, body, source_module, file_path, alias_map)]}

      node, acc ->
        {node, acc}
    end)
    |> elem(1)
  end

  def extract_scenario_metadata(body) do
    Macro.prewalk(body, [], fn
      {:@, _meta, [{:scenario, _, [value]}]} = node, acc ->
        {node, [normalize_scenario_attr(value) | acc]}

      node, acc ->
        {node, acc}
    end)
    |> elem(1)
    |> Enum.reverse()
    |> Enum.reduce(%{}, &Map.merge(&2, &1))
  end

  def extract_test_blocks(body) do
    Macro.prewalk(body, [], fn
      {:test, meta, [name, [do: block]]} = node, acc ->
        {node,
         [
           %TestBlock{name: Utils.stringify(name), kind: :test, line: meta[:line], block: block}
           | acc
         ]}

      {:test, meta, [name, _context_ast, [do: block]]} = node, acc ->
        {node,
         [
           %TestBlock{name: Utils.stringify(name), kind: :test, line: meta[:line], block: block}
           | acc
         ]}

      {:property, meta, [name, [do: block]]} = node, acc ->
        {node,
         [
           %TestBlock{
             name: Utils.stringify(name),
             kind: :property,
             line: meta[:line],
             block: block
           }
           | acc
         ]}

      {:property, meta, [name, _context_ast, [do: block]]} = node, acc ->
        {node,
         [
           %TestBlock{
             name: Utils.stringify(name),
             kind: :property,
             line: meta[:line],
             block: block
           }
           | acc
         ]}

      node, acc ->
        {node, acc}
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  def generate_scenario_id(source_module, describe_name) do
    suffix =
      describe_name
      |> to_string()
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/u, "_")
      |> String.trim("_")

    "#{source_module}.#{suffix}"
  end

  def normalize_tags(tags) when is_list(tags), do: Enum.filter(tags, &is_atom/1)
  def normalize_tags(_tags), do: []

  defp normalize_scenario_attr(value) do
    case Utils.literal_value(value) do
      literal when is_map(literal) ->
        literal

      literal when is_list(literal) ->
        if Keyword.keyword?(literal), do: Map.new(literal), else: %{}

      _ ->
        %{}
    end
  end
end
