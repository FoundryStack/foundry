defmodule SparkMeta.Analyzers.ModuleDoc do
  @moduledoc false

  @behaviour SparkMeta.Analyzer

  alias SparkMeta.Analysis

  @impl SparkMeta.Analyzer
  def analyze(context, %Analysis{} = analysis) do
    moduledoc =
      cond do
        context.dsl_state && is_binary(context.dsl_state.moduledoc) ->
          context.dsl_state.moduledoc

        true ->
          fetch_docs(context.module)
      end

    {:ok, Analysis.put_fact(analysis, :module_doc, moduledoc)}
  end

  defp fetch_docs(module) do
    try do
      case Code.fetch_docs(module) do
        {:docs_v1, _, _, _, %{"en" => doc}, _, _} when is_binary(doc) -> String.trim(doc)
        _ -> nil
      end
    rescue
      _ -> nil
    end
  end
end
