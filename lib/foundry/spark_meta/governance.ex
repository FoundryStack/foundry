defmodule Foundry.SparkMeta.Governance do
  @moduledoc false

  @behaviour SparkMeta.Analyzer

  alias SparkMeta.Analysis
  alias Foundry.SparkMeta.Helpers

  @impl SparkMeta.Analyzer
  def analyze(context, %Analysis{} = analysis) do
    attrs = module_attributes(context.module)
    classifier = Map.get(analysis.facts, :foundry_classifier, %{})

    governance =
      %{
        description: pick_description(context.module, analysis, classifier),
        telemetry_prefix: Helpers.get_attr_list(attrs, :telemetry_prefix),
        runbook:
          Helpers.get_attr_single(attrs, :runbook) || Helpers.extract_runbook_from_source(context.module),
        compliance: Helpers.get_attr_list(attrs, :compliance),
        adrs: Helpers.get_attr_list(attrs, :adrs)
      }

    {:ok, Analysis.put_fact(analysis, :foundry_governance, governance)}
  end

  defp module_attributes(module) do
    module.__info__(:attributes)
  rescue
    _ -> []
  end

  defp pick_description(module, analysis, classifier) do
    module_doc = Map.get(analysis.facts, :module_doc)

    cond do
      is_binary(module_doc) and classifier[:type] == :rule ->
        String.trim(module_doc)

      is_binary(module_doc) ->
        module_doc
        |> String.split("\n\n")
        |> Enum.reject(&(String.trim(&1) == ""))
        |> List.first()
        |> then(&if &1, do: String.trim(&1), else: nil)

      function_exported?(module, :description, 0) ->
        module.description()

      true ->
        nil
    end
  rescue
    _ -> nil
  end
end
