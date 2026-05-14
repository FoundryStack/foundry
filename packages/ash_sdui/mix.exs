defmodule AshSdui.MixProject do
  use Mix.Project

  def project do
    [
      app: :ash_sdui,
      name: "ash_sdui",
      source_url: "https://github.com/MaxSvargal/ash_sdui",
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      description: description(),
    ]
  end

  defp description() do
    "Server-Driven UI for Phoenix LiveView applications backed by Ash resources."
  end

  def application do
    [
      mod: {AshSDUI.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ash, "~> 3.20"},
      {:ash_paper_trail, "~> 0.5"},
      {:spark, "~> 2.0"},
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix, "~> 1.7"},
      {:jason, "~> 1.4"}
    ]
  end

  defp aliases do
    [
      test: "test --no-start"
    ]
  end
end
