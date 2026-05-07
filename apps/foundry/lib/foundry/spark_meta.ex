defmodule Foundry.SparkMeta do
  @moduledoc """
  Foundry-specific facade over the generic `spark_meta` analysis pipeline.
  """

  alias Foundry.SparkMeta.ModuleInfo

  @spec walk(module()) :: ModuleInfo.t()
  def walk(module) when is_atom(module) do
    analyzers =
      [
        SparkMeta.Analyzers.ModuleDoc,
        SparkMeta.Analyzers.Extensions,
        SparkMeta.Analyzers.AshResource,
        SparkMeta.Analyzers.StateMachine,
        Foundry.SparkMeta.Classifier,
        Foundry.SparkMeta.Governance,
        Foundry.SparkMeta.ReactorFacts,
        Foundry.SparkMeta.SideEffects,
        Foundry.SparkMeta.Analyzers.PageMetadata,
        Foundry.SparkMeta.Projector
      ]

    case SparkMeta.analyze(module, analyzers: analyzers) do
      {:ok, analysis} ->
        Map.get(
          analysis.facts,
          :module_info,
          %ModuleInfo{module: module, diagnostics: analysis.diagnostics}
        )

      {:error, {:not_loaded, ^module}} ->
        %ModuleInfo{
          module: module,
          diagnostics: [%{module: module, message: "module could not be loaded", detail: "not_loaded"}]
        }
    end
  rescue
    error ->
      %ModuleInfo{
        module: module,
        diagnostics: [%{module: module, message: "walk failed", detail: Exception.message(error)}]
      }
  end
end
