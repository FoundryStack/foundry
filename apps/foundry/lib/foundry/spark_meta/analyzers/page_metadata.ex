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
        calls_actions: LiveViewActions.analyze(module)
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

  defp page_group(module) do
    module_attribute(module, :page_group)
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
