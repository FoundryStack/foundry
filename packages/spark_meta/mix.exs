defmodule SparkMeta.MixProject do
  use Mix.Project

  def project do
    [
      app: :spark_meta,
      name: "spark_meta",
      source_url: "https://github.com/FoundryStack/spark_meta",
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      description: description(),
      package: package(),
      aliases: [test: "test --exclude integration"]
    ]
  end

  defp description() do
    "Spark DSL walker and introspection library."
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => "https://github.com/FoundryStack/spark_meta"
      }
    ]
  end

  def application do
    [
      mod: {SparkMeta.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:spark, "~> 2.0"},
      {:ash, "~> 3.0"}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
