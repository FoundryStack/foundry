defmodule SparkMeta.Analyzers.Extensions do
  @moduledoc false

  @behaviour SparkMeta.Analyzer

  alias SparkMeta.Analysis

  @impl SparkMeta.Analyzer
  def analyze(context, %Analysis{} = analysis) do
    extensions =
      case context.dsl_state do
        %SparkMeta.DslState{extensions: extensions} -> extensions
        _ -> []
      end

    persisted =
      case context.dsl_state do
        %SparkMeta.DslState{persisted: persisted} -> persisted
        _ -> %{}
      end

    extension_data =
      case context.dsl_state do
        %SparkMeta.DslState{extension_data: extension_data} -> extension_data
        _ -> %{}
      end

    {:ok,
     analysis
     |> Analysis.put_fact(:extensions, extensions)
     |> Analysis.put_fact(:persisted, persisted)
     |> Analysis.put_fact(:extension_data, extension_data)}
  end
end
