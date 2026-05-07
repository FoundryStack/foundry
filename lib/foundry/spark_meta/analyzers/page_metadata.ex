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
  alias Foundry.PageMetadata, as: SharedPageMetadata

  @impl SparkMeta.Analyzer
  def analyze(context, %Analysis{} = analysis) do
    module = context.module

    if is_page_module?(module) do
      {:ok, Analysis.put_fact(analysis, :page_metadata, SharedPageMetadata.analyze(module))}
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
end
