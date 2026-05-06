defmodule ScenarioTracer.MixProject do
  use Mix.Project

  def project do
    [
      app: :scenario_tracer,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:ex_tracer, path: "../ex_tracer"},
      {:jason, "~> 1.4"}
    ]
  end
end
