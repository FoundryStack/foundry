defmodule SparkMeta.Analyzers.AshResource do
  @moduledoc false

  @behaviour SparkMeta.Analyzer

  alias SparkMeta.Analysis

  @impl SparkMeta.Analyzer
  def analyze(context, %Analysis{} = analysis) do
    ash_resource =
      if ash_resource?(context.module, analysis) do
        SparkMeta.AshResourceData.extract(context.module)
      else
        %{
          attributes: [],
          relationships: [],
          actions: [],
          policies: [],
          compliance: [],
          telemetry_prefix: [],
          data_layer: nil
        }
      end

    {:ok, Analysis.put_fact(analysis, :ash_resource, ash_resource)}
  end

  defp ash_resource?(module, analysis) do
    extensions = Map.get(analysis.facts, :extensions, [])

    Enum.any?(extensions, &(&1 == Ash.Resource.Dsl)) ||
      function_exported?(module, :__ash_resource__, 0)
  rescue
    _ -> false
  end
end
