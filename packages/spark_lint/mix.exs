defmodule SparkLint.MixProject do
  use Mix.Project

  def project do
    [
      app: :spark_lint,
      name: "spark_lint",
      source_url: "https://github.com/MaxSvargal/spark_lint",
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      description: description(),
    ]
  end

  defp description() do
    "Lint rule runner for Elixir/Spark/Ash projects."
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    []
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
