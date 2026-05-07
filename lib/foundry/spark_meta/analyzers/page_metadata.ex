defmodule Foundry.SparkMeta.Analyzers.PageMetadata do
  @moduledoc """
  Extracts page-related metadata from LiveView modules.

  Populates:
  - `page_group` from `@page_group` module attribute
  - `page_subtype` from `__sdui_lookup__/0` detection or `@page_subtype` attribute
  - `calls_actions` from AST analysis or `@calls_actions` attribute
  """

  @behaviour SparkMeta.Analyzer

  alias SparkMeta.Analysis
  alias Foundry.SparkMeta.Analyzers.LiveViewActions

  @impl SparkMeta.Analyzer
  def analyze(context, %Analysis{} = analysis) do
    module = context.module

    if is_page_module?(module) do
      page_meta = %{
        page_group: page_group(module),
        page_subtype: page_subtype(module),
        calls_actions: LiveViewActions.analyze(module),
        feature_flags: feature_flags(module)
      }

      {:ok, Analysis.put_fact(analysis, :page_metadata, page_meta)}
    else
      {:ok, analysis}
    end
  end

  defp is_page_module?(module) do
    try do
      function_exported?(module, :mount, 3)
    rescue
      _ -> false
    end
  end

  defp page_subtype(module) do
    case module_attribute(module, :page_subtype) do
      nil -> detect_sdui_subtype(module)
      subtype -> subtype
    end
  end

  defp detect_sdui_subtype(module) do
    try do
      if function_exported?(module, :__sdui_lookup__, 0) do
        :sdui
      else
        nil
      end
    rescue
      _ -> nil
    end
  end

  defp feature_flags(module) do
    case extract_from_source(module, :feature_flags) do
      nil -> []
      flags when is_list(flags) -> flags
      flag -> [flag]
    end
  end

  defp page_group(module) do
    extract_from_source(module, :page_group)
  end

  defp extract_from_source(module, attr_name) do
    case source_file(module) do
      nil -> nil
      path ->
        try do
          path
          |> File.read!()
          |> Code.string_to_quoted!()
          |> extract_attribute(attr_name)
        rescue
          _ -> nil
        end
    end
  end

  defp source_file(module) do
    try do
      module.__info__(:compile)
      |> Keyword.get(:source)
      |> then(&if(&1, do: to_string(&1), else: nil))
    rescue
      _ -> nil
    end
  end

  defp extract_attribute(ast, attr_name) do
    ast
    |> collect_attribute(attr_name)
    |> List.first()
  end

  # Extract @attribute value from defmodule
  defp collect_attribute({:defmodule, _, [{:__aliases__, _, _}, [do: body]]}, attr_name) do
    collect_attribute(body, attr_name)
  end

  # Match @attribute_name with value
  defp collect_attribute({:@, _, [{name, _, [value]}]}, attr_name) when name == attr_name do
    [value]
  end

  # Recurse through list
  defp collect_attribute(list, attr_name) when is_list(list) do
    Enum.flat_map(list, &collect_attribute(&1, attr_name))
  end

  # Recurse through tuple args
  defp collect_attribute({_, _, args}, attr_name) when is_list(args) do
    Enum.flat_map(args, &collect_attribute(&1, attr_name))
  end

  defp collect_attribute(_, _), do: []

  defp module_attribute(module, attr_name) do
    try do
      module.__info__(:attributes)
      |> Keyword.get(attr_name)
      |> case do
        nil -> nil
        [value] -> value
        value -> value
      end
    rescue
      _ -> nil
    end
  end
end
