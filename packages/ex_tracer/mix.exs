defmodule ExTracer.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_tracer,
      name: "ex_tracer",
      source_url: "https://github.com/FoundryStack/ex_tracer",
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
    ]
  end

  defp description() do
    "Scenario extraction primitives for Elixir test suites."
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => "https://github.com/FoundryStack/ex_tracer"
      }
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [{:jason, "~> 1.4"}]
  end
end
