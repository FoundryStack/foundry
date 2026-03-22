defmodule IgamingRef.MixProject do
  use Mix.Project

  def project do
    [
      app: :igaming_ref,
      version: "0.1.0",
      elixir: "~> 1.16",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  def application do
    [
      mod: {IgamingRef.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Core Ash stack
      {:ash, "~> 3.0"},
      {:ash_postgres, "~> 2.0"},
      {:spark, "~> 2.0"},
      {:ecto_sql, "~> 3.11"},
      {:postgrex, ">= 0.0.0"},

      # Phoenix
      {:phoenix, "~> 1.7"},
      {:phoenix_live_view, "~> 1.0"},
      {:bandit, "~> 1.2"},

      # Ash extensions
      {:ash_authentication, "~> 4.0"},
      {:ash_authentication_phoenix, "~> 2.0"},
      {:ash_state_machine, "~> 0.2"},
      {:ash_paper_trail, "~> 0.1"},
      {:ash_archival, "~> 1.0"},
      {:ash_json_api, "~> 1.0"},

      # Reactor (Transfers)
      {:reactor, "~> 0.10"},

      # Money
      {:ash_money, "~> 0.1"},
      {:ex_money, "~> 5.15"},
      {:ex_money_sql, "~> 1.7"},
      {:ex_cldr, "~> 2.0"},

      # Feature flags (runtime: false — no Redis; configure Ecto persistence when needed)
      {:fun_with_flags, "~> 1.11", runtime: false},
      {:fun_with_flags_ui, "~> 1.0", runtime: false},

      # Background jobs
      {:oban, "~> 2.17"},
      {:ash_oban, "~> 0.2", override: true},

      # Rate limiting (runtime: false — configure when needed)
      {:hammer, "~> 6.1", runtime: false},
      {:hammer_plug, "~> 3.0", runtime: false},

      # Observability
      {:opentelemetry, "~> 1.3"},
      {:opentelemetry_exporter, "~> 1.6"},

      # Igniter (required by Foundry)
      {:igniter, "~> 0.3"},

      # Serialisation
      {:jason, "~> 1.4"},

      # Testing
      {:stream_data, "~> 1.0"},
      {:bypass, "~> 2.1", only: :test},
      {:mox, "~> 1.1", only: :test},
      {:wallaby, "~> 0.30", only: :test},
      {:ex_machina, "~> 2.7", only: :test}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ash.setup", "run priv/repo/seeds.exs"],
      "ash.setup": ["ash.create", "ash.migrate"],
      "ash.reset": ["ash.drop", "ash.setup"],
      test: ["ash.migrate --quiet", "test"]
    ]
  end
end
