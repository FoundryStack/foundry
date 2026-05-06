defmodule ExTracer.TestScanner do
  @moduledoc false

  alias ExTracer.TestBlock
  alias ExTracer.Utils

  def extract_from_ast(ast, source_module, file_path, alias_map, framework, callback) do
    metadata_attrs = framework.metadata_attrs()
    test_kinds = framework.test_kinds()

    Macro.prewalk(ast, [], fn
      {:describe, _meta, [describe_name, [do: body]]} = node, acc ->
        {node,
         acc ++
           List.wrap(
             callback.(
               describe_name,
               body,
               source_module,
               file_path,
               alias_map,
               metadata_attrs,
               test_kinds
             )
           )}

      {:describe, _meta, [describe_name, body]} = node, acc ->
        {node,
         acc ++
           List.wrap(
             callback.(
               describe_name,
               body,
               source_module,
               file_path,
               alias_map,
               metadata_attrs,
               test_kinds
             )
           )}

      node, acc ->
        {node, acc}
    end)
    |> elem(1)
  end

  def extract_scenario_metadata(body, metadata_attrs \\ [:scenario]) do
    Macro.prewalk(body, [], fn
      {:@, _meta, [{attr, _, [value]}]} = node, acc ->
        if attr in metadata_attrs do
          {node, [normalize_scenario_attr(attr, value) | acc]}
        else
          {node, acc}
        end

      node, acc ->
        {node, acc}
    end)
    |> elem(1)
    |> Enum.reverse()
    |> Enum.reduce(%{}, &Map.merge(&2, &1))
  end

  def extract_test_blocks(body, test_kinds \\ %{test: :test, property: :property}) do
    Macro.prewalk(body, [], fn
      {block_name, meta, [name, [do: block]]} = node, acc ->
        if Map.has_key?(test_kinds, block_name) do
          {node,
           [
             %TestBlock{name: Utils.stringify(name), kind: Map.fetch!(test_kinds, block_name), line: meta[:line], block: block}
             | acc
           ]}
        else
          {node, acc}
        end

      {block_name, meta, [name, _context_ast, [do: block]]} = node, acc ->
        if Map.has_key?(test_kinds, block_name) do
          {node,
           [
             %TestBlock{
               name: Utils.stringify(name),
               kind: Map.fetch!(test_kinds, block_name),
               line: meta[:line],
               block: block
             }
             | acc
           ]}
        else
          {node, acc}
        end

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

  defp normalize_scenario_attr(:scenario, value) do
    case Utils.literal_value(value) do
      literal when is_map(literal) ->
        literal

      literal when is_list(literal) ->
        if Keyword.keyword?(literal), do: Map.new(literal), else: %{}

      _ ->
        %{}
    end
  end

  defp normalize_scenario_attr(attr, value), do: %{attr => Utils.literal_value(value)}
end
