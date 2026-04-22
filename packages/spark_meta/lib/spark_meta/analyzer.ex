defmodule SparkMeta.Analyzer do
  @moduledoc """
  Ordered pass contract for SparkMeta pipelines.
  """

  @callback analyze(SparkMeta.Context.t(), SparkMeta.Analysis.t()) ::
              {:ok, SparkMeta.Analysis.t()} | {:error, map()}
end
