defmodule SparkMeta.PipelineTest do
  use ExUnit.Case

  defmodule OrderAnalyzer do
    @behaviour SparkMeta.Analyzer

    def analyze(_context, analysis) do
      order = Map.get(analysis.facts, :order, [])
      {:ok, SparkMeta.Analysis.put_fact(analysis, :order, order ++ [:order])}
    end
  end

  defmodule SourceAnalyzer do
    @behaviour SparkMeta.Analyzer

    def analyze(context, analysis) do
      {:ok,
       analysis
       |> SparkMeta.Analysis.put_fact(:source_text, context.source_text)
       |> SparkMeta.Analysis.put_fact(:source_path, context.source_path)}
    end
  end

  defmodule FailingAnalyzer do
    @behaviour SparkMeta.Analyzer

    def analyze(_context, _analysis) do
      {:error, %{message: "failing analyzer"}}
    end
  end

  test "runs analyzers in order and returns accumulated facts" do
    {:ok, analysis} =
      SparkMeta.Pipeline.run(MockResource, analyzers: [OrderAnalyzer, OrderAnalyzer])

    assert analysis.facts.order == [:order, :order]
  end

  test "captures source provider output in the context" do
    provider = fn _module ->
      {:ok, %{path: "inline://mock", text: "defmodule Inline do\nend", ast: {:__block__, [], []}}}
    end

    {:ok, analysis} =
      SparkMeta.Pipeline.run(MockPlainModule,
        analyzers: [SourceAnalyzer],
        source_provider: provider
      )

    assert analysis.facts.source_path == "inline://mock"
    assert analysis.facts.source_text =~ "defmodule Inline"
  end

  test "records diagnostics for analyzer failures without aborting the pipeline" do
    {:ok, analysis} =
      SparkMeta.Pipeline.run(MockResource, analyzers: [FailingAnalyzer, OrderAnalyzer])

    assert [%{message: "failing analyzer"}] = analysis.diagnostics
    assert analysis.facts.order == [:order]
  end

  test "records diagnostics for source provider failures" do
    provider = fn _module -> {:error, :unavailable} end

    {:ok, analysis} =
      SparkMeta.Pipeline.run(MockResource,
        analyzers: [OrderAnalyzer],
        source_provider: provider
      )

    assert Enum.any?(analysis.diagnostics, &(&1.message == "source provider failed"))
  end

  test "default analyzers expose reusable Spark and Ash facts" do
    {:ok, analysis} = SparkMeta.analyze(MockResourceWithDocs)

    assert analysis.facts.module_doc == "A mock resource with rich documentation for testing."
    assert is_list(analysis.facts.extensions)
    assert Enum.any?(analysis.facts.ash_resource.attributes, &(&1.name == :name))
    assert Enum.any?(analysis.facts.ash_resource.relationships, &(&1.name == :owner))
  end
end
